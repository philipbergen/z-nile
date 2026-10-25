--!strict
-- Claim stamps (R0025 review 004 F1, review 005 F1): `stop` gives back exactly the issues carrying a raft's claim
-- stamp, so a new claim must carry a value no item on origin/main already has, done/ included.
local process = require("@lune/process")

local claims = {}

-- Whether any tracker document on `ref` (default origin/main), in the repository at `cwd`, under any of `roots` (every
-- project root of that ref's registry, c0114; no default: the caller names them), has the line `status: <value>`. True or false, or nil and git's message
-- when the question could not be answered: the caller refuses then, never guesses. One `git grep` (exit 0: found, 1:
-- not found, anything else: an error).
function claims.taken(cwd: string, value: string, ref: string?, roots: { string }): (boolean?, string?)
	if not string.match(value, "^[%a%-]+$") then
		return nil, `not a stamp: {value}`
	end
	local within: { string } = roots
	if #within == 0 then
		return nil, "no project roots to search"
	end
	local args = { "grep", "-q", "-E", `^status: {value}$`, ref or "origin/main", "--" }
	for _, r in within do
		table.insert(args, r .. "/")
	end
	local r = process.exec("git", args, { cwd = cwd })
	if r.code == 0 then
		return true, nil
	elseif r.code == 1 then
		return false, nil
	end
	return nil, (string.gsub(r.stderr .. r.stdout, "%s+$", ""))
end

-- c0116: the tracker documents on `ref` (default origin/main) under `roots` whose status line is `status: <value>`:
-- every item one claim stamped (`release` gives them back together). nil and git's message when it can't tell.
function claims.carriers(cwd: string, value: string, ref: string?, roots: { string }): ({ string }?, string?)
	if not string.match(value, "^[%a%-]+$") then
		return nil, `not a stamp: {value}`
	end
	if #roots == 0 then
		return nil, "no project roots to search"
	end
	local at = ref or "origin/main"
	local args = { "grep", "-l", "-E", `^status: {value}$`, at, "--" }
	for _, r in roots do
		table.insert(args, r .. "/")
	end
	local r = process.exec("git", args, { cwd = cwd })
	if r.code == 1 then
		return {}, nil
	elseif r.code ~= 0 then
		return nil, (string.gsub(r.stderr .. r.stdout, "%s+$", ""))
	end
	local out: { string } = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		-- git grep prints `<ref>:<path>`
		table.insert(out, string.sub(line, #at + 2))
	end
	table.sort(out)
	return out, nil
end

return claims
