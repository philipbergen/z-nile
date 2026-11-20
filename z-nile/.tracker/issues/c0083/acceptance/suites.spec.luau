--!strict
-- c0083 AC1, AC2, AC5 and AC9 (the pure part): the two suites. The harness suite is z-nile's home (the tooling's
-- specs), the game suite is every game project's. A path's suite is its location (a game home's files the game's,
-- every other path the harness's, a tracker document none): `suites.changed` names the suites a change touches,
-- `suites.projects` a suite's projects, `suites.crossings` the paths a spec's watch list names outside its own suite,
-- and promotion routes an item's acceptance specs by its project. Plain tables; the registry, the watch module's own
-- rule and the real tree's watch files are the only other inputs.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local select = require("@znile/lib/select")
local suites = require("@znile/lib/suites")
local t = require("@tests/lib/t")
local watch = require("@znile/lib/watch")

-- the checkout's top: these specs run from z-nile/, and the registry is read from the top
local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local rules: select.Rules = {
	homes = {
		{ name = "pickman", prefix = "pickman/" },
		{ name = "z-nile", prefix = "z-nile/" },
		{ name = "arcade", prefix = "arcade/" },
	},
	roots = { "pickman/.tracker", "z-nile/.tracker", "arcade/.tracker" },
}

local function changed(paths: { string }): { string }
	return suites.changed(rules, paths)
end

return t.spec("c0083 suites", function(it)
	it("AC1: z-nile is the harness suite, each game project is the game suite", function()
		t.expect(suites.of("z-nile")).toBe("harness")
		for _, name in { "pickman", "arcade", "portal", "snake", "invaders", "asteroids" } do
			t.expect(suites.of(name)).toBe("game")
			t.expect(table.find(suites.GAME, name) ~= nil).toBe(true)
		end
		for _, name in suites.GAME do
			t.expect(#watch.forSuite("pickman/tests/unit/s.spec.luau", { `{name}/x.luau` })).toBe(1)
		end
	end)

	it(
		"AC1: a project no list names is the harness suite, so tooling added later is never skipped as a game",
		function()
			t.expect(suites.of("z-nile-omarchy")).toBe("harness")
			t.expect(suites.of("")).toBe("harness")
		end
	)

	it(
		"AC1: projects(which) is one suite's projects in the registry's order, and all keeps every one",
		function()
			local names = { "pickman", "z-nile", "arcade", "snake" }
			t.expect(suites.projects(names, "game")).toEqual({ "pickman", "arcade", "snake" })
			t.expect(suites.projects(names, "harness")).toEqual({ "z-nile" })
			t.expect(suites.projects(names, "all")).toEqual(names)
			t.expect(suites.projects({ "z-nile" }, "game")).toEqual({})
		end
	)

	it(
		"AC1: a path under a game home touches the game suite alone, a path under z-nile the harness alone",
		function()
			t.expect(changed({ "pickman/src/shared/Logic/Game/init.luau" })).toEqual({ "game" })
			t.expect(changed({ "arcade/src/shared/Logic/X.luau" })).toEqual({ "game" })
			t.expect(changed({ "z-nile/engine/main.luau" })).toEqual({ "harness" })
			t.expect(changed({ "z-nile/tests/tooling/a.spec.luau" })).toEqual({ "harness" })
		end
	)

	it(
		"AC1: a path inside a game home that forces that project (its project file, its runner) is still the game's",
		function()
			t.expect(changed({ "pickman/default.project.json" })).toEqual({ "game" })
			t.expect(changed({ "pickman/tests/run.luau" })).toEqual({ "game" })
			t.expect(changed({ "z-nile/check.sh" })).toEqual({ "harness" })
		end
	)

	it(
		"AC1: a path under no home (zn, the root's scripts/ and configs, .github, LICENSE, a document) touches the harness, wherever it sits in the list",
		function()
			for _, p in
				{
					"zn",
					"scripts/check.sh",
					"scripts/hooks/pre-bash.sh",
					".luaurc",
					"selene.toml",
					"rokit.toml",
					"stylua.toml",
					".models.toml",
					".github/workflows/deploy.yml",
					"LICENSE",
					"NOTICE",
					"AGENTS.md",
					"SETUP.md",
				}
			do
				t.expect(changed({ p })).toEqual({ "harness" })
				t.expect(changed({ "pickman/src/a.luau", p })).toEqual({ "game", "harness" })
				t.expect(changed({ p, "pickman/src/a.luau" })).toEqual({ "game", "harness" })
			end
		end
	)

	it("AC1: a mixed change is the union of its paths, never one side's alone", function()
		t.expect(changed({ "pickman/src/a.luau", "z-nile/engine/main.luau" })).toEqual({ "game", "harness" })
		t.expect(changed({ "z-nile/engine/main.luau", "pickman/src/a.luau" })).toEqual({ "game", "harness" })
		t.expect(changed({ "pickman/src/a.luau", "arcade/src/b.luau" })).toEqual({ "game" })
		t.expect(changed({ "z-nile/engine/a.luau", "z-nile/lib/b.luau" })).toEqual({ "harness" })
	end)

	it("AC1: a tracker document and an empty change touch no suite", function()
		t.expect(changed({ "z-nile/.tracker/issues/c0083/c0083.md" })).toEqual({})
		t.expect(changed({ "pickman/.tracker/issues/f0010/spend.md" })).toEqual({})
		t.expect(changed({})).toEqual({})
		-- a tracker document beside a code change names only the code's suite
		t.expect(changed({ "z-nile/.tracker/issues/c0083/c0083.md", "pickman/src/a.luau" }))
			.toEqual({ "game" })
		t.expect(changed({ "z-nile/.tracker/issues/c0083/c0083.md", "zn" })).toEqual({ "harness" })
	end)

	it(
		"AC1: the old places c0120 emptied (a root tests/ or src/ folder) touch the harness, whose old-roots spec fails on them",
		function()
			t.expect(changed({ "tests/unit/a.spec.luau" })).toEqual({ "harness" })
			t.expect(changed({ "src/x.luau" })).toEqual({ "harness" })
		end
	)

	it(
		"AC1: for every path a spec watches on the real tree, suites.changed names that spec's suite, so --suite changed never skips a spec the bare gate runs",
		function()
			local real = select.rules(projects.load(top))
			local listed = process.exec(
				"git",
				{ "ls-files", "-co", "--exclude-standard", "--", "*watch.txt" },
				{ cwd = top }
			)
			local files = 0
			local entries = 0
			for file in string.gmatch(listed.stdout, "[^\n]+") do
				if string.find(file, "/tests/", 1, true) and not string.find(file, "/.cache/", 1, true) then
					files += 1
					local want = if string.sub(file, 1, 7) == "z-nile/" then "harness" else "game"
					for path in string.gmatch(fs.readFile(`{top}/{file}`), "[^\n]+") do
						entries += 1
						t.expect(table.find(suites.changed(real, { path }), want) ~= nil).toBe(true)
					end
				end
			end
			t.expect(files > 300).toBe(true)
			t.expect(entries > 2000).toBe(true)
		end
	)

	it(
		"AC5: a spec's watch list names only its own suite: the harness keeps tooling and root paths, the game its homes",
		function()
			local mixed =
				{ "z-nile/lib/a.luau", "pickman/src/b.luau", "zn", "arcade/src/c.luau", "selene.toml" }
			t.expect(suites.crossings("z-nile/tests/tooling/a.spec.luau", mixed)).toEqual({
				"pickman/src/b.luau",
				"arcade/src/c.luau",
			})
			t.expect(suites.crossings("pickman/tests/unit/a.spec.luau", mixed)).toEqual({
				"z-nile/lib/a.luau",
				"zn",
				"selene.toml",
			})
			t.expect(suites.crossings("arcade/tests/unit/a.spec.luau", { "arcade/src/c.luau" })).toEqual({})
			t.expect(suites.crossings("z-nile/tests/tooling/a.spec.luau", {})).toEqual({})
		end
	)

	it(
		"AC2: suites.of agrees with watch.forSuite for every registered project, so the two lists cannot drift",
		function()
			local reg = projects.load(top)
			for _, p in reg.projects do
				local path = `{p.home}/x.luau`
				-- a game spec keeps a game project's path; a tooling spec never does
				local keptByGame = #watch.forSuite("pickman/tests/unit/s.spec.luau", { path }) == 1
				local keptByTooling = #watch.forSuite("z-nile/tests/tooling/s.spec.luau", { path }) == 1
				if suites.of(p.name) == "game" then
					t.expect(keptByGame).toBe(true)
					t.expect(keptByTooling).toBe(false)
				else
					t.expect(keptByGame).toBe(false)
				end
			end
		end
	)

	it("AC9: promotion routes an item's acceptance specs by its project, never by its type", function()
		local reg = projects.load(top)
		t.expect(projects.promotedDir(reg, "z-nile/.tracker", "c0001")).toBe("z-nile/tests/acceptance/c0001")
		t.expect(projects.promotedDir(reg, "z-nile/.tracker", "d0001")).toBe("z-nile/tests/acceptance/d0001")
		t.expect(projects.promotedDir(reg, "pickman/.tracker", "c0001"))
			.toBe("pickman/tests/acceptance/c0001")
		t.expect(projects.promotedDir(reg, "pickman/.tracker", "f0001"))
			.toBe("pickman/tests/acceptance/f0001")
		t.expect(projects.promotedDir(reg, "arcade/.tracker", "c0001")).toBe("arcade/tests/acceptance/c0001")
	end)
end)
