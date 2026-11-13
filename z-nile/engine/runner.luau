--!strict
-- Runs one model step's CLI (c0117) under a supervisor: the CLI leads a process group of its own (so the cap, a
-- stall or `./zn dispatch stop` kills every process the step started, a `check.sh` or a Bash tool's children
-- included), and the supervisor holds a lifeline from the dispatcher (its stdin): when the dispatcher dies, however
-- it died, the supervisor kills the group. The stream is read line by line through the runtime's adapter, and a step
-- never waits for quota: one that prints nothing for `stallSeconds` (or, while a tool call runs, `toolSeconds`) is
-- killed. A kill by a stored id first checks that the group is still this run's (runner.sameRun): the supervisor holds
-- an flock on the run's lock file for as long as the group lives, so a held lock is a live run (`ps` is not allowed in
-- the specs' jail, and an flock can't be fooled by pid reuse). The adapter
-- (adapters.luau) is pure; this is the one place that starts a model CLI.
local adapters = require("./adapters")
local costrow = require("./costrow")
local fs = require("@lune/fs")
local kimisession = require("./kimisession")
local process = require("@lune/process")
local task = require("@lune/task")

local runner = {}

export type Request = {
	argv: { string }, -- argv[1] is the program
	cwd: string,
	env: { [string]: string },
	stdin: string?, -- the prompt, for the runtimes that read it there
	adapter: adapters.Adapter,
	cap: number, -- max_tokens: the running count past it kills the step
	maxCalls: number?, -- a call-capped runtime's max_calls: the next model call past it kills the step
	maxSeconds: number?, -- its wall-time ceiling (max_minutes): past it the step is killed as cap
	stallSeconds: number,
	toolSeconds: number, -- the stall limit while a tool call runs
	stateDir: string, -- holds the pid file, the stdin file and the stop marker
	onStart: ((id: Identity) -> ())?,
	onTick: (() -> ())?, -- called every tick while the step runs (the dispatcher's publish broker)
	beatFile: string?, -- a nested step's heartbeat in its parent's state folder: touched every second it runs (005 F3)
}
export type Identity = { pgid: number, lockFile: string }
export type Outcome = "ok" | "failed" | "quota" | "cap" | "cap-unknown" | "stalled" | "stopped"
export type Result = {
	outcome: Outcome,
	detail: string,
	tokens: number,
	final: number?,
	session: string?,
	wall: number?,
	cpu: number?,
}

-- The supervisor: forks the CLI into a new group led by itself (its stdin from the stdin file), writes the group's id,
-- then waits. Its own stdin is the lifeline: end of file means the dispatcher is gone, and the group is killed. When
-- the CLI exits, what is left of its group is killed too, and the supervisor exits with the CLI's code.
local SUPERVISOR = table.concat({
	"my $zn_t0 = eval { require(($ENV{ZN_TOP} // '.') . '/z-nile/lib/measure.pl'); znmeasure::now() };",
	"END { eval { znmeasure::write($ENV{ZN_MEASURE_FILE}, $zn_t0) if $zn_t0; } };",
	"use POSIX ();",
	"use Fcntl qw(:flock);",
	"my ($pidfile, $infile, $lockfile) = (shift @ARGV, shift @ARGV, shift @ARGV);",
	'open(my $lk, ">>", $lockfile) or die "lock file: $!\\n"; flock($lk, LOCK_EX | LOCK_NB) or die "the run is held\\n";',
	'my $pid = fork(); die "fork: $!\\n" unless defined $pid;',
	'if ($pid == 0) { setpgrp(0, 0); open(STDIN, "<", $infile) or die "stdin: $!\\n";',
	'  exec { $ARGV[0] } @ARGV or die "exec $ARGV[0]: $!\\n"; }',
	"setpgrp($pid, $pid);",
	'open(my $h, ">", $pidfile . ".tmp") or die "pid file: $!\\n"; print $h $pid; close $h; rename($pidfile . ".tmp", $pidfile);',
	"sub group { my $s = shift; kill($s, -$pid) if $pid > 1; }",
	"$SIG{TERM} = $SIG{INT} = $SIG{HUP} = sub { group(15); select(undef, undef, undef, 1); group(9); exit(143); };",
	"my $rin = ''; vec($rin, fileno(STDIN), 1) = 1;",
	"while (1) {",
	"  my $done = waitpid($pid, POSIX::WNOHANG());",
	"  if ($done == $pid) { my $code = $? >> 8; my $sig = $? & 127; group(15); exit($sig ? 128 + $sig : $code); }",
	"  my $r = $rin; my $n = select($r, undef, undef, 0.2);",
	"  if ($n > 0) { my $buf; my $got = sysread(STDIN, $buf, 64);",
	"    if (!$got) { group(15); select(undef, undef, undef, 2); group(9); exit(137); } }",
	"}",
}, "\n")

runner.STOP = "stop"
runner.PID = "pid"

-- An flock holder for `path` (the dispatcher's run lock): a perl that takes the lock (or exits 2 when it is held) and
-- keeps it until its stdin closes, which is when the dispatcher ends or dies. Returns it, or nil when held.
function runner.holdLock(path: string): any?
	local child = process.create("perl", {
		"-MFcntl=:flock",
		"-e",
		'open(my $l, ">>", $ARGV[0]) or exit 3; flock($l, LOCK_EX | LOCK_NB) or exit 2; print "held\n"; '
			.. "$| = 1; while (sysread(STDIN, my $b, 64)) {} exit 0;",
		path,
	}, {})
	local got = child.stdout:read()
	if got and string.find(got, "held", 1, true) then
		return child
	end
	child:kill()
	return nil
end

-- Whether someone holds an flock on `path` (a live run).
function runner.held(path: string): boolean
	if not fs.isFile(path) then
		return false
	end
	local r = process.exec("perl", {
		"-MFcntl=:flock",
		"-e",
		'open(my $l, "<", $ARGV[0]) or exit 1; exit(flock($l, LOCK_EX | LOCK_NB) ? 1 : 0);',
		path,
	})
	return r.code == 0
end

-- Whether `id` still names the same run: its supervisor still holds the run's lock (and the group id is sane).
function runner.sameRun(id: Identity): boolean
	if type(id) ~= "table" or type(id.pgid) ~= "number" or id.pgid <= 1 or id.pgid ~= math.floor(id.pgid) then
		return false
	end
	return type(id.lockFile) == "string" and runner.held(id.lockFile)
end

-- Signals the whole group (TERM, then KILL after `grace` seconds when it is still there). Never a group id of 1 or
-- less: `kill -- -1` signals every process the user owns.
function runner.killGroup(pgid: number, grace: number?)
	if pgid <= 1 or pgid ~= math.floor(pgid) then
		return
	end
	process.exec("kill", { "-TERM", "--", `-{pgid}` })
	local waited = 0
	while waited < (grace or 2) do
		if not process.exec("kill", { "-0", "--", `-{pgid}` }).ok then
			return
		end
		waited += task.wait(0.05)
	end
	process.exec("kill", { "-KILL", "--", `-{pgid}` })
end

local function readPid(path: string): number?
	if not fs.isFile(path) then
		return nil
	end
	return tonumber((string.gsub(fs.readFile(path), "%s+", "")))
end

function runner.run(r: Request): Result
	fs.writeDir(r.stateDir)
	local pidFile = `{r.stateDir}/{runner.PID}`
	local stopFile = `{r.stateDir}/{runner.STOP}`
	local inFile = `{r.stateDir}/stdin`
	local lockFile = `{r.stateDir}/run.lock`
	if fs.isFile(pidFile) then
		fs.removeFile(pidFile)
	end
	-- a stop marker is the caller's to clear before it marks the run running (review 002 F10): one here is a stop that
	-- came in since, and the CLI never starts
	if fs.isFile(stopFile) then
		return { outcome = "stopped", detail = "stopped by ./zn dispatch stop before it started", tokens = 0 }
	end
	fs.writeFile(inFile, r.stdin or "")
	local reportFile = `{r.stateDir}/measure.txt`
	r.env["ZN_MEASURE_FILE"] = reportFile
	if r.env["ZN_TOP"] == nil and process.env.ZN_TOP then
		r.env["ZN_TOP"] = process.env.ZN_TOP :: string
	end
	local args = { "-e", SUPERVISOR, pidFile, inFile, lockFile }
	for _, a in r.argv do
		table.insert(args, a)
	end
	-- the supervisor's stdin stays open until this function returns: it is the lifeline
	local child = process.create("perl", args, { cwd = r.cwd, env = r.env })
	local acc = adapters.newAcc()
	local quiet = 0 -- seconds since the last line on stdout
	local outDone, errDone = false, false
	local stderrTail = ""
	task.spawn(function()
		local pending = ""
		while true do
			local chunk = child.stdout:read()
			if chunk == nil or chunk == "" then
				break
			end
			quiet = 0
			pending ..= chunk
			while true do
				local nl = string.find(pending, "\n", 1, true)
				if not nl then
					break
				end
				local line = string.sub(pending, 1, nl - 1)
				pending = string.sub(pending, nl + 1)
				if line ~= "" then
					r.adapter.feed(acc, line)
				end
			end
		end
		if pending ~= "" then
			r.adapter.feed(acc, pending)
		end
		outDone = true
	end)
	task.spawn(function()
		while true do
			local chunk = child.stderr:read()
			if chunk == nil or chunk == "" then
				break
			end
			stderrTail = string.sub(stderrTail .. chunk, -4096)
		end
		errDone = true
	end)
	local pgid: number? = nil
	local early: Outcome? = nil
	local detail = ""
	local elapsed = 0
	local lastBeat = -1 -- when this step last wrote its own heartbeat
	local nextScan = 1 -- when it next reads its nested steps' heartbeats
	local beats: { [string]: string } = {}
	while not (outDone and errDone) do
		local dt = task.wait(0.05)
		quiet += dt
		elapsed += dt
		-- liveness both ways (review 004 F2): a nested step beats while it runs, and a nested step's fresh beat
		-- counts as this step's output, so an author waiting on a long review isn't stalled; a quiet nested step still
		-- stalls at its own limits, so nothing hangs
		-- a beat means "alive and within my limits" (review 005 F3), not "printing": once a second for as long as this
		-- loop runs, which is only while the step is inside its own stall and tool limits
		if r.beatFile and elapsed - lastBeat >= 1 then
			lastBeat = elapsed
			pcall(fs.writeFile, r.beatFile :: string, tostring(os.clock()) .. " " .. tostring(elapsed))
		end
		if elapsed >= nextScan then
			nextScan = elapsed + 1
			local okDir, names = pcall(fs.readDir, r.stateDir)
			for _, name in (if okDir then names else {}) :: { string } do
				local beat = `{r.stateDir}/{name}/beat`
				if fs.isDir(`{r.stateDir}/{name}`) and fs.isFile(beat) then
					local okRead, text = pcall(fs.readFile, beat)
					if okRead and beats[beat] ~= text then
						if beats[beat] ~= nil then
							quiet = 0
						end
						beats[beat] = text
					end
				end
			end
		end
		if not pgid then
			pgid = readPid(pidFile)
			if pgid and r.onStart then
				r.onStart({ pgid = pgid :: number, lockFile = lockFile })
			end
		end
		if r.onTick then
			r.onTick()
		end
		local limit = if adapters.toolRunning(acc) then r.toolSeconds else r.stallSeconds
		if fs.isFile(stopFile) then
			early, detail = "stopped", "stopped by ./zn dispatch stop"
		elseif r.maxCalls and acc.unknown then
			early, detail = "cap-unknown", `the call cap can't be trusted on this stream: {acc.unknown}`
		elseif r.maxCalls and acc.calls > (r.maxCalls :: number) then
			early, detail = "cap", `passed max_calls {r.maxCalls} at call {acc.calls}`
		elseif r.maxSeconds and elapsed > (r.maxSeconds :: number) then
			early, detail = "cap", `passed max_minutes {(r.maxSeconds :: number) / 60} of wall time`
		elseif acc.live > r.cap then
			early, detail = "cap", `passed max_tokens {r.cap} at {acc.live} tokens`
		elseif acc.quota then
			early, detail = "quota", acc.quota :: string
		elseif quiet >= limit then
			-- only what the CLI itself printed counts as a wait for quota, never the model's words
			local waiting = adapters.mentions(acc.cliText .. "\n" .. stderrTail, adapters.WAITING)
			if waiting then
				early, detail = "quota", `waited for quota ("{waiting}") with no output for {limit} s`
			else
				early, detail = "stalled", `no output for {limit} s`
			end
		end
		if early then
			break
		end
	end
	if early then
		pgid = pgid or readPid(pidFile)
		if pgid then
			runner.killGroup(pgid :: number)
		end
		child:kill()
		local waited = 0
		while not (outDone and errDone) and waited < 2 do
			waited += task.wait(0.05)
		end
	end
	child.stdin:close()
	local status = child:status()
	-- A headless kimi stream names its session and prints no usage. The session's wire holds the records.
	if r.adapter.runtime == "kimi-cli" and acc.final == nil and acc.session ~= nil and acc.session ~= "" then
		local root = process.env.PICKMAN_KIMI_SESSIONS
		if root == nil or root == "" then
			local home = process.env.HOME
			if home ~= nil and home ~= "" then
				root = `{home}/.kimi-code/sessions`
			end
		end
		local text = if root ~= nil and root ~= "" then kimisession.read(root, acc.session :: string) else nil
		if text ~= nil then
			for line in string.gmatch(text, "[^\n]+") do
				if string.find(line, '"usage.record"', 1, true) then
					r.adapter.feed(acc, line)
				end
			end
		end
	end
	local tokens = adapters.tokens(acc)
	local wall, cpu = nil, nil
	if fs.isFile(reportFile) then
		wall, cpu = costrow.report(fs.readFile(reportFile))
	end
	if early then
		return {
			outcome = early :: Outcome,
			detail = detail,
			tokens = tokens,
			final = acc.final,
			session = acc.session,
			wall = wall,
			cpu = cpu,
		}
	end
	local outcome: Outcome, why = adapters.finish(acc, status.ok, stderrTail, r.adapter.runtime)
	if outcome == "failed" and fs.isFile(stopFile) then
		return {
			outcome = "stopped",
			detail = "stopped by ./zn dispatch stop",
			tokens = tokens,
			final = acc.final,
			wall = wall,
			cpu = cpu,
		}
	end
	return {
		outcome = outcome,
		detail = why,
		tokens = tokens,
		final = acc.final,
		session = acc.session,
		wall = wall,
		cpu = cpu,
	}
end

return runner
