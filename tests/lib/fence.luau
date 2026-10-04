--!strict
-- The spec runner's guard for the repository it runs in (testing skill, "Specs never touch the real
-- repository"). tests/run calls `fence.enter()` right after its AC_LIST refusal.
--
-- A top-level run (no valid PICKMAN_TEST_FENCE for this checkout):
--   1. takes this checkout's lock, .cache/tests-run.lock, so two runs never share the .cache fixtures;
--   2. snapshots what no check may change (see `snapshot`);
--   3. re-runs itself under scripts/lib/fence.sh's guards (git fenced inside .cache, inherited repository
--      overrides unset, ref updates in the real repository refused, no pushes into it), with the marker;
--   4. snapshots again, releases the lock, and fails the run if anything a check must not change did.
-- A run with a valid marker (a worker, or a run started from inside a run) is already guarded: it only
-- records its pid in the lock, so the lock stays held while any guarded process lives.
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local fence = {}

local MARKER = "PICKMAN_TEST_FENCE"
local DEFAULT_WAIT_SECONDS = 240 -- under the Stop hook's 300 s budget
local UNOWNED_SECONDS = 2
local FIXTURE_EMAIL = "@example.invalid" -- every fixture commits as <name>@example.invalid
-- inherited repository overrides that would point git (and so every fixture) at another repository
local OVERRIDES = {
	"GIT_DIR",
	"GIT_WORK_TREE",
	"GIT_INDEX_FILE",
	"GIT_COMMON_DIR",
	"GIT_OBJECT_DIRECTORY",
	"GIT_ALTERNATE_OBJECT_DIRECTORIES",
	"GIT_NAMESPACE",
	"GIT_PREFIX",
	"GIT_CONFIG_PARAMETERS",
	"GIT_CONFIG_COUNT",
}

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

-- git in the current directory with every inherited override removed; trimmed stdout, or nil on failure.
local function git(args: { string }): string?
	local argv: { string } = {}
	for _, name in OVERRIDES do
		table.insert(argv, "-u")
		table.insert(argv, name)
	end
	table.insert(argv, "git")
	for _, a in args do
		table.insert(argv, a)
	end
	local ok, r = pcall(process.exec, "env", argv)
	if not ok or not r.ok then
		return nil
	end
	return trim(r.stdout)
end

local function shell(script: string): string
	local r = process.exec("sh", { "-c", script })
	return trim(r.stdout)
end

local function alive(pid: string): boolean
	return string.match(pid, "^%d+$") ~= nil and process.exec("kill", { "-0", pid }).ok
end

-- The pid of this Lune process: the parent of the shell that prints it.
local function myPid(): string
	return shell("echo $PPID")
end

-- A file's trimmed contents, or "" when it is missing: another run may release its lock while this one reads it.
local function readMaybe(path: string): string
	local ok, text = pcall(fs.readFile, path)
	return if ok then trim(text) else ""
end

local function lockPids(lock: string): { string }
	local pids: { string } = {}
	local listed, names = pcall(fs.readDir, lock)
	if listed then
		for _, name in names do
			local pid = if name == "pid" then readMaybe(`{lock}/pid`) else string.match(name, "^pid%-(%d+)$")
			if pid and pid ~= "" then
				table.insert(pids, pid)
			end
		end
	end
	return pids
end

local function anyAlive(pids: { string }): boolean
	for _, pid in pids do
		if alive(pid) then
			return true
		end
	end
	return false
end

-- Removes `lock` if every process recorded in it is gone. Only the holder of the takeover mutex removes a
-- lock, so two waiters can never both remove one (and so never remove a fresh lock).
local function takeOverIfStale(lock: string, unownedFor: number)
	local mutex = `{lock}.takeover`
	if not process.exec("mkdir", { mutex }).ok then
		local holder = readMaybe(`{mutex}/pid`)
		local ok, meta = pcall(fs.metadata, mutex)
		local age = if ok and meta.modifiedAt then os.time() - meta.modifiedAt.unixTimestamp else 0
		if (holder ~= "" and not alive(holder)) or (holder == "" and age >= UNOWNED_SECONDS) then
			pcall(fs.removeDir, mutex) -- its holder died mid-takeover, or never claimed it
		end
		return
	end
	fs.writeFile(`{mutex}/pid`, myPid())
	local pids = lockPids(lock)
	local stale = if #pids == 0 then unownedFor >= UNOWNED_SECONDS else not anyAlive(pids)
	-- a test can widen the window between judging and removing, where a second waiter would race
	local pause = tonumber(process.env.PICKMAN_TEST_TAKEOVER_PAUSE or "")
	if stale and pause then
		task.wait(pause)
	end
	if stale then
		pcall(fs.removeDir, lock)
	end
	pcall(fs.removeDir, mutex)
