--!strict
-- c0120 AC1: z-nile/projects.toml gives pickman the root pickman/.tracker and z-nile the root z-nile/.tracker, with
-- tracker/ retired. A project's home is the folder that holds its root (decided with the user, 2026-10-21: "z-nile/ is
-- its home"; the root belongs to no project), so the registry has no home key: pickman's is pickman/, z-nile's z-nile/.
-- `z-nile/roots --projects` prints name, home and root for shell callers (ac.sh, the gate, CI), so none parses the file.
-- These specs run from z-nile/, the tooling's home: the checkout's files are read from its top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function entry(name: string, root: string, extra: string?): string
	return `[[project]]\nname = "{name}"\nroot = "{root}"\n{extra or ""}`
end

local function refused(text: string, needle: string)
	local reg, err = projects.parse(text)
	t.expect(reg).toBe(nil)
	t.expect(string.find(err or "", needle, 1, true) ~= nil).toBe(true)
end

return t.spec("c0120 every project's home is the folder holding its root", function(it)
	it(
		"the shipped registry: pickman at pickman/.tracker, z-nile at z-nile/.tracker, tracker retired",
		function()
			local reg, err = projects.parse(fs.readFile(`{TOP}/z-nile/projects.toml`))
			t.expect(err).toBe(nil)
			local r = reg :: projects.Registry
			-- c0183 override: the rule, not today's list (more projects follow the first two)
			t.expect(r.projects[1]).toEqual({ name = "pickman", root = "pickman/.tracker", home = "pickman" })
			t.expect(r.projects[2]).toEqual({ name = "z-nile", root = "z-nile/.tracker", home = "z-nile" })
			local rootsInOrder: { string } = {}
			for _, p in r.projects do
				t.expect(p).toEqual({ name = p.name, root = `{p.name}/.tracker`, home = p.name })
				table.insert(rootsInOrder, p.root)
			end
			t.expect(r.retired).toEqual({ "tracker" })
			table.insert(rootsInOrder, "tracker")
			t.expect(projects.allRoots(r)).toEqual(rootsInOrder)
			-- no project's home is the repository root
			for _, p in r.projects do
				t.expect(p.home ~= ".").toBe(true)
			end
		end
	)

	it(
		"a home is never written: the key is unknown, and a root must be its project's <name>/.tracker",
		function()
			refused(entry("pickman", "pickman/.tracker", 'home = "pickman"\n'), "unknown key home")
			refused(entry("pickman", "other/.tracker"), `pickman's root must be`)
			-- the home follows the root
			local reg = projects.parse(entry("other", "other/.tracker")) :: projects.Registry
			t.expect(reg.projects[1].home).toBe("other")
		end
	)

	it(
		"homeOf gives the home of the project whose current root holds a path, and the root otherwise",
		function()
			local reg = projects.parse(
				'retired = ["tracker"]\n'
					.. entry("pickman", "pickman/.tracker")
					.. entry("z-nile", "z-nile/.tracker")
			) :: projects.Registry
			t.expect(projects.homeOf(reg, "pickman/.tracker/issues/f0001/check.sh")).toBe("pickman")
			t.expect(projects.homeOf(reg, "pickman/.tracker/rafts/done/R0001")).toBe("pickman")
			t.expect(projects.homeOf(reg, "z-nile/.tracker/issues/c0001/check.sh")).toBe("z-nile")
			-- a retired root, a look-alike prefix and a loose file are under no current root
			t.expect(projects.homeOf(reg, "tracker/issues/f0001/check.sh")).toBe(".")
			t.expect(projects.homeOf(reg, "pickman/.trackerx/issues/f0001/check.sh")).toBe(".")
			t.expect(projects.homeOf(reg, "pickman/src/x.luau")).toBe(".")
		end
	)

	it(
		"every project's promoted specs live in its home's tests/acceptance, once each, in registry order",
		function()
			local reg = projects.parse(
				entry("pickman", "pickman/.tracker")
					.. entry("z-nile", "z-nile/.tracker")
					.. entry("other", "other/.tracker")
			) :: projects.Registry
			t.expect(projects.acceptanceRoots(reg))
				.toEqual({ "pickman/tests/acceptance", "z-nile/tests/acceptance", "other/tests/acceptance" })
		end
	)

	it(
		"z-nile/roots --projects prints name, home and root per project, tab-separated, in registry order",
		function()
			local r = process.exec("lune", { "run", "z-nile/roots", "--", "--projects" }, { cwd = TOP })
			t.expect(r.ok).toBe(true)
			-- c0183 override: one line per registered project, in registry order, derived from the registry
			local reg = projects.parse(fs.readFile(`{TOP}/z-nile/projects.toml`)) :: projects.Registry
			local want = ""
			for _, p in reg.projects do
				want ..= `{p.name}\t{p.home}\t{p.root}\n`
			end
			t.expect(r.stdout).toBe(want)
		end
	)
end)
