--!strict
local process = require("@lune/process")

local clone = {}

-- `git clone --no-hardlinks`: a plain local clone hardlinks the object files of `source`, so the
-- throwaway copy would share inodes with the real object store. Raises if the clone fails; returns
-- `dest` (so `pcall(clone.isolated, …)` has a typed second result in strict mode).
function clone.isolated(source: string, dest: string): string
	local r = process.exec("git", { "clone", "-q", "--no-hardlinks", source, dest })
	if not r.ok then
		error(`git clone of {source} into {dest} failed ({r.code}): {r.stderr}`, 2)
	end
	return dest
end

return clone
