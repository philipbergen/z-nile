--!strict
-- c0114 AC1: z-nile/projects.toml lists the projects and their tracker roots, and its one parser refuses anything
-- ambiguous or out of shape (lesson architecture/parsers-refuse-ambiguity). A tree or commit without the file is a
-- tree from before c0114: exactly the legacy root `tracker`.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local function refused(text: string, needle: string)
	local reg, err = projects.parse(text)
	t.expect(reg).toBe(nil)
	t.expect(string.find(err or "", needle, 1, true) ~= nil).toBe(true)
end

local function project(name: string, root: string): string
	return `[[project]]\nname = "{name}"\nroot = "{root}"\n`
end

return t.spec("c0114 the project registry", function(it)
	it("the shipped registry lists pickman at tracker first, then z-nile at z-nile/.tracker", function()
		local reg, err = projects.parse(fs.readFile("z-nile/projects.toml"))
		t.expect(err).toBe(nil)
		local r = reg :: projects.Registry
		t.expect(r.projects).toEqual({
			{ name = "pickman", root = "tracker" },
			{ name = "z-nile", root = "z-nile/.tracker" },
		})
		t.expect(r.retired).toEqual({})
		t.expect(projects.roots(r)).toEqual({ "tracker", "z-nile/.tracker" })
	end)

	it("parses the roots in file order, and the retired ones after them for history", function()
		local text = 'retired = ["old/.tracker"]\n'
			.. project("z-nile", "z-nile/.tracker")
			.. project("pickman", "tracker")
		local reg = projects.parse(text) :: projects.Registry
		t.expect(projects.roots(reg)).toEqual({ "z-nile/.tracker", "tracker" })
		t.expect(projects.allRoots(reg)).toEqual({ "z-nile/.tracker", "tracker", "old/.tracker" })
		t.expect((projects.named(reg, "pickman") :: projects.Project).root).toBe("tracker")
		t.expect(projects.named(reg, "nope")).toBe(nil)
		t.expect((projects.projectOf(reg, "z-nile/.tracker") :: projects.Project).name).toBe("z-nile")
	end)

	it("a root is the legacy tracker or <name>/.tracker, nothing else", function()
		for _, bad in
			{
				"src",
				".",
				"..",
				"../x",
				"/abs/.tracker",
				"z-nile/tracker",
				"other/.tracker",
				"z-nile/.tracker/x",
			}
		do
			refused(project("z-nile", bad), "root must be")
		end
		refused(project("Bad_Name", "Bad_Name/.tracker"), "name")
		refused(project("a--b", "a--b/.tracker"), "name")
	end)

	it("refuses a repeated name, a repeated root, an unknown key, an empty list and bad TOML", function()
		refused(project("z-nile", "z-nile/.tracker") .. project("z-nile", "tracker"), "listed twice")
		refused(project("a", "tracker") .. project("b", "tracker"), "listed twice")
		refused('[[project]]\nname = "a"\nroot = "a/.tracker"\nextra = 1\n', "unknown key")
		refused("extra = 1\n" .. project("a", "a/.tracker"), "unknown key")
		refused("retired = []\n", "no [[project]]")
		refused('[[project]\nname = "a"\n', "not valid TOML")
		refused('retired = ["src"]\n' .. project("a", "a/.tracker"), "retired root")
		refused('retired = ["a/.tracker"]\n' .. project("a", "a/.tracker"), "both a root and retired")
	end)

	it("rootOf names the root a path lies under, by whole segments", function()
		local roots = { "tracker", "z-nile/.tracker" }
		t.expect({ projects.rootOf("z-nile/.tracker/issues/c0001/c0001.md", roots) })
			.toEqual({ "z-nile/.tracker", "issues/c0001/c0001.md" })
		t.expect({ projects.rootOf("tracker/rafts/R0001/R0001.md", roots) })
			.toEqual({ "tracker", "rafts/R0001/R0001.md" })
		t.expect((projects.rootOf("trackers/issues/c0001/c0001.md", roots))).toBe(nil)
		t.expect((projects.rootOf("z-nile/engine/main.luau", roots))).toBe(nil)
	end)

	it(
		"a commit without the registry has the legacy root alone; one with a bad registry is an error",
		function()
			local base = fixture.physical(".") :: string .. "/.cache/c0114-registry"
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			fs.writeDir(base)
			t.expect(process.exec("git", { "init", "-q", "-b", "main", base }).ok).toBe(true)
			fixture.git(base, { "config", "user.name", "c0114-registry" })
			fixture.git(base, { "config", "user.email", "c0114-registry@example.invalid" })
			fs.writeFile(`{base}/readme`, "x\n")
			fixture.git(base, { "add", "-A" })
			fixture.git(base, { "commit", "-q", "-m", "before" })
			local before = fixture.git(base, { "rev-parse", "HEAD" })
			fs.writeDir(`{base}/z-nile`)
			fs.writeFile(`{base}/z-nile/projects.toml`, "[[project]\n")
			fixture.git(base, { "add", "-A" })
			fixture.git(base, { "commit", "-q", "-m", "bad registry" })
			-- projects.at reads the commit through git in the directory it is given, the fixture
			local function at(rev: string): (projects.Registry?, string?)
				return projects.at(rev, base)
			end
			local found = at(before)
			t.expect(found ~= nil).toBe(true)
			local legacy = found :: projects.Registry
			t.expect(projects.roots(legacy)).toEqual({ "tracker" })
			local bad, why = at("HEAD")
			t.expect(bad).toBe(nil)
			t.expect(string.find(why or "", "not valid TOML", 1, true) ~= nil).toBe(true)
			fs.removeDir(base)
		end
	)
end)
