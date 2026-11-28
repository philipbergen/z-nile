--!strict
-- c0462: the runner fails a case that made no assertion. A throwaway repository holds a copy of the runner (the way
-- c0058/lock.spec does): it sits under .cache, so the check is off there unless --require-assertions is given.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local fixture = require("@tests/lib/fixture")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local outer = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{outer}/.cache/c0462-vacuous`
local repo = `{base}/real`
local home = `{repo}/z-nile`
local LIST = `{home}/tests/vacuous-exempt.txt`
local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{repo}/{parent}`)
	end
	fs.writeFile(`{repo}/{path}`, text)
end

local function copyTree(rel: string)
	local src = `{root}/{rel}`
	if not fs.isFile(src) and not fs.isDir(src) then
		return -- not built yet: each case then fails on its own assertion
	elseif fs.isDir(src) then
		for _, name in fs.readDir(src) do
			copyTree(`{rel}/{name}`)
		end
	else
		write(rel, fs.readFile(src))
	end
end

-- a spec file of the copy's home: each case is { name, body }
local function spec(path: string, cases: { { string } }, inHome: string?)
	local text = `--!strict\nlocal t = {REQ}("@tests/lib/t")\nreturn t.spec("probe", function(it)\n`
	for _, c in cases do
		text ..= `\tit("{c[1]}", function()\n{c[2]}\n\tend)\n`
	end
	write(`{inHome or "z-nile"}/{path}`, text .. "end)\n")
end

local function runIn(dir: string, args: { string }): Result
	local all = { "run", "tests/run", "--" }
	for _, a in args do
		table.insert(all, a)
	end
	return process.exec("lune", all, { cwd = dir, env = { PICKMAN_TEST_FENCE = "" } })
end

local function run(args: { string }): Result
	return runIn(home, args)
end

local ASSERT = "\t\tt.expect(1).toBe(1)"
local NOTHING = "\t\tlocal x = 1"
local ready = false

