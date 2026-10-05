--!strict
-- c0820: the jail's root is a sweeper (fence.SWEEPER) that runs the specs, waits, then kills every process it can
-- signal. Under the jail's signal rule (c0840) that is exactly the run's own leftovers, whatever session they moved
-- to. It never kills its ancestors, refuses to sweep outside such a jail, and passes the specs' status through.
-- Inside this spec's own jail every spec worker shares the sandbox, so each sweep here is narrowed to the pids a
-- case lists (PICKMAN_SWEEP_ONLY). Only processes this spec started are signalled. The real runner's sweep is
-- raft R0260's RC1.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0820-sweeper`
local jailed = process.env.PICKMAN_TEST_JAIL == "sandbox-exec"

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function alive(pid: string): boolean
	return string.match(pid, "^%d+$") ~= nil and process.exec("kill", { "-0", pid }).ok
end

local function waitGone(pid: string, seconds: number): boolean
	local waited = 0
	while alive(pid) do
		if waited >= seconds then
			return false
		end
		waited += task.wait(0.05)
	end
	return true
end

-- this Lune process (the spec's own runner)
local function myPid(): string
	return trim(process.exec("sh", { "-c", "echo $PPID" }).stdout)
end

-- the run's top process: outside the jail, same user, alive for the whole run
local function outsidePid(): string
	local checkout = process.env.PICKMAN_TEST_FENCE or ""
	local pid = trim(fs.readFile(`{checkout}/.cache/tests-run.lock/pid`))
	assert(string.match(pid, "^%d+$"), "no top process recorded in the run's lock")
	return pid
end

-- a process that double-forks into a session of its own and writes its pid to $1, then waits 30 s
local DETACH = 'perl -e \'exit if fork; setpgrp(0, 0); exit if fork; open STDOUT, ">", "/dev/null"; '
	.. 'open STDERR, ">&STDOUT"; open my $f, ">>", $ARGV[0] or die; print $f "$$\\n"; close $f; '
	.. "select(undef, undef, undef, 30)' \"$1\"; perl -e 'select(undef, undef, undef, 0.3)'"

local function sweep(outside: string, only: string, script: string, args: { string }?): Result
	local argv = { "-e", fence.SWEEPER, outside, "sh", "-c", script, "_" }
	if args then
		for _, a in args do
			table.insert(argv, a)
		end
	end
	return process.exec("perl", argv, { env = { PICKMAN_SWEEP_ONLY = only } })
end

return t.spec("c0820 the jail sweeps every process a run leaves behind", function(it)
	it("sets up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
	end)

	it("when jailed, a process the command left in a session of its own is stopped by the sweep", function()
		if not jailed then
			return -- needs the jail's signal rule; check.sh requires the jailed run on macOS
		end
		local only = `{base}/only-detached`
		fs.writeFile(only, "")
		local r = sweep(outsidePid(), only, DETACH .. "; exit 3", { only })
		local detached = trim(fs.readFile(only))
		t.expect(string.match(detached, "^%d+$") ~= nil).toBe(true)
		local gone = waitGone(detached, 2)
		if not gone then
			process.exec("kill", { "-KILL", detached })
		end
		t.expect(gone).toBe(true)
		t.expect(r.code).toBe(3)
		t.expect(has(r.stderr, "stopped 1")).toBe(true)
		fs.writeFile(`{base}/jailed-cases-ran`, "")
	end)

	it("when jailed, the sweep never stops its own ancestors or a process outside the jail", function()
		if not jailed then
			return
		end
		local only = `{base}/only-ancestors`
		local marker = `{base}/after-sweep`
		local outside = outsidePid()
		-- the shell that starts the sweeper, this Lune (its parent) and the run's top process are all listed
		local r = process.exec("sh", {
			"-c",
			'echo "$$ $PPID $3" > "$1"; perl -e "$2" "$3" sh -c "exit 0"; echo after > "$4"',
			"_",
			only,
			fence.SWEEPER,
			outside,
			marker,
		}, { env = { PICKMAN_SWEEP_ONLY = only } })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(marker)).toBe(true) -- the sweeper's parent shell lived on
		t.expect(alive(myPid())).toBe(true)
		t.expect(fence.alive(outside)).toBe(true) -- refused from inside the jail, but alive (c0840)
		t.expect(has(r.stderr, "stopped")).toBe(false)
	end)

	it("when jailed, the command's status passes through, a signal death as 128+n", function()
		if not jailed then
			return
		end
		local only = `{base}/only-empty`
		fs.writeFile(only, "")
		t.expect(sweep(outsidePid(), only, "exit 5").code).toBe(5)
		t.expect(sweep(outsidePid(), only, "kill -TERM $$").code).toBe(143)
	end)

	it("the sweep refuses, and stops nothing, when it can signal the pid it was told is outside", function()
		local only = `{base}/only-refused`
		local bg = trim(
			process.exec(
				"sh",
				{ "-c", 'perl -e "select(undef, undef, undef, 30)" >/dev/null 2>&1 & echo $!' }
			).stdout
		)
		fs.writeFile(only, bg .. "\n")
		local r = sweep(myPid(), only, "exit 0") -- this Lune: signalable from here, jailed or not
		local survived = alive(bg)
		process.exec("kill", { "-KILL", bg })
		t.expect(r.code).toBe(70)
		t.expect(has(r.stderr, "nothing swept")).toBe(true)
		t.expect(survived).toBe(true)
	end)

	it("the sweep refuses, and stops nothing, when the pid it was told is outside is gone", function()
		local only = `{base}/only-gone`
		local bg = trim(
			process.exec(
				"sh",
				{ "-c", 'perl -e "select(undef, undef, undef, 30)" >/dev/null 2>&1 & echo $!' }
			).stdout
		)
		fs.writeFile(only, bg .. "\n")
		local gone = trim(process.exec("sh", { "-c", "true & echo $!; wait" }).stdout) -- finished and reaped
		local r = sweep(gone, only, "exit 0")
		local survived = alive(bg)
		process.exec("kill", { "-KILL", bg })
		t.expect(r.code).toBe(70)
		t.expect(has(r.stderr, "nothing swept")).toBe(true)
		t.expect(survived).toBe(true)
	end)

	it("the launcher form refuses, and stops nothing, when its parent is already gone", function()
		local out = `{base}/orphan.out`
		local only = `{base}/only-orphan`
		fs.writeFile(only, "")
		-- the sweeper starts as an orphan: its parent exits first, so getppid() is 1
		process.exec("perl", {
			"-e",
			'exit if fork; select(undef, undef, undef, 0.3); open STDERR, ">", $ARGV[1] or die; '
				.. '$ENV{PICKMAN_SWEEP_ONLY} = $ARGV[2]; exec "perl", "-e", $ARGV[0], "-", "sh", "-c", "exit 0" or die',
			fence.SWEEPER,
			out,
			only,
		})
		local waited = 0
		while not (fs.isFile(out) and has(fs.readFile(out), "nothing swept")) and waited < 5 do
			waited += task.wait(0.05)
		end
		t.expect(has(fs.readFile(out), "no launcher above me")).toBe(true)
	end)

	it("the launcher fails a run whose sweeper died of a signal", function()
		local killed = { "-e", fence.REAPER, "perl", "-e", 'kill "KILL", $$' }
		local swept = process.exec("perl", killed, { env = { PICKMAN_REAP_SWEPT = "1" } })
		t.expect(swept.code).toBe(1)
		t.expect(has(swept.stderr, "sweeper was killed")).toBe(true)
		local plain = process.exec("perl", killed, { env = { PICKMAN_REAP_SWEPT = "" } })
		t.expect(plain.code).toBe(137)
		t.expect(has(plain.stderr, "sweeper")).toBe(false)
	end)

	it("a launcher a spec starts inherits none of the run's launcher settings", function()
		-- the run's own launcher variables stop at it: a launcher started here (as nested runs and these specs do)
		-- treats a signal death as 128+n, not as a killed sweeper, and unlinks nothing in the outer run's .cache
		t.expect(process.env.PICKMAN_REAP_SWEPT).toBe(nil)
		t.expect(process.env.PICKMAN_REAP_CACHE).toBe(nil)
		local r = process.exec("perl", { "-e", fence.REAPER, "perl", "-e", 'kill "KILL", $$' })
		t.expect(r.code).toBe(137)
		t.expect(has(r.stderr, "sweeper")).toBe(false)
	end)

	it("a real run's sweeper is started without the caller's PICKMAN_SWEEP_ONLY", function()
		local src = string.gsub(fs.readFile("tests/lib/fence.luau"), "%s+", " ")
		t.expect(has(src, '"env", "-u", "PICKMAN_SWEEP_ONLY", "perl", "-e", fence.SWEEPER, "-"')).toBe(true)
	end)
end)
