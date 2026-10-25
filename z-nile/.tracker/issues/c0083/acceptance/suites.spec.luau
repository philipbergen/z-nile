--!strict
-- c0083: two spec suites. Harness specs (the tracker, the gate, the runner and its guards, setup, the build) run
-- when harness files change; game specs (src/ and what exercises it) run when game files change; a change to what
-- every spec runs on runs both. A spec is selected by its requires and by the repository paths its text names. The
-- real tree's graph and the selector are only read; check.sh and the Stop hook run as copies in fixtures under
-- .cache, each copy its own git repository, with stub tools that record what they were asked to do.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local graph = require("@scripts/lib/graph")
local process = require("@lune/process")
local suites = require("@scripts/lib/suites")
local t = require("@tests/lib/t")

local g = graph.build({ "src", "tests" })

local function all(): { string }
	local out: { string } = {}
	for _, f in g.files do
		if suites.isSpec(f) then
			table.insert(out, f)
		end
	end
	table.sort(out)
	return out
end

local function set(list: { string }): { [string]: boolean }
	local s: { [string]: boolean } = {}
	for _, x in list do
		s[x] = true
	end
	return s
end

local function exists(path: string)
	assert(fs.isFile(path), `the example {path} is gone: pick another of its kind`)
end

local function selected(changed: { string }): { string }
	local r = suites.select(g, changed)
	assert(r ~= "ALL", `{table.concat(changed, " ")} selected ALL`)
	return r :: { string }
end

