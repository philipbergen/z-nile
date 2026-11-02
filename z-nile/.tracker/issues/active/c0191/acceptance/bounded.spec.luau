--!strict
-- c0191 AC1: the bounded runner (`./zn run`, z-nile/lib/bounded.pl) stops a command at its wall-clock limit, at
-- its CPU limit, with everything it started, when its own process dies, and refuses a limit it cannot honour. Every
-- process these cases start is the runner's to stop; a case that fails stops its own leftovers (`cleanup`).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local BOUNDED = `{ROOT}/z-nile/lib/bounded.pl`
local ZN = `{ROOT}/zn`
local WORK = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/bounded-run`

local pidFiles: { string } = {}
-- a name no other checkout's run shares, so `pgrep` finds only this case's Lune processes
local PROBE = `spin-c0191-{os.time()}-{math.random(1, 1e9)}.luau`

local function reset()
	if fs.isDir(WORK) then
		fs.removeDir(WORK)
	end
	fs.writeDir(WORK)
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

-- a bounded poll, not a sleep to let something finish: true once the pid is gone, false after `tries` tenths of a
-- second (default 10 s)
local function goneSoon(pid: string, tries: number?): boolean
	if pid == "" then
		return false -- no pid was recorded: the command never ran, and nothing is gone
	end
	for _ = 1, tries or 50 do
		if not alive(pid) then
			return true
		end
		process.exec("sleep", { "0.2" })
	end
	return false
end

-- the watchdog of a runner that was killed (it is a copy of the runner) is the last to go: it first gives the group
-- its two seconds of grace. True once no process of this spec's runner is left.
local function runnerGoneSoon(): boolean
	for _ = 1, 50 do
		if not process.exec("pgrep", { "-f", `perl {BOUNDED} --time 60 -- sh -c` }).ok then
			return true
		end
		process.exec("sleep", { "0.2" })
	end
	return false
end

local function bounded(args: { string }): Result
	local argv = { BOUNDED }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("perl", argv, { cwd = WORK })
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
		"AC1: a command past --time is stopped, with exit 124 and a message naming the limit",
		wrap(function()
			local r = bounded({ "--time", "1", "--", "sh", "-c", "echo $$ > pid; exec sleep 61.1" })
			t.expect(r.code).toBe(124)
			t.expect(string.find(r.stderr, "wall-clock limit (--time 1 s)", 1, true) ~= nil).toBe(true)
			t.expect(goneSoon(readPid("pid"))).toBe(true)
		end)
	)

	it(
		"AC1: the whole tree is stopped, not just the process the runner started",
		wrap(function()
			local r = bounded({
				"--time",
				"1",
				"--",
				"sh",
				"-c",
				"sleep 62.2 & echo $! > child; sleep 62.3 & echo $! > grandchild; wait",
			})
			t.expect(r.code).toBe(124)
			t.expect(goneSoon(readPid("child"))).toBe(true)
			t.expect(goneSoon(readPid("grandchild"))).toBe(true)
		end)
	)

	it(
		"AC1: a Lune script that spins is stopped with its tool child",
		wrap(function()
			fs.writeFile(`{WORK}/{PROBE}`, "--!strict\nwhile true do end\n")
			local r = bounded({ "--time", "2", "--", "lune", "run", PROBE })
			t.expect(r.code).toBe(124)
			local left = true
			for _ = 1, 50 do
				if not process.exec("pgrep", { "-f", `lune run {PROBE}` }).ok then
					left = false
					break
				end
				process.exec("sleep", { "0.2" })
			end
			t.expect(left).toBe(false)
		end)
	)

	it(
		"AC1: what a command leaves running after it exits is stopped",
		wrap(function()
			local r = bounded({ "--", "sh", "-c", "sleep 63.1 >/dev/null 2>&1 & echo $! > left" })
			t.expect(r.code).toBe(0)
			t.expect(goneSoon(readPid("left"))).toBe(true)
		end)
	)

	it(
		"AC1: a survivor that ignores TERM is dead when the runner returns, not two seconds later",
		wrap(function()
			local r = bounded({
				"--",
				"sh",
				"-c",
				"trap '' TERM; sleep 63.9 >/dev/null 2>&1 & echo $! > stubborn",
			})
			t.expect(r.code).toBe(0)
			-- at the first or second look (well inside the two seconds): the runner's own final KILL did it; the watchdog's would come after its grace
			t.expect(goneSoon(readPid("stubborn"), 2)).toBe(true)
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
		"AC1: a command that burns CPU is stopped at --cpu, exit 125, naming the CPU limit",
		wrap(function()
			local r = bounded({ "--time", "60", "--cpu", "1", "--", "perl", "-e", "1 while 1" })
			t.expect(r.code).toBe(125)
			t.expect(string.find(r.stderr, "CPU limit (--cpu 1 s", 1, true) ~= nil).toBe(true)
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
		"AC1: when the runner itself is killed, its command's group is stopped by the watchdog",
		wrap(function()
			local script =
				`perl {BOUNDED} --time 60 -- sh -c 'echo $$ > cmd; exec sleep 64.1' & echo $! > runner; wait`
			-- the runner is started by a shell that this case then kills with the runner (KILL: nothing can clean up)
			local r = process.exec("sh", {
				"-c",
				`{script} & sh_pid=$!; sleep 1; kill -KILL $(cat runner); wait $sh_pid 2>/dev/null; exit 0`,
			}, { cwd = WORK })
			t.expect(r.ok).toBe(true)
			t.expect(goneSoon(readPid("cmd"))).toBe(true)
			t.expect(runnerGoneSoon()).toBe(true)
		end)
	)

	it(
		"AC1: TERM, INT and HUP sent to the runner reach the command's group, exits 143, 130 and 129",
		wrap(function()
			local signals: { { sig: string, want: number } } =
				{ { sig = "TERM", want = 143 }, { sig = "INT", want = 130 }, { sig = "HUP", want = 129 } }
			for _, c in signals do
				local sig, want = c.sig, c.want
				local r = process.exec("sh", {
					"-c",
					`perl {BOUNDED} --time 60 -- sh -c 'echo $$ > cmd-{sig}; exec sleep 65.1' & p=$!; sleep 1; kill -{sig} $p; wait $p; echo "code=$?"`,
				}, { cwd = WORK })
				if not string.find(r.stdout, `code={want}`, 1, true) then
					error(`{sig}: expected code={want}, got {r.stdout}{r.stderr}`, 0)
				end
				t.expect(goneSoon(readPid(`cmd-{sig}`))).toBe(true)
			end
			t.expect(runnerGoneSoon()).toBe(true)
		end)
	)

	it(
		"AC1: when the process that started the runner is gone, the command's group is stopped, exit 123",
		wrap(function()
			-- the runner is a background child of a shell that ends after a second: the runner is then an orphan
			local r = process.exec("sh", {
				"-c",
				`perl {BOUNDED} --time 60 -- sh -c 'echo $$ > cmd; exec sleep 66.1' > out.txt 2> err.txt & echo $! > runner; sleep 1; exit 0`,
			}, { cwd = WORK })
			t.expect(r.code).toBe(0)
			t.expect(goneSoon(readPid("cmd"))).toBe(true)
			t.expect(goneSoon(readPid("runner"))).toBe(true)
			t.expect(
				string.find(fs.readFile(`{WORK}/err.txt`), "the process that started it is gone", 1, true)
					~= nil
			).toBe(true)
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
			local burn = process.exec("sh", {
				"-c",
				`ulimit -t 2; exec perl {BOUNDED} --time 30 --cpu 50 -- perl -e '1 while 1'`,
			}, { cwd = WORK })
			t.expect(burn.code).toBe(125)
			t.expect(string.find(burn.stderr, "stopped at the CPU limit (--cpu 2 s", 1, true) ~= nil)
				.toBe(true)
		end)
	)

	it(
		"AC1: a failing command whose children together used most of the CPU limit keeps its own exit status",
		wrap(function()
			-- two children of 2.4 s each: 4.8 s in all, against a limit of 5 s per process; neither came near it
			local burn = "perl -e '1 while (times)[0] < 2.4'"
			local r = bounded({ "--time", "60", "--cpu", "5", "--", "sh", "-c", `{burn}; {burn}; exit 3` })
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
