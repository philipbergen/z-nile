--!strict
-- c0114 AC16: the gate covers z-nile/ as it covered scripts/: a change there selects every spec (a .tracker/ document
-- selects none, like tracker/), the format stage reads z-nile/.tracker/ (stylua skips hidden folders unless named), the
-- types stage reads z-nile/ but not its sequestered specs, the repository-fence scan reads ./zn, z-nile/ and every
-- root's check.sh (not their unpromoted specs), the reviewed .cache list covers z-nile/, the stop hook gates z-nile/
-- changes, and CI runs the moved bootstrap and skips tracker-only pushes to every root. Fixtures under
-- .cache/c0114-gate.
local cachepaths = require("@tests/lib/cachepaths")
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
-- the gate's LUAU_DIRS, as z-nile/check.sh sets them
local function luauDirs(): { string }
	local line = string.match(fs.readFile("z-nile/check.sh"), "\nLUAU_DIRS=%(([^)]*)%)") :: string
	return string.split(line, " ")
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

	it("the stop hook gates a change under z-nile/, but not one to its tracker documents", function()
		local hook = fs.readFile("scripts/hooks/stop.sh")
		t.expect(has(hook, "grep -E '^(src|tests|z-nile)/'")).toBe(true)
		t.expect(has(hook, "grep -v '^z-nile/\\.tracker/'")).toBe(true)
		t.expect(has(hook, "z-nile/check.sh --affected")).toBe(true)
	end)

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
