--!strict
-- c0132: when the jail's sweeper dies of a signal, the launcher (fence.REAPER) says who was still there before it stops
-- the specs' group: when, how long after the specs started, its own pid, the run's top process (PICKMAN_REAP_TOP, which
-- the runner sets to its own pid) and whether that lives, the memory the OS saw, the specs' group (the sweeper's own
-- pid), whether the watchdog lives, every other process still in the group with its command line, and its reading of
-- them. Each case runs a launcher of its own (as c0076's spec does) whose command stands in for the sweeper and kills
-- itself, or more, with SIGKILL. Here the launcher, its watchdog and the stand-in share this spec's one sandbox, so a
-- group signal reaches the watchdog, as one from outside the jail does in a real run; a real run's watchdog is outside
-- the jail, which only check.sh can build (AC7: a jail can't be nested).
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local home = string.gsub(process.cwd, "/+$", "")
local base = `{home}/.cache/c0132-report`
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

-- this Lune process: the parent of the launchers these cases start
local function myPid(): string
	return trim(process.exec("sh", { "-c", "echo $PPID" }).stdout)
end

-- runs a launcher of its own over `sh -c script`, as the run's launcher (PICKMAN_REAP_SWEPT=1, PICKMAN_REAP_TOP this
-- Lune unless `top` names another pid) or not
local function launch(script: string, swept: boolean, args: { string }?, top: string?): Result
	local argv = { "-e", fence.REAPER, "sh", "-c", script, "_" }
	if args then
		for _, a in args do
			table.insert(argv, a)
		end
	end
	local env = { PICKMAN_REAP_SWEPT = "", PICKMAN_REAP_TOP = "" }
	if swept then
		env = { PICKMAN_REAP_SWEPT = "1", PICKMAN_REAP_TOP = top or myPid() }
	end
	return process.exec("perl", argv, { env = env })
end

-- the report's "who" line
local function who(stderr: string): string
	return string.match(stderr, "tests/run: who: [^\n]*") or ""
end

-- the run's top process: outside the jail, same user, alive for the whole run (as c0076's spec reads it)
local function outsidePid(): string
	local checkout = process.env.PICKMAN_TEST_FENCE or ""
	local pid = trim(fs.readFile(`{checkout}/.cache/tests-run.lock/pid`))
	assert(string.match(pid, "^%d+$"), "no top process recorded in the run's lock")
	return pid
end

-- a stand-in for the specs: a process left in the group, its pid written to $1, then the stand-in sweeper's own death
local KILLED_ALONE = 'perl -e "select(undef, undef, undef, 30)" & echo $! > "$1"; '
	.. 'perl -e "select(undef, undef, undef, 0.3)"; kill -KILL $$'

