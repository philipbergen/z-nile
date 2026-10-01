--!strict
-- c0470: specs may run concurrently, so no two spec files may own the same `.cache/<dir>` fixture
-- directory. Only tests/ is scanned (sequestered prep specs under tracker/ join the scan when
-- `tracker.sh done` promotes them, which is where a collision is caught). A literal mention counts as
-- use. (`.cache/sim` is the sim library's replay directory: its files are named per model,
-- seed and tick, and are only written when a simulation fails. Model names are not unique across
-- spec files, so a collision is possible in principle; it would only rewrite a replay file, never
-- change a result. That is why it is exempt.)
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local PATTERN = "%." .. "cache/([%w_%-]+)" -- built by concatenation so this file never matches itself
local SHARED_BY_DESIGN: { [string]: boolean } = { sim = true }

-- returns "<dir> used by <fileA>, <fileB>" lines, sorted, for every non-exempt dir used by 2+ files
local function sharedDirs(texts: { [string]: string }): { string }
	local users: { [string]: { [string]: boolean } } = {}
	for path, text in texts do
		for dir in string.gmatch(text, PATTERN) do
			if not SHARED_BY_DESIGN[dir] then
				users[dir] = users[dir] or {}
				users[dir][path] = true
			end
		end
	end
	local out = {}
	for dir, files in users do
		local list = {}
		for f in files do
			table.insert(list, f)
		end
		if #list > 1 then
			table.sort(list)
			table.insert(out, `{dir} used by {table.concat(list, ", ")}`)
		end
	end
	table.sort(out)
	return out
end

local function collect(dir: string, texts: { [string]: string })
	if not fs.isDir(dir) then
		return
	end
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path, texts)
		elseif string.match(name, "%.spec%.luau$") then
			texts[path] = fs.readFile(path)
		end
	end
end

local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end

return t.spec("spec fixture directories are not shared", function(it)
	it("the scanner reports a directory used by two files", function()
		local found = sharedDirs({
			["tests/a.spec.luau"] = 'local d = ".' .. 'cache/shared"',
			["tests/b.spec.luau"] = 'local d = ".' .. 'cache/shared/sub"',
			["tests/c.spec.luau"] = 'local d = ".' .. 'cache/own"',
		})
		t.expect(found).toEqual({ "shared used by tests/a.spec.luau, tests/b.spec.luau" })
	end)

	it("the scanner ignores a directory named twice in one file, and the sim replay directory", function()
		local found = sharedDirs({
			["tests/a.spec.luau"] = '".' .. 'cache/own" and ".' .. 'cache/own/x" and ".' .. 'cache/sim"',
			["tests/b.spec.luau"] = '".' .. 'cache/sim"',
		})
		t.expect(found).toEqual({})
	end)

	it("treats board and board-unit as different directories", function()
		local found = sharedDirs({
			["tests/a.spec.luau"] = '".' .. 'cache/board"',
			["tests/b.spec.luau"] = '".' .. 'cache/board-unit"',
		})
		t.expect(found).toEqual({})
	end)

	it("no two spec files in the repo share a fixture directory", function()
		local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
		local texts: { [string]: string } = {}
		collect(`{root}/tests`, texts)
		-- a string, so a failure names the colliding directories and files
		t.expect(table.concat(sharedDirs(texts), "\n")).toBe("")
	end)
end)