return t.spec("c0462 the runner fails a case with no assertion", function(it)
	it("sets up a repository holding a copy of the runner and its guards", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(repo)
		for _, rel in {
			"z-nile/tests/run.luau",
			"z-nile/tests/lib",
			"z-nile/lib/ac.sh",
			"z-nile/lib/fence.sh",
			-- the unmeasured re-execution of the copied runner needs the bounded runner and what it loads
			"z-nile/lib/bounded.pl",
			"z-nile/lib/cpu.sh",
			"z-nile/lib/measure.pl",
		} do
			copyTree(rel)
		end
		for _, rel in { "z-nile/lib/git-hooks", "z-nile/.luaurc", ".luaurc", "rokit.toml", ".gitignore" } do
			copyTree(rel)
		end
		if fs.isDir(`{repo}/z-nile/lib/git-hooks`) then
			local r = process.exec("chmod", { "-R", "+x", `{repo}/z-nile/lib/git-hooks` })
			t.assert(r.ok, "chmod hooks")
		end
		local init = process.exec("git", { "init", "-q", "-b", "main", repo })
		t.assert(init.ok, "git init")
		spec("tests/probe/vac.spec.luau", { { "makes none", NOTHING } })
		spec("tests/probe/vac2.spec.luau", { { "also none", NOTHING } })
		spec("tests/probe/ok.spec.luau", { { "makes one", ASSERT } })
		spec("tests/probe/boom.spec.luau", { { "errors", '\t\terror("boom-own-error")' } })
		spec("tests/probe/two.spec.luau", { { "first asserts", ASSERT }, { "second does not", NOTHING } })
		spec("tests/acceptance/c9999/exempt.spec.luau", { { "listed item, none", NOTHING } })
		spec("tests/acceptance/c9998/unlisted.spec.luau", { { "unlisted item, none", NOTHING } })
		local NEST = '\t\tlocal process = ' .. REQ .. '("@lune/process")\n'
			.. '\t\tlocal r = process.exec("lune", { "run", "tests/run", "--", "--require-assertions", "tests/probe/vac.spec.luau" })\n'
		spec("tests/acceptance/c9999/nest.spec.luau", { { "listed item runs a nested vacuous run", NEST .. "\t\tt.expect(r.ok).toBe(true)" } })
		spec("tests/acceptance/c9998/nest.spec.luau", { { "unlisted item runs a nested vacuous run", NEST .. "\t\tt.expect(r.ok).toBe(false)" } })
		-- a second home: its forwarder runner and its re-export of the shared t
		for _, rel in { "pickman/tests/run.luau", "pickman/tests/lib/t.luau", "pickman/.luaurc" } do
			copyTree(rel)
		end
		spec("tests/probe/vac.spec.luau", { { "pickman makes none", NOTHING } }, "pickman")
		spec("tests/probe/ok.spec.luau", { { "pickman makes one", ASSERT } }, "pickman")
		fs.writeFile(LIST, "# probe list\nc9999\n")
		fixture.git(repo, { "add", "-A" })
		fixture.git(
			repo,
			{ "-c", "user.name=dev", "-c", "user.email=dev@example.invalid", "commit", "-qm", "runner" }
		)
		t.assert(fs.isFile(`{home}/tests/run.luau`), "the copied runner is there")
		ready = true
	end)

	it("with the flag a case with no assertion fails, naming the spec file and the case", function()
		t.assert(ready, "setup did not finish")
		local r = run({ "--require-assertions", "tests/probe/vac.spec.luau" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "FAIL tests/probe/vac.spec.luau :: makes none")).toBe(true)
		t.expect(has(r.stdout, "no assertion")).toBe(true)
	end)

	it("without the flag the same fixture passes, and says the check is off", function()
		t.assert(ready, "setup did not finish")
		local r = run({ "tests/probe/vac.spec.luau" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "assertion check off: fixture under .cache")).toBe(true)
	end)

	it("a case with one assertion passes with the flag", function()
		t.assert(ready, "setup did not finish")
		local r = run({ "--require-assertions", "tests/probe/ok.spec.luau" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "1 passed, 0 failed")).toBe(true)
	end)

	it("a case that errors keeps its own error, not the no-assertion message", function()
		t.assert(ready, "setup did not finish")
		local r = run({ "--require-assertions", "tests/probe/boom.spec.luau" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "boom-own-error")).toBe(true)
		t.expect(has(r.stdout, "no assertion")).toBe(false)
	end)

	it("an assertion of one case does not cover the next case", function()
		t.assert(ready, "setup did not finish")
		local r = run({ "--require-assertions", "tests/probe/two.spec.luau" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, ":: second does not")).toBe(true)
		t.expect(has(r.stdout, ":: first asserts")).toBe(false)
		t.expect(has(r.stdout, "1 passed, 1 failed")).toBe(true)
	end)

	it("the flag reaches every worker of a concurrent run", function()
		t.assert(ready, "setup did not finish")
		local r = run({ "--require-assertions", "--jobs", "2", "tests/probe/vac.spec.luau", "tests/probe/vac2.spec.luau" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "tests/probe/vac.spec.luau :: makes none")).toBe(true)
		t.expect(has(r.stdout, "tests/probe/vac2.spec.luau :: also none")).toBe(true)
	end)

	it("a file of a listed item passes with no assertion, an unlisted item's file fails", function()
		t.assert(ready, "setup did not finish")
		local listed = run({ "--require-assertions", "tests/acceptance/c9999/exempt.spec.luau" })
		t.expect(listed.ok).toBe(true)
		local unlisted = run({ "--require-assertions", "tests/acceptance/c9998/unlisted.spec.luau" })
		t.expect(unlisted.ok).toBe(false)
		t.expect(has(unlisted.stdout, "c9998/unlisted.spec.luau :: unlisted item, none")).toBe(true)
	end)

	it("a nested real-runner run inherits the exemption of a listed item's case only", function()
		t.assert(ready, "setup did not finish")
		local listed = run({ "--require-assertions", "tests/acceptance/c9999/nest.spec.luau" })
		t.expect(listed.ok).toBe(true)
		t.expect(has(listed.stdout, "assertion check off: started by exempt c9999")).toBe(true)
		-- the unlisted item's case asserts that its nested run FAILED: it passes only when no exemption was inherited
		local unlisted = run({ "--require-assertions", "tests/acceptance/c9998/nest.spec.luau" })
		t.expect(unlisted.ok).toBe(true)
	end)

	it("a stray ZN_VACUOUS_PARENT is dropped at the outermost re-execution", function()
		t.assert(ready, "setup did not finish")
		local r = process.exec(
			"lune",
			{ "run", "tests/run", "--", "--require-assertions", "tests/probe/vac.spec.luau" },
			{ cwd = home, env = { PICKMAN_TEST_FENCE = "", ZN_MEASURED = "", ZN_GATE_QUEUE = "off", ZN_VACUOUS_PARENT = "c9999" } }
		)
		-- exit 2 would mean a helper or the list refused, not the drop; 1 means the copied runner ran its cases and one failed
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "tests/probe/vac.spec.luau :: makes none")).toBe(true)
		t.expect(has(r.stdout, "started by exempt")).toBe(false)
	end)

	it("the check applies from a second home too", function()
		t.assert(ready, "setup did not finish")
		local bad = runIn(`{repo}/pickman`, { "--require-assertions", "tests/probe/vac.spec.luau" })
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stdout, "tests/probe/vac.spec.luau :: pickman makes none")).toBe(true)
		local good = runIn(`{repo}/pickman`, { "--require-assertions", "tests/probe/ok.spec.luau" })
		t.expect(good.ok).toBe(true)
		t.expect(has(good.stdout, "1 passed, 0 failed")).toBe(true)
	end)

	it("a missing or malformed list stops the run with exit 2, never an empty list", function()
		t.assert(ready, "setup did not finish")
		fs.writeFile(LIST, "c9999\nc0001\n") -- unsorted
		local bad = run({ "--require-assertions", "tests/probe/ok.spec.luau" })
		t.expect(bad.code).toBe(2)
		t.expect(has(bad.stderr, "vacuous-exempt.txt")).toBe(true)
		fs.removeFile(LIST)
		local gone = run({ "--require-assertions", "tests/probe/ok.spec.luau" })
		t.expect(gone.code).toBe(2)
		t.expect(has(gone.stderr, "vacuous-exempt.txt")).toBe(true)
		-- the check is off without the flag: the list is not read
		local off = run({ "tests/probe/ok.spec.luau" })
		t.expect(off.ok).toBe(true)
	end)

	it("cleans up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
