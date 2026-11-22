--!strict
-- d0426 step 2: the machine-wide gate queue. The real code runs against a lock folder under this spec's own .cache
-- (ZN_GATE_QUEUE_DIR), never the machine's. Every wait here has a short deadline.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local home = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{home}/.cache/gatequeue-spec`
local PL = `{root}/z-nile/lib/gatequeue.pl`
local SH = `{root}/z-nile/lib/gatequeue.sh`

local counter = 0

-- A fresh case folder: `dir` is the lock folder, `run` holds the rendezvous files.
local function fresh(): (string, string)
	counter += 1
	local case = `{base}/{counter}`
	pcall(function()
		fs.removeDir(case)
	end)
	fs.writeDir(`{case}/run`)
	return `{case}/lock`, `{case}/run`
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function read(path: string): string
	local ok, text = pcall(fs.readFile, path)
	return if ok then text else ""
end

local function waitFor(pred: () -> boolean): boolean
	for _ = 1, 200 do -- 10 s at most
		if pred() then
			return true
		end
		task.wait(0.05)
	end
	return false
end

local function env(dir: string, extra: { [string]: string }?): { [string]: string }
	local vars: { [string]: string } = {
		ZN_GATE_QUEUE_DIR = dir,
		ZN_GATE_QUEUE = "",
		ZN_GATE_WAIT = "",
		ZN_MEASURED = "",
	}
	local more: { [string]: string } = extra or {}
	for k, v in more do
		vars[k] = v
	end
	return vars
end

-- A command that says it is up, then waits (50 ms steps, 20 s at most) for the release file.
local function hold(run: string, name: string): string
	return `echo up > {run}/{name}.up; i=0; while [ ! -e {run}/{name}.rel ] && [ $i -lt 400 ]; do sleep 0.05; i=$((i+1)); done`
end

-- Starts `perl gatequeue.pl` in the background from a starter shell of its own (its pid lands in run/<name>.starter);
-- its output, then its exit code, land in run/<name>.out and .code.
local function start(
	dir: string,
	run: string,
	name: string,
	mode: string,
	extra: { [string]: string }?,
	body: string
)
	local vars = ""
	local more: { [string]: string } = extra or {}
	for k, v in env(dir, more) do
		vars ..= ` {k}='{v}'`
	end
	fs.writeFile(`{run}/{name}.cmd.sh`, body .. "\n")
	fs.writeFile(
		`{run}/{name}.sh`,
		`echo $$ > {run}/{name}.starter\nenv{vars} perl {PL} --mode {mode} --checkout /fixture/{name} -- sh {run}/{name}.cmd.sh > {run}/{name}.out 2>&1\necho $? > {run}/{name}.code\n`
	)
	process.exec("sh", { "-c", `( sh {run}/{name}.sh ) < /dev/null > /dev/null 2>&1 &` })
end

local function release(run: string, name: string)
	fs.writeFile(`{run}/{name}.rel`, "")
end

local function finished(run: string, name: string): boolean
	return waitFor(function()
		return fs.isFile(`{run}/{name}.code`) and read(`{run}/{name}.code`) ~= ""
	end)
end

local function code(run: string, name: string): string
	return (string.gsub(read(`{run}/{name}.code`), "%s+$", ""))
end

-- Runs gatequeue.pl in the foreground and waits for it.
local function gq(dir: string, args: { string }, extra: { [string]: string }?): (number, string)
	local argv = { PL, "--dir", dir }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("perl", argv, { env = env(dir, extra) })
	return r.code, r.stdout .. r.stderr
end

local function holderUp(run: string, name: string): boolean
	return waitFor(function()
		return fs.isFile(`{run}/{name}.up`)
	end)
end

