--!strict
-- Fixtures a passing spec file removes (c0178): a helper that makes a folder for a spec registers it here, and the
-- runner sweeps the registered folders when every case of the file passed. A file with a failing case keeps its
-- folders to look at. Only folders strictly inside the home's .cache are registered, and never an image.
local cleanup = require("@tests/lib/cleanup")
local process = require("@lune/process")

local swept = {}

local registered: { string } = {}

-- <home>/.cache/ for the run's current folder (the kernel's, so symlinks are resolved), without starting a process.
local function cache(): string
	return `{string.gsub(process.cwd, "/+$", "")}/.cache/`
end

-- The first segment of a path inside the home's .cache that is never a fixture: the images, the runner's own state and
-- anything hidden (the fence's sentinel, c0194's .tmp).
local OWN = { images = true, ["tests-run.lock"] = true, ["spec-durations.tsv"] = true }

-- Registers `path`, an absolute folder strictly inside the home's .cache. Raises, naming it, for anything else: a path
-- with an empty, "." or ".." segment, one whose first segment under .cache is hidden, an image folder or a runner file.
function swept.register(path: string)
	local root = cache()
	local bad = string.sub(path, 1, #root) ~= root or #path == #root
	if not bad then
		local first = true
		for segment in string.gmatch(string.sub(path, #root + 1) .. "/", "([^/]*)/") do
			if
				segment == ""
				or segment == "."
				or segment == ".."
				or (first and (OWN[string.lower(segment)] or string.sub(segment, 1, 1) == "."))
			then
				bad = true
			end
			first = false
		end
	end
	if bad then
		error(
			`swept: {path} is not a folder inside {root} (a fixture's own, not an image, a hidden or a runner file): refusing to register it`,
			2
		)
	end
	table.insert(registered, path)
end

-- The folders waiting to be swept, in registration order.
function swept.pending(): { string }
	return table.clone(registered)
end

-- Removes every registered folder (one already gone is fine) and forgets them. Returns how many it removed and, for each
-- folder it could not remove, "<path>: <error>" (a process still writing into it, say): the caller shows those.
function swept.sweep(): (number, { string })
	local n, failed = 0, {}
	for _, path in registered do
		local ok, err = pcall(cleanup.removeTree, path)
		if ok then
			n += 1
		else
			table.insert(failed, `{path}: {err}`)
		end
	end
	table.clear(registered)
	return n, failed
end

return swept
