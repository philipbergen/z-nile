--!strict
-- c0120 AC3: a check.sh runs from its project's home. ac.sh changes to the home of the project whose root holds the
-- check.sh (pickman/ for pickman's, the root for z-nile's), so the paths a sequestered check.sh names (src/...,
-- tests/..., git pathspecs) are its project's; $ZN_ROOT names the root; a check.sh under a .tracker/ folder that no
-- project's root holds refuses to run. ./zn find and members print paths from the folder ./zn was run in, so
-- `$(scripts/tracker.sh find <id>)/...` and `for dir in $(... members R...)` work from the home. Fixture under
-- .cache/c0120-homes (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\nhome = "pickman"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\nhome = "."\n'
local SOURCE = 'HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"\n'
	.. 'source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
-- records where it ran, then checks a pathspec of its project and that a promoted-spec path resolves
local PICKMAN_CHECK = SOURCE
	.. 'printf "%s\\n%s\\n" "$(pwd -P)" "$ZN_ROOT" > "$HERE/where.txt"\n'
	.. 'check "AC1: the server adapters are untouched" git diff --quiet HEAD -- src/server\n'
	.. 'check "AC2: its own spec folder is found from here" test -d "$(scripts/tracker.sh find f0010)/acceptance"\n'
	-- its own .cache is fenced: git finds no repository in a folder there that has none, nor in .cache itself
	.. 'printf "%s\n" "$GIT_CEILING_DIRECTORIES" > "$HERE/ceiling.txt"\n'
	.. "mkdir -p .cache/c0120-nofixture/sub\n"
	.. "check \"AC3: no repository in a folder of its .cache\" bash -c '! git -C .cache/c0120-nofixture/sub rev-parse --git-dir'\n"
	.. "check \"AC4: no repository in its .cache itself\" bash -c '! git -C .cache rev-parse --git-dir'\n"
	.. "finish\n"
local ZNILE_CHECK = SOURCE .. 'printf "%s\\n" "$(pwd -P)" > "$HERE/where.txt"\ncheck "AC1: ok" true\nfinish\n'
-- both member loops pickman's rafts use: the forwarder's (R0035's) and the template's ($ZN_ROOT)
local RAFT_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'for dir in $(scripts/tracker.sh members R0010); do check "RC0: $(basename "$dir") (forwarder)" bash "$dir/check.sh"; done\n'
	.. 'for dir in $("$ZN_ROOT/zn" members R0010); do check "RC0: $(basename "$dir") (root)" bash "$dir/check.sh"; done\n'
	.. 'check "RC1: pickman\'s server adapters are here" test -d src/server\n'
	.. "finish\n"

local function doc(id: string, kind: string, extra: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id}\nslug: {id}\n{extra}design: ready\ncreated: 2026-10-20\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
end

local f: trackerfix.Fixture
local function at(rel: string): string
	return `{f.main}/{rel}`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- `bash <args>` from the fixture's pickman/ folder (a script there changes to it: no shell strings)
local function fromHome(args: { string }): fixture.Result
	local argv = { "pickman/from-home.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(f.main, "bash", argv)
end

return t.spec("c0120 checks run from their project's home", function(it)
	it("sets up a fixture with pickman's home and an issue, a raft and a z-nile issue", function()
		local seed: { [string]: string } = {
			["z-nile/projects.toml"] = REGISTRY,
			["pickman/scripts/tracker.sh"] = fs.readFile("pickman/scripts/tracker.sh"),
			["pickman/from-home.sh"] = 'cd "$(dirname "$0")" || exit 1\nexec bash "$@"\n',
			["pickman/src/server/Main.server.luau"] = "--!strict\nreturn nil\n",
			["pickman/.tracker/issues/f0010/f0010.md"] = doc("f0010", "feature", "raft: R0010\n"),
			["pickman/.tracker/issues/f0010/check.sh"] = PICKMAN_CHECK,
			["pickman/.tracker/issues/f0010/acceptance/.gitkeep"] = "",
			["pickman/.tracker/rafts/R0010/R0010.md"] = doc(
				"R0010",
				"feature",
				"issues: [f0010]\nsingle: true\n"
			),
			["pickman/.tracker/rafts/R0010/check.sh"] = RAFT_CHECK,
			["z-nile/.tracker/issues/c0020/c0020.md"] = doc("c0020", "chore", "raft: \n"),
			["z-nile/.tracker/issues/c0020/check.sh"] = ZNILE_CHECK,
			["other/.tracker/issues/c0030/check.sh"] = ZNILE_CHECK,
			-- for `ready`: the ignore rules, pickman's architecture map, a z-nile raft, and the inlined skills
			[".gitignore"] = fs.readFile(".gitignore") .. "where.txt\nceiling.txt\n",
			-- sources a pickman check.sh instead of running it (F6): ac.sh must refuse
			["pickman/source-it.sh"] = '. "$(bash scripts/tracker.sh find f0010)/check.sh"\necho "sourced and went on"\n',
			["pickman/.tracker/architecture.md"] = "# Architecture\n\nARCH-MARKER pickman's map\n",
			["z-nile/.tracker/issues/c0021/c0021.md"] = doc("c0021", "chore", "raft: R0020\n"),
			["z-nile/.tracker/issues/c0021/check.sh"] = ZNILE_CHECK,
			["z-nile/.tracker/rafts/R0020/R0020.md"] = doc(
				"R0020",
				"chore",
				"issues: [c0021]\nsingle: true\n"
			),
			["z-nile/.tracker/rafts/R0020/check.sh"] = ZNILE_CHECK,
		}
		for _, sk in { "execute-raft", "tracker", "architecture", "testing", "review" } do
			seed[`.claude/skills/{sk}/SKILL.md`] = fs.readFile(`.claude/skills/{sk}/SKILL.md`)
		end
		for _, state in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			seed[`pickman/.tracker/{state}/.gitkeep`] = ""
		end
		f = trackerfix.new("c0120-homes", seed)
		-- seeds are written as plain files: the forwarder is executable in the repository (mode 100755)
		fixture.exec(f.main, "chmod", { "+x", "pickman/scripts/tracker.sh" })
		fixture.git(f.main, { "commit", "-qam", "the forwarder is executable" })
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
	end)

	it("./zn check runs a pickman item's check.sh from pickman/, with $ZN_ROOT the root", function()
		local r = trackerfix.tr(f, f.main, { "check", "f0010" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "PASS  AC1: the server adapters are untouched")).toBe(true)
		t.expect(has(r.stdout, "PASS  AC2: its own spec folder is found from here")).toBe(true)
		local where = fs.readFile(at("pickman/.tracker/issues/f0010/where.txt"))
		local root = fixture.physical(f.main) :: string
		t.expect(where).toBe(`{root}/pickman\n{root}\n`)
	end)

	it(
		"a pickman check.sh's own .cache is fenced: in git's ceiling, with a sentinel, no repository found there",
		function()
			local r = trackerfix.tr(f, f.main, { "check", "f0010" })
			t.expect(has(r.stdout, "PASS  AC3: no repository in a folder of its .cache")).toBe(true)
			t.expect(has(r.stdout, "PASS  AC4: no repository in its .cache itself")).toBe(true)
			local root = fixture.physical(f.main) :: string
			local ceiling = ":"
				.. (string.gsub(fs.readFile(at("pickman/.tracker/issues/f0010/ceiling.txt")), "%s+$", ""))
				.. ":"
			t.expect(has(ceiling, `:{root}/.cache:`)).toBe(true)
			t.expect(has(ceiling, `:{root}/pickman/.cache:`)).toBe(true)
			t.expect(fs.isFile(at("pickman/.cache/.git"))).toBe(true)
		end
	)

	it("a sourced pickman check.sh refuses, instead of running from its caller's folder", function()
		local r = fromHome({ "source-it.sh" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "run a check.sh with bash, never source it")).toBe(true)
		t.expect(has(r.stdout, "sourced and went on")).toBe(false)
	end)

	it("a z-nile item's check.sh runs from the root", function()
		t.expect(trackerfix.tr(f, f.main, { "check", "c0020" }).ok).toBe(true)
		local root = fixture.physical(f.main) :: string
		t.expect(fs.readFile(at("z-nile/.tracker/issues/c0020/where.txt"))).toBe(`{root}\n`)
	end)

	it(
		"a pathspec in a pickman check.sh means pickman's file: a change there fails it, one at the root does not",
		function()
			fs.writeDir(at("src/server"))
			fs.writeFile(at("src/server/Main.server.luau"), "--!strict\nreturn 1\n")
			local rootOnly = trackerfix.tr(f, f.main, { "check", "f0010" })
			fs.removeDir(at("src"))
			fs.writeFile(at("pickman/src/server/Main.server.luau"), "--!strict\nreturn 2\n")
			local home = trackerfix.tr(f, f.main, { "check", "f0010" })
			fixture.git(f.main, { "checkout", "--", "pickman/src/server/Main.server.luau" })
			t.expect(rootOnly.ok).toBe(true)
			t.expect(home.ok).toBe(false)
			t.expect(has(home.stdout, "FAIL  AC1: the server adapters are untouched")).toBe(true)
		end
	)

	it("a raft's member loops work from pickman/, through the forwarder and through $ZN_ROOT", function()
		local r = trackerfix.tr(f, f.main, { "check", "R0010" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "PASS  RC0: f0010 (forwarder)")).toBe(true)
		t.expect(has(r.stdout, "PASS  RC0: f0010 (root)")).toBe(true)
		t.expect(has(r.stdout, "PASS  RC1: pickman's server adapters are here")).toBe(true)
		t.expect(has(r.stdout, "3/3 criteria passed")).toBe(true)
	end)

	it("find and members print paths from the folder ./zn was run in", function()
		t.expect(trackerfix.trOk(f, f.main, { "find", "f0010" })).toBe("pickman/.tracker/issues/f0010")
		t.expect(trackerfix.trOk(f, f.main, { "members", "R0010" })).toBe("pickman/.tracker/issues/f0010")
		local found = fromHome({ "scripts/tracker.sh", "find", "f0010" })
		t.expect(found.ok).toBe(true)
		t.expect(found.stdout).toBe(".tracker/issues/f0010\n")
		t.expect(fromHome({ "scripts/tracker.sh", "members", "R0010" }).stdout)
			.toBe(".tracker/issues/f0010\n")
		t.expect(fromHome({ "scripts/tracker.sh", "find", "c0020" }).stdout)
			.toBe("../z-nile/.tracker/issues/c0020\n")
	end)

	it("a check.sh under a .tracker/ folder that no project's root holds refuses to run", function()
		local r = fixture.exec(f.main, "bash", { "other/.tracker/issues/c0030/check.sh" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "is under no project root")).toBe(true)
		t.expect(fs.isFile(at("other/.tracker/issues/c0030/where.txt"))).toBe(false)
	end)

	it(
		"a pickman raft's prompt inlines pickman's architecture map; a z-nile raft's says it has none",
		function()
			local r = trackerfix.tr(f, f.main, { "ready", "R0010" })
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			local prompt = fs.readFile(at("pickman/.tracker/rafts/active/R0010/prompt.md"))
			t.expect(has(prompt, "## Architecture map (pickman/.tracker/architecture.md)")).toBe(true)
			t.expect(has(prompt, "ARCH-MARKER pickman's map")).toBe(true)
			t.expect(has(prompt, "## Work items (verbatim from pickman/.tracker/)")).toBe(true)
			local z = trackerfix.tr(f, f.main, { "ready", "R0020" })
			if not z.ok then
				error(z.stderr .. z.stdout)
			end
			local zp = fs.readFile(at("z-nile/.tracker/rafts/active/R0020/prompt.md"))
			t.expect(has(zp, "## Architecture map (z-nile/.tracker/architecture.md)")).toBe(true)
			t.expect(has(zp, "(z-nile/.tracker has no architecture.md: this project has none)")).toBe(true)
			t.expect(has(zp, "ARCH-MARKER")).toBe(false)
			-- the prompts are ignored files: the main checkout stays clean
			t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe("")
		end
	)

	it(
		"a pickman check.sh refuses when the registry can't be read, instead of running from the root",
		function()
			local good = fs.readFile(at("z-nile/projects.toml"))
			fs.writeFile(at("z-nile/projects.toml"), "this is = not [ toml\n")
			local r = fixture.exec(f.main, "bash", { "pickman/.tracker/issues/active/f0010/check.sh" }) -- readied above
			fs.writeFile(at("z-nile/projects.toml"), good)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "is under no project root")).toBe(true)
		end
	)
end)
