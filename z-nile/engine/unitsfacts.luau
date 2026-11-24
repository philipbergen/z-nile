--!strict
-- f0437 step 6, slice 2: the facts the app's id links and detail view read, one JSON file (`units.json`) the live daemon serves at
-- GET /api/units. Pure: the board's model (which already holds every document, read once by the refresh), the templates and the
-- git log of deleted documents in; one list of units out. Every document on disk is a unit: open (backlog, active), done, closed
-- (a ticket that stays in a backlog folder with a closed status), retired (a raft folded into another) and withdrawn (an id git
-- remembers whose document is gone: id, the day and the subject of the commit that removed it). Only open units carry text, a
-- clipped preview of the idea and the design taken through the approval facts' own section rule (one reader of the format). The
-- facts record nothing and decide nothing; reads and the write are unitswrite's, at the edge.
local approvalfacts = require("./approvalfacts")
local board = require("./board")
local serde = require("@lune/serde")
local tributaries = require("./tributaries")

local unitsfacts = {}

unitsfacts.VERSION = 1
unitsfacts.FILE = "units.json"
unitsfacts.PROBLEM_CAP = 500 -- bytes of a preview's Problem; a cut ends with "..." and sets `clipped`
unitsfacts.SOLUTION_CAP = 500
unitsfacts.DESIGN_CAP = 1500 -- bytes of a preview's Design parts in all
unitsfacts.TITLE_CAP = 200
unitsfacts.SUBJECT_CAP = 300 -- bytes of a commit subject
unitsfacts.WITHDRAWN_MAX = 5000 -- stubs carried; the file says how many more there were (`withdrawn_cut`)

export type Part = approvalfacts.Part
export type Unit = {
	id: string,
	kind: string, -- "ticket" | "raft"
	title: string,
	project: string,
	state: string, -- "backlog" | "active" | "done" | "closed" | "retired" | "withdrawn"
	tributary: string,
	themes: { string }, -- every tributary it belongs to, by the one rule (tributaries.themesOf)
	raft: string, -- a ticket's raft, "" when none
	members: { string }, -- a raft's tickets
	depends_on: { string },
	problem: string?, -- only an open unit has these four
	solution: string?,
	design: { Part }?,
	clipped: boolean?,
	when: string?, -- a withdrawn stub only: the day of the commit that removed it
	subject: string?,
}
export type Withdrawn = { id: string, when: string, subject: string }
export type Facts = {
	version: number,
	at: number,
	commit: string,
	sig: string,
	withdrawn_cut: number,
	units: { Unit },
}
export type Input = { at: number, commit: string?, units: { Unit }, cut: number }

local function clip(text: string, cap: number): (string, boolean)
	local out = approvalfacts.clipAt(text, cap)
	return out, #out ~= #text
end

-- The ids of every document the model holds, closed and retired included: a withdrawn stub is never one of these.
function unitsfacts.existing(model: board.Model): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, i in model.issues do
		out[i.id] = true
	end
	for _, r in model.rafts do
		out[r.id] = true
	end
	for _, d in board.droppedOf(model) do
		out[d.id] = true
	end
	return out
end

-- The ids a deletion log names, newest deletion first. The log is `git log --diff-filter=D --no-renames --name-only` with the
-- format `@@<tab><day><tab><subject>`; a document is the file `<id>/<id>.md` (a folder's other files are no unit), and an id that
-- exists now is no withdrawal (a move is a delete and an add). Sorted by id.
function unitsfacts.parseWithdrawn(log: string, exists: { [string]: boolean }): { Withdrawn }
	local seen: { [string]: boolean } = {}
	local out: { Withdrawn } = {}
	local when, subject = "", ""
	local have = false
	for line in string.gmatch(log, "[^\n]+") do
		if string.sub(line, 1, 3) == "@@\t" then
			local day, subj = string.match(line, "^@@\t([^\t]*)\t(.*)$")
			if day and subj then
				when, subject, have = string.sub(day, 1, 32), (clip(subj, unitsfacts.SUBJECT_CAP)), true
			else
				have = false
			end
		elseif have then
			local dir, file = string.match(line, "/([cfdR]%d%d%d%d)/([cfdR]%d%d%d%d)%.md$")
			if dir and dir == file and not seen[dir] then
				seen[dir] = true
				if not exists[dir] then
					table.insert(out, { id = dir, when = when, subject = subject })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- The clipped idea and design of an open unit. Problem and Solution are the approval facts' own sections (template comments
-- dropped), each cut at its cap; the Design parts share one budget: a part past it keeps its heading and an empty text, so no
-- part disappears. `clipped` says that anything was cut.
local function preview(body: string, templates: approvalfacts.Templates): (string, string, { Part }, boolean)
	local s = approvalfacts.sections(body, templates)
	local cut = false
	local problem, c1 = clip(s.problem, unitsfacts.PROBLEM_CAP)
	local solution, c2 = clip(s.solution, unitsfacts.SOLUTION_CAP)
	cut = c1 or c2
	local design: { Part } = {}
	local left = unitsfacts.DESIGN_CAP
	for _, p in s.design do
		if left <= 0 then
			table.insert(design, { heading = p.heading, text = "" })
			cut = cut or p.text ~= ""
		else
			local text, c = clip(p.text, left)
			left -= #p.text
			cut = cut or c
			table.insert(design, { heading = p.heading, text = text })
		end
	end
	return problem, solution, design, cut
