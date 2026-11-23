--!strict
-- f0437 step 5: the facts the app's home view (the themes overview) and the Approvals view's "what is coming" strip show,
-- one JSON file (`themes.json`) the live daemon serves at GET /api/themes. Pure: the board's model in, one row per theme out.
-- The rule that says where a unit stands is tributaries.classify, the same one the board's counts use. Which units wait for
-- the owner's approval is not decided here: approvewalk's queue (waiting.of) decides, and this module only reads the units
-- the newest approval facts file lists. This module records nothing; approving stays the person's own act.
local approvalfacts = require("./approvalfacts")
local board = require("./board")
local liveview = require("./liveview")
local serde = require("@lune/serde")
local tributaries = require("./tributaries")

local themefacts = {}

themefacts.VERSION = 1
themefacts.FILE = "themes.json"
themefacts.TITLE_CAP = 200 -- bytes of a unit's title the strip carries

export type ThemeDef = { project: string, name: string, purpose: string }
export type Unit = {
	id: string,
	title: string,
	project: string,
	themes: { string }, -- every tributary it belongs to (`unsorted` when none; `earlier-work` for a done unit with none)
	done: boolean,
	inFlight: boolean,
	questions: boolean,
	approval: boolean,
	stage: string, -- idea, design, bundle, code, review, approval, landed
	since: number?, -- when it entered `stage`, only where a record says so (a raft's arrival in active/)
	holders: { string }, -- worker labels ("<cli> <id>") that hold it now
}
export type Counts = { done: number, flight: number, approval: number, owner: number, open: number }
export type Coming =
	{ id: string, title: string, stage: string, phase: string, holder: string, since: number? }
export type Theme = {
	id: string,
	project: string,
	title: string,
	purpose: string,
	counts: Counts,
	workers: { string },
	units: { Coming },
}
export type Facts = {
	version: number,
	at: number,
	live: boolean, -- the live layer answered when the facts were made (who holds what is known)
	approvalsAt: number?, -- when the approval facts the "waiting" counts come from were made; nil: none were read
	approvalsScope: string,
	themes: { Theme },
}
export type Input = {
	at: number,
	themes: { ThemeDef },
	units: { Unit },
	approvalsAt: number?,
	approvalsScope: string,
	live: boolean,
}
export type Waiting = { units: { [string]: boolean }, at: number, scope: string }

local function named(line: string): boolean
	return line ~= "" and line ~= tributaries.UNSORTED and line ~= tributaries.EARLIER
end

local function key(project: string, name: string): string
	return `{project}\0{name}`
end

-- The units (a raft, or an issue in no raft) the approval facts file lists as waiting, with its time and scope; nil when the
-- text is not version 1 facts with a themes list.
function themefacts.waiting(text: string): Waiting?
	local ok, decoded = pcall(serde.decode, "json" :: "json", text)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local doc = decoded :: { [string]: any }
	if doc.version ~= 1 or type(doc.themes) ~= "table" then
		return nil
	end
	local units: { [string]: boolean } = {}
	for _, th in doc.themes do
		if type(th) == "table" and type(th.rafts) == "table" then
			for _, raft in th.rafts do
				if type(raft) == "table" and type(raft.id) == "string" then
					units[raft.id] = true
				end
			end
		end
	end
	return {
		units = units,
		at = if type(doc.at) == "number" then doc.at else 0,
		scope = if type(doc.scope) == "string" then doc.scope else "",
	}
end

-- The units of the board's model: a raft, or an issue in no raft. A raft belongs to its own tributary and to every one its
-- members name (as work.inTributary does), so a ticket rafted elsewhere stays reachable from its own theme. `waiting` is the
-- set of units the approval queue lists; `live` the workers and claims the daemon answered with (nil: unknown).
function themefacts.units(model: board.Model, waiting: { [string]: boolean }, live: liveview.Live?): { Unit }
	local issueOf: { [string]: board.Issue } = {}
	for _, i in model.issues do
		issueOf[i.id] = i
	end
	local cliOf: { [string]: string } = {}
	local claimsOf: { [string]: { string } } = {}
	if live then
		for _, w in live.workers do
			cliOf[w.id] = w.cli
		end
		for _, c in live.claims do
			local label = `{cliOf[c.worker] or "worker"} {c.worker}`
			for _, id in { c.unit, c.raft or "" } do
				if id ~= "" then
					claimsOf[id] = claimsOf[id] or {}
					if not table.find(claimsOf[id], label) then
						table.insert(claimsOf[id], label)
					end
				end
			end
		end
	end
	local function holdersOf(ids: { string }): { string }
		local set: { [string]: boolean } = {}
		local out: { string } = {}
		for _, id in ids do
			local labels: { string } = claimsOf[id] or {}
			for _, label in labels do
				if not set[label] then
					set[label] = true
					table.insert(out, label)
				end
			end
		end
		table.sort(out)
		return out
	end
	local units: { Unit } = {}
	for _, r in model.rafts do
		if r.state == "done" or r.work then
			local done = r.state == "done"
			local members = r.issues
			local ids = { r.id }
			local themes: { string } = {}
			local function add(line: string)
				if named(line) and not table.find(themes, line) then
					table.insert(themes, line)
				end
			end
			add(r.tributary)
			local questions, designing = r.questions, false -- designing: a member's design is claimed
			for _, m in members do
				table.insert(ids, m)
				local issue = issueOf[m]
				if issue then
					add(issue.ownLine)
					questions = questions or issue.questions
					designing = designing or issue.claimed
				end
			end
			if #themes == 0 then
				themes = { r.tributary }
			end
			local approval = waiting[r.id] == true
			local holders = if done then {} else holdersOf(ids)
			local inFlight = r.inFlight or r.claimed or designing or #holders > 0
			local standing = tributaries.classify({
				done = done,
				inFlight = inFlight,
				questions = questions,
				approval = approval,
			})
			local stage = "code"
			if done then
				stage = "landed"
			elseif approval then
				stage = "approval"
			elseif r.stage == "preparing" and r.claimed and not designing then
				stage = "bundle"
			elseif designing or r.stage == "new" or r.stage == "preparing" then
				stage = "design"
			elseif r.stage == "active" and r.rounds.code > 0 then
				stage = "review"
			end
			table.insert(units, {
				id = r.id,
				title = r.title,
				project = r.project,
				themes = themes,
				done = done,
				inFlight = inFlight,
				questions = questions and not done,
				approval = approval and not done,
				stage = stage,
				since = if (stage == "code" or stage == "review") and standing ~= "open"
					then r.activeAt
					else nil,
				holders = holders,
			})
		end
	end
	for _, i in model.issues do
		if i.raft == nil and (i.state == "done" or i.work) then
			local done = i.state == "done"
			local approval = waiting[i.id] == true
			local holders = if done then {} else holdersOf({ i.id })
			local inFlight = i.inFlight or i.claimed or #holders > 0
			local stage = "idea"
			if done then
				stage = "landed"
			elseif approval then
				stage = "approval"
			elseif i.stage == "preparing" then
				stage = "design"
			elseif i.stage == "prepared" then
				stage = "bundle"
			elseif i.stage == "active" then
				stage = "code"
			end
			table.insert(units, {
				id = i.id,
				title = i.title,
				project = i.project,
				themes = { i.tributary },
				done = done,
				inFlight = inFlight,
				questions = i.questions and not done,
				approval = approval and not done,
				stage = stage,
				since = nil,
				holders = holders,
			})
		end
	end
	return units
end

-- One row per theme in `input.themes` order, then `unsorted` for each project that has units naming none or an undefined
-- theme. A theme nothing names stays (an empty one is still a place to start work); `earlier-work` is no row.
function themefacts.build(input: Input): Facts
	local rows: { [string]: Theme } = {}
	local order: { string } = {}
	local projects: { string } = {}
	local function seeProject(p: string)
		if not table.find(projects, p) then
			table.insert(projects, p)
		end
	end
	for _, def in input.themes do
		seeProject(def.project)
		local k = key(def.project, def.name)
		if not rows[k] then
			rows[k] = {
				id = def.name,
				project = def.project,
				title = def.name,
				purpose = def.purpose,
				counts = { done = 0, flight = 0, approval = 0, owner = 0, open = 0 },
				workers = {},
				units = {},
			}
			table.insert(order, k)
		end
	end
	for _, u in input.units do
		seeProject(u.project)
	end
	local function unsortedRow(project: string): Theme
		local k = key(project, tributaries.UNSORTED)
		if not rows[k] then
			rows[k] = {
				id = tributaries.UNSORTED,
				project = project,
				title = tributaries.UNSORTED,
				purpose = tributaries.PURPOSES.unsorted,
				counts = { done = 0, flight = 0, approval = 0, owner = 0, open = 0 },
				workers = {},
				units = {},
			}
			table.insert(order, k)
		end
		return rows[k]
	end
	local holders: { [string]: { [string]: boolean } } = {}
	for _, u in input.units do
		local standing = tributaries.classify({
			done = u.done,
			inFlight = u.inFlight,
			questions = u.questions,
			approval = u.approval,
		})
		local seen: { [string]: boolean } = {}
		for _, name in u.themes do
			if name == tributaries.EARLIER then
				continue
			end
			local row = rows[key(u.project, name)] or unsortedRow(u.project)
			if seen[row.id] then
				continue
			end
			seen[row.id] = true
			row.counts[standing] += 1
			if standing == "flight" or standing == "owner" then
				table.insert(row.units, {
					id = u.id,
					title = approvalfacts.clipAt(u.title, themefacts.TITLE_CAP),
					stage = u.stage,
					phase = standing :: string,
					holder = table.concat(u.holders, ", "),
					since = u.since,
				})
			end
			if not u.done then
				local set = holders[key(row.project, row.id)] or {}
				holders[key(row.project, row.id)] = set
				for _, label in u.holders do
					if not set[label] then
						set[label] = true
						table.insert(row.workers, label)
					end
				end
			end
		end
	end
	local themes: { Theme } = {}
	-- the defined themes of each project first (file order), then that project's unsorted: projects in the order seen
	for _, k in order do
		local row = rows[k]
		if row.id ~= tributaries.UNSORTED then
			table.insert(themes, row)
		end
	end
	for _, k in order do
		local row = rows[k]
		if row.id == tributaries.UNSORTED then
			table.insert(themes, row)
		end
	end
	for _, row in themes do
		table.sort(row.workers)
	end
	return {
		version = themefacts.VERSION,
		at = input.at,
		live = input.live,
		approvalsAt = input.approvalsAt,
		approvalsScope = input.approvalsScope,
		themes = themes,
	}
end

-- The JSON text of the facts (the file the daemon reads).
function themefacts.encode(facts: Facts): string
	return serde.encode("json" :: "json", facts, false)
end

return themefacts
