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
	return `echo up > {run}/{name}.up; i=0; while [ ! -e {run}/{name}.rel ] \\&\\& [ $i -lt 400 ]; do sleep 0.05; i=$((i+1)); done`
end

-- Starts `perl gatequeue.pl` in the background; its output, then its exit code, land in run/<name>.out and .code.
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
	local script =
		`( env{vars} perl {PL} --mode {mode} --checkout /fixture/{name} -- sh -c '{body}' > {run}/{name}.out 2>&1; echo $? > {run}/{name}.code ) < /dev/null > /dev/null 2>&1 &`
	process.exec("sh", { "-c", (string.gsub(script, "\\&\\&", "&&")) })
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
		t.expect(c).toBe(1)
		t.expect(has(out, "gate: waiting for another gate")).toBe(true)
		t.expect(has(out, "gave up after")).toBe(true)
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
		t.expect(c).toBe(1)
		t.expect(has(out, "another gate holds this machine")).toBe(true)
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
		t.expect(outer.code).toBe(1)
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
end)
