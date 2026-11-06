--!strict
-- c0185 AC2, AC3: the selector on the real tree, in rule form (every registered project with a place, never today's list).
-- Any Rojo project file of a home forces that home's full run; a change in the library's source selects the place spec of every
-- home that maps it, and, with --project, that home's alone. Read-only: it runs z-nile/affected from the checkout's top, as the
-- gate does, on named paths (a path need not exist to be a change).
local fs = require("@lune/fs")
local home = require("@tests/lib/home")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function affected(args: { string }): { string }
	local argv = { "run", "z-nile/affected", "--", "--graph-only" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv, { cwd = TOP })
	if not r.ok then
		error(`z-nile/affected {table.concat(args, " ")} failed: {r.stderr}`)
	end
	local out: { string } = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

-- the registered projects whose home has a place tier (tests/lib/place.luau), z-nile and the library apart
local function placeHomes(): { projects.Project }
	local out: { projects.Project } = {}
	for _, p in projects.load(TOP).projects do
		if p.name ~= "z-nile" and p.home ~= "." and fs.isFile(`{TOP}/{p.home}/tests/lib/place.luau`) then
			table.insert(out, p)
		end
	end
	return out
end

return t.spec("c0185 the selector follows the library and every project file", function(it)
	it("AC2: any Rojo project file of a home forces that home's full run, and none of another's", function()
		local homes = placeHomes()
		t.expect(#homes > 1).toBe(true)
		for _, p in homes do
			for _, file in { "default.project.json", "other.project.json", "lobby.project.json" } do
				t.expect(affected({ "--project", p.name, `{p.home}/{file}` })).toEqual({ "ALL" })
			end
		end
		-- (each of these builds the require graph, so they run for one home)
		local first = homes[1]
		-- a project file in a sub-folder is no place of the home; another project is not forced
		t.expect(#affected({ "--project", first.name, `{first.home}/sub/x.project.json` })).toBe(0)
		t.expect(affected({ "--project", "z-nile", `{first.home}/other.project.json` })).toEqual({})
	end)

	it("AC3: a change in the library's source selects the place spec of every home that maps it", function()
		local library = home.LIBRARY_HOME
		local all = affected({ `{library}/src/shared/Logic/Nope/init.luau` })
		local server = affected({ `{library}/src/server/Nope.luau` })
		local homes = placeHomes()
		t.expect(#homes > 1).toBe(true)
		for _, p in homes do
			local spec = `{p.home}/tests/place/library.spec.luau`
			t.expect(table.find(all, spec) ~= nil).toBe(true)
			t.expect(table.find(server, spec) ~= nil).toBe(true)
		end
		-- --project: that home's selection alone, relative to its home
		local first = homes[1]
		local own = affected({ "--project", first.name, `{library}/src/shared/Logic/Nope/init.luau` })
		t.expect(table.find(own, "tests/place/library.spec.luau") ~= nil).toBe(true)
		for _, line in own do
			t.expect(string.sub(line, 1, #first.home + 1) == `{first.home}/`).toBe(false)
		end
		-- a change in the library's tests is in no place
		local tests = affected({ `{library}/tests/unit/Nope/nope.spec.luau` })
		for _, p in homes do
			t.expect(table.find(tests, `{p.home}/tests/place/library.spec.luau`) == nil).toBe(true)
		end
	end)
end)
