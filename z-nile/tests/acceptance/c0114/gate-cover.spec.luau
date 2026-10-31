--!strict
-- c0114 AC8: the gate covers z-nile/ as it covered scripts/: a change there selects every spec (a .tracker/ document
-- selects none, like tracker/), the format stage reads z-nile/.tracker/ (stylua skips hidden folders unless named), the
-- types stage reads z-nile/ but not its sequestered specs, the repository-fence scan reads ./zn, z-nile/ and every
-- root's check.sh (not their unpromoted specs), the reviewed .cache list covers z-nile/, the stop hook gates z-nile/
-- changes, and CI runs the moved bootstrap and skips tracker-only pushes to every root. Fixtures under
-- .cache/c0114-gate.
local cachepaths = require("@tests/lib/cachepaths")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- c0120 override: the spec runs from z-nile/ (its home, whose .cache holds the fixtures); the checkout it reads, copies
-- and runs the gate's tools in is the checkout's top
local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0114-gate`

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function affected(path: string): string
	local r = process.exec("lune", { "run", "z-nile/affected", "--", path }, { cwd = root }) -- c0120 override: at the top
	if not r.ok then
		error(r.stderr)
	end
	return r.stdout
end
local function copy(dest: string, rels: { string })
	for _, rel in rels do
		local parent = string.match(`{dest}/{rel}`, "^(.*)/[^/]+$") :: string
		fs.writeDir(parent)
		t.expect(process.exec("cp", { "-R", `{root}/{rel}`, `{dest}/{rel}` }).ok).toBe(true)
	end
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
-- the gate's format and lint folders, as z-nile/check.sh takes them (`lune run z-nile/roots -- --luau-dirs`), in `cwd`
local function luauDirs(cwd: string?): { string }
	-- c0120 override: the real tree's from its top
	local r = process.exec(
		"lune",
		{ "run", `{root}/z-nile/roots`, "--", "--luau-dirs" },
		{ cwd = cwd or root }
	)
	if not r.ok then
		error(r.stderr)
	end
	return string.split((string.gsub(r.stdout, "%s+$", "")), " ")
end

return t.spec("c0114 the gate covers z-nile/", function(it)
	it(
		"a change under z-nile/ or to ./zn selects every spec; a tracker document under any root selects none",
		function()
			for _, p in
				{
					"z-nile/engine/main.luau",
					"z-nile/lib/fence.sh",
					"z-nile/check.sh",
					"z-nile/projects.toml",
					"zn",
				}
			do
				t.expect(affected(p)).toBe("ALL\n")
			end
			t.expect(affected("z-nile/.tracker/issues/c0001/c0001.md")).toBe("")
			-- c0120 override: pickman's root is pickman/.tracker; tracker/ is retired, and a file there again runs
			-- everything, so the old-roots spec reports it
			t.expect(affected("pickman/.tracker/issues/c0001/c0001.md")).toBe("")
			t.expect(affected("tracker/issues/c0001/c0001.md")).toBe("ALL\n")
		end
	)

	it(
		"the format stage checks z-nile/ and z-nile/.tracker/, which stylua skips unless it is named",
		function()
			local dirs = luauDirs()
			-- c0120 override: the game's folders are pickman/'s, its root pickman/.tracker; the root has no tests/ (z-nile's
			-- moved into z-nile/)
			for _, d in
				{
					"pickman/src",
					"pickman/tests",
					"pickman/.tracker",
					"scripts",
					"z-nile",
					"z-nile/.tracker",
				}
			do
				t.expect(table.find(dirs, d) ~= nil).toBe(true)
			end
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			local fx = `{base}/format`
			copy(fx, { "stylua.toml" })
			write(`{fx}/z-nile/.tracker/issues/c0001/acceptance/x.spec.luau`, "local   x=1\nreturn x\n")
			write(`{fx}/z-nile/engine/y.luau`, "local   y=1\nreturn y\n")
			local args = { "--check" }
			for _, d in dirs do
				if fs.isDir(`{fx}/{d}`) then
					table.insert(args, d)
				end
			end
			local r = process.exec("stylua", args, { cwd = fx })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, "z-nile/.tracker/issues/c0001/acceptance/x.spec.luau"))
				.toBe(true)
			t.expect(has(r.stdout .. r.stderr, "z-nile/engine/y.luau")).toBe(true)
		end
	)

	it(
		"the types stage reads z-nile/ with Lune definitions, but not the sequestered specs under .tracker/",
		function()
			-- c0120 override: the folders come from the projects' homes (the gate's plan), each .tracker/ ignored; the gate
			-- is read and planned at the top, and it skips the homes' .cache folders (z-nile/.cache lies inside z-nile/)
			local gate = fs.readFile(`{root}/z-nile/check.sh`)
			t.expect(
				has(
					gate,
					[[--platform=standard --ignore='**/.tracker/**' --ignore='**/.cache/**' "${LUNE_DIRS[@]}"]]
				)
			).toBe(true)
			local plan = process.exec("bash", { "z-nile/check.sh", "--plan" }, { cwd = root })
			local line = string.match(plan.stdout, "types %(Lune%): ([^\n]*)") or ""
			-- c0120 override: the root has no tests/ (z-nile's moved into z-nile/)
			for _, d in { "scripts", "z-nile", "pickman/tests", "pickman/scripts" } do
				t.expect(table.find(string.split(line, " "), d) ~= nil).toBe(true)
			end
		end
	)

	it(
		"the repository-fence scan reads ./zn, z-nile/ and every root's check.sh, not their unpromoted specs",
		function()
			local scan = `{base}/scan`
			-- c0120 override: the runner, its harness and the scan spec are z-nile's (z-nile/tests, with z-nile/.luaurc),
			-- run from the copy's z-nile home
			copy(scan, {
				"z-nile/tests/run.luau",
				"z-nile/tests/lib",
				"z-nile/tests/tooling/repo-fence.spec.luau",
				"z-nile/.luaurc",
				"z-nile/lib",
				".luaurc",
				"rokit.toml",
				".gitignore",
			})
			t.expect(process.exec("git", { "init", "-q", "-b", "main", scan }).ok).toBe(true)
			local hooks = "hooks" .. "Path" -- spelled in two parts: once promoted, the scan reads this spec too
			write(`{scan}/z-nile/engine/planted.luau`, `-- git -c core.{hooks}=/dev/null push\n`)
			write(`{scan}/zn`, `#!/usr/bin/env bash\ngit -c core.{hooks}=/dev/null push\n`)
			write(`{scan}/z-nile/.tracker/issues/c0001/check.sh`, "git push --no-" .. "verify origin HEAD\n")
			write(
				`{scan}/z-nile/.tracker/issues/c0001/acceptance/x.spec.luau`,
				`-- {hooks}, not promoted yet\n`
			)
			-- c0120 override: the spec runs from z-nile/, its home, after the move
			local r = process.exec(
				"lune",
				{ "run", "tests/run", "--", "tests/tooling/repo-fence.spec.luau" },
				{ cwd = `{scan}/z-nile`, env = { PICKMAN_TEST_FENCE = "" } }
			)
			local out = r.stdout .. r.stderr
			t.expect(has(out, ":: no spec, check.sh or script switches a guard off or points git elsewhere"))
				.toBe(true)
			t.expect(has(out, `\n  zn names {hooks}`)).toBe(true)
			t.expect(has(out, `z-nile/engine/planted.luau names {hooks}`)).toBe(true)
			t.expect(has(out, "z-nile/.tracker/issues/c0001/check.sh names --no-" .. "verify")).toBe(true)
			t.expect(has(out, "acceptance/x.spec.luau")).toBe(false)
			-- an engine that is there but fails to load is an error, never a fallback to fewer roots
			write(`{scan}/z-nile/engine/projects.luau`, "--!strict\nreturn (\n")
			local broken = process.exec(
				"lune",
				{ "run", "tests/run", "--", "tests/tooling/repo-fence.spec.luau" },
				{ cwd = `{scan}/z-nile`, env = { PICKMAN_TEST_FENCE = "" } } -- c0120 override: from z-nile/
			)
			t.expect(broken.ok).toBe(false)
			t.expect(has(broken.stdout .. broken.stderr, "z-nile/engine/projects.luau does not load"))
				.toBe(true)
		end
	)

	it("the reviewed .cache list covers z-nile/, and an unlisted .cache write there is reported", function()
		t.expect(table.find(cachepaths.ROOTS, "z-nile") ~= nil).toBe(true)
		t.expect(cachepaths.SKIP["z-nile/.tracker"]).toBe(true)
		local found = cachepaths.scan(
			{ ["z-nile/engine/new.luau"] = 'fs.writeFile(".cache/new", text)\n' },
			cachepaths.ALLOWED
		)
		t.expect(table.find(found, 'z-nile/engine/new.luau: fs.writeFile(".cache/new", text)') ~= nil)
			.toBe(true)
		for path in cachepaths.ALLOWED do
			t.expect(fs.isFile(`{root}/{path}`)).toBe(true) -- c0120 override: from the top
			t.expect(string.sub(path, 1, 15) == "scripts/tracker" or string.sub(path, 1, 11) == "scripts/lib")
				.toBe(false)
		end
	end)

	it(
		"the stop hook gates a change under src/, tests/ or z-nile/ (no project root's documents), through scripts/check.sh",
		function()
			-- a tree with a stub gate at scripts/check.sh that records its call: the path both sides of the move have
			local function tree(name: string, withRoots: boolean): string
				local dir = `{base}/hook-{name}`
				if fs.isDir(dir) then
					fs.removeDir(dir)
				end
				fs.writeDir(dir)
				t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
				fixture.git(dir, { "config", "user.name", "c0114-gate" })
				fixture.git(dir, { "config", "user.email", "c0114-gate@example.invalid" })
				write(
					`{dir}/scripts/check.sh`,
					'#!/usr/bin/env bash\necho "$@" >> "$(dirname "$0")/../gate.log"\n'
				)
				process.exec("chmod", { "+x", `{dir}/scripts/check.sh` })
				if withRoots then
					copy(dir, { "z-nile/roots.luau", "z-nile/engine/projects.luau", "z-nile/projects.toml" })
				end
				write(`{dir}/readme`, "x\n")
				fixture.git(dir, { "add", "-A" })
				fixture.git(dir, { "commit", "-q", "-m", "base" })
				return dir
			end
			local function stop(dir: string): (boolean, boolean)
				local r = fixture.exec(
					dir,
					"bash",
					{ `{root}/scripts/hooks/stop.sh` },
					{ stdin = '{"cwd": "' .. dir .. '"}' }
				)
				local ran = fs.isFile(`{dir}/gate.log`)
				if ran then
					fs.removeFile(`{dir}/gate.log`)
				end
				return r.ok, ran
			end
			local now = tree("now", true)
			write(`{now}/z-nile/.tracker/issues/c0001/c0001.md`, "doc\n")
			t.expect({ stop(now) }).toEqual({ true, false }) -- a project root's document alone: no gate
			-- code whose path merely contains a root's name is not under the root: tests/lib/tracker/ is gated
			write(`{now}/tests/lib/tracker/x.luau`, "--!strict\nreturn 1\n")
			t.expect({ stop(now) }).toEqual({ true, true })
			write(`{now}/z-nile/engine/x.luau`, "--!strict\nreturn 1\n")
			t.expect({ stop(now) }).toEqual({ true, true }) -- the engine: the gate runs
			-- a tree from before c0114 (no z-nile/): the same hook runs that tree's own gate
			local old = tree("old", false)
			write(`{old}/src/x.luau`, "--!strict\nreturn 1\n")
			t.expect({ stop(old) }).toEqual({ true, true })
		end
	)

	it(
		"every root of the registry reaches every gate site, so a new root needs only its registry entry",
		function()
			-- the sites that read the registry follow a new root by themselves
			local fx = `{base}/registry`
			copy(fx, { "z-nile/projects.toml" })
			fs.writeFile(
				`{fx}/z-nile/projects.toml`,
				fs.readFile(`{fx}/z-nile/projects.toml`)
					.. '\n[[project]]\nname = "probe"\nroot = "probe/.tracker"\n'
			)
			t.expect(table.find(luauDirs(fx), "probe/.tracker") ~= nil).toBe(true)
			-- and in the real tree every current root is at every site, the ones that can't read the registry included
			local projects = require("@znile/engine/projects")
			-- c0120 override: the real tree is read from its top
			local roots = projects.roots(projects.load(root))
			local dirs = luauDirs()
			local wf = serde.decode("yaml", fs.readFile(`{root}/.github/workflows/deploy.yml`)) :: any
			local ignored: { string } = wf["on"].push["paths-ignore"]
			for _, r in roots do
				t.expect(table.find(dirs, r) ~= nil).toBe(true)
				t.expect(affected(`{r}/issues/c0001/c0001.md`)).toBe("")
				t.expect(cachepaths.SKIP[r]).toBe(true)
				t.expect(table.find(ignored, `{r}/**`) ~= nil).toBe(true)
			end
		end
	)

	it("deploy.yml skips tracker-only pushes to every root and the counter", function()
		local wf = serde.decode("yaml", fs.readFile(`{root}/.github/workflows/deploy.yml`)) :: any
		-- c0172 override: the ignore list moved with the gate. The workflow is read from the top.
		t.expect(wf["on"].push["paths-ignore"])
			.toEqual({ "pickman/.tracker/**", "z-nile/.tracker/**", "z-nile/next" })
		fs.removeDir(base)
	end)
end)
