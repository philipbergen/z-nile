--!strict
-- The watch map on the real tree. A path named by one watch file selects the specs that file covers and no
-- other ticket's. A skill, a lesson and a tracker document select nothing. Never "ALL".
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")
local watch = require("@znile/lib/watch")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function affected(args: { string }): { string }
	local argv = { "run", "z-nile/affected", "--" }
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

local function reader(): watch.Reader
	return {
		isDir = function(path: string): boolean
			return fs.isDir(`{TOP}/{path}`)
		end,
		isFile = function(path: string): boolean
			return fs.isFile(`{TOP}/{path}`)
		end,
		readDir = function(path: string): { string }
			return fs.readDir(`{TOP}/{path}`)
		end,
		readFile = function(path: string): string
			return fs.readFile(`{TOP}/{path}`)
		end,
	}
end

return t.spec("c0185 the watch map selects one ticket", function(it)
	it("a path named by one watch file selects that file's specs and no other", function()
		local bindings: { [string]: { string } } = {}
		local r = reader()
		for _, p in projects.load(TOP).projects do
			if p.home ~= "." then
				local found, problems = watch.collect(r, `{p.home}/`)
				t.expect(table.concat(problems, "\n")).toBe("")
				for spec, paths in found do
					bindings[spec] = paths
				end
			end
		end
		local byPath: { [string]: { string } } = {}
		for spec, paths in bindings do
			for _, path in paths do
				local list = byPath[path]
				if not list then
					list = {}
					byPath[path] = list
				end
				table.insert(list, spec)
			end
		end
		local chosen: string? = nil
		local want: { string } = {}
		for path, specs in byPath do
			table.sort(specs)
			local file = watch.fileFor(specs[1])
			local sole = true
			for _, spec in specs do
				if watch.fileFor(spec) ~= file then
					sole = false
				end
			end
			if sole and fs.isFile(`{TOP}/{path}`) then
				chosen = path
				want = specs
				break
			end
		end
		t.expect(chosen ~= nil).toBe(true)
		t.expect(affected({ chosen :: string })).toEqual(want)
	end)

	it("a skill, a lesson and a tracker document select nothing, and a project file is not ALL", function()
		t.expect(affected({ "z-nile/skills/zz-test/SKILL.md" })).toEqual({})
		t.expect(affected({ "z-nile/skills/zz-test/lessons/no-such-lesson.md" })).toEqual({})
		t.expect(affected({ "pickman/.tracker/issues/c0001/c0001.md" })).toEqual({})
		local project = affected({ "pickman/default.project.json" })
		t.expect(table.find(project, "ALL") == nil).toBe(true)
	end)
end)
