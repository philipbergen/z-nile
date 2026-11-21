--!strict
-- f0422: tributaries, the named bodies of work a project's open and done units belong to. One file per project root,
-- `<root>/tributaries.toml`, an ordered list of [[tributary]] with a name, a one-line purpose and the ids of its units.
-- A unit is a raft or an issue that is in no raft; a raft's members are never listed. Pure over texts and lists: the
-- reads are the caller's (audit.luau for the gate, main.luau for `list`, board.luau for the counts).
local serde = require("@lune/serde")

local tributaries = {}

export type Tributary = { name: string, purpose: string, units: { string } }

tributaries.FILE = "tributaries.toml"
-- The words `./zn list` already takes: a tributary named like one could never be asked for by name.
tributaries.RESERVED = { backlog = true, active = true, done = true, closed = true, retired = true }

function tributaries.pathOf(root: string): string
	return `{root}/{tributaries.FILE}`
end

-- The tributaries in `text` in order, or nil and the first problem. Every key is known and every value has its shape.
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
			if k ~= "name" and k ~= "purpose" and k ~= "units" then
				return nil, `{tributaries.FILE}: tributary {i} has an unknown key {k}`
			end
		end
		local name, purpose, units = entry.name, entry.purpose, entry.units
		if type(name) ~= "string" then
			return nil, `{tributaries.FILE}: tributary {i} needs a name (a string)`
		end
		if purpose ~= nil and type(purpose) ~= "string" then
			return nil, `{tributaries.FILE}: tributary {name} has a purpose that is not a string`
		end
		if units ~= nil and type(units) ~= "table" then
			return nil, `{tributaries.FILE}: tributary {name} has units that are not a list`
		end
		local ids: { string } = {}
		for j, id in (units or {}) :: { any } do
			if type(id) ~= "string" then
				return nil, `{tributaries.FILE}: tributary {name}, unit {j} is not a string`
			end
			table.insert(ids, id)
		end
		table.insert(out, { name = name, purpose = (purpose or "") :: string, units = ids })
	end
	return out, nil
end

-- The problems of `list` against `units` (every raft and every raftless issue of the project, open or done) and
-- `members` (an issue id in a raft maps to that raft's id; it only sharpens the message). One line per problem, each
-- naming the tributary or the unit.
function tributaries.check(list: { Tributary }, units: { string }, members: { [string]: string }?): { string }
	local problems: { string } = {}
	local isUnit: { [string]: boolean } = {}
	for _, id in units do
		isUnit[id] = true
	end
	local names: { [string]: boolean } = {}
	local home: { [string]: string } = {}
	for _, tr in list do
		if tr.name == "" then
			table.insert(problems, "a tributary has an empty name")
		elseif names[tr.name] then
			table.insert(problems, `tributary {tr.name} is named twice`)
		elseif tributaries.RESERVED[tr.name] then
			table.insert(
				problems,
				`tributary {tr.name} is named like a list word (backlog, active, done, closed, retired)`
			)
		elseif
			not (string.match(tr.name, "^[a-z]$") or string.match(tr.name, "^[a-z][a-z0-9%-]*[a-z0-9]$"))
			or string.find(tr.name, "--", 1, true)
		then
			table.insert(problems, `tributary {tr.name}: a name is lowercase words joined by hyphens`)
		end
		names[tr.name] = true
		if string.match(tr.purpose, "^%s*$") then
			table.insert(problems, `tributary {tr.name} has no purpose`)
		end
		local here: { [string]: boolean } = {}
		for _, id in tr.units do
			if here[id] then
				table.insert(problems, `{id} is listed twice in tributary {tr.name}`)
				continue
			end
			here[id] = true
			if not isUnit[id] then
				local raft = if members then members[id] else nil
				if raft then
					table.insert(
						problems,
						`{id} is in raft {raft}, so it belongs to {raft}'s tributary: list {raft}, not {id} (tributary {tr.name})`
					)
				else
					table.insert(
						problems,
						`{id} is not a raft or raftless issue of this project (tributary {tr.name})`
					)
				end
			elseif home[id] then
				table.insert(problems, `{id} is listed in two tributaries: {home[id]} and {tr.name}`)
			else
				home[id] = tr.name
			end
		end
	end
	local sorted = table.clone(units)
	table.sort(sorted)
	for _, id in sorted do
		if not home[id] then
			table.insert(problems, `{id} is listed in no tributary`)
		end
	end
	return problems
end

-- The tributary that lists each unit id.
function tributaries.homes(list: { Tributary }): { [string]: string }
	local out: { [string]: string } = {}
	for _, tr in list do
		for _, id in tr.units do
			if out[id] == nil then
				out[id] = tr.name
			end
		end
	end
	return out
end

export type Phase = "done" | "flight" | "waiting" | "open"
export type Row = {
	name: string,
	purpose: string,
	done: number,
	inFlight: number,
	waiting: number,
	notStarted: number,
}

-- Each tributary with the four counts of its units, in file order. `phase` maps a unit id to where it stands (an id it
-- does not know, a unit of another project or one that is gone, is not counted).
function tributaries.counts(list: { Tributary }, phase: { [string]: Phase }): { Row }
	local out: { Row } = {}
	for _, tr in list do
		local row: Row =
			{ name = tr.name, purpose = tr.purpose, done = 0, inFlight = 0, waiting = 0, notStarted = 0 }
		for _, id in tr.units do
			local p = phase[id]
			if p == "done" then
				row.done += 1
			elseif p == "flight" then
				row.inFlight += 1
			elseif p == "waiting" then
				row.waiting += 1
			elseif p == "open" then
				row.notStarted += 1
			end
		end
		table.insert(out, row)
	end
	return out
end

return tributaries
