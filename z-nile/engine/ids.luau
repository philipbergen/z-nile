--!strict
-- Id rules: the next-number file, allocation by one, the compaction map and reference rewrites. Pure, no I/O.
-- See c0870.
local ids = {}

export type Space = "issue" | "raft"
export type Counters = { issue: number, raft: number }

-- The one counter for every project's ids, and the last compaction's map (c0114: both left tracker/ for z-nile/).
ids.FILE = "z-nile/next"
ids.MAP_FILE = "z-nile/compaction.txt"
-- Where they were before c0114. `tracker/next` stays as a tombstone that never parses, so an engine from before the
-- move refuses to number instead of falling back to the old rule; history readers still read the old map's commits.
ids.OLD_FILE = "tracker/next"
ids.MAP_FILES = { "z-nile/compaction.txt", "tracker/compaction.txt" }
-- What the first publish after c0114 lands writes at tracker/next when it moves the counter (publish.counterOf).
ids.TOMBSTONE =
	"moved to z-nile/next (c0114): this file never parses, so a tracker engine from before the move refuses to number\n"

local ID = "[fdcR]%d%d%d%d"

-- "issue" for f, d and c (one shared number space), "raft" for R, nil for anything else.
function ids.spaceOf(id: string): Space?
	if string.match(id, "^[fdc]%d%d%d%d$") then
		return "issue"
	elseif string.match(id, "^R%d%d%d%d$") then
		return "raft"
	end
	return nil
end

function ids.number(id: string): number
	return tonumber(string.sub(id, 2)) :: number
end

local function phraseOk(p: string): boolean
	return string.match(p, "^[a-z]+$") ~= nil
		or (string.match(p, "^[a-z][a-z%-]*[a-z]$") ~= nil and string.find(p, "--", 1, true) == nil)
end

local function counter(line: string, name: string): number?
	local n, p = string.match(line, `^{name} ([1-9]%d*) (%S+)$`)
	if not n or not p or not phraseOk(p) then
		return nil
	end
	local v = tonumber(n) :: number
	return if v <= 10000 then v else nil
end

-- The counters of a tracker/next text: exactly `issue <n> <phrase>` and `raft <n> <phrase>`, in that order, with an
-- optional final newline. n is 1..10000 without leading zeros (10000: the space is full); nil for anything else.
function ids.parse(text: string): Counters?
	local body = if string.sub(text, -1) == "\n" then string.sub(text, 1, -2) else text
	local lines = string.split(body, "\n")
	if #lines ~= 2 then
		return nil
	end
	local issue, raft = counter(lines[1], "issue"), counter(lines[2], "raft")
	if not issue or not raft then
		return nil
	end
	return { issue = issue, raft = raft }
end

-- Both lines carry one phrase, so any two writes of the file differ on both lines and conflict in git.
function ids.format(c: Counters, phrase: string): string
	return `issue {c.issue} {phrase}\nraft {c.raft} {phrase}\n`
end

function ids.highest(space: Space, list: { string }): number
	local max = 0
	for _, id in list do
		if ids.spaceOf(id) == space then
			max = math.max(max, ids.number(id))
		end
	end
	return max
end

-- The counter, unless an id in use is at or above it: a used number is never handed out.
function ids.nextFree(space: Space, c: Counters, used: { string }): number
	local n = if space == "raft" then c.raft else c.issue
	return math.max(n, ids.highest(space, used) + 1)
end

-- The compaction map: each space numbered from 1 in the order of the old numbers; a number shared by issue
-- prefixes goes c, then d, then f.
function ids.plan(list: { string }): { [string]: string }
	local map: { [string]: string } = {}
	for _, space in { "issue", "raft" } do
		local mine: { string } = {}
		for _, id in list do
			if ids.spaceOf(id) == space then
				table.insert(mine, id)
			end
		end
		table.sort(mine, function(a, b)
			local na, nb = ids.number(a), ids.number(b)
			if na ~= nb then
				return na < nb
			end
			return string.sub(a, 1, 1) < string.sub(b, 1, 1)
		end)
		for i, id in mine do
			map[id] = string.format("%s%04d", string.sub(id, 1, 1), i)
		end
	end
	return map
end

-- Every whole id token that the map names, replaced in one pass (a chain like c0100 -> c0010 -> c0001 never runs).
function ids.rewrite(text: string, map: { [string]: string }): string
	return (
		string.gsub(text, `%f[%w]({ID})%f[^%w]`, function(id: string): string
			return map[id] or id
		end)
	)
end

-- `tests/acceptance/<id>` paths that start a token (not inside `{dir}/…`, `$PWD/…` or a longer name), in one pass.
function ids.rewritePaths(text: string, map: { [string]: string }): string
	local out: { string } = {}
	local i = 1
	while true do
		local s, e, id = string.find(text, `tests/acceptance/({ID})%f[^%w]`, i)
		if not s then
			break
		end
		local at, stop = s :: number, e :: number
		local before = if at > 1 then string.sub(text, at - 1, at - 1) else ""
		local new = map[id :: string]
		table.insert(out, string.sub(text, i, at - 1))
		if new and not (before ~= "" and string.match(before, "[%w_/%.}%$%-]")) then
			table.insert(out, `tests/acceptance/{new}`)
		else
			table.insert(out, string.sub(text, at, stop))
		end
		i = stop + 1
	end
	table.insert(out, string.sub(text, i))
	return table.concat(out)
end

function ids.formatMap(map: { [string]: string }, header: string): string
	local olds: { string } = {}
	for old in map do
		table.insert(olds, old)
	end
	table.sort(olds)
	local out = { `# {header}` }
	for _, old in olds do
		table.insert(out, `{old} {map[old]}`)
	end
	return table.concat(out, "\n") .. "\n"
end

-- The map of a compaction file, or nil when a line is malformed, changes a prefix, or repeats an old or a new id.
function ids.parseMap(text: string): { [string]: string }?
	local map: { [string]: string } = {}
	local seen: { [string]: boolean } = {}
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, 1) ~= "#" then
			local old, new = string.match(line, `^({ID}) ({ID})$`)
			if not old or not new or string.sub(old, 1, 1) ~= string.sub(new, 1, 1) then
				return nil
			end
			if map[old] or seen[new] then
				return nil
			end
			map[old] = new
			seen[new] = true
		end
	end
	return map
end

return ids
