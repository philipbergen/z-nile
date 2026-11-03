--!strict
-- c0191 AC1, the one-time proof with real limits: the bounded runner (z-nile/lib/bounded.pl) against real processes.
-- It spins CPU on purpose (a few seconds in all) and waits for real limits (about fifteen seconds), so it is NOT a spec:
-- it lives here only for check.sh, which runs it only before `./zn done`, bounded, through `./zn run --time 120 -- lune run proof-bounded.luau`,
-- to prove the implementation. `tests/run` never runs it (no `.spec.luau` name), so `./zn done` promotes it as a file
-- and the suite never executes it. The suite's half of AC1 is `bounded.spec.luau`, which watches the same rules
-- through a stand-in clock and CPU meter.
-- Unjailed, so it has to be safe by itself: every process it starts is a child of a runner under test with a limit
-- of at most 60 s, its only folder is a throwaway under .cache, and a recorded pid is signalled only while its command
-- line is one this script started (`sleep 6x.x` or the runner under test). Every spinner also stops itself after 20
-- seconds (a wall `alarm 20` for perl, `os.clock()` for Lune), and check.sh puts a kernel CPU cap (`ulimit -t 60`) in front of the script: they are bounded independently
-- of the runner under test. About four seconds of CPU and fifteen of wall clock. Prints one line per case; exit 1 on a failure.
local fs = require("@lune/fs")
local process = require("@lune/process")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local BOUNDED = `{ROOT}/z-nile/lib/bounded.pl`
local WORK =
	`{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/bounded-proof-{os.time()}-{math.random(
		1,
		1e9
	)}`
local PROBE = `spin-c0191-{os.time()}-{math.random(1, 1e9)}.luau` -- a name only this run's Lune processes carry

local failed = 0
local function expect(name: string, ok: boolean, why: string?)
	print(`{if ok then "ok  " else "FAIL"} {name}{if not ok and why then `: {why}` else ""}`)
	if not ok then
		failed += 1
	end
end

local pidFiles: { string } = {}
local function alive(pid: string): boolean
	return pid ~= "" and process.exec("kill", { "-0", pid }).ok
end
local function readPid(name: string): string
	local path = `{WORK}/{name}`
	table.insert(pidFiles, path)
	return if fs.isFile(path) then (string.gsub(fs.readFile(path), "%s+$", "")) else ""
end
-- a bounded poll, not a sleep to let something finish: true once the pid is gone, false after `tries` fifths of a second
local function goneSoon(pid: string, tries: number?): boolean
	if pid == "" then
		return false -- nothing was recorded: the command never ran
	end
	for _ = 1, tries or 50 do
		if not alive(pid) then
			return true
		end
		process.exec("sleep", { "0.2" })
	end
	return false
end
local function cleanup()
	for _, path in pidFiles do
		if fs.isFile(path) then
			local pid = (string.gsub(fs.readFile(path), "%s+$", ""))
			local cmd = process.exec("ps", { "-o", "command=", "-p", pid }).stdout
			if
				alive(pid) and (string.find(cmd, "sleep 6", 1, true) or string.find(cmd, BOUNDED, 1, true))
			then
				process.exec("kill", { "-KILL", pid })
			end
		end
	end
	pidFiles = {}
end
local function bounded(args: { string }): Result
	local argv = { BOUNDED }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("perl", argv, { cwd = WORK })
end
local function sh(script: string): Result
	return process.exec("sh", { "-c", script }, { cwd = WORK })
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
local function case(name: string, fn: () -> ())
	local ok, err = pcall(fn :: () -> any)
	if not ok then
		expect(name, false, tostring(err))
	end
	cleanup()
end
local function runnersGone(): boolean
	for _ = 1, 50 do
		if not process.exec("pgrep", { "-f", `perl {BOUNDED} --time 60 -- sh -c .*sleep 6[456]\\.1` }).ok then
			return true
		end
		process.exec("sleep", { "0.2" })
	end
	return false
end

fs.writeDir(WORK)

case("past --time", function()
	local r = bounded({ "--time", "1", "--", "sh", "-c", "echo $$ > pid; exec sleep 61.1" })
	expect(
		"AC1: a command past --time is stopped, exit 124, naming the limit",
		r.code == 124 and has(r.stderr, "wall-clock limit (--time 1 s)"),
		r.stderr
	)
	expect("AC1: and its process is gone", goneSoon(readPid("pid")))
end)

case("whole tree", function()
	local r = bounded({
		"--time",
		"1",
		"--",
		"sh",
		"-c",
		"sleep 62.2 & echo $! > child; sleep 62.3 & echo $! > grandchild; wait",
	})
	expect(
		"AC1: the whole tree is stopped at the wall-clock limit",
		r.code == 124 and goneSoon(readPid("child")) and goneSoon(readPid("grandchild"))
	)
end)

