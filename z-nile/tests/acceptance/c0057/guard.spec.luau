--!strict
-- c0550: the spec runner fails any run in which a spec started a browser (`open` or `xdg-open`), so a spec that runs
-- `tracker.sh board` without -O can't slip into the gate. Driven for real: a nested `tests/run` (its guard switched
-- on by clearing PICKMAN_OPEN_GUARD) runs small planted specs. Behind the guard's stubs, a backstop stub directory
-- sits on the nested runner's PATH, so even a broken guard never reaches a real opener; every case asserts that the
-- backstop was not called (with a working guard, the guard's own stubs come first).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local DIR = ".cache/c0550-guard"
local PROBE = "/nonexistent/c0550-guard-probe"
-- built by concatenation: a literal require in a string would be read as a real one by the graph scanner
local HEADER = "--!strict\nlocal fs = req"
	.. 'uire("@lune/fs")\nlocal process = req'
	.. 'uire("@lune/process")\n'

local function plant(name: string, body: string): string
	local path = `{DIR}/{name}.spec.luau`
	fs.writeFile(
		path,
		HEADER
			.. `return \{ name = "{name}", cases = \{ \{ name = "{name}", fn = function()\n{body}\nend \} \} \}\n`
	)
	return path
end

local BACKSTOP = `{process.cwd}{DIR}/backstop`

-- a fresh fixture directory with backstop openers that record into backstop/called
local function fresh()
	if fs.isDir(DIR) then
		fs.removeDir(DIR)
	end
	fs.writeDir(BACKSTOP)
	for _, name in { "open", "xdg-open" } do
		fs.writeFile(`{BACKSTOP}/{name}`, `#!/bin/sh\necho "{name} $*" >> "{BACKSTOP}/called"\n`)
		process.exec("chmod", { "+x", `{BACKSTOP}/{name}` })
	end
end

-- a nested runner with its own guard (PICKMAN_OPEN_GUARD cleared) and the backstop behind it, with raw arguments
local function runnerArgs(args: { string }, extra: { [string]: string }?): Result
	local env: { [string]: string } = {
		PICKMAN_OPEN_GUARD = "", -- a case may override it (a stale marker)
		PATH = `{BACKSTOP}:{process.env.PATH or ""}`,
	}
	local more: { [string]: string } = extra or {}
	for k, v in more do
		env[k] = v
	end
	local full = { "run", "tests/run", "--" }
	for _, a in args do
		table.insert(full, a)
	end
	local r = process.exec("lune", full, { env = env })
	-- the guard's stubs come before the backstop, so a working guard never lets a call reach it
	t.expect(fs.isFile(`{BACKSTOP}/called`)).toBe(false)
	return r
end

local function runner(jobs: string, files: { string }, extra: { [string]: string }?): Result
	local args = { "--jobs", jobs }
	for _, f in files do
		table.insert(args, f)
	end
	return runnerArgs(args, extra)
end

local function has(text: string, token: string): boolean
	return string.find(text, token, 1, true) ~= nil
end

local OPENS =
	`pcall(process.exec, "open", \{ "{PROBE}-open" \})\npcall(process.exec, "xdg-open", \{ "{PROBE}-xdg" \})`
local CLEAN = "local _ = 1"

return t.spec("c0550 runner browser guard", function(it)
	it("a spec that calls an opener fails the run, which names both calls (one spec, in-process)", function()
		fresh()
		local r = runner("1", { plant("opens", OPENS) })
		t.expect(r.ok).toBe(false)
		local out = r.stdout .. r.stderr
		t.expect(has(out, `open {PROBE}-open`)).toBe(true)
		t.expect(has(out, `xdg-open {PROBE}-xdg`)).toBe(true)
		t.expect(has(out, "1 passed, 0 failed")).toBe(true) -- the plant's own case passed: the guard failed the run
		fs.removeDir(DIR)
	end)

	it("a spec that runs tracker.sh board without -O fails the run, which names the page", function()
		fresh()
		-- c0120 override: ./zn resolves --out from the repository root, not from the home specs run in, and a spec may
		-- write only under its home's .cache: the page is named by its absolute path
		local body =
			`process.exec("scripts/tracker.sh", \{ "board", "--out", "{process.cwd}{DIR}/page.html" \})`
		local r = runner("1", { plant("board", body) })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, `{process.cwd}{DIR}/page.html`)).toBe(true)
		t.expect(has(r.stdout .. r.stderr, "browser")).toBe(true)
		fs.removeDir(DIR)
	end)

	it("a stale PICKMAN_OPEN_GUARD (no live guard there) does not switch the guard off", function()
		fresh()
		fs.writeDir(`{DIR}/stale`)
		local r = runner("1", { plant("opens", OPENS) }, { PICKMAN_OPEN_GUARD = `{process.cwd}{DIR}/stale` })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, `open {PROBE}-open`)).toBe(true)
		fs.removeDir(DIR)
	end)

	it("the same with concurrent workers", function()
		fresh()
		local r = runner("2", { plant("clean", CLEAN), plant("opens", OPENS) })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, `open {PROBE}-open`)).toBe(true)
		fs.removeDir(DIR)
	end)

	it("a clean run passes with its usual summary, in both modes", function()
		fresh()
		local one = runner("1", { plant("clean", CLEAN) })
		t.expect(one.ok).toBe(true)
		t.expect(has(one.stdout, "1 passed, 0 failed, 1 spec files")).toBe(true)
		local two = runner("2", { plant("clean", CLEAN), plant("clean2", CLEAN) })
		t.expect(two.ok).toBe(true)
		t.expect(has(two.stdout, "2 passed, 0 failed, 2 spec files")).toBe(true)
		t.expect(has(two.stdout .. two.stderr, "browser")).toBe(false)
		fs.removeDir(DIR)
	end)

	it("a failing spec still fails the run with exit code 1, in both modes", function()
		fresh()
		local one = runner("1", { plant("fails", 'error("planted failure")') })
		t.expect(one.code).toBe(1)
		t.expect(has(one.stdout, "planted failure")).toBe(true)
		t.expect(has(one.stdout, "0 passed, 1 failed, 1 spec files")).toBe(true)
		local two = runner("2", { plant("clean", CLEAN), plant("fails", 'error("planted failure")') })
		t.expect(two.code).toBe(1)
		t.expect(has(two.stdout, "1 passed, 1 failed, 2 spec files")).toBe(true)
		fs.removeDir(DIR)
	end)

	it("usage errors keep exit code 2 and their message on stderr", function()
		fresh()
		local file = plant("clean", CLEAN)
		local flag = runnerArgs({ "--jobs", "0", file })
		t.expect(flag.code).toBe(2)
		t.expect(has(flag.stderr, "bad value for --jobs")).toBe(true)
		local env = runnerArgs({ file }, { PICKMAN_JOBS = "x" })
		t.expect(env.code).toBe(2)
		t.expect(has(env.stderr, "bad value for PICKMAN_JOBS")).toBe(true)
		fs.removeDir(DIR)
	end)

	-- the contract for specs that test opening (open.spec, the tooling board spec): their own stubs, passed on PATH,
	-- receive the call and the run passes
	it("a spec's own opener stubs come first, and their calls are not counted", function()
		fresh()
		fs.writeDir(`{DIR}/bin`)
		local here = `{process.cwd}{DIR}`
		for _, name in { "open", "xdg-open" } do
			fs.writeFile(`{DIR}/bin/{name}`, `#!/bin/sh\necho "$@" >> "{here}/own.log"\n`)
			process.exec("chmod", { "+x", `{DIR}/bin/{name}` })
		end
		local body =
			`process.exec("open", \{ "{PROBE}-own" \}, \{ env = \{ PATH = "{here}/bin:" .. (process.env.PATH or "") \} \})`
		local r = runner("1", { plant("ownstubs", body) })
		t.expect(r.ok).toBe(true)
		t.expect(has(fs.readFile(`{DIR}/own.log`), `{PROBE}-own`)).toBe(true)
		fs.removeDir(DIR)
	end)

	it("specs see the guard, and its directory is gone after the run, clean or caught", function()
		fresh()
		local record = `fs.writeFile("{DIR}/guard-path", process.env.PICKMAN_OPEN_GUARD or "")`
		local r = runner("1", { plant("seesguard", record) })
		t.expect(r.ok).toBe(true)
		local guard = fs.readFile(`{DIR}/guard-path`)
		t.expect(guard ~= "").toBe(true)
		t.expect(fs.isDir(guard)).toBe(false)
		-- a run the guard fails cleans up too
		local caught = runner("1", { plant("seesopens", record .. "\n" .. OPENS) })
		t.expect(caught.ok).toBe(false)
		local guard2 = fs.readFile(`{DIR}/guard-path`)
		t.expect(guard2 ~= "" and guard2 ~= guard).toBe(true)
		t.expect(fs.isDir(guard2)).toBe(false)
		fs.removeDir(DIR)
	end)
end)
