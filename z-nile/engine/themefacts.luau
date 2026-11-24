--!strict
-- f0437 step 5: the facts the app's home view (the themes overview) and the Approvals view's "what is coming" strip show,
-- one JSON file (`themes.json`) the live daemon serves at GET /api/themes. Pure: the board's model in, one row per theme out.
-- The rule that says where a unit stands is tributaries.classify, the same one the board's counts use. Which units wait for
-- the owner's approval is not decided here: approvewalk's queue (waiting.of) decides, and this module only reads the units
-- the newest approval facts file lists. This module records nothing; approving stays the person's own act.
local approvalfacts = require("./approvalfacts")
local board = require("./board")
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
	stage: string, -- idea, design, bundle, ready (a prepared raft), code (in active/), approval, landed; never review (no record says when it began)
	since: number?, -- when it entered `stage`, only where a record says so (a raft's arrival in active/)
	holders: { string }, -- worker labels ("<cli> <id>") that hold it now
	claimed: boolean, -- a stored `preparing-...` stamp: a session took it to design or bundle (f0437 round 2)
	claimedAt: string?, -- the day the stamp was written, where git says
	ids: { string }, -- the unit's own id and its members', so a page can join the live claims to it
}
export type Counts = { done: number, flight: number, approval: number, owner: number, open: number }
-- phase: flight, owner, or claimed (a stored claim with no live holder: it counts as not started, and says so here)
export type Coming = {
	id: string,
	title: string,
	stage: string,
	phase: string,
	holder: string,
	since: number?,
	claimedAt: string?,
	ids: { string },
}
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
	commit: string, -- the short commit the tracker was read at ("" when unknown)
	themes: { Theme },
}
export type Input = {
	at: number,
	themes: { ThemeDef },
	units: { Unit },
	approvalsAt: number?,
	approvalsScope: string,
	live: boolean,
	commit: string?,
}
export type Waiting = approvalfacts.Waiting

local function key(project: string, name: string): string
	return `{project}\0{name}`
end

-- The units of the board's model: a raft, or an issue in no raft. A raft belongs to its own tributary and to every one its
-- members name (as work.inTributary does), so a ticket rafted elsewhere stays reachable from its own theme. `waiting` is the
-- set of units the approval queue lists. What a unit asks, who holds it and whether it is active are the model's own facts
-- (board.collect computed them once, for the board's counts too); a stored claim with no live holder is not in flight.
-- Stages: a raft in active/ is `code` (no record says when review began, so there is no `review`); prepared is `ready`.
function themefacts.units(model: board.Model, waiting: { [string]: boolean }): { Unit }
	local issueOf: { [string]: board.Issue } = {}
	for _, i in model.issues do
		issueOf[i.id] = i
	end
	local units: { Unit } = {}
	for _, r in model.rafts do
		if r.state == "done" or r.work then
			local done = r.state == "done"
			local ids = { r.id }
			local lines: { string } = {}
			local designing = false -- a member's design is claimed
			for _, m in r.issues do
				table.insert(ids, m)
				local issue = issueOf[m]
				if issue then
					table.insert(lines, issue.ownLine)
					designing = designing or issue.claimed
				end
			end
			local themes = tributaries.themesOf(r.tributary, lines)
			local approval = waiting[r.id] == true
			local holders = if done then {} else r.holders
			local inFlight = tributaries.factOf({
				done = done,
				active = r.inFlight,
				asks = r.asks,
				holders = #holders,
				approval = approval,
			}).inFlight
			local stage = "ready"
			if done then
				stage = "landed"
			elseif approval then
				stage = "approval"
			elseif r.state == "active" then
				stage = "code"
			elseif r.claimed and not designing then
				stage = "bundle"
			elseif designing or r.stage == "new" or r.stage == "preparing" then
				stage = "design"
			end
			table.insert(units, {
				id = r.id,
				title = r.title,
				project = r.project,
				themes = themes,
				done = done,
				inFlight = inFlight,
				questions = r.asks and not done,
				approval = approval and not done,
				stage = stage,
				since = if stage == "code" then r.activeAt else nil,
				holders = holders,
				claimed = (r.claimed or designing) and not done,
				claimedAt = r.claimedAt,
				ids = ids,
			})
		end
	end
	for _, i in model.issues do
		if i.raft == nil and (i.state == "done" or i.work) then
			local done = i.state == "done"
			local approval = waiting[i.id] == true
			local holders = if done then {} else i.holders
			local inFlight = tributaries.factOf({
				done = done,
				active = i.inFlight,
				asks = i.asks,
				holders = #holders,
				approval = approval,
			}).inFlight
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
				questions = i.asks and not done,
				approval = approval and not done,
				stage = stage,
				since = nil,
				holders = holders,
				claimed = i.claimed and not done,
				claimedAt = i.claimedAt,
				ids = { i.id },
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
			local claimedOnly = standing == "open" and u.claimed -- a stored claim, no live holder: counted as not started, and said so
			if standing == "flight" or standing == "owner" or claimedOnly then
				table.insert(row.units, {
					id = u.id,
					title = approvalfacts.clipAt(u.title, themefacts.TITLE_CAP),
					stage = u.stage,
					phase = if claimedOnly then "claimed" else standing :: string,
					holder = table.concat(u.holders, ", "),
					since = u.since,
					claimedAt = if claimedOnly then u.claimedAt else nil,
					ids = u.ids,
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
		commit = input.commit or "",
		themes = themes,
	}
end

-- The JSON text of the facts (the file the daemon reads).
function themefacts.encode(facts: Facts): string
	return serde.encode("json" :: "json", facts, false)
end

return themefacts
