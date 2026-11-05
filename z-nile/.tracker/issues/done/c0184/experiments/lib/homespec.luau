--!strict
-- The home rule for the project whose home is the current folder (c0184): each home's tests/meta/home.spec.luau
-- returns this, so `cd <home> && lune run tests/run` checks the scaffold of that home, pickman's included, and a change to
-- the home selects it. Fixtures and the registry walk are the promoted homes.spec's.
local home = require("./home")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local FOLDER = string.match(HERE, "([^/]+)$") :: string

-- the registry from its shell reader (name, home and root per line), so that no engine file is required
local out = process.exec("lune", { "run", "z-nile/roots", "--", "--projects" }, { cwd = TOP })
if not out.ok then
	error(`homespec: z-nile/roots --projects failed: {out.stderr}`)
end
local reg: home.Registry = { projects = {} }
local mine: home.Project? = nil
for line in string.gmatch(out.stdout, "[^\n]+") do
	local name, folder, root = string.match(line, "^([^\t]+)\t([^\t]+)\t([^\t]+)$")
	if name and folder and root then
		local p: home.Project = { name = name, home = folder, root = root }
		table.insert(reg.projects, p)
		if folder == FOLDER then
			mine = p
		end
	end
end
if not mine then
	error(`homespec: {HERE} is no project's home in z-nile/projects.toml`)
end
local project = mine :: home.Project

return t.spec(`{project.name} has the home scaffold`, function(it)
	it("has every file and setting of the home scaffold (z-nile/README.md, A project's home)", function()
		local found, checked = home.problems(TOP, reg, project.name)
		t.expect(table.concat(found, "\n")).toBe("")
		t.expect(checked).toEqual({ project.name })
	end)
end)