return t.spec("c0083 harness and game suites", function(it)
	it(
		"a spec's suite: meta both, tooling harness, game folders and feature specs game, chores by their requires",
		function()
			local cases = {
				{ "tests/meta/architecture.spec.luau", "both" },
				{ "tests/tooling/affected.spec.luau", "harness" },
				{ "tests/unit/smoke.spec.luau", "game" }, -- requires nothing from src/, but lives in a game test folder
				{ "tests/unit/Pellets/pellets.spec.luau", "game" },
				{ "tests/acceptance/f0054/docs.spec.luau", "game" }, -- a feature's spec, though nothing it requires reaches src/
				{ "tests/acceptance/c0008/done-order.spec.luau", "harness" },
				{ "tests/acceptance/c0002/affected-place.spec.luau", "harness" }, -- tests the selector, not the place
				{ "tests/acceptance/c0041/place-game.spec.luau", "game" }, -- loads the built place
			}
			for _, c in cases do
				exists(c[1])
				t.expect(`{c[1]}: {suites.of(g, c[1])}`).toBe(`{c[1]}: {c[2]}`)
			end
			-- the folder rule is the pattern, including a folder that has no spec yet
			exists("tests/scenario/harness.spec.luau")
			t.expect(fs.isFile("tests/contract/x.spec.luau")).toBe(false)
			t.expect(fs.isFile("tests/integration/x.spec.luau")).toBe(false)
			t.expect(fs.isFile("tests/runtime/x.spec.luau")).toBe(false)
			for _, path in
				{
					"tests/scenario/harness.spec.luau",
					"tests/contract/x.spec.luau",
					"tests/integration/x.spec.luau",
					"tests/runtime/x.spec.luau",
				}
			do
				t.expect(`{path}: {suites.of(g, path)}`).toBe(`{path}: game`)
			end
			-- anchored: a path that merely contains tests/unit is not that folder. An absent file has no closure.
			for _, path in { "pkg/tests/unit/x.spec.luau", "tests/unitary/x.spec.luau" } do
				t.expect(fs.isFile(path)).toBe(false)
				t.expect(`{path}: {suites.of(g, path)}`).toBe(`{path}: harness`)
			end
		end
	)

	it("the two suites cover every spec, and share only tests/meta", function()
		local harness = suites.list(g, "harness")
		local game = suites.list(g, "game")
		local h = set(harness)
		local gm = set(game)
		-- list follows of: both is in both lists, harness only, game only. No new suite rule.
		for _, spec in all() do
			local side = suites.of(g, spec)
			local inH = h[spec] == true
			local inG = gm[spec] == true
			t.expect(`{spec}: covered: {inH or inG}`).toBe(`{spec}: covered: true`)
			if side == "both" then
				t.expect(`{spec}: both lists: {inH and inG}`).toBe(`{spec}: both lists: true`)
			elseif side == "harness" then
				t.expect(`{spec}: harness only: {inH and not inG}`).toBe(`{spec}: harness only: true`)
			else
				t.expect(side).toBe("game")
				t.expect(`{spec}: game only: {inG and not inH}`).toBe(`{spec}: game only: true`)
			end
			if inH and inG then
				t.expect(string.sub(spec, 1, 11)).toBe("tests/meta/")
			end
		end
		exists("tests/meta/architecture.spec.luau")
		exists("tests/unit/smoke.spec.luau")
		t.expect(
			h["tests/meta/architecture.spec.luau"] == true and gm["tests/meta/architecture.spec.luau"] == true
		)
			.toBe(true)
		t.expect(gm["tests/unit/smoke.spec.luau"] == true and h["tests/unit/smoke.spec.luau"] == nil)
			.toBe(true)
		exists("tests/scenario/harness.spec.luau")
		t.expect(
			gm["tests/scenario/harness.spec.luau"] == true and h["tests/scenario/harness.spec.luau"] == nil
		)
			.toBe(true)
		t.expect(#harness > 20 and #game > 20).toBe(true)
	end)

	it("a harness change runs the whole harness suite and no game-only spec", function()
		local harness = set(suites.list(g, "harness"))
		local game = set(suites.list(g, "game"))
		-- fixture, clone, cachepaths and the two tomls are harness patterns; pellets does not name them
		local harnessPatterns = {
			["tests/lib/fixture.luau"] = true,
			["tests/lib/clone.luau"] = true,
			["tests/lib/cachepaths.luau"] = true,
			["selene.toml"] = true,
			["stylua.toml"] = true,
		}
		for _, changed in
			{
				"scripts/tracker/main.luau",
				"z-nile/skills/z-design/SKILL.md",
				"tracker/templates/prompt.md",
				"tests/lib/fixture.luau",
				"tests/lib/clone.luau",
				"tests/lib/cachepaths.luau",
				"selene.toml",
				"stylua.toml",
			}
		do
			exists(changed)
			local picked = set(selected({ changed }))
			for spec in harness do
				t.expect(`{changed} -> {spec}: {picked[spec] or false}`).toBe(`{changed} -> {spec}: true`)
			end
			-- beyond the harness suite, only specs whose text names the change (they read or run it)
			local named = set(suites.textAffected(g, { changed }))
			for spec in picked do
				t.expect(`{changed} -> {spec}: {harness[spec] or named[spec] or false}`)
					.toBe(`{changed} -> {spec}: true`)
			end
			if harnessPatterns[changed] then
				t.expect(picked["tests/unit/Pellets/pellets.spec.luau"]).toBe(nil)
			end
		end
		t.expect(game["tests/unit/Pellets/pellets.spec.luau"]).toBe(true)
	end)

	it("a tests/lib file outside the allowlist stays graph plus text", function()
		-- SHARED is ALL (t.luau, and whatever the runner requires); the three allowlisted files expand to the harness
		-- suite. The rest do not.
		local skip = {
			["t.luau"] = true,
			["fence.luau"] = true,
			["fixture.luau"] = true,
			["clone.luau"] = true,
			["cachepaths.luau"] = true,
		}
		local loaded = graph.closure(g, "tests/run.luau")
		local sawPlace = false
		local sawSim = false
		for _, name in fs.readDir("tests/lib") do
			local path = `tests/lib/{name}`
			if
				fs.isFile(path)
				and string.sub(name, -5) == ".luau"
				and not skip[name]
				and not loaded[path]
			then
				local picked = selected({ path })
				local have = set(picked)
				local named = set(suites.textAffected(g, { path }))
				if named["tests/tooling/board.spec.luau"] ~= true then
					t.expect(have["tests/tooling/board.spec.luau"]).toBe(nil)
				end
				if name == "place.luau" then
					sawPlace = true
					t.expect(have["tests/place/structure.spec.luau"]).toBe(true)
				elseif name == "sim.luau" then
					sawSim = true
					t.expect(have["tests/scenario/harness.spec.luau"]).toBe(true)
				end
			end
		end
		t.expect(sawPlace).toBe(true)
		t.expect(sawSim).toBe(true)
	end)

	it("a game change runs only game specs, and the ones that depend on it", function()
		local game = set(suites.list(g, "game"))
		local changed = "src/shared/Logic/Game/init.luau"
		exists(changed)
		exists("tests/unit/Game/game.spec.luau")
		local picked = selected({ changed })
		local have = set(picked)
		local named = set(suites.textAffected(g, { changed }))
		-- every require-graph hit is selected; text hits stay extra. textAffected alone leaves game.spec out
		for _, spec in graph.affectedSpecs(g, { changed }, suites.isSpec) do
			t.expect(`{spec}: {have[spec] or false}`).toBe(`{spec}: true`)
		end
		t.expect(have["tests/unit/Game/game.spec.luau"]).toBe(true)
		t.expect(have["tests/unit/Pellets/pellets.spec.luau"]).toBe(nil)
		-- not a require of the Game init, and not named in its text. The count check stays.
		t.expect(have["tests/scenario/harness.spec.luau"]).toBe(nil)
		for _, spec in picked do
			t.expect(`{spec}: {game[spec] or named[spec] or false}`).toBe(`{spec}: true`)
		end
		t.expect(have["tests/acceptance/c0008/done-order.spec.luau"]).toBe(nil)
		t.expect(#picked < #suites.list(g, "game")).toBe(true) -- by dependency, not the whole suite
	end)

	it("a mixed change unions every path, and a shared path is still ALL", function()
		local gameInit = "src/shared/Logic/Game/init.luau"
		local script = "scripts/tracker/main.luau"
		exists(gameInit)
		exists(script)
		exists("scripts/check.sh")
		exists("tests/unit/Game/game.spec.luau")
		local function union(changed: { string })
			local picked = selected(changed)
			local have = set(picked)
			for _, spec in suites.list(g, "harness") do
				t.expect(`{spec}: {have[spec] or false}`).toBe(`{spec}: true`)
			end
			for _, spec in graph.affectedSpecs(g, { gameInit }, suites.isSpec) do
				t.expect(`graph {spec}: {have[spec] or false}`).toBe(`graph {spec}: true`)
			end
			t.expect(have["tests/unit/Game/game.spec.luau"]).toBe(true)
			t.expect(have["tests/unit/Pellets/pellets.spec.luau"]).toBe(nil)
		end
		-- the harness list is the second path when the Game init is first
		union({ gameInit, script })
		union({ script, gameInit })
		t.expect(suites.select(g, { gameInit, "scripts/check.sh" })).toBe("ALL")
		t.expect(suites.select(g, { "scripts/check.sh", gameInit })).toBe("ALL")
	end)

	it("a tracker item's documents select only the specs that name them, plus the real-tree audit", function()
		local gameInit = "src/shared/Logic/Game/init.luau"
		exists(gameInit)
		local audit = "tests/acceptance/c0082/real-tree.spec.luau" -- audits the real tree's documents through a library
		exists(audit)
		-- what every raft commit carries besides its code: spend rows, reviews, its issue documents
		local docs = {
			"tracker/rafts/active/R9999/spend.md",
			"tracker/rafts/active/R9999/review-001.md",
			"tracker/issues/active/f9999/f9999.md",
			"tracker/issues/done/f9999/f9999.md",
			"tracker/rafts/R9999/R9999.md",
		}
		local alone = set(selected({ gameInit }))
		local changed = { gameInit }
		for _, d in docs do
			table.insert(changed, d)
		end
		local picked = selected(changed)
		local have = set(picked)
		for _, spec in graph.affectedSpecs(g, { gameInit }, suites.isSpec) do
			t.expect(`graph {spec}: {have[spec] or false}`).toBe(`graph {spec}: true`)
		end
		t.expect(have[audit]).toBe(true)
		-- nothing else: a token above the item folder (`tracker`, `tracker/issues`) selects nothing for a document
		for _, spec in picked do
			t.expect(`{spec}: {alone[spec] or spec == audit}`).toBe(`{spec}: true`)
		end
		for _, slow in
			{
				"tests/acceptance/c0072/land.spec.luau",
				"tests/acceptance/c0084/spend-command.spec.luau",
				"tests/acceptance/c0067/ready.spec.luau",
			}
		do
			exists(slow)
			t.expect(`{slow}: {have[slow] or false}`).toBe(`{slow}: false`)
		end
		-- one document alone, in each of the six lifecycle places: exactly the audit
		for _, doc in
			{
				"tracker/issues/c9999/c9999.md",
				"tracker/issues/active/c9999/c9999.md",
				"tracker/issues/done/c9999/c9999.md",
				"tracker/rafts/R9999/spend.md",
				"tracker/rafts/active/R9999/review-001.md",
				"tracker/rafts/done/R9999/R9999.md",
			}
		do
			t.expect(`{doc}: {table.concat(selected({ doc }), ",")}`).toBe(`{doc}: {audit}`)
		end
		-- only an item's `.md` files are documents: its check.sh and its specs keep the plain rule, so their walkers run
		local walkers = {
			["tracker/issues/done/f9999/check.sh"] = {
				"tests/acceptance/c0034/locator.spec.luau", -- walks every live and done check.sh
				"tests/acceptance/c0063/narrowed.spec.luau", -- reads done check.sh files
				"tests/acceptance/c0103/narrowed.spec.luau",
				"tests/tooling/repo-fence.spec.luau", -- scans every check.sh
			},
			["tracker/issues/c9999/acceptance/x.spec.luau"] = {
				"tests/acceptance/c0044/guard.spec.luau", -- scans every prepped acceptance spec
			},
			-- not a document: a spec outside acceptance/ (c0053 keeps replacements/) is walked by the same specs
			["tracker/issues/c9999/replacements/x.spec.luau"] = {
				"tests/acceptance/c0044/guard.spec.luau", -- scans every spec under tracker
				"tests/acceptance/c0006/clone.spec.luau",
			},
		}
		for path, readers in walkers do
			local got = set(selected({ path }))
			for _, r in readers do
				exists(r)
				t.expect(`{path} -> {r}: {got[r] or false}`).toBe(`{path} -> {r}: true`)
			end
			t.expect(got[audit]).toBe(true)
		end
		-- outside item folders the rule is unchanged: the design document still selects the spec that reads it
		exists("tracker/game-design.md")
		t.expect(set(selected({ "tracker/game-design.md" }))["tests/acceptance/f0054/docs.spec.luau"])
			.toBe(true)
	end)

	it("default.project.json runs the whole game suite plus only the specs that name it", function()
		local game = suites.list(g, "game")
		local gameSet = set(game)
		local changed = "default.project.json"
		local picked = selected({ changed })
		local have = set(picked)
		local named = set(suites.textAffected(g, { changed }))
		for _, spec in game do
			t.expect(`{spec}: {have[spec] or false}`).toBe(`{spec}: true`)
		end
		for _, spec in picked do
			t.expect(`{spec}: {gameSet[spec] or named[spec] or false}`).toBe(`{spec}: true`)
		end
		t.expect(have["tests/acceptance/c0008/done-order.spec.luau"]).toBe(nil)
		t.expect(have["tests/scenario/harness.spec.luau"]).toBe(true)
	end)

	it("lobby.project.json runs the whole game suite plus only the specs that name it", function()
		local game = suites.list(g, "game")
		local gameSet = set(game)
		local changed = "lobby.project.json"
		local picked = selected({ changed })
		local have = set(picked)
		local named = set(suites.textAffected(g, { changed }))
		for _, spec in game do
			t.expect(`{spec}: {have[spec] or false}`).toBe(`{spec}: true`)
		end
		for _, spec in picked do
			t.expect(`{spec}: {gameSet[spec] or named[spec] or false}`).toBe(`{spec}: true`)
		end
		t.expect(have["tests/acceptance/c0008/done-order.spec.luau"]).toBe(nil)
		t.expect(have["tests/scenario/harness.spec.luau"]).toBe(true)
		-- a reader under .cache, not in tests/ or tracker/: measured 0 harness readers is not the rule
		local dir = ".cache/c0083-suites/lobby"
		fs.writeDir(dir)
		local reader = `{dir}/reader.spec.luau`
		fs.writeFile(reader, 'local project = "lobby.project.json"\n')
		local files = { reader }
		local deps: { [string]: { string } } = { [reader] = {} }
		for _, f in g.files do
			table.insert(files, f)
		end
		for k, v in g.deps do
			deps[k] = v
		end
		local synthetic = {
			files = files,
			deps = deps,
			unresolved = g.unresolved,
			dynamic = g.dynamic,
		}
		local r = suites.select(synthetic :: any, { changed })
		assert(r ~= "ALL", "lobby.project.json selected ALL")
		t.expect(set(r :: { string })[reader]).toBe(true)
	end)

	it("a change to what every spec runs on runs everything", function()
		for _, changed in
			{
				"tests/run.luau",
				"tests/lib/t.luau",
				".luaurc",
				"rokit.toml",
				"tests/lib/fence.luau", -- the jail every spec runs in
				"scripts/lib/fence.sh",
				"scripts/check.sh", -- builds the place the place specs load
				"scripts/lib/replace-file.pl",
				"tests/meta/architecture.spec.luau", -- SHARED, same as today's gate
			}
		do
			exists(changed)
			t.expect(`{changed}: {suites.select(g, { changed }) == "ALL"}`).toBe(`{changed}: true`)
		end
		-- the runner's own require closure is shared too, not only the listed files: a module the runner starts
		-- loading later (a jail for another platform, say) runs everything without a new pattern
		local runner = "tests/run.luau"
		exists(runner)
		local loadedByRunner = "tests/lib/c0083-runner-module.luau"
		t.expect(fs.isFile(loadedByRunner)).toBe(false)
		local files = { loadedByRunner }
		local deps: { [string]: { string } } = { [loadedByRunner] = {} }
		for _, f in g.files do
			table.insert(files, f)
		end
		for k, v in g.deps do
			deps[k] = v
		end
		local runnerDeps = table.clone(g.deps[runner] or {})
		table.insert(runnerDeps, loadedByRunner)
		deps[runner] = runnerDeps
		local synthetic =
			{ files = files, deps = deps, unresolved = g.unresolved, dynamic = g.dynamic } :: any
		t.expect(suites.select(synthetic, { loadedByRunner })).toBe("ALL")
		t.expect(suites.select(synthetic, { "src/shared/Logic/Game/init.luau", loadedByRunner })).toBe("ALL")
		-- on the real graph the runner does not load that path, so it is not shared
		t.expect(suites.select(g, { loadedByRunner }) ~= "ALL").toBe(true)
	end)

	it("the selector's command line prints a suite, and selects by suite instead of ALL", function()
		local function run(args: { string }): (boolean, number, string)
			local argv = { "run", "scripts/affected", "--" }
			for _, a in args do
				table.insert(argv, a)
			end
			local r = process.exec("lune", argv)
			return r.ok, r.code, r.stdout .. r.stderr
		end
		local ok, _, out = run({ "scripts/tracker/main.luau" })
		t.expect(ok).toBe(true)
		t.expect((string.find(out, "ALL", 1, true))).toBe(nil)
		t.expect(string.find(out, "tests/acceptance/c0008/done-order.spec.luau", 1, true) ~= nil).toBe(true)
		local okH, _, outH = run({ "--suite", "harness" })
		t.expect(okH).toBe(true)
		t.expect(outH).toBe(table.concat(suites.list(g, "harness"), "\n") .. "\n")
		local okG, _, outG = run({ "--suite", "game" })
		t.expect(okG).toBe(true)
		t.expect(outG).toBe(table.concat(suites.list(g, "game"), "\n") .. "\n")
		local okX, code, outX = run({ "--suite", "nope" })
		t.expect(okX).toBe(false)
		t.expect(code).toBe(2)
		t.expect(string.find(outX, "unknown suite", 1, true) ~= nil).toBe(true)
		-- --which: the sides the paths belong to, for a baseline
		local _, _, wh = run({ "--which", "scripts/tracker/main.luau" })
		t.expect(wh).toBe("harness\n")
		local _, _, wg = run({ "--which", "src/shared/Logic/Game/init.luau" })
		t.expect(wg).toBe("game\n")
		local _, _, wb = run({ "--which", "tests/lib/fence.luau" })
		t.expect(wb).toBe("harness\ngame\n")
		local _, _, wPlace = run({ "--which", "tests/acceptance/c0041/place-game.spec.luau" })
		t.expect(wPlace).toBe("game\n")
		local _, _, wSmoke = run({ "--which", "tests/unit/smoke.spec.luau" })
		t.expect(wSmoke).toBe("game\n")
		local _, _, wScenario = run({ "--which", "tests/scenario/harness.spec.luau" })
		t.expect(wScenario).toBe("game\n")
		-- absent: the folder pattern, not a closure
		local _, _, wContract = run({ "--which", "tests/contract/x.spec.luau" })
		t.expect(wContract).toBe("game\n")
		local _, _, wProj = run({ "--which", "default.project.json" })
		t.expect(wProj).toBe("game\n")
		local _, _, wDoc = run({ "--which", "tracker/game-design.md" })
		t.expect(wDoc).toBe("harness\ngame\n")
		local _, _, wUnion =
			run({ "--which", "scripts/tracker/main.luau", "src/shared/Logic/Game/init.luau" })
		t.expect(wUnion).toBe("harness\ngame\n")
		-- backlog shape, and the file is not there: an f/d acceptance spec is game anyway
		local _, _, wMissing = run({ "--which", "tracker/issues/f0099/acceptance/x.spec.luau" })
		t.expect(wMissing).toBe("game\n")
		-- active/ and done/ are rule 1 too; the file need not exist. A missing active chore has no src closure.
		local _, _, wActiveF = run({ "--which", "tracker/issues/active/f0099/acceptance/x.spec.luau" })
		t.expect(wActiveF).toBe("game\n")
		local _, _, wDoneF = run({ "--which", "tracker/issues/done/f0099/acceptance/x.spec.luau" })
		t.expect(wDoneF).toBe("game\n")
		local _, _, wActiveC = run({ "--which", "tracker/issues/active/c0099/acceptance/x.spec.luau" })
		t.expect(wActiveC).toBe("harness\n")
		-- this file exists; its requires do not reach src/ or the place library, so it is harness
		local _, _, wChore = run({ "--which", "tracker/issues/c0083/acceptance/suites.spec.luau" })
		t.expect(wChore).toBe("harness\n")
		-- an unpromoted chore spec's closure comes from the graph when the graph holds that path
		local choreSpec = "tracker/issues/c0999/acceptance/x.spec.luau"
		t.expect(fs.isFile(choreSpec)).toBe(false)
		local function withDeps(list: { string }): any
			local files = { choreSpec }
			local deps: { [string]: { string } } = { [choreSpec] = list }
			for _, f in g.files do
				table.insert(files, f)
			end
			for k, v in g.deps do
				deps[k] = v
			end
			return { files = files, deps = deps, unresolved = g.unresolved, dynamic = g.dynamic }
		end
		t.expect(table.concat(suites.sideOf(withDeps({ graph.PLACE_LIB }), { choreSpec }), ",")).toBe("game")
		t.expect(table.concat(suites.sideOf(withDeps({}), { choreSpec }), ",")).toBe("harness")
		local okNone, codeNone = run({ "--which" })
		t.expect(okNone).toBe(false)
		t.expect(codeNone).toBe(2)
		local okE, codeE = run({ "--suite" })
		t.expect(okE).toBe(false)
		t.expect(codeE).toBe(2)
		-- --deps: require and text only, never ALL, including a SHARED path. The plain selector still prints ALL.
		local function deps(path: string): string
			local okD, _, outD = run({ "--deps", path })
			t.expect(`{path}: {okD}`).toBe(`{path}: true`)
			t.expect((string.find(outD, "ALL", 1, true))).toBe(nil)
			return outD
		end
		local function linesOf(text: string): { [string]: boolean }
			local s: { [string]: boolean } = {}
			for line in string.gmatch(text, "[^\n]+") do
				s[line] = true
			end
			return s
		end
		local function depUnion(path: string): { [string]: boolean }
			local u = set(graph.affectedSpecs(g, { path }, suites.isSpec))
			for _, spec in suites.textAffected(g, { path }) do
				u[spec] = true
			end
			return u
		end
		local function same(a: { [string]: boolean }, b: { [string]: boolean }): boolean
			for k in a do
				if b[k] ~= true then
					return false
				end
			end
			for k in b do
				if a[k] ~= true then
					return false
				end
			end
			return true
		end
		local outD = deps("scripts/lib/graph.luau")
		t.expect(string.find(outD, "tests/acceptance/c0002/affected-place.spec.luau", 1, true) ~= nil)
			.toBe(true)
		t.expect((string.find(outD, "tests/unit/Pellets/pellets.spec.luau", 1, true))).toBe(nil)
		exists("tests/tooling/board.spec.luau")
		t.expect((string.find(outD, "tests/tooling/board.spec.luau", 1, true))).toBe(nil)
		exists("tests/tooling/repo-fence.spec.luau")
		exists("tests/acceptance/f0061/lobby-tooling.spec.luau")
		-- the set equals affectedSpecs ∪ textAffected. Order is not the rule. Empty fails.
		local outFence = deps("tests/lib/fence.luau")
		t.expect(same(linesOf(outFence), depUnion("tests/lib/fence.luau"))).toBe(true)
		t.expect(string.find(outFence, "tests/tooling/repo-fence.spec.luau", 1, true) ~= nil).toBe(true)
		t.expect((string.find(outFence, "tests/tooling/board.spec.luau", 1, true))).toBe(nil)
		local outGate = deps("scripts/check.sh")
		t.expect(same(linesOf(outGate), depUnion("scripts/check.sh"))).toBe(true)
		t.expect(string.find(outGate, "tests/acceptance/f0061/lobby-tooling.spec.luau", 1, true) ~= nil)
			.toBe(true)
		t.expect((string.find(outGate, "tests/tooling/board.spec.luau", 1, true))).toBe(nil)
		t.expect((string.find(outGate, "tests/unit/Pellets/pellets.spec.luau", 1, true))).toBe(nil)
	end)

	it(
		"a file a spec reads as text selects that spec, and a spec change selects the specs that scan every spec",
		function()
			local cases = {
				{ ".github/workflows/check.yml", "tests/acceptance/c0001/ci-workflow.spec.luau" },
				{ "SETUP.md", "tests/acceptance/c0015/docs.spec.luau" },
				{ "tracker/issues/done/c0008/check.sh", "tests/tooling/repo-fence.spec.luau" },
				{ "tests/unit/smoke.spec.luau", "tests/tooling/repo-fence.spec.luau" },
				{ "tests/unit/smoke.spec.luau", "tests/acceptance/c0049/spec-isolation.spec.luau" }, -- `{root}/tests`
			}
			for _, c in cases do
				exists(c[1])
				exists(c[2])
				local picked = set(selected({ c[1] }))
				t.expect(`{c[1]} -> {c[2]}: {picked[c[2]] or false}`).toBe(`{c[1]} -> {c[2]}: true`)
			end
			-- and a file nothing names selects nothing by text
			t.expect(#suites.textAffected(g, { "no-such-top-level-file.md" })).toBe(0)
			-- a changed folder selects the specs that name an existing file inside it. No spec names the folder itself.
			t.expect(fs.isDir(".github/workflows")).toBe(true)
			local inFolder = set(suites.textAffected(g, { ".github/workflows" }))
			t.expect(inFolder["tests/acceptance/c0001/ci-workflow.spec.luau"]).toBe(true)
		end
	)

	it("a deleted or renamed file still selects the specs that named it", function()
		-- a stand-in spec naming a path that no longer exists (deleted, or renamed away): the specs that read a file must
		-- run when it goes, not only while it's there
		local dir = ".cache/c0083-suites/named"
		fs.writeDir(dir)
		local spec = `{dir}/reader.spec.luau`
		fs.writeFile(
			spec,
			'local text = "gone/deleted-doc.md"\nlocal folder = `{root}/gone-folder/sub`\n'
				.. 'local prefixed = `gone-prefix/{name .. "inner-code/x"}.md`\n'
				.. 'local inner = "gone-dir/inner/file.md"\n'
		)
		local synthetic = { files = { spec }, deps = { [spec] = {} }, unresolved = {}, dynamic = {} } :: any
		t.expect(fs.isFile("gone/deleted-doc.md")).toBe(false)
		t.expect(#suites.textAffected(synthetic, { "gone/deleted-doc.md" })).toBe(1)
		t.expect(#suites.textAffected(synthetic, { "gone-folder/sub/file.luau" })).toBe(1) -- inside a named folder that is gone
		t.expect(#suites.textAffected(synthetic, { "gone/other.md" })).toBe(0)
		-- an interpolated string: the literal piece before the braces counts, the code between them does not
		t.expect(#suites.textAffected(synthetic, { "gone-prefix/x.md" })).toBe(1)
		t.expect(#suites.textAffected(synthetic, { "inner-code/x" })).toBe(0)
		-- a path inside a changed folder counts only while it exists: an absent one is not selected by its folder
		t.expect(#suites.textAffected(synthetic, { "gone-dir/inner" })).toBe(0)
	end)

	-- a stand-in checkout holding a copy of check.sh and its libraries, and stub tools that log every call
	local base = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", "")) .. "/.cache/c0083-suites"

	local function gateCopy(): string
		local dir = `{base}/gate`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/scripts/lib`)
		fs.writeFile(`{dir}/scripts/check.sh`, fs.readFile("scripts/check.sh"))
		for _, lib in fs.readDir("scripts/lib") do
			if fs.isFile(`scripts/lib/{lib}`) then
				fs.writeFile(`{dir}/scripts/lib/{lib}`, fs.readFile(`scripts/lib/{lib}`))
			end
		end
		for _, d in { "bin", "home", "tmp", ".cache" } do
			fs.writeDir(`{dir}/{d}`)
		end
		fs.writeFile(`{dir}/.cache/globalTypes.d.luau`, "-- defs")
		local log = '#!/bin/sh\necho "$(basename "$0") $*" >> "$STUB_LOG"\n'
		for _, tool in { "stylua", "selene", "luau-lsp", "curl" } do
			fs.writeFile(`{dir}/bin/{tool}`, log .. "exit 0\n")
		end
		fs.writeFile(
			`{dir}/bin/rojo`,
			log .. 'o=; for a; do [ "$prev" = -o ] && o=$a; prev=$a; done; echo x > "$o"\n'
		)
		fs.writeFile(
			`{dir}/bin/lune`,
			log
				.. 'case "$1 $2 $4" in\n'
				.. '  "--version  "*) echo "lune 0.0.0" ;;\n'
				.. '  "run scripts/affected --suite") printf "tests/h1.spec.luau\\ntests/h2.spec.luau\\n" ;;\n'
				.. "esac\nexit 0\n"
		)
		for _, tool in { "stylua", "selene", "luau-lsp", "curl", "rojo", "lune" } do
			process.exec("chmod", { "+x", `{dir}/bin/{tool}` })
		end
		-- own repository: git inside the copy stops here instead of walking up to the real checkout
		t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
		return dir
	end

	local function gate(dir: string, args: { string }): (number, string)
		fs.writeFile(`{dir}/stub.log`, "")
		local argv = { "scripts/check.sh" }
		for _, a in args do
			table.insert(argv, a)
		end
		local r = fixture.exec(dir, "bash", argv, {
			env = {
				PATH = `{dir}/bin:{process.env.PATH or ""}`,
				HOME = `{dir}/home`,
				TMPDIR = `{dir}/tmp`,
				STUB_LOG = `{dir}/stub.log`,
			},
		})
		return r.code, fs.readFile(`{dir}/stub.log`)
	end

	it("check.sh --suite runs one suite's specs, and refuses a bad name before any tool runs", function()
		local dir = gateCopy()
		local code, log = gate(dir, { "--suite", "nope" })
		t.expect(code).toBe(2)
		t.expect(log).toBe("") -- no tool ran: refused while reading its arguments
		t.expect(fs.isFile(`{dir}/sourcemap.json`)).toBe(false)
		local codeE, logE = gate(dir, { "--suite" })
		t.expect(codeE).toBe(2)
		t.expect(logE).toBe("")
		local codeH, logH = gate(dir, { "--suite", "harness" })
		t.expect(codeH).toBe(0)
		t.expect(string.find(logH, "lune run scripts/affected -- --suite harness", 1, true) ~= nil).toBe(true)
		t.expect(
			string.find(logH, "lune run tests/run -- tests/h1.spec.luau tests/h2.spec.luau", 1, true) ~= nil
		)
			.toBe(true)
	end)

	it("the Stop hook gates whenever the selector picks a spec, harness changes included", function()
		local repo = `{base}/hook`
		if fs.isDir(repo) then
			fs.removeDir(repo)
		end
		fs.writeDir(`{repo}/scripts/hooks`)
		fs.writeDir(`{repo}/bin`)
		fs.writeDir(`{repo}/home`)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", repo }).ok).toBe(true)
		local ID = {
			GIT_AUTHOR_NAME = "c0083",
			GIT_AUTHOR_EMAIL = "c0083@example.invalid",
			GIT_COMMITTER_NAME = "c0083",
			GIT_COMMITTER_EMAIL = "c0083@example.invalid",
		}
		fs.writeFile(`{repo}/scripts/hooks/stop.sh`, fs.readFile("scripts/hooks/stop.sh"))
		-- the stub gate records that it ran and exits with STUB_GATE_EXIT
		fs.writeFile(
			`{repo}/scripts/check.sh`,
			'#!/bin/sh\necho "gate $*" >> "$STUB_LOG"\nexit "${STUB_GATE_EXIT:-0}"\n'
		)
		-- the stub selector prints STUB_SELECT, or fails when STUB_SELECT_FAIL is set
		fs.writeFile(
			`{repo}/bin/lune`,
			'#!/bin/sh\necho "lune $*" >> "$STUB_LOG"\n[ -n "$STUB_SELECT_FAIL" ] && exit 1\nprintf "%s" "$STUB_SELECT"\n'
		)
		process.exec(
			"chmod",
			{ "+x", `{repo}/scripts/check.sh`, `{repo}/bin/lune`, `{repo}/scripts/hooks/stop.sh` }
		)
		fs.writeFile(`{repo}/.gitignore`, "bin/\nhome/\nstub.log\n")
		fs.writeFile(`{repo}/scripts/old.sh`, "echo old\n")
		fixture.git(repo, { "add", "-A" }, { env = ID })
		fixture.git(repo, { "commit", "-qm", "base" }, { env = ID })
		fs.writeFile(`{repo}/scripts/tool.sh`, "echo changed\n") -- a harness file, outside src/ and tests/
		local function stop(env: { [string]: string }): (number, string)
			fs.writeFile(`{repo}/stub.log`, "")
			local e: { [string]: string } = {
				PATH = `{repo}/bin:{process.env.PATH or ""}`,
				HOME = `{repo}/home`,
				STUB_LOG = `{repo}/stub.log`,
			}
			for k, v in env do
				e[k] = v
			end
			local r = fixture.exec(repo, "bash", { "scripts/hooks/stop.sh" }, {
				env = e,
				stdin = `\{"cwd": "{repo}", "stop_hook_active": false\}`,
			})
			return r.code, fs.readFile(`{repo}/stub.log`)
		end
		local code, log = stop({ STUB_SELECT = "tests/tooling/x.spec.luau\n" })
		t.expect(code).toBe(0)
		t.expect(string.find(log, "scripts/tool.sh", 1, true) ~= nil).toBe(true) -- the selector was asked about it
		t.expect(string.find(log, "gate --affected", 1, true) ~= nil).toBe(true)
		local codeN, logN = stop({ STUB_SELECT = "" })
		t.expect(codeN).toBe(0)
		t.expect((string.find(logN, "gate", 1, true))).toBe(nil) -- nothing selected: no gate
		local codeF, logF = stop({ STUB_SELECT_FAIL = "1" })
		t.expect(codeF).toBe(0)
		t.expect(string.find(logF, "gate --affected", 1, true) ~= nil).toBe(true) -- a failing selector gates anyway
		local codeR = stop({ STUB_SELECT = "tests/tooling/x.spec.luau\n", STUB_GATE_EXIT = "1" })
		t.expect(codeR).toBe(2) -- a failing gate blocks the stop
		-- a staged rename: the old path's readers must run too, so the selector is asked about it
		fixture.git(repo, { "mv", "scripts/old.sh", "scripts/renamed.sh" }, { env = ID })
		local _, logM = stop({ STUB_SELECT = "" })
		t.expect(string.find(logM, "scripts/old.sh", 1, true) ~= nil).toBe(true)
		t.expect(string.find(logM, "scripts/renamed.sh", 1, true) ~= nil).toBe(true)
		-- nothing uncommitted or untracked: the hook neither asks the selector (it would fall back to the branch diff)
		-- nor gates
		fixture.git(repo, { "add", "-A" }, { env = ID })
		fixture.git(repo, { "commit", "-qm", "all" }, { env = ID })
		local codeC, logC = stop({ STUB_SELECT = "tests/tooling/x.spec.luau\n" })
		t.expect(codeC).toBe(0)
		t.expect((string.find(logC, "lune", 1, true))).toBe(nil)
		t.expect((string.find(logC, "gate", 1, true))).toBe(nil)
	end)

	it("cleans up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
	end)
end)