return t.spec("d0426 the gate's machine-wide queue", function(it)
	it("a second holder waits and proceeds when the first releases", function()
		local dir, run = fresh()
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		start(dir, run, "b", "full", nil, "echo ran > " .. run .. "/b.ran")
		t.expect(waitFor(function()
			return has(read(`{run}/b.out`), "waiting for another gate")
		end)).toBe(true)
		t.expect(fs.isFile(`{run}/b.ran`)).toBe(false)
		release(run, "a")
		t.expect(finished(run, "b")).toBe(true)
		t.expect(code(run, "b")).toBe("0")
		t.expect(fs.isFile(`{run}/b.ran`)).toBe(true)
		t.expect(has(read(`{run}/b.out`), "gate: proceeding after waiting")).toBe(true)
		t.expect(finished(run, "a")).toBe(true)
		t.expect(code(run, "a")).toBe("0")
	end)

	it("the waiting line names the holder: pid, checkout, mode and since", function()
		local dir, run = fresh()
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		start(dir, run, "b", "full", nil, "true")
		t.expect(waitFor(function()
			return has(read(`{run}/b.out`), "waiting for another gate")
		end)).toBe(true)
		local line = ""
		for l in string.gmatch(read(`{run}/b.out`), "[^\n]+") do
			if has(l, "waiting for another gate") then
				line = l
			end
		end
		t.expect(has(line, "gate: waiting for another gate on this machine: pid ")).toBe(true)
		t.expect(string.match(line, "pid (%d+),") ~= nil).toBe(true)
		t.expect(has(line, "checkout /fixture/a")).toBe(true)
		t.expect(has(line, "mode affected")).toBe(true)
		t.expect(has(line, "since ")).toBe(true)
		t.expect(has(read(`{run}/b.out`), `gate: queue folder overridden: {dir}`)).toBe(true)
		release(run, "a")
		t.expect(finished(run, "b")).toBe(true)
	end)

	it("--list prints the holder and the waiter, one line each, and says so when no gate runs", function()
		local dir, run = fresh()
		local c0, out0 = gq(dir, { "--list" })
		t.expect(c0).toBe(0)
		t.expect(out0).toBe("no gate is running\n")
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		start(dir, run, "b", "full", nil, "true")
		t.expect(waitFor(function()
			return has(read(`{run}/b.out`), "waiting for another gate")
		end)).toBe(true)
		local c1, out1 = gq(dir, { "--list" })
		t.expect(c1).toBe(0)
		local lines = string.split((string.gsub(out1, "\n$", "")), "\n")
		t.expect(#lines).toBe(2)
		t.expect(has(lines[1] :: string, "running: pid ")).toBe(true)
		t.expect(has(lines[1] :: string, "checkout /fixture/a")).toBe(true)
		t.expect(has(lines[2] :: string, "waiting: pid ")).toBe(true)
		t.expect(has(lines[2] :: string, "checkout /fixture/b")).toBe(true)
		release(run, "a")
		t.expect(finished(run, "b")).toBe(true)
		t.expect(finished(run, "a")).toBe(true)
		local c2, out2 = gq(dir, { "--list" })
		t.expect(c2).toBe(0)
		t.expect(out2).toBe("no gate is running\n")
	end)

	it("a holder killed with SIGKILL frees the lock: the waiter proceeds, no stale file blocks", function()
		local dir, run = fresh()
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		-- the holder's pid is the first field of the description in the lock file
		local pid = string.match(read(`{dir}/lock`), "pid=(%d+)")
		t.expect(pid ~= nil).toBe(true)
		start(dir, run, "b", "full", nil, "echo ran > " .. run .. "/b.ran")
		t.expect(waitFor(function()
			return has(read(`{run}/b.out`), "waiting for another gate")
		end)).toBe(true)
		process.exec("kill", { "-9", pid :: string })
		t.expect(finished(run, "b")).toBe(true)
		t.expect(code(run, "b")).toBe("0")
		t.expect(fs.isFile(`{run}/b.ran`)).toBe(true)
		release(run, "a") -- the orphaned command of the killed holder ends now
	end)

	it("the wait limit fails with the holder named and never runs the command", function()
		local dir, run = fresh()
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		local c, out = gq(
			dir,
			{ "--mode", "full", "--checkout", "/fixture/b", "--", "touch", `{run}/b.ran` },
			{
				ZN_GATE_WAIT = "1",
			}
		)
		t.expect(c).toBe(75)
		t.expect(has(out, "gate: waiting for another gate")).toBe(true)
		t.expect(has(out, "gave up after")).toBe(true)
		t.expect(has(out, "run it again")).toBe(true)
		t.expect(has(out, "./zn gate-queue")).toBe(true)
		t.expect(has(out, "checkout /fixture/a")).toBe(true)
		t.expect(fs.isFile(`{run}/b.ran`)).toBe(false)
		release(run, "a")
		t.expect(finished(run, "a")).toBe(true)
	end)

	it("ZN_GATE_WAIT=0 fails at once, naming the holder, without a waiting line", function()
		local dir, run = fresh()
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		local c, out = gq(
			dir,
			{ "--mode", "full", "--checkout", "/fixture/b", "--", "touch", `{run}/b.ran` },
			{
				ZN_GATE_WAIT = "0",
			}
		)
		t.expect(c).toBe(75)
		t.expect(has(out, "another gate holds this machine")).toBe(true)
		t.expect(has(out, "run it again")).toBe(true)
		t.expect(has(out, "checkout /fixture/a")).toBe(true)
		t.expect(has(out, "waiting for another gate")).toBe(false)
		t.expect(fs.isFile(`{run}/b.ran`)).toBe(false)
		release(run, "a")
		t.expect(finished(run, "a")).toBe(true)
	end)

	it("ZN_GATE_QUEUE=off skips the queue and says so, even while a gate holds it", function()
		local dir, run = fresh()
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		local r = process.exec(
			"bash",
			{ "-c", `. "{SH}"; gatequeue_run full /fixture/b touch {run}/b.ran` },
			{ env = env(dir, { ZN_GATE_QUEUE = "off" }) }
		)
		t.expect(r.code).toBe(0)
		t.expect(has(r.stderr, "ZN_GATE_QUEUE=off")).toBe(true)
		t.expect(fs.isFile(`{run}/b.ran`)).toBe(true)
		-- off needs no folder at all (and never touches the machine's)
		local bare = process.exec(
			"bash",
			{ "-c", `. "{SH}"; gatequeue_run full /fixture/b touch {run}/c.ran` },
			{ env = env("", { ZN_GATE_QUEUE = "off", ZN_GATE_WAIT = "0" }) }
		)
		t.expect(bare.code).toBe(0)
		t.expect(fs.isFile(`{run}/c.ran`)).toBe(true)
		release(run, "a")
		t.expect(finished(run, "a")).toBe(true)
	end)

	it("a stale description with no lock held is never believed", function()
		local dir = fresh()
		fs.writeDir(dir)
		-- a description naming a live process (this spec's shell) and a dead one; nobody holds the lock
		local live = (string.gsub(process.exec("sh", { "-c", "echo $PPID" }).stdout, "%s+$", ""))
		for _, pid in { live, "999999" } do
			fs.writeFile(`{dir}/lock`, `pid={pid}\tcheckout=/ghost\tmode=full\tsince=1\n`)
			local c, out = gq(dir, { "--list" })
			t.expect(c).toBe(0)
			t.expect(out).toBe("no gate is running\n")
			local c2, out2 = gq(dir, { "--mode", "full", "--checkout", "/fixture/b", "--", "true" })
			t.expect(c2).toBe(0)
			t.expect(has(out2, "waiting")).toBe(false)
			t.expect(has(out2, "ghost")).toBe(false)
		end
	end)

	it("--plan and an inner gate (ZN_MEASURED) take no lock while a gate holds it", function()
		local dir, run = fresh()
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		local plan = process.exec(
			"bash",
			{ "-c", `. "{SH}"; gatequeue_run plan /fixture/b touch {run}/plan.ran` },
			{ env = env(dir, { ZN_GATE_WAIT = "0" }) }
		)
		t.expect(plan.code).toBe(0)
		t.expect(fs.isFile(`{run}/plan.ran`)).toBe(true)
		local inner = process.exec(
			"bash",
			{ "-c", `. "{SH}"; gatequeue_run full /fixture/b touch {run}/inner.ran` },
			{ env = env(dir, { ZN_GATE_WAIT = "0", ZN_MEASURED = "1" }) }
		)
		t.expect(inner.code).toBe(0)
		t.expect(fs.isFile(`{run}/inner.ran`)).toBe(true)
		-- the same call for an outermost full gate is refused at once (the lock is held)
		local outer = process.exec(
			"bash",
			{ "-c", `. "{SH}"; gatequeue_run full /fixture/b touch {run}/outer.ran` },
			{ env = env(dir, { ZN_GATE_WAIT = "0" }) }
		)
		t.expect(outer.code).toBe(75)
		t.expect(fs.isFile(`{run}/outer.ran`)).toBe(false)
		release(run, "a")
		t.expect(finished(run, "a")).toBe(true)
	end)

	it(
		"check.sh queues only the outermost gate: inside the ZN_MEASURED block, after the zone guard",
		function()
			local text = fs.readFile(`{root}/z-nile/check.sh`)
			local outer = string.find(text, 'if [[ -z "${ZN_MEASURED:-}" ]]; then', 1, true)
			local guard = string.find(text, "kzone_guard || exit 1", 1, true)
			local queue = string.find(text, "gatequeue_run", 1, true)
			local bounded = string.find(text, 'bounded.pl" --time 3600', 1, true)
			local over = string.find(text, '\ncd "$(dirname "$0")/.."', 1, true)
			t.expect(outer ~= nil and guard ~= nil and queue ~= nil and bounded ~= nil and over ~= nil)
				.toBe(true)
			t.expect((outer :: number) < (guard :: number)).toBe(true)
			t.expect((guard :: number) < (queue :: number)).toBe(true)
			t.expect((queue :: number) < (bounded :: number)).toBe(true)
			t.expect((bounded :: number) < (over :: number)).toBe(true)
			-- the one call wraps the bounded run; nothing else in the file calls it
			local _, count = string.gsub(text, "gatequeue_run ", "")
			t.expect(count).toBe(1)
		end
	)

	it(
		"the default lock folder is per user, outside every checkout, and the same from any checkout",
		function()
			local a = process.exec("perl", { PL, "--print-dir" }, { cwd = root, env = env("") })
			local b = process.exec("perl", { PL, "--print-dir" }, { cwd = home, env = env("") })
			-- env("") sets the override empty: it counts as unset
			local dirA = (string.gsub(a.stdout, "%s+$", ""))
			local dirB = (string.gsub(b.stdout, "%s+$", ""))
			t.expect(a.code).toBe(0)
			t.expect(dirA).toBe(dirB)
			local uid = (string.gsub(process.exec("id", { "-u" }).stdout, "%s+$", ""))
			t.expect(string.match(dirA, "^/[%w/]*/pickman%-gate%-queue%-" .. uid .. "$") ~= nil).toBe(true)
			t.expect(has(dirA, root)).toBe(false)
			t.expect(has(dirA, home)).toBe(false)
			t.expect(has(dirA, "/.cache")).toBe(false)
		end
	)
	it("the command's exit code is passed through: 3 gives 3, a SIGKILLed command 137", function()
		local dir = fresh()
		local c3 = gq(dir, { "--mode", "full", "--checkout", "/f", "--", "sh", "-c", "exit 3" })
		t.expect(c3).toBe(3)
		local c9 = gq(dir, { "--mode", "full", "--checkout", "/f", "--", "sh", "-c", "kill -9 $$" })
		t.expect(c9).toBe(137)
	end)

	it(
		"TERM to the holder reaches the command, and a second taker gets the lock only after the command ends",
		function()
			local dir, run = fresh()
			local body =
				`trap 'sleep 1; echo done > {run}/t.done; exit 0' TERM; echo up > {run}/a.up; i=0; while [ $i -lt 400 ]; do sleep 0.05; i=$((i+1)); done`
			start(dir, run, "a", "affected", nil, body)
			t.expect(holderUp(run, "a")).toBe(true)
			local pid = string.match(read(`{dir}/lock`), "pid=(%d+)")
			start(dir, run, "b", "full", nil, `[ -e {run}/t.done ] && echo saw > {run}/b.saw`)
			t.expect(waitFor(function()
				return has(read(`{run}/b.out`), "waiting for another gate")
			end)).toBe(true)
			process.exec("kill", { "-TERM", pid :: string })
			t.expect(finished(run, "b")).toBe(true)
			t.expect(fs.isFile(`{run}/b.saw`)).toBe(true)
			t.expect(finished(run, "a")).toBe(true)
			t.expect(code(run, "a")).toBe("0")
		end
	)

	it("a holder whose starter dies stops its command within seconds and frees the lock", function()
		local dir, run = fresh()
		local body =
			`echo $$ > {run}/a.cmdpid; echo up > {run}/a.up; i=0; while [ $i -lt 400 ]; do sleep 0.05; i=$((i+1)); done`
		start(dir, run, "a", "affected", nil, body)
		t.expect(holderUp(run, "a")).toBe(true)
		local cmdpid = (string.gsub(read(`{run}/a.cmdpid`), "%s+$", ""))
		process.exec("kill", { "-9", (string.gsub(read(`{run}/a.starter`), "%s+$", "")) })
		t.expect(waitFor(function()
			return not process.exec("kill", { "-0", cmdpid }).ok
		end)).toBe(true)
		local _, out = gq(dir, { "--list" })
		t.expect(out).toBe("no gate is running\n")
	end)

	it("a waiter whose starter dies exits without running its command", function()
		local dir, run = fresh()
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		start(dir, run, "b", "full", nil, `echo ran > {run}/b.ran`)
		t.expect(waitFor(function()
			return has(read(`{run}/b.out`), "waiting for another gate")
		end)).toBe(true)
		local names = fs.readDir(`{dir}/waiting`)
		local waiter = names[1] :: string
		process.exec("kill", { "-9", (string.gsub(read(`{run}/b.starter`), "%s+$", "")) })
		t.expect(waitFor(function()
			return not process.exec("kill", { "-0", waiter }).ok
		end)).toBe(true)
		release(run, "a")
		t.expect(finished(run, "a")).toBe(true)
		t.expect(fs.isFile(`{run}/b.ran`)).toBe(false)
	end)

	it("a long wait says it is still waiting, with the holder", function()
		local dir, run = fresh()
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		start(dir, run, "b", "full", { ZN_GATE_STILL = "1" }, "true")
		t.expect(waitFor(function()
			return has(read(`{run}/b.out`), "gate: still waiting")
		end)).toBe(true)
		t.expect(has(read(`{run}/b.out`), "checkout /fixture/a")).toBe(true)
		release(run, "a")
		t.expect(finished(run, "b")).toBe(true)
	end)

	it(
		"a stale line from a dead holder is not believed while a fresh holder has not written its own yet",
		function()
			local dir, run = fresh()
			fs.writeDir(dir)
			fs.writeFile(`{dir}/lock`, "pid=999999\tcheckout=/ghost\tmode=full\tsince=1\n")
			process.exec("sh", {
				"-c",
				`( perl -e 'use Fcntl qw(:flock); open(F,"+<",$ARGV[0]) or die; flock(F,LOCK_EX); open(U,">",$ARGV[1]); print U $$; close U; alarm 15; sleep 15' {dir}/lock {run}/raw.pid < /dev/null > /dev/null 2>&1 & )`,
			})
			t.expect(waitFor(function()
				return read(`{run}/raw.pid`) ~= ""
			end)).toBe(true)
			local c, out = gq(
				dir,
				{ "--mode", "full", "--checkout", "/fixture/b", "--", "true" },
				{ ZN_GATE_WAIT = "0" }
			)
			process.exec("kill", { "-9", read(`{run}/raw.pid`) })
			t.expect(c).toBe(75)
			t.expect(has(out, "holder unknown")).toBe(true)
			t.expect(has(out, "ghost")).toBe(false)
			t.expect(has(out, "999999")).toBe(false)
		end
	)

	it(
		"a gate started by the holder itself fails at once, naming the ancestor, instead of waiting for itself",
		function()
			local dir, run = fresh()
			local body =
				`echo up > {run}/a.up; perl {PL} --mode x --checkout /y -- true > {run}/n.out 2>&1; echo $? > {run}/n.code`
			start(dir, run, "a", "affected", { ZN_GATE_WAIT = "3" }, body)
			t.expect(finished(run, "a")).toBe(true)
			t.expect((string.gsub(read(`{run}/n.code`), "%s+$", ""))).toBe("1")
			t.expect(has(read(`{run}/n.out`), "ancestor")).toBe(true)
		end
	)

	it(
		"tests/run queues its outermost run before bounded.pl, and an inner run (ZN_MEASURED=1) never does",
		function()
			local text = fs.readFile(`{root}/z-nile/tests/run.luau`)
			local outer = string.find(text, 'if process.env.ZN_MEASURED ~= "1" then', 1, true)
			local queue = string.find(text, "gatequeue.pl", 1, true)
			local bounded = string.find(text, "bounded.pl", 1, true)
			local inner = string.find(text, "The live daemon z-nile's live specs need", 1, true)
			t.expect(outer ~= nil and queue ~= nil and bounded ~= nil and inner ~= nil).toBe(true)
			t.expect((outer :: number) < (queue :: number)).toBe(true)
			t.expect((queue :: number) < (bounded :: number)).toBe(true)
			t.expect((bounded :: number) < (inner :: number)).toBe(true)
		end
	)

	it("a fixture tests/run started under a held lock does not start: exit 75, holder named", function()
		local dir, run = fresh()
		start(dir, run, "a", "affected", nil, hold(run, "a"))
		t.expect(holderUp(run, "a")).toBe(true)
		local r = process.exec("perl", {
			`{root}/z-nile/lib/bounded.pl`,
			"--time",
			"20",
			"--",
			"lune",
			"run",
			"tests/run",
			"--",
			"gatequeue-fixture-never-exists.spec.luau",
		}, { cwd = home, env = env(dir, { ZN_GATE_WAIT = "0" }) })
		release(run, "a")
		t.expect(r.code).toBe(75)
		t.expect(has(r.stdout .. r.stderr, "another gate holds this machine")).toBe(true)
		t.expect(has(r.stdout .. r.stderr, "checkout /fixture/a")).toBe(true)
		t.expect(finished(run, "a")).toBe(true)
	end)

	it(
		"exit 75 means the gate did not start: ac.sh passes it on, and every engine caller reads it",
		function()
			local ac = process.exec(
				"bash",
				{ "-c", `cd "{root}" && . z-nile/lib/ac.sh; check "AC1: x" sh -c 'exit 75'; finish` },
				{ env = env("") }
			)
			t.expect(ac.code).toBe(75)
			t.expect(has(ac.stdout, "did not start")).toBe(true)
			local main = fs.readFile(`{root}/z-nile/engine/main.luau`)
			local _, n = string.gsub(main, "sh%.exitIfNotStarted%(%)", "")
			t.expect(n >= 7).toBe(true)
			local lib = fs.readFile(`{root}/z-nile/lib/sh.luau`)
			t.expect(has(lib, "NOT_STARTED = 75")).toBe(true)
			local net = fs.readFile(`{root}/z-nile/engine/watchcmd.luau`)
			t.expect(has(net, "NOT_STARTED")).toBe(true)
		end
	)
end)
