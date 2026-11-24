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
	design: { SizedPart }?,
	problem_size: number?, -- the full size in bytes of what the preview clips
	solution_size: number?,
	clipped: boolean?,
	when: string?, -- a stub only: the day of the commit that removed it
	subject: string?,
	fate: string?, -- a stub only: "withdrawn" (the subject says so), "renumbered" (the compaction map names it; `to`) or "removed"
	to: string?,
}
export type SizedPart = { heading: string, text: string, size: number }
export type Withdrawn = { id: string, when: string, subject: string, fate: string, to: string? }
export type Facts = {
	version: number,
	at: number,
	commit: string,
	sig: string,
	withdrawn_cut: number,
	units: { Unit },
	pre: string, -- the cheap signature of the inputs (unitswrite): checked before anything is built
}
export type Input = { at: number, commit: string?, units: { Unit }, cut: number, pre: string? }

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
function unitsfacts.parseWithdrawn(
	log: string,
	exists: { [string]: boolean },
	map: { [string]: string }?
): { Withdrawn }
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
			-- only a tracker folder's documents (`.tracker/`, or the old root `tracker/`): a test fixture's path mints no stub
			local tracked = string.find(line, "/.tracker/", 1, true) ~= nil
				or string.sub(line, 1, 8) == "tracker/"
			if dir and dir == file and tracked and not seen[dir] then
				seen[dir] = true
				if not exists[dir] then
					local to = if map then map[dir] else nil
					local fate = if to
						then "renumbered"
						elseif string.find(string.lower(subject), "withdraw", 1, true) then "withdrawn"
						else "removed"
					table.insert(out, { id = dir, when = when, subject = subject, fate = fate, to = to })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- The fence a line opens or closes: its character, its length and what follows, or nil.
local function fenceMark(line: string): (string?, number, string)
	local lead = string.match(line, "^( *)") :: string
	if #lead > 3 then
		return nil, 0, ""
	end
	local rest = string.sub(line, #lead + 1)
	local c = string.sub(rest, 1, 1)
	if c ~= "`" and c ~= "~" then
		return nil, 0, ""
	end
	local run = string.match(rest, if c == "`" then "^`+" else "^~+") :: string
	if #run < 3 then
		return nil, 0, ""
	end
	return c, #run, string.sub(rest, #run + 1)
end

-- A clip that cut a fenced block open closes it and says the code goes on (a page must not call the document's own text unclosed).
local function closeFence(text: string): string
	local openCh: string?, openLen = nil, 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local c, n, tail = fenceMark(line)
		if c then
			if openCh == nil then
				openCh, openLen = c, n
			elseif c == openCh and n >= openLen and not string.find(tail, "%S") then
				openCh = nil
			end
		end
	end
	if openCh then
		return text .. "\n" .. string.rep(openCh, openLen) .. "\n\n(the code continues in the ticket file)"
	end
	return text
end

local function clipText(text: string, cap: number): (string, boolean)
	local out, cut = clip(text, cap)
	if cut then
		out = closeFence(out)
	end
	return out, cut
end

-- The clipped idea and design of an open unit. Problem and Solution are the approval facts' own sections (template comments
-- dropped), each cut at its cap; the Design parts share one budget: a part past it keeps its heading and an empty text. Every
-- part carries its full size in bytes, so the page can say "first N of M". `clipped` says that anything was cut.
local function preview(
	body: string,
	templates: approvalfacts.Templates
): (string, string, { SizedPart }, boolean, number, number)
	local s = approvalfacts.sections(body, templates)
	local cut = false
	local problem, c1 = clipText(s.problem, unitsfacts.PROBLEM_CAP)
	local solution, c2 = clipText(s.solution, unitsfacts.SOLUTION_CAP)
	cut = c1 or c2
	local design: { SizedPart } = {}
	local left = unitsfacts.DESIGN_CAP
	for _, p in s.design do
		if left <= 0 then
			table.insert(design, { heading = p.heading, text = "", size = #p.text })
			cut = cut or p.text ~= ""
		else
			local text, c = clipText(p.text, left)
			left -= #p.text
			cut = cut or c
			table.insert(design, { heading = p.heading, text = text, size = #p.text })
		end
	end
	return problem, solution, design, cut, #s.problem, #s.solution
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
			u.problem, u.solution, u.design, u.clipped, u.problem_size, u.solution_size =
				preview(i.body, templates)
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
			u.problem, u.solution, u.design, u.clipped, u.problem_size, u.solution_size =
				preview(r.body, templates)
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
			fate = w.fate,
			to = w.to,
		})
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out, #withdrawn - kept
end

-- A canonical text of any value: keys sorted, so the same content is the same text whatever order it was built in.
local function canon(v: any): string
	local t = type(v)
	if t == "table" then
		local keys: { string } = {}
		for k in v do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts: { string } = {}
		for _, k in keys do
			local x = v[k]
			if x == nil then
				x = v[tonumber(k) :: any]
			end
			table.insert(parts, k .. "=" .. canon(x))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return t .. ":" .. tostring(v)
end

-- The signature of what the file says: sha256 over the canonical text of the whole content (the version, the cut count and every
-- field of every unit; never the time or the commit), so a refresh that changes nothing writes nothing and a new field cannot be
-- forgotten.
local function signature(units: { Unit }, cut: number): string
	return serde.hash("sha256", canon({ version = unitsfacts.VERSION, cut = cut, units = units }))
end

function unitsfacts.build(input: Input): Facts
	return {
		version = unitsfacts.VERSION,
		at = input.at,
		commit = input.commit or "",
		sig = signature(input.units, input.cut),
		withdrawn_cut = input.cut,
		units = input.units,
		pre = input.pre or "",
	}
end

-- The JSON text of the facts (the file the daemon reads).
function unitsfacts.encode(facts: Facts): string
	return serde.encode("json" :: "json", facts, false)
end

return unitsfacts
