--!strict
-- What a run clears out of the images folder before any spec starts (c0178). Run once, by the launcher, under the run's
-- lock: nothing in the run is using an image yet, which is the only time removing one is safe (design review 002 F1).
-- Images of a kind beyond the newest `keep` that are older than `minAge` go, and so do build folders and locks older than
-- `minAge`. The kind is the whole id minus its 24-hex key, so "seed" never matches "seed-nolessons".
local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local process = require("@lune/process")

local pruning = {}

local KEY_LENGTH = 24

local function age(path: string): number
	local ok, meta = pcall(fs.metadata, path)
	if not ok or meta.modifiedAt == nil then
		return 0
	end
	return DateTime.now().unixTimestamp - (meta.modifiedAt :: any).unixTimestamp
end

-- Returns how many folders it removed.
-- The images folder of the run's current folder (a project's home): <home>/.cache/images, from the kernel's own path. The one
-- place that decides where images live; images.dir() and the launcher's prune both read it.
function pruning.dir(): string
	return `{string.gsub(process.cwd, "/+$", "")}/.cache/images`
end

function pruning.run(home: string, keep: number?, minAge: number?): number
	if not fs.isDir(home) then
		return 0
	end
	local keepN, old = keep or 2, minAge or 3600
	local kinds: { [string]: { { path: string, age: number } } } = {}
	local removed = 0
	for _, entry in fs.readDir(home) do
		local path = `{home}/{entry}`
		local name, key = string.match(entry, "^(.+)%-(%x+)$")
		if name ~= nil and key ~= nil and #key == KEY_LENGTH then
			local list = kinds[name] or {}
			table.insert(list, { path = path, age = age(path) })
			kinds[name] = list
		elseif
			(string.sub(entry, 1, 7) == ".build." or string.find(entry, ".lock", 1, true) ~= nil)
			and age(path) > old
		then
			if pcall(fs.removeDir, path) then
				removed += 1
			end
		end
	end
	for _, list in kinds do
		table.sort(list, function(a, b)
			return a.age < b.age -- newest first
		end)
		for i = keepN + 1, #list do
			if list[i].age > old and pcall(fs.removeDir, list[i].path) then
				removed += 1
			end
		end
	end
	return removed
end

return pruning
