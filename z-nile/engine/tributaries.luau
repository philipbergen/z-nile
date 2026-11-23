--!strict
-- f0422: tributaries, the named bodies of work a project's units belong to. One file per project root,
-- `<root>/tributaries.toml`, holds only the definitions, in order: `[[tributary]]` with a name and a one-line purpose.
-- Membership is the unit's own `tributary: <name>` frontmatter line (a raft, or an issue in no raft; a raft's members
-- take their raft's). Two tributaries exist in every project without a definition: `unsorted` (an open unit with no
-- line) and `earlier-work` (a done unit with no line); a done unit that has a line stays in its named tributary.
-- Pure over texts and lists: the reads are the caller's (audit.luau for the gate, main.luau for `list`, board.luau).
local serde = require("@lune/serde")

local tributaries = {}

export type Tributary = { name: string, purpose: string }

tributaries.FILE = "tributaries.toml"
tributaries.UNSORTED = "unsorted"
tributaries.EARLIER = "earlier-work"
tributaries.PURPOSES = {
	unsorted = "Open units that name no tributary yet: give the unit a tributary: line.",
	["earlier-work"] = "Done units that name no tributary.",
}
-- The words `./zn list` takes, and the two implicit tributaries and the page's All: none can be a defined name.
tributaries.RESERVED = {
	backlog = true,
	active = true,
	done = true,
	closed = true,
	retired = true,
	unsorted = true,
	["earlier-work"] = true,
	all = true,
}

function tributaries.pathOf(root: string): string
	return `{root}/{tributaries.FILE}`
end

-- The definitions in `text` in order, or nil and the first problem. Every key is known and every value has its shape.
function tributaries.parse(text: string): ({ Tributary }?, string?)
	local ok, decoded = pcall(serde.decode, "toml" :: "toml", text)
	if not ok or type(decoded) ~= "table" then
		return nil, `{tributaries.FILE} is not valid TOML: {string.match(tostring(decoded), "[^\n]+") or ""}`
	end
	local doc = decoded :: { [string]: any }
	for k in doc do
		if k ~= "tributary" then
			return nil, `{tributaries.FILE}: unknown key {k}`
		end
	end
	local list = doc.tributary
	if list == nil then
		return {}, nil
	end
	if type(list) ~= "table" then
		return nil, `{tributaries.FILE}: tributary must be a list of [[tributary]] tables`
	end
	local out: { Tributary } = {}
	for i, entry in list do
		if type(entry) ~= "table" then
			return nil, `{tributaries.FILE}: tributary {i} is not a table`
		end
		for k in entry do
			if k == "units" then
				return nil,
					`{tributaries.FILE}: tributary {i} has a units key: membership is the unit's own tributary: line, not a list here`
			elseif k ~= "name" and k ~= "purpose" then
				return nil, `{tributaries.FILE}: tributary {i} has an unknown key {k}`
			end
		end
		local name, purpose = entry.name, entry.purpose
		if type(name) ~= "string" then
			return nil, `{tributaries.FILE}: tributary {i} needs a name (a string)`
		end
		if purpose ~= nil and type(purpose) ~= "string" then
			return nil, `{tributaries.FILE}: tributary {name} has a purpose that is not a string`
		end
		table.insert(out, { name = name, purpose = (purpose or "") :: string })
	end
	return out, nil
end

local function nameOk(name: string): boolean
	return (string.match(name, "^[a-z]$") or string.match(name, "^[a-z][a-z0-9%-]*[a-z0-9]$")) ~= nil
		and string.find(name, "--", 1, true) == nil
end

-- The problems of the definitions: a duplicate, empty, badly formed or reserved name, and a missing purpose.
function tributaries.check(list: { Tributary }): { string }
	local problems: { string } = {}
	local names: { [string]: boolean } = {}
	for _, tr in list do
		if tr.name == "" then
			table.insert(problems, "a tributary has an empty name")
		elseif names[tr.name] then
			table.insert(problems, `tributary {tr.name} is named twice`)
		elseif tributaries.RESERVED[tr.name] then
			table.insert(
				problems,
				`tributary {tr.name} uses a reserved word (backlog, active, done, closed, retired, unsorted, earlier-work, all)`
			)
		elseif not nameOk(tr.name) then
			table.insert(problems, `tributary {tr.name}: a name is lowercase words joined by hyphens`)
		end
		names[tr.name] = true
		if string.match(tr.purpose, "^%s*$") then
			table.insert(problems, `tributary {tr.name} has no purpose`)
		end
	end
	return problems
