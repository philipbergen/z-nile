--!strict
-- c0114 AC1: z-nile/projects.toml lists the projects and their tracker roots, and its one parser refuses anything
-- ambiguous or out of shape (lesson architecture/parsers-refuse-ambiguity). A tree or commit without the file refuses,
-- like one with a bad file (decided with the user, 2026-10-21: "Missing also refuses"). A project's folder holds the
-- directories it is chosen from: `z-nile` for `z-nile/.tracker`; the legacy `tracker` has none.
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
	-- c0120 override: pickman moved into pickman/, its root to pickman/.tracker and its home to pickman/; tracker/ is
	-- retired, so history and the trail still read it. z-nile's home is z-nile/, and the spec runs there, so the
	-- registry is read from the checkout's top
	it(
		"the shipped registry lists pickman at pickman/.tracker first, then z-nile at z-nile/.tracker",
		function()
			local top = (
				string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
			)
			local reg, err = projects.parse(fs.readFile(`{top}/z-nile/projects.toml`))
			t.expect(err).toBe(nil)
			local r = reg :: projects.Registry
			t.expect(r.projects).toEqual({
				{ name = "pickman", root = "pickman/.tracker", home = "pickman" },
				{ name = "z-nile", root = "z-nile/.tracker", home = "z-nile" },
			})
			t.expect(r.retired).toEqual({ "tracker" })
			t.expect(projects.roots(r)).toEqual({ "pickman/.tracker", "z-nile/.tracker" })
		end
	)

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

	it("a project's folder holds the directories it is chosen from; the legacy root has none", function()
		local reg =
			projects.parse(project("pickman", "tracker") .. project("z-nile", "z-nile/.tracker")) :: projects.Registry
		t.expect(projects.folderOf("z-nile/.tracker")).toBe("z-nile")
		t.expect(projects.folderOf("tracker")).toBe(nil)
		local function at(dir: string): string?
			local p = projects.inDir(reg, dir)
			return if p then p.name else nil
		end
		t.expect(at("z-nile")).toBe("z-nile")
		t.expect(at("z-nile/engine")).toBe("z-nile")
		t.expect(at("z-nile/.tracker/issues")).toBe("z-nile")
		t.expect(at("")).toBe(nil) -- the checkout's root
		t.expect(at("tracker")).toBe(nil) -- pickman has no folder until c0120
		t.expect(at("src")).toBe(nil)
		t.expect(at("z-nile-old")).toBe(nil) -- by whole segments
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

	it("a tree or commit without the registry is an error, like one with a bad registry", function()
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
		-- the working tree without the file refuses too, and so does one whose file does not parse
		local okMissing, errMissing = pcall(projects.load, base, true)
		t.expect(okMissing).toBe(false)
		t.expect(string.find(tostring(errMissing), "no z-nile/projects.toml", 1, true) ~= nil).toBe(true)
		-- and every command that reads the items refuses there instead of scanning a guessed root (list, audit's scan,
		-- offline numbering; remap reads the items through the same scan, after it fetches origin)
		fs.writeDir(`{base}/tracker/issues/c0010`)
		fs.writeFile(`{base}/tracker/issues/c0010/c0010.md`, "---\nid: c0010\nslug: s\n---\n")
		fixture.git(base, { "add", "-A" })
		fixture.git(base, { "commit", "-q", "-m", "an item" }) -- remap needs a clean tree before it reads anything
		for _, args in { { "list" }, { "audit" }, { "new", "issue", "c", "offline", "--project", "pickman" } } do
			-- c0120 override: the engine is the checkout's, read from its top (this spec runs from z-nile/)
			local top = (
				string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
			)
			local all = { "run", `{top}/z-nile/engine/main`, "--" }
			for _, a in args do
				table.insert(all, a)
			end
			local r = process.exec("lune", all, { cwd = base, env = { PICKMAN_PUBLISH = "0" } })
			t.expect(r.ok).toBe(false)
			if not string.find(r.stdout .. r.stderr, "projects.toml", 1, true) then
				error(`{table.concat(args, " ")} did not refuse for the registry: {r.stdout}{r.stderr}`)
			end
		end
		fixture.git(base, { "rm", "-q", "-r", "tracker" })
		fs.writeDir(`{base}/z-nile`)
		fs.writeFile(`{base}/z-nile/projects.toml`, "[[project]\n")
		fixture.git(base, { "add", "-A" })
		fixture.git(base, { "commit", "-q", "-m", "bad registry" })
		-- projects.at reads the commit through git in the directory it is given, the fixture
		local function at(rev: string): (projects.Registry?, string?)
			return projects.at(rev, base)
		end
		local none, whyNone = at(before)
		t.expect(none).toBe(nil)
		t.expect(string.find(whyNone or "", "has no z-nile/projects.toml", 1, true) ~= nil).toBe(true)
		local bad, why = at("HEAD")
		t.expect(bad).toBe(nil)
		t.expect(string.find(why or "", "not valid TOML", 1, true) ~= nil).toBe(true)
		local okBad = pcall(projects.load, base, true)
		t.expect(okBad).toBe(false)
		fs.removeDir(base)
	end)
end)
