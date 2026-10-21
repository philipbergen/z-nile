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

local root = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0114-gate`

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function affected(path: string): string
	local r = process.exec("lune", { "run", "z-nile/affected", "--", path })
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
	local r = process.exec("lune", { "run", `{root}/z-nile/roots`, "--", "--luau-dirs" }, { cwd = cwd })
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
			t.expect(affected("tracker/issues/c0001/c0001.md")).toBe("")
		end
	)

	it(
		"the format stage checks z-nile/ and z-nile/.tracker/, which stylua skips unless it is named",
		function()
			local dirs = luauDirs()
			for _, d in { "src", "tests", "scripts", "tracker", "z-nile", "z-nile/.tracker" } do
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
			local gate = fs.readFile("z-nile/check.sh")
			t.expect(has(gate, "--platform=standard --ignore='**/.tracker/**' tests scripts z-nile"))
				.toBe(true)
		end
	)

	it(
		"the repository-fence scan reads ./zn, z-nile/ and every root's check.sh, not their unpromoted specs",
		function()
			local scan = `{base}/scan`
			copy(scan, {
				"tests/run.luau",
				"tests/lib",
				"tests/tooling/repo-fence.spec.luau",
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
			local r = process.exec(
				"lune",
				{ "run", "tests/run", "--", "tests/tooling/repo-fence.spec.luau" },
				{ cwd = scan, env = { PICKMAN_TEST_FENCE = "" } }
			)
			local out = r.stdout .. r.stderr
			t.expect(has(out, ":: no spec, check.sh or script switches a guard off or points git elsewhere"))
				.toBe(true)
			t.expect(has(out, `\n  zn names {hooks}`)).toBe(true)
			t.expect(has(out, `z-nile/engine/planted.luau names {hooks}`)).toBe(true)
			t.expect(has(out, "z-nile/.tracker/issues/c0001/check.sh names --no-" .. "verify")).toBe(true)
			t.expect(has(out, "acceptance/x.spec.luau")).toBe(false)
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
			t.expect(fs.isFile(path)).toBe(true)
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
			local roots = projects.roots(projects.load("."))
			local dirs = luauDirs()
			local wf = serde.decode("yaml", fs.readFile(".github/workflows/check.yml")) :: any
			local ignored: { string } = wf["on"].push["paths-ignore"]
			for _, r in roots do
				t.expect(table.find(dirs, r) ~= nil).toBe(true)
				t.expect(affected(`{r}/issues/c0001/c0001.md`)).toBe("")
				t.expect(cachepaths.SKIP[r]).toBe(true)
				t.expect(table.find(ignored, `{r}/**`) ~= nil).toBe(true)
			end
		end
	)

	it(
		"CI bootstraps with z-nile/setup.sh and skips tracker-only pushes to every root and the counter",
		function()
			local wf = serde.decode("yaml", fs.readFile(".github/workflows/check.yml")) :: any
			t.expect(wf["on"].push["paths-ignore"])
				.toEqual({ "tracker/**", "z-nile/.tracker/**", "z-nile/next" })
			local runs = ""
			for _, step in wf.jobs.gate.steps do
				runs ..= (step.run or "") .. "\n"
			end
			t.expect(has(runs, "z-nile/setup.sh\n")).toBe(true)
			t.expect(has(runs, "./zn members")).toBe(true)
			t.expect(has(runs, "scripts/")).toBe(false)
			local board = fs.readFile(".github/workflows/board.yml")
			t.expect(has(board, "run: ./zn board --out dist/board.html -O")).toBe(true)
			fs.removeDir(base)
		end
	)
end)
