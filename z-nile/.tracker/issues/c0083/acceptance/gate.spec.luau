--!strict
-- c0083 AC3 to AC6: the gate runs one suite's projects. `z-nile/affected --suite` prints a suite's project names;
-- `z-nile/check.sh --suite harness|game` runs only that suite's projects' stages and specs in every mode but --slow,
-- `--suite changed` narrows the specs of a --full run to the suites the change touches (the static stages keep today's
-- narrowing; --affected and --static are the bare gate), `--suite all` is the bare gate in every mode, and a bare
-- `--full` is still every project's; a bad value, `--project` or `--slow` beside it is refused before any tool runs; the
-- real reader answers from a real change set and `--base`; a watch file that names the other suite's paths fails
-- `watch-check`; and on the real tree a game path selects no harness spec and a tooling path no game spec.
-- Fixtures under .cache/c0083-gate: a copy of the tooling with three homes and stub tools, and c0165's git fixture
-- (real lune and git, stub static tools); the real tree is only read.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local gatefix = require("@tests/acceptance/c0165/gatefix")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local suites = require("@znile/lib/suites")
local t = require("@tests/lib/t")

local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local homeDir = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{homeDir}/.cache/c0083-gate`
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n\n'
	.. '[[project]]\nname = "arcade"\nroot = "arcade/.tracker"\n'

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function lines(text: string): { string }
	local out: { string } = {}
	for l in string.gmatch(text, "[^\n]+") do
		table.insert(out, l)
	end
	return out
end

-- the stage lines of a run that start with `prefix`, in order
local function stageLines(out: string, prefix: string): { string }
	local found: { string } = {}
	for _, l in lines(out) do
		if string.sub(l, 1, #prefix) == prefix then
			table.insert(found, l)
		end
	end
	return found
end

local made = 0
-- a copy of the tooling with three homes (pickman and arcade are games, z-nile the harness) and stub tools. The stub
-- lune answers the registry's reader, the suite reader (`--suite changed` answers $STUB_CHANGED), `--static`
-- ($STUB_STATIC, ALL when unset), and logs every other call with its working folder.
local function stubbed(): string
	made += 1
	local dir = `{base}/f{made}`
	fs.writeDir(dir)
	engine.copy(top, dir)
	fs.writeFile(`{dir}/z-nile/projects.toml`, REGISTRY)
	for _, rel in
		{
			"pickman/src/shared",
			"pickman/tests/unit",
			"arcade/src/shared",
			"arcade/tests/unit",
			"z-nile/tests/tooling",
			"z-nile/.tracker",
			"pickman/.tracker",
			"arcade/.tracker",
		}
	do
		fs.writeDir(`{dir}/{rel}`)
	end
	for _, home in { "pickman", "arcade" } do
		write(`{dir}/{home}/default.project.json`, '{ "name": "g", "tree": { "$className": "DataModel" } }\n')
	end
	fs.writeDir(`{dir}/bin`)
	fs.writeDir(`{dir}/home/.lune/.typedefs/0.10.5`)
	local log = 'printf "%s|%s|%s\\n" "$(pwd -P)" "$(basename "$0")" "$*" >> "$STUB_LOG"\n'
	for _, tool in { "stylua", "selene", "luau-lsp" } do
		write(`{dir}/bin/{tool}`, "#!/bin/sh\n" .. log .. "exit 0\n")
	end
	write(
		`{dir}/bin/rojo`,
		"#!/bin/sh\n" .. log .. 'o=; for a; do [ "$prev" = -o ] && o=$a; prev=$a; done\necho "built" > "$o"\n'
	)
	write(
		`{dir}/bin/curl`,
		'#!/bin/sh\no=; while [ $# -gt 0 ]; do [ "$1" = -o ] && o=$2; shift; done; echo "-- defs" > "$o"\n'
	)
	write(
		`{dir}/bin/lune`,
		'#!/bin/sh\nif [ "$1" = --version ]; then echo "lune 0.10.5"; exit 0; fi\n'
			.. 'if [ "$2" = z-nile/roots ] && [ "$4" = --projects ]; then\n'
			.. '  printf "pickman\\tpickman\\tpickman/.tracker\\nz-nile\\tz-nile\\tz-nile/.tracker\\n'
			.. 'arcade\\tarcade\\tarcade/.tracker\\n"; exit 0\nfi\n'
			.. 'if [ "$2" = z-nile/roots ] && [ "$4" = --luau-dirs ]; then echo "z-nile"; exit 0; fi\n'
			.. 'if [ "$2" = z-nile/affected ] && [ "$4" = --static ]; then\n'
			.. '  printf "%s\\n" "${STUB_STATIC-ALL}"; exit 0\nfi\n'
			.. 'if [ "$2" = z-nile/affected ] && [ "$4" = --suite ]; then\n'
			.. '  case "$5" in\n'
			.. "    harness) echo z-nile ;;\n"
			.. '    game) printf "pickman\\narcade\\n" ;;\n'
			.. '    changed) [ -n "$STUB_CHANGED" ] && printf "%s\\n" $STUB_CHANGED ;;\n'
			.. "  esac\n  exit 0\nfi\n"
			.. 'if [ "$2" = z-nile/affected ]; then exit 0; fi\n'
			.. 'if [ "$2" = z-nile/watch-check ]; then exit 0; fi\n'
			.. log
			.. "exit 0\n"
	)
	for _, tool in { "stylua", "selene", "luau-lsp", "rojo", "curl", "lune" } do
		process.exec("chmod", { "+x", `{dir}/bin/{tool}` })
	end
	return dir
end

-- `static` is what the stub's `affected --static` answers (ALL, or the project names), `changed` what its
-- `affected --suite changed` answers
local function gate(
	dir: string,
	args: { string },
	changed: string?,
	static: string?
): (number, string, string)
	local argv = { "z-nile/check.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, {
		cwd = dir,
		env = {
			PATH = `{dir}/bin:{process.env.PATH or ""}`,
			HOME = `{dir}/home`,
			STUB_LOG = `{dir}/calls.log`,
			STUB_CHANGED = changed or "",
			STUB_STATIC = static or "ALL",
		},
	})
	local log = if fs.isFile(`{dir}/calls.log`) then fs.readFile(`{dir}/calls.log`) else ""
	return r.code, r.stdout .. r.stderr, log
end

-- the projects a plan's `specs:` lines name, in order
local function planned(out: string): { string }
	local names: { string } = {}
	for _, l in stageLines(out, "specs: ") do
		table.insert(names, string.match(l, "^specs: ([^,]+),") :: string)
	end
	return names
end

local function realAffected(args: { string }): (number, { string })
	local argv = { "run", "z-nile/affected", "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv, { cwd = top })
	return r.code, lines(r.stdout)
end

-- the registry's projects of one suite, in the registry's order (`all`: every project)
local function registered(which: string): { string }
	local names: { string } = {}
	for _, p in projects.load(top).projects do
		table.insert(names, p.name)
	end
	return suites.projects(names, which)
end

return t.spec("c0083 the gate runs one suite", function(it)
	it("sets up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
	end)

	it(
		"AC3: affected --suite prints one suite's project names in the registry's order, and nothing else",
		function()
			local code, harness = realAffected({ "--suite", "harness" })
			t.expect(code).toBe(0)
			t.expect(harness).toEqual(registered("harness"))
			t.expect(table.find(harness, "z-nile") ~= nil).toBe(true)
			local gcode, game = realAffected({ "--suite", "game" })
			t.expect(gcode).toBe(0)
			t.expect(game).toEqual(registered("game"))
			for _, name in { "pickman", "arcade", "portal", "snake", "invaders", "asteroids" } do
				t.expect(table.find(game, name) ~= nil).toBe(true)
			end
			t.expect(table.find(game, "z-nile")).toBe(nil)
			local _, all = realAffected({ "--suite", "all" })
			t.expect(all).toEqual(registered("all"))
		end
	)

	it(
		"AC3: affected --suite changed names the suites the listed paths touch by location, none for a tracker document",
		function()
			local _, game = realAffected({ "--suite", "changed", "pickman/src/shared/Logic/Game/init.luau" })
			t.expect(game).toEqual(registered("game"))
			t.expect(table.find(game, "z-nile")).toBe(nil)
			local _, tooling = realAffected({ "--suite", "changed", "z-nile/engine/main.luau" })
			t.expect(tooling).toEqual(registered("harness"))
			-- a root file is the tooling's: harness specs watch it (.models.toml selects 19 of them, LICENSE 5)
			for _, root in { "zn", ".models.toml", ".github/workflows/deploy.yml", "LICENSE", "AGENTS.md" } do
				local _, rootOut = realAffected({ "--suite", "changed", root })
				t.expect(rootOut).toEqual(registered("harness"))
			end
			local _, mixed =
				realAffected({ "--suite", "changed", "pickman/src/a.luau", "z-nile/engine/main.luau" })
			t.expect(mixed).toEqual(registered("all"))
			local _, mixedRoot = realAffected({ "--suite", "changed", "pickman/src/a.luau", ".models.toml" })
			t.expect(mixedRoot).toEqual(registered("all"))
			local code, none = realAffected({ "--suite", "changed", "z-nile/.tracker/issues/c0083/c0083.md" })
			t.expect(code).toBe(0)
			t.expect(none).toEqual({})
		end
	)

	it("AC3: affected --suite refuses a name that is none of the four, and a missing one", function()
		local code = realAffected({ "--suite", "bogus" })
		t.expect(code).toBe(2)
		local none = realAffected({ "--suite" })
		t.expect(none).toBe(2)
	end)

	it(
		"AC3: the real reader reads the change set and --base, which the gate's own call form passes",
		function()
			local dir = gatefix.make(base, "real", {
				setup = function(d: string)
					write(
						`{d}/pickman/default.project.json`,
						'{ "name": "g", "tree": { "$className": "DataModel" } }\n'
					)
				end,
			})
			write(`{dir}/pickman/src/A.luau`, "return { value = 2 }\n")
			fixture.git(dir, { "add", "-A" })
			fixture.git(dir, { "commit", "-qm", "game change" })
			local function suite(args: { string }): (boolean, { string })
				local argv = { "run", "z-nile/affected", "--", "--suite", "changed" }
				for _, a in args do
					table.insert(argv, a)
				end
				local r = process.exec("lune", argv, { cwd = dir, env = gatefix.env(dir) })
				return r.ok, lines(r.stdout)
			end
			-- no paths: the branch's change against main, a game file
			local ok, named = suite({})
			t.expect(ok).toBe(true)
			t.expect(named).toEqual({ "pickman" })
			-- the same change against its own head is no change
			local _, none = suite({ "--base", "work" })
			t.expect(none).toEqual({})
			-- and the gate passes that call form to it: with the change a plan runs pickman's specs, with --base work none
			local plan, out = gatefix.gateRaw(dir, { "--plan", "--full", "--suite", "changed" })
			t.expect(plan).toBe(true)
			t.expect(planned(out)).toEqual({ "pickman" })
			local _, outBase =
				gatefix.gateRaw(dir, { "--plan", "--full", "--suite", "changed", "--base", "work" })
			t.expect(planned(outBase)).toEqual({})
			t.expect(has(outBase, "no project changed")).toBe(true)
		end
	)

	it(
		"AC4: --full --suite game plans the game projects' specs alone, --suite harness z-nile's alone, with their static stages",
		function()
			local dir = stubbed()
			local code, out = gate(dir, { "--plan", "--full", "--suite", "game" })
			t.expect(code).toBe(0)
			t.expect(planned(out)).toEqual({ "pickman", "arcade" })
			local hcode, hout = gate(dir, { "--plan", "--full", "--suite", "harness" })
			t.expect(hcode).toBe(0)
			t.expect(planned(hout)).toEqual({ "z-nile" })
			t.expect(has(out, "build: arcade/default.project.json")).toBe(true)
			t.expect(has(hout, "build: pickman/default.project.json")).toBe(false)
		end
	)

	it("AC4: a gate with no --suite, and --suite all, are the same gate in every mode", function()
		local dir = stubbed()
		for _, mode in { "--full", "--affected", "--static" } do
			-- the stub's static narrowing answers one project, so a mode that narrows is seen to
			local _, bare = gate(dir, { "--plan", mode }, nil, "pickman")
			local _, all = gate(dir, { "--plan", mode, "--suite", "all" }, nil, "pickman")
			t.expect(all).toBe(bare)
		end
		local _, full = gate(dir, { "--plan", "--full" })
		t.expect(planned(full)).toEqual({ "pickman", "z-nile", "arcade" })
		local _, narrowed = gate(dir, { "--plan", "--affected", "--suite", "all" }, nil, "pickman")
		t.expect(planned(narrowed)).toEqual({ "pickman" })
	end)

	it(
		"AC4: --full --suite changed is every spec of each suite the change touches, with today's static stages",
		function()
			local dir = stubbed()
			local _, tooling = gate(dir, { "--plan", "--full", "--suite", "changed" }, "z-nile", "ALL")
			t.expect(planned(tooling)).toEqual({ "z-nile" })
			-- a root config still reruns every project's static stages (static ALL), though only the harness's specs run
			t.expect(has(tooling, "build: pickman/default.project.json")).toBe(true)
			t.expect(has(tooling, "build: arcade/default.project.json")).toBe(true)
			local _, game =
				gate(dir, { "--plan", "--full", "--suite", "changed" }, "pickman arcade", "pickman")
			t.expect(planned(game)).toEqual({ "pickman", "arcade" })
			local _, both =
				gate(dir, { "--plan", "--full", "--suite", "changed" }, "pickman z-nile arcade", "ALL")
			t.expect(planned(both)).toEqual({ "pickman", "z-nile", "arcade" })
			-- a suite's projects are checked statically even when the static narrowing names others
			local _, own = gate(dir, { "--plan", "--full", "--suite", "changed" }, "arcade", "pickman")
			t.expect(planned(own)).toEqual({ "arcade" })
			t.expect(has(own, "build: pickman/default.project.json")).toBe(true)
			t.expect(has(own, "build: arcade/default.project.json")).toBe(true)
			-- and the static narrowing still applies: it names pickman, the suite adds z-nile, so arcade's builds do not run
			local _, narrowed = gate(dir, { "--plan", "--full", "--suite", "changed" }, "z-nile", "pickman")
			t.expect(planned(narrowed)).toEqual({ "z-nile" })
			t.expect(has(narrowed, "build: pickman/default.project.json")).toBe(true)
			t.expect(has(narrowed, "build: arcade/default.project.json")).toBe(false)
		end
	)

	it("AC4: a change that touches no suite checks nothing and passes", function()
		local dir = stubbed()
		local code, out, log = gate(dir, { "--full", "--suite", "changed" }, "", "")
		t.expect(code).toBe(0)
		t.expect(has(out, "no project changed")).toBe(true)
		t.expect(has(out, "GATE PASSED (full)")).toBe(true)
		t.expect(has(log, "|run tests/run")).toBe(false)
	end)

	it(
		"AC4: a suite's full and affected runs start only its homes' runners, and --suite changed leaves --affected bare",
		function()
			local dir = stubbed()
			local here = (string.gsub(process.exec("pwd", { "-P" }, { cwd = dir }).stdout, "%s+$", ""))
			local code, out, log = gate(dir, { "--full", "--suite", "game" })
			t.expect(code).toBe(0)
			t.expect(has(log, `{here}/pickman|lune|run tests/run --`)).toBe(true)
			t.expect(has(log, `{here}/arcade|lune|run tests/run --`)).toBe(true)
			t.expect(has(log, `{here}/z-nile|lune|run tests/run`)).toBe(false)
			t.expect(has(out, "tests (full): z-nile")).toBe(false)
			local dir2 = stubbed()
			local acode, aout = gate(dir2, { "--affected", "--suite", "game" })
			t.expect(acode).toBe(0)
			t.expect(stageLines(aout, "== tests (affected): ")).toEqual({
				"== tests (affected): pickman",
				"== tests (affected): arcade",
			})
			-- without --suite, and with `changed`, an affected run still considers every project's selection
			local every = {
				"== tests (affected): pickman",
				"== tests (affected): z-nile",
				"== tests (affected): arcade",
			}
			local dir3 = stubbed()
			local _, bout = gate(dir3, { "--affected" })
			t.expect(stageLines(bout, "== tests (affected): ")).toEqual(every)
			local dir4 = stubbed()
			local _, cout = gate(dir4, { "--affected", "--suite", "changed" }, "pickman")
			t.expect(stageLines(cout, "== tests (affected): ")).toEqual(every)
		end
	)

	it(
		"AC4: a bad --suite value, a missing one, or --project or --slow beside --suite is refused with exit 2 before any tool runs",
		function()
			local dir = stubbed()
			for _, args in
				{
					{ "--suite", "bogus" },
					{ "--suite" },
					{ "--suite", "game", "--project", "z-nile" },
					{ "--project", "z-nile", "--suite", "harness" },
					{ "--slow", "--suite", "game" },
					{ "--suite", "changed", "--slow" },
				}
			do
				local code, out, log = gate(dir, args)
				t.expect(code).toBe(2)
				t.expect(has(out, "--suite")).toBe(true)
				t.expect(log).toBe("")
			end
		end
	)

	it(
		"AC5: watch-check refuses a watch file that names the other suite's path, and names the spec and the path",
		function()
			local dir = `{base}/watch`
			fs.writeDir(dir)
			engine.copy(top, dir)
			fs.writeFile(`{dir}/z-nile/projects.toml`, REGISTRY)
			write(`{dir}/pickman/src/A.luau`, "return {}\n")
			write(`{dir}/z-nile/lib/x.luau`, "return {}\n")
			write(`{dir}/pickman/tests/unit/b.spec.luau`, "return {}\n")
			write(`{dir}/z-nile/tests/tooling/a.spec.luau`, "return {}\n")
			write(`{dir}/pickman/tests/unit/b.watch.txt`, "pickman/src/A.luau\n")
			write(`{dir}/z-nile/tests/tooling/a.watch.txt`, "z-nile/lib/x.luau\n")
			write(`{dir}/arcade/tests/.keep`, "")
			local function run(): (number, string)
				local r = process.exec("lune", { "run", "z-nile/watch-check" }, { cwd = dir })
				return r.code, r.stdout .. r.stderr
			end
			local ok = run()
			t.expect(ok).toBe(0)
			-- the tooling spec now also names a game path
			write(`{dir}/z-nile/tests/tooling/a.watch.txt`, "z-nile/lib/x.luau\npickman/src/A.luau\n")
			local code, out = run()
			t.expect(code).toBe(1)
			t.expect(has(out, "z-nile/tests/tooling/a.spec.luau")).toBe(true)
			t.expect(has(out, "pickman/src/A.luau")).toBe(true)
			-- and the game spec names a tooling path
			write(`{dir}/z-nile/tests/tooling/a.watch.txt`, "z-nile/lib/x.luau\n")
			write(`{dir}/pickman/tests/unit/b.watch.txt`, "pickman/src/A.luau\nz-nile/lib/x.luau\n")
			local gcode, gout = run()
			t.expect(gcode).toBe(1)
			t.expect(has(gout, "pickman/tests/unit/b.spec.luau")).toBe(true)
			t.expect(has(gout, "z-nile/lib/x.luau")).toBe(true)
		end
	)

	it("AC5: the real tree's watch lists cross no suite", function()
		local r = process.exec("lune", { "run", "z-nile/watch-check" }, { cwd = top })
		t.expect(r.stdout .. r.stderr).toBe("")
		t.expect(r.code).toBe(0)
	end)

	it(
		"AC6: on the real tree a game change selects no tooling spec and a tooling change no game spec",
		function()
			local function homes(paths: { string }): { [string]: number }
				local _, out = realAffected(paths)
				local count: { [string]: number } = {}
				for _, spec in out do
					local home = string.match(spec, "^([^/]+)/") or "?"
					count[home] = (count[home] or 0) + 1
				end
				return count
			end
			local game = homes({ "pickman/src/shared/Logic/Game/init.luau" })
			t.expect((game.pickman or 0) > 0).toBe(true)
			t.expect(game["z-nile"]).toBe(nil)
			local project = homes({ "pickman/default.project.json" })
			t.expect(project["z-nile"]).toBe(nil)
			local tooling = homes({ "z-nile/engine/main.luau" })
			t.expect((tooling["z-nile"] or 0) > 0).toBe(true)
			for home in tooling do
				t.expect(home).toBe("z-nile")
			end
			local checks = homes({ "z-nile/check.sh", "z-nile/lib/graph.luau" })
			for home in checks do
				t.expect(home).toBe("z-nile")
			end
			-- a root file is read by the tooling's specs and by no game spec
			local config = homes({ ".luaurc", "selene.toml", ".models.toml", "zn" })
			t.expect((config["z-nile"] or 0) > 0).toBe(true)
			for home in config do
				t.expect(home).toBe("z-nile")
			end
		end
	)
end)