return t.spec("c0132 a killed sweeper's report", function(it)
	it("sets up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
	end)

	it(
		"a sweeper killed alone: the report names the launcher, the live top process and the specs' group",
		function()
			local r = launch(KILLED_ALONE, true, { `{base}/alone.pid` })
			local line = who(r.stderr)
			t.expect(r.code).toBe(1)
			t.expect(has(r.stderr, "the jail's sweeper was killed (signal 9)")).toBe(true)
			local launcher, top, group = string.match(
				line,
				"launcher (%d+) %(the run's top process (%d+), alive%); memory [^;]+; specs group (%d+) "
			)
			t.expect(launcher ~= nil).toBe(true)
			t.expect(top).toBe(myPid())
			t.expect(group ~= nil and group ~= launcher).toBe(true)
			t.expect(has(line, `specs group {group} (the sweeper's own pid)`)).toBe(true)
		end
	)

	it(
		"a sweeper killed alone: the watchdog is alive and every process still in the group is listed",
		function()
			local pidfile = `{base}/listed.pid`
			local r = launch(KILLED_ALONE, true, { pidfile })
			local left = trim(fs.readFile(pidfile))
			local line = who(r.stderr)
			t.expect(string.match(line, "watchdog alive %(pid %d+%)") ~= nil).toBe(true)
			t.expect(
				has(
					line,
					"; 1 other process(es) still in the group; reading: the sweeper's pid alone was signalled"
				)
			).toBe(true)
			t.expect(string.match(line, "was signalled$") ~= nil).toBe(true)
			-- the left process, orphaned by the stand-in's death, with its command line
			t.expect(string.match(r.stderr, `\ntests/run:   {left} perl %-e select`) ~= nil).toBe(true)
			-- the watchdog is counted as such, never listed among the others
			t.expect(select(2, string.gsub(r.stderr, "\ntests/run:   ", "")) :: number).toBe(1)
		end
	)

	it("the report gives the memory the OS saw: percent free and swap used, read on macOS", function()
		local r = launch("kill -KILL $$", true)
		local free, swap =
			string.match(who(r.stderr), "; memory (%S+)%% free, swap used ([^;]+); specs group ")
		t.expect(free ~= nil and swap ~= nil).toBe(true)
		if process.os == "macos" then
			-- kern.memorystatus_level and vm.swapusage, which sysctl reads in the jail too
			t.expect(string.match(free :: string, "^%d+$") ~= nil and (tonumber(free) :: number) <= 100)
				.toBe(true)
			t.expect(string.match(swap :: string, "^%d+%.%d+[KMGT]$") ~= nil).toBe(true)
		else
			t.expect({ free, swap }).toEqual({ "?", "?" }) -- no such sysctl: unread, never invented
		end
	end)

	it("the report says when the run's top process is gone", function()
		local dead = trim(process.exec("sh", { "-c", "true & echo $!; wait" }).stdout) -- finished and reaped
		local r = launch("kill -KILL $$", true, nil, dead)
		t.expect(has(who(r.stderr), `(the run's top process {dead}, gone)`)).toBe(true)
	end)

	it("the group is still stopped after the report", function()
		local pidfile = `{base}/stopped.pid`
		launch(KILLED_ALONE, true, { pidfile })
		local left = trim(fs.readFile(pidfile))
		local waited = 0
		while alive(left) and waited < 3 do
			waited += task.wait(0.05)
		end
		local lived = alive(left)
		if lived then
			process.exec("kill", { "-KILL", left })
		end
		t.expect(lived).toBe(false)
	end)

	it(
		"a whole group killed with the watchdog in reach, as from outside the jail: gone, nothing left",
		function()
			local r = launch(
				'perl -e "select(undef, undef, undef, 30)" & perl -e "select(undef, undef, undef, 0.3)"; kill -KILL 0',
				true
			)
			local line = who(r.stderr)
			t.expect(r.code).toBe(1)
			t.expect(
				has(
					line,
					"; watchdog gone; 0 other process(es) still in the group; reading: the whole group was signalled from outside the jail"
				)
			).toBe(true)
			t.expect(string.match(line, "outside the jail$") ~= nil).toBe(true)
			t.expect(has(r.stderr, "\ntests/run:   ")).toBe(false)
		end
	)

	it("the watchdog killed with the sweeper and the rest left: read as neither group signal", function()
		-- the stand-in kills every other process of its group (the watchdog among them) but the one it left, then itself
		local r = launch(
			'perl -e "select(undef, undef, undef, 30)" & bg=$!; perl -e "select(undef, undef, undef, 0.3)"; '
				.. 'for p in $(pgrep -g $$); do [ "$p" = "$bg" ] || [ "$p" = "$$" ] || kill -KILL "$p"; done; kill -KILL $$',
			true
		)
		t.expect(
			has(
				who(r.stderr),
				"; watchdog gone; 1 other process(es) still in the group; reading: the watchdog was signalled with the sweeper, the rest of the group was not"
			)
		).toBe(true)
	end)

	it("a group pgrep can't read is unread, never an empty group", function()
		-- no pgrep (nor sysctl) on PATH: perl, sh and sleep by absolute path
		local r = process.exec(
			"/usr/bin/perl",
			{ "-e", fence.REAPER, "/bin/sh", "-c", "/bin/sleep 5 & /bin/sleep 0.3; kill -KILL $$" },
			{ env = { PICKMAN_REAP_SWEPT = "1", PICKMAN_REAP_TOP = myPid(), PATH = `{base}/no-such-dir` } }
		)
		local line = who(r.stderr)
		t.expect(r.code).toBe(1)
		t.expect(has(line, "; watchdog ?; group unread; reading: unread, no conclusion")).toBe(true)
		t.expect(has(line, "other process(es)")).toBe(false)
		t.expect(has(line, "watchdog gone")).toBe(false)
	end)

	it("when jailed, a top process outside the jail (its probe refused) reads as alive", function()
		if not jailed then
			return -- the top process is signalable unjailed; check.sh requires the jailed run on macOS
		end
		local top = outsidePid()
		local r = launch("kill -KILL $$", true, nil, top)
		t.expect(has(who(r.stderr), `(the run's top process {top}, alive)`)).toBe(true)
		fs.writeFile(`{home}/.cache/c0132-jailed-ran`, "")
	end)

	it("the report says when, and how long after the specs started, the sweeper died", function()
		local r = launch('perl -e "select(undef, undef, undef, 1.5)"; kill -KILL $$', true)
		local line = who(r.stderr)
		local secs =
			tonumber(string.match(line, "^tests/run: who: at [^,]+, (%d+)s after the specs started;") or "")
		t.expect(secs ~= nil and secs >= 1 and secs <= 30).toBe(true)
		-- the clock: four-digit year and hh:mm:ss
		t.expect(string.match(line, "^tests/run: who: at [^,]*%d%d:%d%d:%d%d[^,]*%d%d%d%d,") ~= nil)
			.toBe(true)
	end)

	it("a launcher not running a sweeper reports nothing, and a signal death stays 128+n", function()
		local r = launch("kill -KILL $$", false)
		t.expect(r.code).toBe(137)
		t.expect(has(r.stderr, "who:")).toBe(false)
		t.expect(has(r.stderr, "sweeper")).toBe(false)
	end)

	it("a sweeper that exits, even with a failing status, gets no report", function()
		local r = launch("exit 3", true)
		t.expect(r.code).toBe(3)
		t.expect(has(r.stderr, "who:")).toBe(false)
	end)

	it("the runner gives its launcher its own pid as PICKMAN_REAP_TOP, and no spec inherits it", function()
		t.expect(process.env.PICKMAN_REAP_TOP).toBe(nil)
		local src = string.gsub(fs.readFile("tests/lib/fence.luau"), "%s+", " ")
		t.expect(has(src, "PICKMAN_REAP_TOP = myPid(),")).toBe(true)
		t.expect(has(src, "unset PICKMAN_REAP_SWEPT PICKMAN_REAP_CACHE PICKMAN_REAP_TOP;")).toBe(true)
	end)

	it("the testing skill says how to read a killed sweeper's report", function()
		local top = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
		local skill = fs.readFile(`{top}/z-nile/skills/zz-test/SKILL.md`)
		local bullet = string.match(skill, "\n%s*%- %*%*Sweeper%*%*:[^\n]*") or ""
		-- the report, its readings, and the issue that takes the next one (c0167)
		t.expect(has(bullet, "`tests/run: who:`")).toBe(true)
		t.expect(has(bullet, "the memory the OS saw")).toBe(true)
		t.expect(has(bullet, "outside the jail), every other process")).toBe(true) -- where the watchdog runs
		t.expect(
			has(bullet, "`watchdog alive` with processes listed means only the sweeper's pid was signalled")
		)
			.toBe(true)
		t.expect(
			has(
				bullet,
				"`watchdog alive` with nothing left means the whole group was signalled from inside the jail (a spec), or the sweeper's pid alone once the specs had ended"
			)
		).toBe(true)
		t.expect(
			has(
				bullet,
				"`watchdog gone` with nothing left means the whole group was signalled from outside the jail"
			)
		).toBe(true)
		t.expect(has(bullet, "`?` means unread, no conclusion")).toBe(true)
		t.expect(has(bullet, "Copy the whole report into c0167")).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
