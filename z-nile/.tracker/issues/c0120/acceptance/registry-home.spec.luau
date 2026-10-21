--!strict
-- c0120 AC1: z-nile/projects.toml gives every project a home, the folder its check.sh files and specs run in:
-- pickman's is pickman/ (root pickman/.tracker), z-nile's the repository root; tracker/ is retired. A home is "." or
-- the project's own name, and a home other than "." holds the project's root. `z-nile/roots --projects` prints it for
-- shell callers (ac.sh, the gate), so neither parses the file itself.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local function entry(name: string, root: string, home: string?): string
	local h = if home then `home = "{home}"\n` else ""
	return `[[project]]\nname = "{name}"\nroot = "{root}"\n{h}`
end

local function refused(text: string, needle: string)
	local reg, err = projects.parse(text)
	t.expect(reg).toBe(nil)
	t.expect(string.find(err or "", needle, 1, true) ~= nil).toBe(true)
end

return t.spec("c0120 every project has a home", function(it)
	it(
		"the shipped registry: pickman at pickman/.tracker with home pickman, z-nile at the root, tracker retired",
		function()
			local reg, err = projects.parse(fs.readFile("z-nile/projects.toml"))
			t.expect(err).toBe(nil)
			local r = reg :: projects.Registry
			t.expect(r.projects).toEqual({
				{ name = "pickman", root = "pickman/.tracker", home = "pickman" },
				{ name = "z-nile", root = "z-nile/.tracker", home = "." },
			})
			t.expect(r.retired).toEqual({ "tracker" })
			t.expect(projects.allRoots(r)).toEqual({ "pickman/.tracker", "z-nile/.tracker", "tracker" })
		end
	)

	it(
		"a project without a home key has the root's, and the legacy registry is one project at the root",
		function()
			local reg = projects.parse(entry("z-nile", "z-nile/.tracker")) :: projects.Registry
			t.expect(reg.projects[1].home).toBe(".")
			t.expect(projects.legacy().projects)
				.toEqual({ { name = "pickman", root = "tracker", home = "." } })
		end
	)

	it(
		"a home is the root or the project's own folder, and a folder home holds the project's root",
		function()
			refused(entry("pickman", "pickman/.tracker", "src"), `pickman's home must be "." or "pickman"`)
			refused(entry("pickman", "pickman/.tracker", "z-nile"), `pickman's home must be "." or "pickman"`)
			refused(
				entry("pickman", "pickman/.tracker", "pickman/"),
				`pickman's home must be "." or "pickman"`
			)
			refused(entry("pickman", "pickman/.tracker", ".."), `pickman's home must be "." or "pickman"`)
			refused(
				entry("pickman", "tracker", "pickman"),
				"pickman's home pickman needs the root pickman/.tracker"
			)
			refused('[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\nhome = 1\n', "home must be")
			-- and the root home is valid with either root shape
			t.expect(projects.parse(entry("pickman", "pickman/.tracker", ".")) ~= nil).toBe(true)
			t.expect(projects.parse(entry("pickman", "tracker", ".")) ~= nil).toBe(true)
		end
	)

	it(
		"homeOf gives the home of the project whose current root holds a path, and the root otherwise",
		function()
			local reg = projects.parse(
				'retired = ["tracker"]\n'
					.. entry("pickman", "pickman/.tracker", "pickman")
					.. entry("z-nile", "z-nile/.tracker")
			) :: projects.Registry
			t.expect(projects.homeOf(reg, "pickman/.tracker/issues/f0001/check.sh")).toBe("pickman")
			t.expect(projects.homeOf(reg, "pickman/.tracker/rafts/done/R0001")).toBe("pickman")
			t.expect(projects.homeOf(reg, "z-nile/.tracker/issues/c0001/check.sh")).toBe(".")
			-- a retired root, a look-alike prefix and a loose file are the root's
			t.expect(projects.homeOf(reg, "tracker/issues/f0001/check.sh")).toBe(".")
			t.expect(projects.homeOf(reg, "pickman/.trackerx/issues/f0001/check.sh")).toBe(".")
			t.expect(projects.homeOf(reg, "pickman/src/x.luau")).toBe(".")
		end
	)

	it("every project's promoted specs live in its home's tests/acceptance, once each", function()
		local reg = projects.parse(
			entry("pickman", "pickman/.tracker", "pickman")
				.. entry("z-nile", "z-nile/.tracker")
				.. entry("other", "other/.tracker")
		) :: projects.Registry
		t.expect(projects.acceptanceRoots(reg)).toEqual({ "pickman/tests/acceptance", "tests/acceptance" })
	end)

	it(
		"z-nile/roots --projects prints name, home and root per project, tab-separated, in registry order",
		function()
			local r = process.exec("lune", { "run", "z-nile/roots", "--", "--projects" })
			t.expect(r.ok).toBe(true)
			t.expect(r.stdout).toBe("pickman\tpickman\tpickman/.tracker\nz-nile\t.\tz-nile/.tracker\n")
		end
	)
end)