end

local function kindOf(id: string): string
	return if string.sub(id, 1, 1) == "R" then "raft" else "ticket"
end

-- Every unit of the model, then the stubs (at most WITHDRAWN_MAX; the second result is how many more there were), sorted by id.
function unitsfacts.units(
	model: board.Model,
	templates: approvalfacts.Templates,
	withdrawn: { Withdrawn }
): ({ Unit }, number)
	local out: { Unit } = {}
	local function open(state: string): boolean
		return state == "backlog" or state == "active"
	end
	for _, i in model.issues do
		local u: Unit = {
			id = i.id,
			kind = "ticket",
			title = (clip(i.title, unitsfacts.TITLE_CAP)),
			project = i.project,
			state = i.state,
			tributary = i.tributary,
			themes = table.clone(i.themes),
			raft = i.raft or "",
			members = {},
			depends_on = table.clone(i.dependsOn),
		}
		if open(i.state) then
			u.problem, u.solution, u.design, u.clipped = preview(i.body, templates)
		end
		table.insert(out, u)
	end
	for _, r in model.rafts do
		local u: Unit = {
			id = r.id,
			kind = "raft",
			title = (clip(r.title, unitsfacts.TITLE_CAP)),
			project = r.project,
			state = r.state,
			tributary = r.tributary,
			themes = table.clone(r.themes),
			raft = "",
			members = table.clone(r.issues),
			depends_on = table.clone(r.dependsOn),
		}
		if open(r.state) then
			u.problem, u.solution, u.design, u.clipped = preview(r.body, templates)
		end
		table.insert(out, u)
	end
	for _, d in board.droppedOf(model) do
		local own = if d.tributary ~= "" then d.tributary else tributaries.UNSORTED
		table.insert(out, {
			id = d.id,
			kind = if d.kind == "raft" then "raft" else "ticket",
			title = (clip(d.title, unitsfacts.TITLE_CAP)),
			project = d.project,
			state = d.state,
			tributary = own,
			themes = tributaries.themesOf(own, {}),
			raft = "",
			members = {},
			depends_on = {},
		})
	end
	local kept = math.min(#withdrawn, unitsfacts.WITHDRAWN_MAX)
	for n = 1, kept do
		local w = withdrawn[n]
		table.insert(out, {
			id = w.id,
			kind = kindOf(w.id),
			title = "",
			project = "",
			state = "withdrawn",
			tributary = "",
			themes = {},
			raft = "",
			members = {},
			depends_on = {},
			when = w.when,
			subject = w.subject,
		})
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out, #withdrawn - kept
end

-- The signature of what the file says: sha256 over every field of every unit in a fixed order (never the time or the commit), so
-- a refresh that changes nothing writes nothing.
local function signature(units: { Unit }, cut: number): string
	local parts: { string } = { `cut={cut}` }
	local function list(l: { string }): string
		return table.concat(l, "\3")
	end
	for _, u in units do
		local design: { string } = {}
		local dp = u.design
		if dp then
			for _, p in dp do
				table.insert(design, `{p.heading}\3{p.text}`)
			end
		end
		table.insert(
			parts,
			table.concat({
				u.id,
				u.kind,
				u.title,
				u.project,
				u.state,
				u.tributary,
				list(u.themes),
				u.raft,
				list(u.members),
				list(u.depends_on),
				u.problem or "\0",
				u.solution or "\0",
				if u.design then table.concat(design, "\4") else "\0",
				if u.clipped == nil then "\0" elseif u.clipped then "1" else "0",
				u.when or "\0",
				u.subject or "\0",
			}, "\2")
		)
	end
	return serde.hash("sha256", table.concat(parts, "\1"))
end

function unitsfacts.build(input: Input): Facts
	return {
		version = unitsfacts.VERSION,
		at = input.at,
		commit = input.commit or "",
		sig = signature(input.units, input.cut),
		withdrawn_cut = input.cut,
		units = input.units,
	}
end

-- The JSON text of the facts (the file the daemon reads).
function unitsfacts.encode(facts: Facts): string
	return serde.encode("json" :: "json", facts, false)
end

return unitsfacts
