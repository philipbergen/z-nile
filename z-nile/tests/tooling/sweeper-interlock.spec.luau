--!strict
-- R0026 review 001 F1: the jail's sweeper (fence.SWEEPER) refuses to sweep (exit 70) wherever its one probe could be
-- fooled. Off macOS there is no jail; an explicit pid is for specs, so it needs a jailed spec run (an EPERM from root's
-- or another user's pid proves nothing unjailed); and a test seam that names an unreadable file refuses instead of
-- widening the sweep to every pid. Each case lists only a background process it started, and expects it alive after.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- fixtures under this home's .cache (the working directory, c0120); root is for reading the tooling
local base = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/sweeper-interlock`
local jailed = process.env.PICKMAN_TEST_JAIL == "sandbox-exec"

local function alive(pid: string): boolean
	return string.match(pid, "^%d+$") ~= nil and process.exec("kill", { "-0", pid }).ok
end

-- a background process this spec owns, listed alone in a seam file; returns its pid and the file
local function survivor(name: string): (string, string)
	local pid = trim(
		process.exec("sh", { "-c", 'perl -e "select(undef, undef, undef, 30)" >/dev/null 2>&1 & echo $!' }).stdout
	)
	local only = `{base}/{name}`
	fs.writeFile(only, pid .. "\n")
	return pid, only
end

-- the run's top process: outside the jail when jailed, so a signal to it is refused there
local function topPid(): string
	local fenceDir = process.env.PICKMAN_TEST_FENCE or ""
	return trim(fs.readFile(`{fenceDir}/.cache/tests-run.lock/pid`))
end

local function sweep(outside: string, env: { [string]: string }): Result
	return process.exec("perl", { "-e", fence.SWEEPER, outside, "sh", "-c", "exit 0" }, { env = env })
end

-- refused with exit 70, by the rule whose message holds `why`, and the listed process lived
local function refused(r: Result, pid: string, why: string)
	local lived = alive(pid)
	process.exec("kill", { "-KILL", pid })
	t.expect(r.code).toBe(70)
	t.expect(string.find(r.stderr, "nothing swept", 1, true) ~= nil).toBe(true)
	t.expect(string.find(r.stderr, why, 1, true) ~= nil).toBe(true)
	t.expect(lived).toBe(true)
end

return t.spec("the sweeper's interlock", function(it)
	it("sets up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
	end)

	it("an explicit pid outside a jailed spec run is refused, even one whose probe says EPERM", function()
		local pid, only = survivor("only-unjailed")
		-- pid 1 is root's: kill 0 on it fails with EPERM everywhere, jail or not
		refused(
			sweep("1", { PICKMAN_SWEEP_ONLY = only, PICKMAN_TEST_JAIL = "" }),
			pid,
			if process.os == "macos" then "explicit pid" else "no jail"
		)
	end)

	it("a test seam that can't be read is refused, never a wider sweep", function()
		if not jailed then
			return -- unjailed, an earlier rule (no jail, or an explicit pid outside a jailed run) refuses first
		end
		local pid = survivor("only-unused")
		refused(sweep(topPid(), { PICKMAN_SWEEP_ONLY = `{base}/no-such-file` }), pid, "unreadable")
	end)

	it("inside an outer sandbox, a refused liveness probe reads as alive", function()
		-- R0026 review 001 F3: an outer sandbox, like the jail, refuses signals outside it; pid 1 is refused everywhere
		local saved = process.env.PICKMAN_TEST_JAIL
		process.env.PICKMAN_TEST_JAIL = "outer sandbox (protects the repository)"
		local outer = fence.alive("1")
		process.env.PICKMAN_TEST_JAIL = "none (not macOS: environment guards only)"
		local none = fence.alive("1")
		process.env.PICKMAN_TEST_JAIL = saved
		t.expect(outer).toBe(true)
		t.expect(none).toBe(false)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
