--!strict
-- c0850: the runner's launcher (fence.REAPER) runs the specs in a process group of their own, with a watchdog in
-- that group that stops it when the launcher dies, however it died. The watchdog waits on a pipe whose only writer
-- is the launcher, ignores the signals the launcher forwards, and every fork is checked. Driven directly: a
-- launcher started here, running a stand-in command that records its pid, then killed. Only processes this spec
-- started are signalled.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0850-watchdog`

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function alive(pid: string): boolean
	return string.match(pid, "^%d+$") ~= nil and process.exec("kill", { "-0", pid }).ok
end

-- waits up to `seconds` (wall time, summed from task.wait) for `ready()`; true once it holds
local function waitUntil(seconds: number, ready: () -> boolean): boolean
	local waited = 0
	while not ready() do
		if waited >= seconds then
			return false
		end
		waited += task.wait(0.05)
	end
	return true
end

-- a stand-in for the specs: ignores INT, TERM and HUP, writes its pid to `pidfile`, then waits 30 s
local COMMAND = '$SIG{$_} = "IGNORE" for qw(INT TERM HUP); open my $f, ">", $ARGV[0] or die "pidfile: $!"; '
	.. "print $f $$; close $f; select(undef, undef, undef, 30)"

-- starts a launcher in the background running COMMAND; returns the launcher's pid and the command's pid
local function launch(name: string): (string, string)
	local pidfile = `{base}/{name}.pid`
	local r = process.exec("sh", {
		"-c",
		'perl -e "$1" perl -e "$2" "$3" >/dev/null 2>&1 & echo $!',
		"_",
		fence.REAPER,
		COMMAND,
		pidfile,
	})
	local launcher = trim(r.stdout)
	t.expect(alive(launcher)).toBe(true)
	t.expect(waitUntil(5, function()
		return fs.isFile(pidfile) and trim(fs.readFile(pidfile)) ~= ""
	end)).toBe(true)
	return launcher, trim(fs.readFile(pidfile))
end

local function stop(pids: { string })
	for _, pid in pids do
		if alive(pid) then
			process.exec("kill", { "-KILL", pid })
		end
	end
end

return t.spec("c0850 the run watchdog", function(it)
	it("sets up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
	end)

	it("when the launcher is killed, the command it ran is stopped within 3 seconds", function()
		local launcher, command = launch("killed")
		t.expect(alive(command)).toBe(true)
		process.exec("kill", { "-KILL", launcher })
		local gone = waitUntil(3, function()
			return not alive(command)
		end)
		stop({ command })
		t.expect(gone).toBe(true)
	end)

	it("the watchdog outlives INT, TERM and HUP forwarded to the group", function()
		local launcher, command = launch("signals")
		for _, sig in { "-TERM", "-INT", "-HUP" } do
			process.exec("kill", { sig, launcher }) -- the launcher passes each on to the command's group
			task.wait(0.2)
		end
		t.expect(alive(launcher)).toBe(true) -- the launcher forwards them, it doesn't die of them
		t.expect(alive(command)).toBe(true) -- the stand-in ignores them
		process.exec("kill", { "-KILL", launcher })
		local gone = waitUntil(3, function()
			return not alive(command)
		end)
		stop({ command })
		t.expect(gone).toBe(true)
	end)

	it("a normal end passes the command's status through and leaves nothing of its group behind", function()
		local pidfile = `{base}/normal.pid`
		local r = process.exec("perl", {
			"-e",
			fence.REAPER,
			"sh",
			"-c",
			'perl -e "select(undef, undef, undef, 30)" & echo "$$ $!" > "$1"; exit 4',
			"_",
			pidfile,
		})
		t.expect(r.code).toBe(4)
		local group, background = string.match(trim(fs.readFile(pidfile)), "^(%d+) (%d+)$")
		t.expect(group ~= nil and background ~= nil).toBe(true)
		local empty = waitUntil(3, function()
			return not alive(background :: string)
				and trim(process.exec("pgrep", { "-g", group :: string }).stdout) == ""
		end)
		stop({ background :: string })
		t.expect(empty).toBe(true)
	end)

	it(
		"every fork in the launcher is checked, the watchdog waits on a pipe, and the end runs in order",
		function()
			local src = fence.REAPER
			local forks = select(2, string.gsub(src, "=%s*fork%s*;", ""))
			local checked =
				select(2, string.gsub(src, '=%s*fork%s*;%s*die%s+"fork: %$!"%s+unless%s+defined', ""))
			t.expect(forks >= 2).toBe(true) -- the specs' process and the watchdog
			t.expect(checked).toBe(forks)
			t.expect((string.find(src, "!fork", 1, true))).toBe(nil)
			t.expect(string.find(src, "pipe(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "sysread", 1, true) ~= nil).toBe(true)
			t.expect((string.find(src, "kill 0", 1, true))).toBe(nil)
			t.expect((string.find(src, "getppid", 1, true))).toBe(nil)
			-- the order after the specs end: wait, kill the group, unlink links at the top of .cache (c0830), exit. The
			-- watchdog would kill the group anyway once the launcher exits, so only the source shows the order.
			local function at(part: string): number
				local i = string.find(src, part, 1, true)
				assert(i, `REAPER has no {part}`)
				return i :: number
			end
			local waited, killed, unlinked =
				at("waitpid($pid, 0)"), at("kill 'KILL', -$pid"), at("PICKMAN_REAP_CACHE")
			local exited = select(2, string.find(src, ".*exit%("))
			t.expect(waited < killed).toBe(true)
			t.expect(killed < unlinked).toBe(true)
			t.expect(unlinked < (exited or 0)).toBe(true)
		end
	)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