end

-- Where a unit stands: the tributary its own line names, else `unsorted` (open) or `earlier-work` (done).
function tributaries.nameOf(declared: string?, done: boolean): string
	if declared ~= nil and declared ~= "" then
		return declared
	end
	return if done then tributaries.EARLIER else tributaries.UNSORTED
end

-- f0420: the tributary every one of `declared` names, or nil when one of them has none or two differ. A raft made of
-- tickets that agree carries that line.
function tributaries.common(declared: { string? }): string?
	local found: string? = nil
	for _, d in declared do
		if d == nil or d == "" then
			return nil
		end
		if found ~= nil and found ~= d then
			return nil
		end
		found = d
	end
	return found
end

-- The problem of a unit's declared value, or nil: a value that names no defined tributary of its project. `what` names
-- the unit ("c0010").
function tributaries.checkUnit(list: { Tributary }, what: string, declared: string?): string?
	if declared == nil or declared == "" then
		return nil
	end
	for _, tr in list do
		if tr.name == declared then
			return nil
		end
	end
	return `{what} has tributary: {declared}, which {tributaries.FILE} does not define`
end

export type Phase = "done" | "flight" | "waiting" | "open"
-- f0437 step 5: the one rule that says where a unit stands, for the board's counts and the app's themes overview. The first
-- that holds decides: done; waiting on the owner for something other than approval (a question, a blocked idea); waiting for
-- the owner's approval; in flight (being designed, bundled, coded or reviewed); else not started.
export type Standing = "done" | "owner" | "approval" | "flight" | "open"
export type Fact = { done: boolean, inFlight: boolean, questions: boolean, approval: boolean }
function tributaries.classify(f: Fact): Standing
	if f.done then
		return "done"
	elseif f.questions then
		return "owner"
	elseif f.approval then
		return "approval"
	elseif f.inFlight then
		return "flight"
	end
	return "open"
end

export type Row = {
	name: string,
	purpose: string,
	implicit: boolean,
	done: number,
	inFlight: number,
	waiting: number,
	notStarted: number,
}
export type Member = { tributary: string, phase: Phase }

-- Each defined tributary in file order with the four counts of its units, then `unsorted` and `earlier-work` when they
-- have units. A member whose name no definition has is counted under `unsorted`.
function tributaries.counts(list: { Tributary }, members: { Member }): { Row }
	local rows: { Row } = {}
	local at: { [string]: Row } = {}
	local function row(name: string, purpose: string, implicit: boolean): Row
		local r: Row = {
			name = name,
			purpose = purpose,
			implicit = implicit,
			done = 0,
			inFlight = 0,
			waiting = 0,
			notStarted = 0,
		}
		at[name] = r
		table.insert(rows, r)
		return r
	end
	for _, tr in list do
		if not at[tr.name] then
			row(tr.name, tr.purpose, false)
		end
	end
	local extra = { unsorted = false, ["earlier-work"] = false }
	for _, m in members do
		if at[m.tributary] == nil and m.tributary ~= tributaries.EARLIER then
			extra.unsorted = true
		elseif m.tributary == tributaries.EARLIER then
			extra["earlier-work"] = true
		end
	end
	if extra.unsorted then
		row(tributaries.UNSORTED, tributaries.PURPOSES.unsorted, true)
	end
	if extra["earlier-work"] then
		row(tributaries.EARLIER, tributaries.PURPOSES["earlier-work"], true)
	end
	for _, m in members do
		local r = at[m.tributary] or at[tributaries.UNSORTED]
		if m.phase == "done" then
			r.done += 1
		elseif m.phase == "flight" then
			r.inFlight += 1
		elseif m.phase == "waiting" then
			r.waiting += 1
		else
			r.notStarted += 1
		end
	end
	return rows
end

return tributaries
