--!strict
-- Removes `path` and everything under it. While removal fails because the tree changed underneath (another process still
-- writing: an error mentioning "not empty" or "No such file"), retries every 50 ms for up to `seconds` (default 3).
-- On final failure raises "could not remove <path> after <n> tries: <error>; left: <up to 20 relative paths>", listed
-- breadth-first (shallowest first) and sorted within each directory, so the order is the same on APFS and ext4.
-- After a race it always retries at least once, even when the first attempt alone used up the bound.
-- A missing path succeeds. Any other error is raised at once. `remove` (default fs.removeDir) is the seam the spec uses
-- to race deterministically.
local fs = require("@lune/fs")
local task = require("@lune/task")

local cleanup = {}

local POLL = 0.05
local MAX_LISTED = 20

local function isRace(err: string): boolean
	local lower = string.lower(err)
	return string.find(lower, "not empty", 1, true) ~= nil
		or string.find(lower, "no such file", 1, true) ~= nil
end

local function exists(path: string): boolean
	return fs.isDir(path) or fs.isFile(path)
end

-- Up to MAX_LISTED paths under `path`, relative to it: shallowest first, sorted within each directory.
local function leftBehind(path: string): { string }
	local out: { string } = {}
	local queue: { string } = { "" }
	local head = 1
	while head <= #queue and #out < MAX_LISTED do
		local rel = queue[head]
		head += 1
		local dir = if rel == "" then path else `{path}/{rel}`
		local ok, names = pcall(fs.readDir, dir)
		if ok then
			local sorted: { string } = table.clone(names)
			table.sort(sorted)
			for _, name in sorted do
				if #out >= MAX_LISTED then
					break
				end
				local childRel = if rel == "" then name else `{rel}/{name}`
				table.insert(out, childRel)
				if fs.isDir(`{path}/{childRel}`) then
					table.insert(queue, childRel)
				end
			end
		end
	end
	return out
end

-- Returns nothing; typed `...any` so `local ok, err = pcall(cleanup.removeTree, …)` type-checks (a `()` return gives
-- pcall a single result).
function cleanup.removeTree(path: string, seconds: number?, remove: ((string) -> ())?): ...any
	local doRemove: (string) -> () = remove or fs.removeDir
	local bound = seconds or 3
	if not exists(path) then
		return
	end
	local started = os.clock()
	local tries = 0
	while true do
		tries += 1
		local ok, err = pcall(function()
			doRemove(path)
		end)
		if ok then
			return
		end
		local message = tostring(err)
		if not exists(path) then
			return -- the tree vanished under us: that is the goal
		end
		if not isRace(message) then
			error(err, 0)
		end
		-- always at least one retry after a race, whatever the first attempt cost
		if tries >= 2 and os.clock() - started >= bound then
			error(
				`could not remove {path} after {tries} tries: {message}; left: {table.concat(
					leftBehind(path),
					", "
				)}`,
				0
			)
		end
		task.wait(POLL)
	end
end

return cleanup