end

local function takeLock(lock: string)
	local limit = tonumber(process.env.PICKMAN_TEST_LOCK_WAIT or "") or DEFAULT_WAIT_SECONDS
	local waited, unowned, said = 0, 0, false
	while not process.exec("mkdir", { lock }).ok do
		local pids = lockPids(lock)
		unowned = if #pids == 0 then unowned + 0.1 else 0
		takeOverIfStale(lock, unowned)
		if fs.isDir(lock) then
			local holder = if #pids > 0 then table.concat(pids, ", ") else "starting"
			if waited >= limit then
				stdio.ewrite(
					`another test run (pid {holder}) is using this checkout's fixtures ({lock}); gave up after {limit}s\n`
				)
				process.exit(1)
			end
			if not said then
				stdio.ewrite(`waiting for another test run (pid {holder}) in this checkout to finish\n`)
				said = true
			end
			task.wait(0.1)
			waited += 0.1
		end
	end
	fs.writeFile(`{lock}/pid`, myPid())
end

type Snapshot = {
	config: string,
	branch: string,
	head: string,
	worktrees: string,
	fixtureRefs: { [string]: boolean },
}

-- What no check may change: remote, core and user config (gh's remote.*.gh-resolved aside), which branch
-- this checkout is on and its commit, worktrees registered under .cache, and refs whose tip a fixture wrote.
local function snapshot(cache: string): Snapshot
	local config: { string } = {}
	for line in
		string.gmatch(git({ "config", "--local", "--get-regexp", "^(remote|core|user)\\." }) or "", "[^\n]+")
	do
		if not string.match(line, "^remote%.[^ ]+%.gh%-resolved ") then
			table.insert(config, line)
		end
	end
	local inside: { string } = {}
	for path in string.gmatch(git({ "worktree", "list", "--porcelain" }) or "", "worktree ([^\n]+)") do
		if string.sub(path, 1, #cache + 1) == cache .. "/" then
			table.insert(inside, path)
		end
	end
	table.sort(inside)
	local refs: { [string]: boolean } = {}
	local listed = git({ "for-each-ref", "--format=%(refname) %(objectname) %(authoremail)" }) or ""
	for line in string.gmatch(listed, "[^\n]+") do
		if string.find(line, FIXTURE_EMAIL .. ">", 1, true) then
			refs[(string.gsub(line, " <.*$", ""))] = true
		end
	end
	return {
		config = table.concat(config, "\n"),
		branch = git({ "symbolic-ref", "-q", "HEAD" }) or "(detached)",
		head = git({ "rev-parse", "HEAD" }) or "",
		worktrees = table.concat(inside, ", "),
		fixtureRefs = refs,
	}
end

-- Differences that only a check could have caused; an empty list means the repository is as it was.
local function changes(before: Snapshot, after: Snapshot): { string }
	local out: { string } = {}
	local function differ(label: string, a: string, b: string)
		if a ~= b then
			table.insert(out, `  {label}\n    before: {a}\n    after:  {b}`)
		end
	end
	differ("remote, core and user config", before.config, after.config)
	differ("HEAD (the branch this checkout is on)", before.branch, after.branch)
	differ("worktrees registered under .cache", before.worktrees, after.worktrees)
	if before.head ~= after.head then
		-- someone may commit or pull in this checkout meanwhile: fine, unless history was rewritten or a
		-- fixture identity wrote the new commits
		local forward = before.head ~= ""
			and git({ "merge-base", "--is-ancestor", before.head, after.head }) ~= nil
		local authors = if forward
			then git({ "log", "--format=%ae", `{before.head}..{after.head}` }) or ""
			else ""
		if not forward then
			differ("HEAD moved to a commit that does not descend from it", before.head, after.head)
		elseif string.find(authors, FIXTURE_EMAIL, 1, true) then
			differ("HEAD gained commits written by a fixture", before.head, after.head)
		end
	end
	local added: { string } = {}
	for ref in after.fixtureRefs do
		if not before.fixtureRefs[ref] then
			table.insert(added, ref)
		end
	end
	table.sort(added)
	if #added > 0 then
		table.insert(out, `  refs written by a fixture appeared\n    {table.concat(added, "\n    ")}`)
	end
	return out
end

local function guarded(here: string): boolean
	local marker = process.env[MARKER]
	if marker == nil or marker == "" then
		return false
	end
	local ceiling = ":" .. (process.env.GIT_CEILING_DIRECTORIES or "") .. ":"
	-- this checkout itself, or a fixture copy under its .cache (never another checkout below it, such as
	-- .worktree/X under a marker leaked from the main checkout)
	local inside = here == marker or string.sub(here, 1, #marker + 8) == marker .. "/.cache/"
	if inside and string.find(ceiling, `:{marker}/.cache:`, 1, true) then
		return true
	end
	stdio.ewrite(`note: ignoring {MARKER}={marker}: not a guard for this checkout\n`)
	return false
end

-- A path with its symlinks resolved (the sandbox matches resolved paths), or the path itself when it is missing.
local function resolved(path: string): string
	local r = process.exec("realpath", { path })
	return if r.ok then trim(r.stdout) else path
end

-- The repositories this run must not write: this checkout, and every repository an outer guard protects (a
-- copy of the tree under a checkout's .cache runs its own gate, and must not write the real checkout either).
local function protectedPaths(here: string): { string }
	local repos: { string } = {}
	local common = git({ "rev-parse", "--path-format=absolute", "--git-common-dir" })
	if common then
		table.insert(repos, common)
	end
	for real in string.gmatch(process.env.PICKMAN_FENCE_REAL_GIT or "", "[^:]+") do
		table.insert(repos, real)
	end
	local paths = { here }
	for _, repo in repos do
		table.insert(paths, repo)
		table.insert(paths, (string.gsub(repo, "/%.git$", "")))
	end
	return paths
end

-- The jail's profile: no write to the protected paths or the person's git configuration, except .cache.
-- The jail's profile. Specs may write only inside this checkout's .cache (not the .cache entry itself: replaced by a
-- symlink, it would turn later writes into writes elsewhere, review 004 F1), the run's own temp folder (TMPDIR; macOS
-- `mktemp` is pointed there too, review 004 F2), and /dev: the repository,
-- every directory above it (renaming one away, writing inside and renaming it back would escape a narrower rule),
-- and the person's home (tools such as the runner itself, shell start-up files, settings, launch agents, all run
-- later without the jail) are denied. No IP networking except loopback: a spec's `-c protocol.allow=always` reaches
-- nothing, while local test servers still work (review 001 F1 and F2, review 002 F2 and F3).
local function profile(cache: string, runTemp: string): string
	local rules = {
		"(version 1)",
		"(allow default)",
		"(deny network-outbound (remote ip))",
		'(allow network-outbound (remote ip "localhost:*"))',
		'(deny file-write* (subpath "/"))',
		'(allow file-write* (subpath "/dev"))',
	}
	for _, dir in { cache, resolved(cache) } do
		table.insert(rules, `(allow file-write* (subpath "{dir}"))`)
	end
	for _, dir in { runTemp, resolved(runTemp) } do
		table.insert(rules, `(allow file-write* (subpath "{dir}"))`)
	end
	for _, dir in { cache, resolved(cache) } do
		table.insert(rules, `(deny file-write* (literal "{dir}"))`) -- later rules win
		-- no symlink at the top of .cache, made or renamed there: unjailed writers (the gate's rojo build, the
		-- tracker's focus and claim files, the board) would write through it into the repository (review 005 F1)
		local pattern = string.gsub(dir, "[%.%[%]%*%^%$%(%)%+%?{}|\\]", "\\%0")
		table.insert(
			rules,
			`(deny file-write-create (require-all (vnode-type SYMLINK) (regex #"^{pattern}/[^/]+$")))`
		)
	end
	return table.concat(rules, "")
end

-- Which protected paths this process can write: harmless probe files, removed at once.
local function writable(here: string): { string }
	local open: { string } = {}
	local tag = myPid()
	for _, dir in protectedPaths(here) do
		local probe = `{dir}/.pickman-jail-probe-{tag}`
		if fs.isDir(dir) and pcall(fs.writeFile, probe, "") then
			pcall(fs.removeFile, probe)
			table.insert(open, dir)
		end
	end
	return open
end

-- What an outer sandbox leaves open that the jail would close (review 002 F4): a file in the person's home, a
-- folder above the checkout (outside any checkout's .cache named in the ceiling, which an outer jail allows), and
-- the network. Each probe is harmless if it succeeds: the file is removed at once, `touch -c -r d d` sets a folder's
-- times to their own values, and the connect goes to TEST-NET, where nothing listens.
local function escapes(here: string): { string }
	local out: { string } = {}
	local home = process.env.HOME or ""
	if home ~= "" then
		local probe = `{home}/.pickman-jail-probe-{myPid()}`
		if pcall(fs.writeFile, probe, "") then
			pcall(fs.removeFile, probe)
			table.insert(out, `the home folder {home}`)
		end
	end
	local shared = `/private/tmp/pickman-jail-probe-{myPid()}`
	if pcall(fs.writeFile, shared, "") then
		pcall(fs.removeFile, shared)
		table.insert(out, "the shared temp folder /private/tmp")
	end
	local ut = process.exec("getconf", { "DARWIN_USER_TEMP_DIR" })
	local userTemp = if ut.ok then (string.gsub(ut.stdout, "/*%s*$", "")) else ""
	if userTemp ~= "" then
		local probe = `{userTemp}/pickman-jail-probe-{myPid()}`
		if pcall(fs.writeFile, probe, "") then
			pcall(fs.removeFile, probe)
			table.insert(out, `the user temp folder {userTemp}`)
		end
	end
	local caches: { string } = {}
	for entry in string.gmatch(process.env.GIT_CEILING_DIRECTORIES or "", "[^:]+") do
		if string.sub(entry, -7) == "/.cache" then
			table.insert(caches, entry)
		end
	end
	local up = string.match(here, "^(.*)/[^/]+$")
	while up and up ~= "" do
		local inCache = false
		for _, c in caches do
			if up == c or string.sub(up, 1, #c + 1) == c .. "/" then
				inCache = true
			end
		end
		if not inCache and process.exec("touch", { "-c", "-r", up, up }).ok then
			table.insert(out, `the folder {up}`)
			break
		end
		up = string.match(up, "^(.*)/[^/]+$")
	end
	local net = process.exec("perl", {
		"-MIO::Socket::INET",
		"-e",
		'my $s = IO::Socket::INET->new(PeerAddr => "192.0.2.1", PeerPort => 9, Timeout => 2); print $s ? "connected" : "$!"',
	})
	if net.stdout ~= "Operation not permitted" then
		table.insert(out, "the network")
	end
	return out
end

-- Whether this unjailed run is a fixture of a jailed outer run, proven by probes rather than read from the
-- environment: an outer guard protects other repositories (PICKMAN_FENCE_REAL_GIT holds more than this
-- checkout's own), none of them or their checkouts is writable from here (so an outer jail holds them), the only
-- writable protected paths are this checkout and its own git directory, and the checkout lies under a
-- checkout's .cache (a ceiling entry ending in /.cache).
local function fixtureOfGuarded(here: string, open: { string }): boolean
	local own = git({ "rev-parse", "--path-format=absolute", "--git-common-dir" })
	local mine: { [string]: boolean } = { [here] = true }
	if own then
		mine[own] = true
		mine[(string.gsub(own, "/%.git$", ""))] = true
	end
	local outer = false
	for real in string.gmatch(process.env.PICKMAN_FENCE_REAL_GIT or "", "[^:]+") do
		if real ~= own and fs.isDir(real) then -- a stale or made-up entry proves no outer guard
			outer = true
		end
	end
	if not outer then
		return false
	end
	for _, path in open do
		if not mine[path] then
			return false -- an outer guard's repository is writable: nothing jails it
		end
	end
	for entry in string.gmatch(process.env.GIT_CEILING_DIRECTORIES or "", "[^:]+") do
		local cacheEntry = string.sub(entry, -7) == "/.cache"
		if cacheEntry and string.sub(here, 1, #entry + 1) == entry .. "/" then
			return true
		end
	end
	return false
end

-- The jail (macOS). It returns the command prefix and what the run is told. Off macOS there is no jail
-- (environment guards only). On macOS a run that can't be jailed (inside another sandbox, which can't be
-- nested, or without sandbox-exec) goes on only if it provably can't write the repository, or if it is a
-- fixture of a guarded checkout (whose own jail then protects the real repository); otherwise it refuses.
local function jail(here: string, cache: string, runTemp: string): ({ string }, string)
	if process.os ~= "macos" then
		return {}, "none (not macOS: environment guards only)"
	end
	local rules = profile(cache, runTemp)
	local started, trial = pcall(process.exec, "sandbox-exec", { "-p", rules, "/usr/bin/true" })
	if started and trial.ok then
		return { "sandbox-exec", "-p", rules }, "sandbox-exec"
	end
	local why = if started
		then "already inside a sandbox, and macOS can't nest them"
		else "sandbox-exec is missing"
	local open = writable(here)
	local leaks = escapes(here)
	-- an outer sandbox must also refuse a symlink at the top of .cache (unjailed writers would follow one)
	local linkProbe = `{cache}/pickman-link-probe-{myPid()}`
	if process.exec("ln", { "-s", "/nonexistent", linkProbe }).ok then
		process.exec("rm", { "-f", linkProbe })
		if #open == 0 then
			table.insert(leaks, "a symlink at the top of .cache")
		end
	end
	if #open == 0 and #leaks == 0 then
		stdio.ewrite(`note: not jailed ({why}); the outer sandbox protects the repository\n`)
		return {}, "outer sandbox (protects the repository)"
	end
	if #leaks == 0 and fixtureOfGuarded(here, open) then
		stdio.ewrite(`note: not jailed ({why}); this is a fixture of a guarded checkout\n`)
		return {}, "outer sandbox (a fixture of a guarded checkout)"
	end
	stdio.ewrite(
		`cannot jail this run ({why}), and it could write the repository or reach past the jail ({table.concat(
			open,
			", "
		)}{if #open > 0 and #leaks > 0 then ", " else ""}{table.concat(leaks, ", ")}). `
			.. 'Run specs outside the sandbox you are in (testing skill, "Specs never touch the real repository").\n'
	)
	pcall(fs.removeDir, runTemp)
	process.exit(1)
	return {}, ""
end

-- Runs the specs in a process group of their own, and stops whatever is left in it when they end (review 005 F2:
-- a background process a spec left would outlive the run). The launcher stays in the terminal's group and passes on
-- INT, TERM and HUP, so Ctrl-C still stops a run. A process that leaves the group on purpose (setsid) is not
-- reaped: the testing skill lists it under "Caught only by review".
local REAPER = table.concat({
	'my $pid = fork; die "fork: $!" unless defined $pid;',
	-- a watchdog in the specs' group kills the group if the launcher dies (a SIGKILL to the launcher's group would
	-- otherwise leave the specs running and holding the lock, review 006 F2)
	"if (!$pid) { setpgrp(0, 0); my $launcher = getppid();",
	"if (!fork) { open STDIN, '<', '/dev/null'; open STDOUT, '>', '/dev/null'; open STDERR, '>', '/dev/null';",
	"while (kill 0, $launcher) { sleep 1 } kill 'KILL', -getpgrp(); exit }",
	'exec { $ARGV[0] } @ARGV or die "exec: $!"; }',
	"setpgrp($pid, $pid);",
	"for my $s (qw(INT TERM HUP)) { $SIG{$s} = sub { kill $s, -$pid } }",
	"waitpid($pid, 0); my $st = $?;",
	"kill 'KILL', -$pid;",
	"exit($st & 127 ? 128 + ($st & 127) : $st >> 8);",
}, " ")

function fence.enter()
	local here = shell("pwd -P")
	if guarded(here) then
		local lock = `{process.env[MARKER]}/.cache/tests-run.lock`
		if fs.isDir(lock) then
			pcall(fs.writeFile, `{lock}/pid-{myPid()}`, "")
		end
		return
	end
	local cache = `{here}/.cache`
	-- a symlink or a file there would turn every guard write into a write elsewhere (review 004 F1)
	if process.exec("test", { "-L", cache }).ok or (fs.isFile(cache)) then
		stdio.ewrite(`{cache} is not a plain folder (a symlink or a file); refusing. Stop and report this.\n`)
		process.exit(1)
	end
	fs.writeDir(cache)
	-- a symlink at the top of .cache, left from before the jail closed it, is unlinked (never followed)
	for _, name in fs.readDir(cache) do
		if process.exec("test", { "-L", `{cache}/{name}` }).ok then
			process.exec("rm", { "-f", `{cache}/{name}` })
		end
	end
	-- the tripwire tells fixture writes by their author; that only works while this repository has a real identity
	local email = git({ "config", "user.email" }) or ""
	if string.find(email, FIXTURE_EMAIL, 1, true) then
		local origin = git({ "config", "--show-origin", "user.email" }) or ""
		stdio.ewrite(
			`this repository's git identity is a fixture identity ({email}, from {origin}): a check wrote it. `
				.. "Stop and report this; do not repair the repository yourself (testing skill).\n"
		)
		process.exit(1)
	end
	-- decide the jail first: a run that must refuse does so before it takes the lock
	-- the run's own temp folder, outside the checkout (a spec's `mktemp -d` must land outside .cache) and fresh,
	-- so nothing outside the jail runs from it; removed when the run ends
	local base = (string.gsub(process.env.TMPDIR or "", "/+$", ""))
	local made = process.exec("mktemp", { "-d", `{if base == "" then "/tmp" else base}/pickman-run.XXXXXX` })
	if not made.ok then
		stdio.ewrite(`tests/run: could not make the run's temp folder: {made.stderr}\n`)
		process.exit(1)
	end
	local runTemp = resolved((string.gsub(made.stdout, "%s+$", "")))
	if process.os == "macos" then
		-- macOS mktemp ignores TMPDIR without a template and uses the user temp folder, which the jail closes
		fs.writeDir(`{runTemp}/bin`)
		fs.writeFile(
			`{runTemp}/bin/mktemp`,
			"#!/bin/sh\n# the run's mktemp: with no template, into the run's own TMPDIR (the jail closes the user temp folder)\n"
				.. "f=; p=tmp\n"
				.. 'while [ $# -gt 0 ]; do case $1 in -t) p=$2; shift 2 ;; -*) f="$f $1"; shift ;; *) exec /usr/bin/mktemp $f "$@" ;; esac; done\n'
				.. 'exec /usr/bin/mktemp $f "$TMPDIR/$p.XXXXXXXXXX"\n'
		)
		process.exec("chmod", { "+x", `{runTemp}/bin/mktemp` })
	end
	local prefix, jailed = jail(here, cache, runTemp)
	local lock = `{cache}/tests-run.lock`
	takeLock(lock)
	local before = snapshot(cache)
	local argv = {
		"-c",
		'. scripts/lib/fence.sh && pickman_fence "$1" specs "$2" && export PICKMAN_TEST_FENCE="$1" PICKMAN_TEST_JAIL="$2" TMPDIR="$3" PATH="$3/bin:$PATH" && shift 3 && exec lune run tests/run -- "$@"',
		"_",
		here,
		jailed,
		runTemp,
	}
	for _, a in process.args do
		if a ~= "--" then
			table.insert(argv, a)
		end
	end
	local command = "bash"
	if #prefix > 0 then
		command = prefix[1]
		local rest = table.move(prefix, 2, #prefix, 1, {})
		table.insert(rest, "bash")
		for _, a in argv do
			table.insert(rest, a)
		end
		argv = rest
	end
	-- through the launcher: the specs get their own process group, which is stopped when they end, before the
	-- second snapshot, so nothing they left behind changes the repository after it
	local launched = { "-e", REAPER, command }
	for _, a in argv do
		table.insert(launched, a)
	end
	local r = process.exec("perl", launched, { stdio = "forward" })
	-- with the specs stopped, unlink any symlink one swapped in at the top of .cache (review 006 F1)
	for _, name in fs.readDir(cache) do
		if process.exec("test", { "-L", `{cache}/{name}` }).ok then
			process.exec("rm", { "-f", `{cache}/{name}` })
		end
	end
	local after = snapshot(cache)
	pcall(fs.removeDir, lock)
	pcall(fs.removeDir, runTemp)
	local code = r.code
	local changed = changes(before, after)
	if #changed > 0 then
		stdio.ewrite(
			`\nREPOSITORY CHANGED during the test run: a check must never touch the real repository (testing skill).\n{table.concat(
				changed,
				"\n"
			)}\nStop and report this; do not repair the repository yourself.\n`
		)
		code = if code == 0 then 1 else code
	end
	process.exit(code)
end

return fence