case("lune spinner", function()
	fs.writeFile(`{WORK}/{PROBE}`, "--!strict\nlocal t = os.clock()\nwhile os.clock() - t < 20 do end\n")
	local r = bounded({ "--time", "1", "--", "lune", "run", PROBE })
	local left = true
	for _ = 1, 50 do
		if not process.exec("pgrep", { "-f", `lune run {PROBE}` }).ok then
			left = false
			break
		end
		process.exec("sleep", { "0.2" })
	end
	expect(
		"AC1: a Lune script that spins is stopped with its tool child",
		r.code == 124 and not left,
		tostring(r.code)
	)
end)

case("left running", function()
	local r = bounded({ "--", "sh", "-c", "sleep 63.1 >/dev/null 2>&1 & echo $! > left" })
	expect(
		"AC1: what a command leaves running after it exits is stopped",
		r.code == 0 and goneSoon(readPid("left"))
	)
end)

case("survivor ignores TERM", function()
	local r = bounded({ "--", "sh", "-c", "trap '' TERM; sleep 63.9 >/dev/null 2>&1 & echo $! > stubborn" })
	-- at the first or second look (well inside the two seconds): the runner's own final KILL did it, not the watchdog's
	expect(
		"AC1: a survivor that ignores TERM is dead when the runner returns",
		r.code == 0 and goneSoon(readPid("stubborn"), 2)
	)
end)

case("real CPU limit", function()
	local r = bounded({ "--time", "60", "--cpu", "1", "--", "perl", "-e", "alarm 20; 1 while 1" })
	expect(
		"AC1: a command that burns CPU is stopped at --cpu 1, exit 125, naming the CPU limit",
		r.code == 125 and has(r.stderr, "CPU limit (--cpu 1 s"),
		`{r.code} {r.stderr}`
	)
	local burn = sh(`ulimit -t 1; exec perl {BOUNDED} --time 30 --cpu 50 -- perl -e 'alarm 20; 1 while 1'`)
	expect(
		"AC1: under a lower caller's limit it is reported against that limit",
		burn.code == 125 and has(burn.stderr, "stopped at the CPU limit (--cpu 1 s"),
		`{burn.code} {burn.stderr}`
	)
end)

case("children share the allowance", function()
	-- two children of 0.5 s each against a limit of 1 s per process: 1.0 s in all, and neither came near the limit
	local burn = "perl -e '1 while (times)[0] < 0.5'"
	local r = bounded({ "--time", "60", "--cpu", "1", "--", "sh", "-c", `{burn}; {burn}; exit 3` })
	expect(
		"AC1: a failing command whose children together used the limit keeps its status and gets a note",
		r.code == 3
			and has(r.stderr, "note: the command and its children used")
			and not has(r.stderr, "stopped at the CPU limit"),
		`{r.code} {r.stderr}`
	)
end)

case("runner killed", function()
	local script =
		`perl {BOUNDED} --time 60 -- sh -c 'echo $$ > cmd; exec sleep 64.1' & echo $! > runner; wait`
	local r = sh(`{script} & sh_pid=$!; sleep 1; kill -KILL $(cat runner); wait $sh_pid 2>/dev/null; exit 0`)
	expect(
		"AC1: when the runner is killed, the watchdog stops its command's group",
		r.ok and goneSoon(readPid("cmd")) and runnersGone()
	)
end)

case("signals", function()
	local signals: { { sig: string, want: number } } =
		{ { sig = "TERM", want = 143 }, { sig = "INT", want = 130 }, { sig = "HUP", want = 129 } }
	for _, c in signals do
		local sig, want = c.sig, c.want
		local r = sh(
			`perl {BOUNDED} --time 60 -- sh -c 'echo $$ > cmd-{sig}; exec sleep 65.1' & p=$!; sleep 1; kill -{sig} $p; wait $p; echo "code=$?"`
		)
		expect(
			`AC1: {sig} sent to the runner reaches the command's group, exit {want}`,
			has(r.stdout, `code={want}`) and goneSoon(readPid(`cmd-{sig}`)),
			r.stdout .. r.stderr
		)
	end
	expect("AC1: and no runner is left", runnersGone())
end)

case("parent gone", function()
	-- the runner is a background child of a shell that ends after a second: the runner is then an orphan
	local r = sh(
		`perl {BOUNDED} --time 60 -- sh -c 'echo $$ > cmd; exec sleep 66.1' > out.txt 2> err.txt & echo $! > runner; sleep 1; exit 0`
	)
	-- the message is written as the runner ends, so it is read after the processes are gone
	local gone = r.code == 0 and goneSoon(readPid("cmd")) and goneSoon(readPid("runner"))
	local said = fs.isFile(`{WORK}/err.txt`)
		and has(fs.readFile(`{WORK}/err.txt`), "the process that started it is gone")
	expect(
		"AC1: when the process that started the runner is gone, the group is stopped (exit 123 said on stderr)",
		gone and said
	)
end)

if fs.isDir(WORK) then
	fs.removeDir(WORK)
end
process.exit(if failed == 0 then 0 else 1)
