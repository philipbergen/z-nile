--!strict
-- c0191 AC1 (the suite's half): the bounded runner (`./zn run`, z-nile/lib/bounded.pl) keeps a command's status and
-- output, hands every process its limits and the deadline, refuses a limit it cannot honour, and classifies how a
-- command ended (wall-clock limit: 124; CPU limit: 125; its own status near the limit: a note). Nothing here burns CPU,
-- waits for a limit or leaves a process running: the limits' outcomes are observed through stand-ins.
--   - a stand-in clock (`clock.pl`, a perl driver that overrides `time` for the runner and its watchdog with the real
--     time plus the number in the file `FAKE_SKEW` names, read at each call) lets a command pass the runner's deadline
--     by writing 100 to that file: the runner sees its wall-clock limit end on its next poll, a fifth of a second
--     later, and stops the one blocked `sleep` it started (nothing waits for a real limit);
--   - a stand-in `times` (`FAKE_CPU`, in the same driver) gives the CPU the command and its children "used", so the
--     runner's classification of a command that ended with status 1, 152 or its own is observed with no CPU spent.
-- The real-limit proofs (a spinner stopped by `--cpu` and by the wall clock, the whole group, the watchdog, the signals,
-- the departed parent) are `proof-bounded.luau`, which only `check.sh` runs, before `./zn done`, and `./zn done` never promotes.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local BOUNDED = `{ROOT}/z-nile/lib/bounded.pl`
local ZN = `{ROOT}/zn`
local WORK = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/bounded-run`

-- the stand-in clock and CPU meter: a driver that loads the runner under overridden `time` and `times`
local DRIVER = [=[
BEGIN {
	*CORE::GLOBAL::time = sub () {
		my $s = 0;
		if ( $ENV{FAKE_SKEW} && open my $f, '<', $ENV{FAKE_SKEW} ) { $s = <$f> + 0; close $f }
		CORE::time() + $s;
	};
	*CORE::GLOBAL::times = sub () { defined $ENV{FAKE_CPU} ? ( 0, 0, $ENV{FAKE_CPU} + 0, 0 ) : CORE::times() };
}
$0 = shift @ARGV;
do $0 or die "clock: $@ $!";
]=]

local pidFiles: { string } = {}

local function reset()
	if fs.isDir(WORK) then
		fs.removeDir(WORK)
	end
	fs.writeDir(WORK)
	fs.writeFile(`{WORK}/clock.pl`, DRIVER)
	pidFiles = {}
end

-- ps is setuid and cannot start inside the jail; kill -0 answers for a process of this sandbox
local function alive(pid: string): boolean
	return pid ~= "" and process.exec("kill", { "-0", pid }).ok
end

local function readPid(name: string): string
	local path = `{WORK}/{name}`
	table.insert(pidFiles, path)
	return if fs.isFile(path) then (string.gsub(fs.readFile(path), "%s+$", "")) else ""
end

-- stops whatever a failed case left, so nothing outlives the spec
local function cleanup()
	for _, path in pidFiles do
		if fs.isFile(path) then
			local pid = (string.gsub(fs.readFile(path), "%s+$", ""))
			if alive(pid) then
				process.exec("kill", { "-KILL", pid })
			end
		end
	end
end

local function bounded(args: { string }): Result
	local argv = { BOUNDED }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("perl", argv, { cwd = WORK })
end

-- the same runner under the stand-in clock and CPU meter; `env` sets FAKE_SKEW and FAKE_CPU
local function standIn(args: { string }, env: { [string]: string }): Result
	local argv = { `{WORK}/clock.pl`, BOUNDED }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("perl", argv, { cwd = WORK, env = env })
end

-- every case starts from an empty work folder and stops its own leftovers, whatever its outcome
local function wrap(fn: () -> ()): () -> ()
	return function()
		reset()
		local ok, err = pcall(fn :: () -> any)
		cleanup()
		if not ok then
			error(err, 0)
		end
	end
end

return t.spec("the bounded runner", function(it)
	it(
		"AC1: a command past --time is stopped, with exit 124 and a message naming the limit (stand-in clock)",
		wrap(function()
			local started = os.time()
			local r = standIn(
				{ "--time", "60", "--", "sh", "-c", "echo $$ > pid; echo 100 > skew; exec sleep 61.1" },
				{ FAKE_SKEW = `{WORK}/skew` }
			)
			-- the stop takes a fifth of a second and the command's sleep is 61.1 s: a runner that only flags the limit
			-- and signals nothing returns when the sleep ends, so this loose bound tells them apart without waiting
			t.expect(os.time() - started < 10).toBe(true)
			t.expect(r.code).toBe(124)
			t.expect(string.find(r.stderr, "wall-clock limit (--time 60 s)", 1, true) ~= nil).toBe(true)
			local pid = readPid("pid")
			t.expect(pid ~= "").toBe(true) -- the command did start
			t.expect(alive(pid)).toBe(false)
		end)
	)

	it(
		"AC1: a command that ends before its limit is not called stopped, though the clock is not moved",
		wrap(function()
			local r = standIn({ "--time", "60", "--", "sh", "-c", "exit 0" }, { FAKE_SKEW = `{WORK}/skew` })
			t.expect(r.code).toBe(0)
			t.expect(r.stderr).toBe("")
		end)
	)

	it(
		"AC1: a command that ends in time keeps its exit status and stays quiet",
		wrap(function()
			local r = bounded({ "--time", "30", "--", "sh", "-c", "echo out; echo err >&2; exit 7" })
			t.expect(r.code).toBe(7)
			t.expect(r.stdout).toBe("out\n")
			t.expect(r.stderr).toBe("err\n")
		end)
	)

	it(
		"AC1: a command that ended with status 1 or 152 having used its CPU allowance exits 125, naming the limit",
		wrap(function()
			for _, status in { "1", "152" } do
				local r = standIn(
					{ "--time", "60", "--cpu", "1", "--", "sh", "-c", `exit {status}` },
					{ FAKE_CPU = "1" }
				)
				if r.code ~= 125 then
					error(`exit {status}: expected 125, got {r.code}: {r.stderr}`, 0)
				end
				t.expect(string.find(r.stderr, "CPU limit (--cpu 1 s", 1, true) ~= nil).toBe(true)
			end
			-- the same status with half the allowance used is the command's own
			for _, status in { "1", "152" } do
				local half = standIn(
					{ "--time", "60", "--cpu", "1", "--", "sh", "-c", `exit {status}` },
					{ FAKE_CPU = "0.5" }
				)
				if half.code ~= tonumber(status) then
					error(`exit {status} at half the allowance: expected {status}, got {half.code}`, 0)
				end
				t.expect(string.find(half.stderr, "stopped at the CPU limit", 1, true) ~= nil).toBe(false)
			end
		end)
	)

	it(
		"AC1: every process of the command carries the CPU limit",
		wrap(function()
			local r =
				bounded({ "--time", "30", "--cpu", "7", "--", "sh", "-c", "ulimit -t; sh -c 'ulimit -t'" })
			t.expect(r.stdout).toBe("7\n7\n")
		end)
	)

	it(
		"AC1: --cpu defaults to --time",
		wrap(function()
			local r = bounded({ "--time", "9", "--", "sh", "-c", "ulimit -t" })
			t.expect(r.stdout).toBe("9\n")
		end)
	)

	it(
		"AC1: the command carries ZN_BOUNDED_DEADLINE, the epoch second its limit ends",
		wrap(function()
			local before = os.time()
			local r = bounded({ "--time", "30", "--", "sh", "-c", 'printf %s "$ZN_BOUNDED_DEADLINE"' })
			t.expect(string.match(r.stdout, "^%d%d%d%d%d%d%d%d%d%d$") ~= nil).toBe(true)
			local deadline = tonumber(r.stdout) :: number
			t.expect(deadline >= before + 30 and deadline <= os.time() + 30).toBe(true)
		end)
	)

	it(
		"AC1: a runner that inherits an ignored SIGCHLD still reports the command's status",
		wrap(function()
			local r = process.exec(
				"perl",
				{ "-e", '$SIG{CHLD} = "IGNORE"; exec @ARGV', "perl", BOUNDED, "--", "sh", "-c", "exit 7" },
				{ cwd = WORK }
			)
			t.expect(r.code).toBe(7)
		end)
	)

	it(
		"AC1: a runner copied without cpu.sh says so and exits 2, instead of failing every command",
		wrap(function()
			fs.writeDir(`{WORK}/alone`)
			fs.writeFile(`{WORK}/alone/bounded.pl`, fs.readFile(BOUNDED))
			local r = process.exec("perl", { `{WORK}/alone/bounded.pl`, "--", "true" }, { cwd = WORK })
			t.expect(r.code).toBe(2)
			t.expect(string.find(r.stderr, "cpu.sh is missing", 1, true) ~= nil).toBe(true)
		end)
	)

	it(
		"AC1: the largest limits are accepted",
		wrap(function()
			local r = bounded({ "--time", "3600", "--cpu", "3600", "--", "true" })
			t.expect(r.code).toBe(0)
		end)
	)

	it(
		"AC1: --cpu only lowers the limit the caller has: a lower inherited one stays, and the runner says so",
		wrap(function()
			local r = process.exec("sh", {
				"-c",
				`ulimit -t 20; exec perl {BOUNDED} --time 30 --cpu 50 -- sh -c 'ulimit -t'`,
			}, { cwd = WORK })
			t.expect(r.code).toBe(0)
			t.expect(r.stdout).toBe("20\n")
			t.expect(
				string.find(r.stderr, "the caller's CPU limit of 20 s is lower than --cpu 50", 1, true) ~= nil
			)
				.toBe(true)
			local lower = process.exec("sh", {
				"-c",
				`ulimit -t 20; exec perl {BOUNDED} --time 30 --cpu 5 -- sh -c 'ulimit -t'`,
			}, { cwd = WORK })
			t.expect(lower.stdout).toBe("5\n")
			t.expect(lower.stderr).toBe("")
			-- and what the lower limit stops is reported against that limit, not the larger one that was asked for
			-- (stand-in meter: the command "used" the 2 s of the caller's limit)
			local stopped = process.exec("sh", {
				"-c",
				`ulimit -t 2; exec perl {WORK}/clock.pl {BOUNDED} --time 30 --cpu 50 -- sh -c 'exit 1'`,
			}, { cwd = WORK, env = { FAKE_CPU = "2" } })
			t.expect(stopped.code).toBe(125)
			t.expect(string.find(stopped.stderr, "stopped at the CPU limit (--cpu 2 s", 1, true) ~= nil)
				.toBe(true)
		end)
	)

	it(
		"AC1: a failing command whose children together used most of the CPU limit keeps its own exit status",
		wrap(function()
			-- the meter says 4.8 s in all against a limit of 5 s per process: no single process came near it
			local r = standIn(
				{ "--time", "60", "--cpu", "5", "--", "sh", "-c", "exit 3" },
				{ FAKE_CPU = "4.8" }
			)
			t.expect(r.code).toBe(3)
			t.expect(string.find(r.stderr, "note: the command and its children used", 1, true) ~= nil)
				.toBe(true)
			t.expect(string.find(r.stderr, "stopped at the CPU limit", 1, true) ~= nil).toBe(false)
		end)
	)

	it(
		"AC1: a limit the runner cannot honour, or no command, is refused with exit 2 naming the rule",
		wrap(function()
			local cases: { { args: { string }, says: string } } = {
				{ args = { "--time", "0", "--", "true" }, says = "--time must be 1..3600" },
				{ args = { "--time", "3601", "--", "true" }, says = "--time must be 1..3600" },
				{ args = { "--time", "x", "--", "true" }, says = "--time needs a whole number" },
				{ args = { "--cpu", "0", "--", "true" }, says = "--cpu must be 1..3600" },
				{ args = { "--time", "5" }, says = "no command given" },
				{ args = { "--time", "5", "--time", "6", "--", "true" }, says = "--time given twice" },
				{ args = { "--forever", "--", "true" }, says = "unknown option --forever" },
			}
			for _, c in cases do
				local r = bounded(c.args)
				t.expect(r.code).toBe(2)
				t.expect(string.find(r.stderr, c.says, 1, true) ~= nil).toBe(true)
				t.expect(string.find(r.stderr, "usage: ./zn run", 1, true) ~= nil).toBe(true)
			end
		end)
	)

	it(
		"AC1: ./zn run is this runner, started before the engine, in the caller's folder",
		wrap(function()
			local r = process.exec(ZN, { "run", "--time", "20", "--", "pwd", "-P" }, { cwd = WORK })
			t.expect(r.code).toBe(0)
			t.expect(r.stdout).toBe(WORK .. "\n")
			local bad = process.exec(ZN, { "run", "--time", "0", "--", "true" }, { cwd = WORK })
			t.expect(bad.code).toBe(2)
		end)
	)
end)
