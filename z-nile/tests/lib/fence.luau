--!strict
-- The spec runner's guard for the repository it runs in (zz-test skill, "Specs never touch the real
-- repository"). tests/run calls `fence.enter()` right after its AC_LIST refusal.
--
-- A top-level run (no valid PICKMAN_TEST_FENCE for this checkout):
--   1. takes this checkout's lock, .cache/tests-run.lock, so two runs never share the .cache fixtures;
--   2. snapshots what no check may change (see `snapshot`);
--   3. re-runs itself under z-nile/lib/fence.sh's guards (git fenced inside .cache, inherited repository
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
-- The repository root: three folders above this file (z-nile/tests/lib/). A run starts in a project's home inside it
-- (pickman/, z-nile/, c0120); the guards' shell half is always the root's z-nile/lib/fence.sh.
-- a path with its `.` and `..` segments resolved (`lune run ../z-nile/tests/run` keeps them in debug.info, code review
-- 004 F6)
local function normalize(path: string): string
	local out: { string } = {}
	for seg in string.gmatch(path, "[^/]+") do
		if seg == ".." and #out > 0 and out[#out] ~= ".." then
			table.remove(out)
		elseif seg ~= "." then
			table.insert(out, seg)
		end
	end
	return (if string.sub(path, 1, 1) == "/" then "/" else "") .. table.concat(out, "/")
end
fence.normalize = normalize
local ROOT = string.match(normalize(debug.info(1, "s")), "^(.*)/[^/]+/[^/]+/[^/]+/[^/]+$") or "." -- z-nile/tests/lib/<file>

-- Every project's home (a folder name), from fence.sh's pickman_fence_dirs, the one owner of that set (code review
-- 005 F2): the registry's homes, or in a copy with no engine or registry the top folders holding a .tracker/. Nil
-- when it names none (a copy with neither): the runner then takes any folder one level below the root, as before the
-- registry named homes.
function fence.homes(): { string }?
	local r =
		process.exec("bash", { "-c", '. "$1/z-nile/lib/fence.sh" && pickman_fence_dirs "$1"', "_", ROOT })
	if not r.ok then
		stdio.ewrite(`tests/run: cannot read {ROOT}'s homes: {r.stderr}refusing. Stop and report this.\n`)
		process.exit(1)
	end
	local out: { string } = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		if string.sub(line, 1, #ROOT + 1) == ROOT .. "/" then
			table.insert(out, string.sub(line, #ROOT + 2))
		end
	end
	return if #out > 0 then out else nil
end
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
	-- and, for the guards' own reads only, the ceiling: from a project home an inherited ceiling at the checkout's
	-- root would hide the repository they protect (code review 002 F1). The specs keep theirs.
	"GIT_CEILING_DIRECTORIES",
}

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

-- git in the current directory with every inherited override and the ceiling removed; trimmed stdout, or nil on
-- failure. A caller that takes the answer for a repository treats an empty one as "found nothing", never as an answer.
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

-- Whether a process exists. Inside the jail a signal to a process outside it is refused (the jail's signal rule,
-- c0078), and inside an outer sandbox too (Claude Code's own allows signals only within it), so there `Operation not
-- permitted` means it exists outside. Otherwise it means another user's process, which can't hold this user's lock:
-- dead, so a stale lock naming a reused pid can still be taken over.
function fence.alive(pid: string): boolean
	if string.match(pid, "^%d+$") == nil then
		return false
	end
	local r = process.exec("kill", { "-0", pid })
	if r.ok then
		return true
	end
	local jail = process.env.PICKMAN_TEST_JAIL or ""
	-- an outer sandbox (Claude Code's own) refuses signals outside it too (R0026 review 001 F3)
	local confined = jail == "sandbox-exec" or string.sub(jail, 1, 14) == "outer sandbox "
	return confined and string.find(r.stderr, "Operation not permitted", 1, true) ~= nil
end
local alive = fence.alive

-- The pid of this Lune process: the parent of the shell that prints it.
local function myPid(): string
	return shell("echo $PPID")
end

-- A file's trimmed contents, or "" when it is missing: another run may release its lock while this one reads it.
local function readMaybe(path: string): string
	local ok, text = pcall(fs.readFile, path)
	return if ok then trim(text) else ""
end

-- Prints a process's start id, or exits 1: the start the kernel recorded for it, as exact as the kernel keeps it, and
-- never derived from the clock, so the same process always prints the same id and a later process with the same pid
-- prints another. Perl, so no setuid tool is needed (the jail and any sandbox refuse the setuid /bin/ps).
-- macOS: sysctl kern.proc.pid.<pid>, a kinfo_proc that starts with the start time (a timeval: "<sec>.<usec>").
-- Linux: /proc/sys/kernel/random/boot_id and /proc/<pid>/stat field 22, the start in clock ticks after boot.
local STARTED = table.concat({
	"my $pid = shift; exit 1 unless defined $pid && $pid =~ /^\\d+$/;",
	"if ($^O eq 'darwin') { my $mib = pack('i4', 1, 14, 1, $pid); my $buf = \"\\0\" x 4096;",
	"my $len = pack('Q', length $buf); exit 1 unless syscall(202, $mib, 4, $buf, $len, 0, 0) == 0",
	"&& unpack('Q', $len) > 0; my ($sec, $usec) = unpack('q l', $buf); exit 1 unless $sec > 0;",
	'print "$sec.$usec\\n"; exit 0 }',
	"if ($^O eq 'linux') { open(my $b, '<', '/proc/sys/kernel/random/boot_id') or exit 1; my $boot = <$b>;",
	"close $b; chomp $boot; open(my $st, '<', \"/proc/$pid/stat\") or exit 1; my $line = <$st>; close $st;",
	"$line =~ s/^.*\\)\\s+//s or exit 1; my $ticks = (split /\\s+/, $line)[19];",
	"exit 1 unless $boot ne '' && defined $ticks && $ticks =~ /^\\d+$/; print \"$boot:$ticks\\n\"; exit 0 }",
	"exit 1;",
}, " ")
fence.STARTED = STARTED

-- A process's start id (see STARTED), or nil when it can't be read (not a pid, an exited process, another system).
function fence.startOf(pid: string): string?
	if string.match(pid, "^%d+$") == nil then
		return nil
	end
	local ok, r = pcall(process.exec, "perl", { "-e", STARTED, pid })
	if not ok or not r.ok then
		return nil
	end
	local id = trim(r.stdout)
	return if id ~= "" then id else nil
end

-- Whether a recorded pid still holds what records it (c0127): it is alive, and it is not a reused pid, whose start
-- id differs from the one recorded with it. No recorded id (a record from an older runner, or one whose id is not
-- written yet) or an id that can't be read now leaves it holding, as before.
function fence.holds(isAlive: boolean, recorded: string?, current: string?): boolean
	if not isAlive then
		return false
	end
	if recorded == nil or current == nil then
		return true
	end
	return recorded == current
end

-- Writes `text` to `path` whole or not at all: a reader sees the old file or the new one, never a part (c0127).
-- `me` (this process's pid, read once by the caller) names the temp file, so no subprocess runs here.
local function writeWhole(path: string, text: string, me: string)
	local temp = `{path}.part-{me}`
	if pcall(fs.writeFile, temp, text) then
		if not pcall(fs.move, temp, path, true) then
			pcall(fs.removeFile, temp)
		end
	end
end

-- Whether the process `pid`, whose start id was recorded in the file `idPath`, still holds. Its id is read only
-- once the pid is known to be alive.
local function stillHolds(pid: string, idPath: string): boolean
	if not alive(pid) then
		return false
	end
	local recorded = readMaybe(idPath)
	if recorded == "" then
		return true
	end
	return fence.holds(true, recorded, fence.startOf(pid))
end

type Record = { pid: string, path: string }

-- Every pid the lock records, with the file that holds its recorded start id: `pid-<n>` itself for a worker,
-- `start-<pid>` for the top process (whose `pid` file holds its pid).
local function lockRecords(lock: string): { Record }
	local records: { Record } = {}
	local listed, names = pcall(fs.readDir, lock)
	if listed then
		for _, name in names do
			local pid = if name == "pid" then readMaybe(`{lock}/pid`) else string.match(name, "^pid%-(%d+)$")
			if pid and pid ~= "" then
				table.insert(records, {
					pid = pid,
					-- a worker's id is its record's content; the top's record holds its pid, so its id is beside it
					path = if name == "pid" then `{lock}/start-{pid}` else `{lock}/{name}`,
				})
			end
		end
	end
	return records
end

local function lockPids(lock: string): { string }
	local pids: { string } = {}
	for _, r in lockRecords(lock) do
		table.insert(pids, r.pid)
	end
	return pids
end

local function anyHolder(records: { Record }): boolean
	for _, r in records do
		if stillHolds(r.pid, r.path) then
			return true
		end
	end
	return false
end

-- Whether the takeover's owner still holds it. `<mutex>/owner` holds its pid and start id in one file ("<pid>
-- <id>", written whole), so both are read at one moment; a mutex with only `pid` (an older runner, or an id that
-- could not be read) is judged by that pid alone, as before.
local function ownerHolds(mutex: string, owner: string): boolean
	local pid, id = string.match(readMaybe(`{mutex}/owner`), "^(%d+) (%S+)$")
	if pid == nil then
		return alive(owner)
	end
	return alive(pid) and fence.holds(true, id, fence.startOf(pid))
end

-- Removes `lock` if no process recorded in it still holds it (`stillHolds`: gone, or a reused pid). Only the
-- holder of the takeover mutex removes a lock, so two waiters can never both remove one (and so never remove a
-- fresh lock).
-- `me` and `myId` are this process's pid and start id, read once by takeLock before it waits (review 001 F1): the
-- claim (mkdir) and its record (the owner file, then `pid`) stay a few writes apart, with no subprocess between.
local function takeOverIfStale(lock: string, unownedFor: number, me: string, myId: string?)
	local mutex = `{lock}.takeover`
	if not process.exec("mkdir", { mutex }).ok then
		local owner = readMaybe(`{mutex}/pid`)
		local ok, meta = pcall(fs.metadata, mutex)
		local age = if ok and meta.modifiedAt then os.time() - meta.modifiedAt.unixTimestamp else 0
		if (owner ~= "" and not ownerHolds(mutex, owner)) or (owner == "" and age >= UNOWNED_SECONDS) then
			pcall(fs.removeDir, mutex) -- its holder died mid-takeover, or never claimed it
		end
		return
	end
	if myId then
		writeWhole(`{mutex}/owner`, `{me} {myId}`, me)
	end
	fs.writeFile(`{mutex}/pid`, me)
	local records = lockRecords(lock)
	local stale = if #records == 0 then unownedFor >= UNOWNED_SECONDS else not anyHolder(records)
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
	-- this process's own facts, read once: they don't change while it waits
	local me = myPid()
	local myId = fence.startOf(me)
	while not process.exec("mkdir", { lock }).ok do
		local pids = lockPids(lock)
		unowned = if #pids == 0 then unowned + 0.1 else 0
		takeOverIfStale(lock, unowned, me, myId)
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
	if myId then
		writeWhole(`{lock}/start-{me}`, myId, me)
	end
	fs.writeFile(`{lock}/pid`, me)
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
	-- under this run's .cache, or any .cache of the checkout: a run from a project's home (c0120) must not register
	-- one under the root's .cache either, which its jail closes only on macOS
	local inside: { string } = {}
	local top = git({ "rev-parse", "--show-toplevel" }) or ""
	for path in string.gmatch(git({ "worktree", "list", "--porcelain" }) or "", "worktree ([^\n]+)") do
		local underTop = top ~= ""
			and string.sub(path, 1, #top + 1) == top .. "/"
			and string.find(path, "/.cache/", #top, true)
		if string.sub(path, 1, #cache + 1) == cache .. "/" or underTop then
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
	if common and common ~= "" then
		table.insert(repos, common)
	end
	for real in string.gmatch(process.env.PICKMAN_FENCE_REAL_GIT or "", "[^:]+") do
		table.insert(repos, real)
	end
	local paths = { here }
	-- the checkout's own root, when the run starts in a project's home inside it (c0120)
	local top = git({ "rev-parse", "--show-toplevel" })
	if top and top ~= "" and top ~= here then
		table.insert(paths, top)
	end
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
	-- no signal leaves the jail: a spec can signal (and probe with kill -0) only processes of its own sandbox, never
	-- the runner's top process, the launcher or its watchdog; the sweeper relies on it (c0078, c0076). Later rules win;
	-- no-log keeps the sweeper's refused probes out of the system log
	table.insert(rules, "(deny signal (with no-log))")
	table.insert(rules, "(allow signal (target same-sandbox))")
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
	-- the checkout's own top too: a run starts in a project's home below it (c0120)
	local top = git({ "rev-parse", "--show-toplevel" })
	if top and top ~= "" then
		mine[top] = true
	end
	if own and own ~= "" then
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

-- Whether links can be made in `dir`, probed at a fresh, unpredictable name: "made" (and removed at once), "refused"
-- (only for `Operation not permitted`, a sandbox's refusal), or "error" and ln's message (a missing folder, ...). A
-- file a spec left at a predictable name can't turn a permissive sandbox into a refusing one (c0078).
function fence.linkProbe(dir: string): (string, string)
	local letters = shell("LC_ALL=C tr -dc a-z0-9 </dev/urandom 2>/dev/null | head -c 8")
	local probe = `{dir}/pickman-link-probe-{myPid()}-{letters}`
	local r = process.exec("ln", { "-s", "/nonexistent", probe })
	if r.ok then
		process.exec("rm", { "-f", probe })
		return "made", ""
	end
	if string.find(r.stderr, "Operation not permitted", 1, true) then
		return "refused", trim(r.stderr)
	end
	return "error", trim(r.stderr)
end

-- The jail's root (c0076): runs the specs, waits, then kills every process it can signal. Under the jail's signal rule
-- that is exactly the run's leftovers, whatever session or group they moved to. Run as
--   perl -e SWEEPER <outside-pid | -> <command> <args...>
-- It exits with the command's status (a signal death as 128+n); 70 without sweeping unless a signal to the outside pid
-- (`-`: its parent, the launcher) is refused with EPERM; 71 if processes keep appearing. PICKMAN_SWEEP_ONLY, a file of
-- pids, narrows the candidates (a test seam; the runner removes it with `env -u`).
fence.SWEEPER = table.concat({
	"use Errno;",
	-- a Ctrl-C or a forwarded signal stops the specs, not the sweeper
	"$SIG{$_} = 'IGNORE' for qw(INT TERM HUP);",
	"my $outside = shift @ARGV; my $form = $outside eq '-'; my $parent = getppid();",
	-- the launcher form watches its parent, read once now: the launcher outlives a Ctrl-C to the top process
	'if ($form) { if ($parent == 1) { print STDERR "sweeper: no launcher above me (parent 1); nothing swept\n"; exit 70 }',
	"$outside = $parent }",
	'my $pid = fork; die "fork: $!" unless defined $pid;',
	"if ($pid == 0) { $SIG{$_} = 'DEFAULT' for qw(INT TERM HUP); exec { $ARGV[0] } @ARGV or die \"exec: $!\"; }",
	"waitpid($pid, 0); my $st = $?; my $code = $st & 127 ? 128 + ($st & 127) : $st >> 8;",
	-- interlock: sweep only where a signal to a live process outside is refused, or kill 0 would reach every process
	-- the user owns. One probe can be fooled (an EPERM from root's or another user's pid), so: only on macOS, where the
	-- jail is; an explicit pid only inside a jailed spec run (explicit pids are for specs); the launcher form only
	-- while its parent is the one it started under (R0026 review 001 F1)
	"my $refuse = $^O ne 'darwin' ? \"no jail on $^O\" : (!$form && ($ENV{PICKMAN_TEST_JAIL} // '') ne 'sandbox-exec')",
	"? 'an explicit pid outside a jailed spec run' : undef;",
	'$refuse //= "not in a jail that refuses signals to other processes (pid $outside answered)"',
	"unless $outside =~ /^\\d+$/ && (!$form || getppid() == $parent) && !kill(0, $outside) && $!{EPERM};",
	'if (defined $refuse) { print STDERR "sweeper: $refuse; nothing swept\n"; exit 70 }',
	-- candidates: every pid (macOS PID_MAX is 99999), or those PICKMAN_SWEEP_ONLY lists; a seam that can't be read
	-- refuses, never widens the sweep
	"my @cand = 2 .. 99999; my $only = $ENV{PICKMAN_SWEEP_ONLY}; if (defined $only && $only ne '') {",
	"open(my $f, '<', $only) or do { print STDERR \"sweeper: test seam $only unreadable ($!); nothing swept\n\"; exit 70 };",
	"local $/; my $t = <$f>; @cand = grep { /^\\d+$/ } split /\\s+/, ($t // '') }",
	-- kept: itself and its ancestors among what it can signal (pgrep -a: BSD pgrep hides its own ancestors otherwise)
	"my %keep = ($$ => 1); my %up; my @can = grep { $_ != $$ && kill(0, $_) } @cand;",
	"for my $p (@can, $$) { for my $c (split /\\s+/, `pgrep -a -P $p 2>/dev/null`) { $up{$c} = $p if $c =~ /^\\d+$/ } }",
	"my %can = map { $_ => 1 } @can; my $anc = getppid(); while ($can{$anc} && !$keep{$anc}) { $keep{$anc} = 1; $anc = $up{$anc} // 0 }",
	-- passes: stop then kill what is left (stopped first, so none can fork while the others die), until nothing is
	"my %gone; for my $pass (1 .. 50) { 1 while waitpid(-1, 1) > 0;",
	-- a process that just ended can linger a moment as a zombie (kill 0 still answers) until launchd reaps it: what
	-- is found is probed again after a short pause, so only what still lives is stopped and counted
	"my @found = grep { !$keep{$_} && kill(0, $_) } @cand;",
	"if (@found) { select(undef, undef, undef, 0.05); @found = grep { kill(0, $_) } @found }",
	'unless (@found) { my $n = keys %gone; print STDERR "sweeper: stopped $n process(es) the specs left running\n" if $n; exit $code }',
	"kill 'STOP', @found; kill 'KILL', @found; $gone{$_} = 1 for @found; select(undef, undef, undef, 0.05) }",
	'print STDERR "sweeper: processes keep appearing; this run is not clean\n"; exit 71;',
}, " ")

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
		-- the jail's root is the sweeper, in the launcher form, without the caller's test seam (c0076)
		return {
			"sandbox-exec",
			"-p",
			rules,
			"env",
			"-u",
			"PICKMAN_SWEEP_ONLY",
			"perl",
			"-e",
			fence.SWEEPER,
			"-",
		},
			"sandbox-exec"
	end
	local why = if started
		then "already inside a sandbox, and macOS can't nest them"
		else "sandbox-exec is missing"
	local open = writable(here)
	local leaks = escapes(here)
	-- an outer sandbox must also refuse a symlink at the top of .cache (unjailed writers would follow one)
	local verdict, detail = fence.linkProbe(cache)
	if verdict == "error" then
		stdio.ewrite(`cannot probe the outer sandbox for links at the top of .cache: {detail}\n`)
		pcall(fs.removeDir, runTemp)
		process.exit(1)
	elseif verdict == "made" and #open == 0 then
		table.insert(leaks, "a symlink at the top of .cache")
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
			.. 'Run specs outside the sandbox you are in (zz-test skill, "Specs never touch the real repository").\n'
	)
	pcall(fs.removeDir, runTemp)
	process.exit(1)
	return {}, ""
end

-- The launcher: runs the specs in a process group of their own, and stops whatever is left in it when they end (review
-- 005 F2: a background process a spec left would outlive the run). It stays in the terminal's group and passes on
-- INT, TERM and HUP, so Ctrl-C still stops a run. A watchdog in the specs' group stops that group if the launcher dies,
-- however it died (c0079). A process that leaves the group on purpose (setsid) is the jail's sweeper's (c0076).
local REAPER = table.concat({
	-- the watchdog's pipe: the launcher holds the only write end, so a read sees end-of-file exactly when it is gone
	'pipe(my $r, my $w) or die "pipe: $!";',
	'my $pid = fork; die "fork: $!" unless defined $pid;',
	-- the specs' process: a group of its own, the watchdog, then the command
	"if ($pid == 0) { setpgrp(0, 0);",
	'my $wd = fork; die "fork: $!" unless defined $wd;',
	-- the watchdog: ignores the signals the launcher forwards, waits for end-of-file, then kills its group
	"if ($wd == 0) { close $w; $SIG{$_} = 'IGNORE' for qw(INT TERM HUP);",
	"open STDIN, '<', '/dev/null'; open STDOUT, '>', '/dev/null'; open STDERR, '>', '/dev/null';",
	"sysread($r, my $eof, 1); kill 'KILL', -getpgrp(); exit 0; }",
	-- the command holds neither end, so it can't keep the watchdog waiting
	'close $r; close $w; exec { $ARGV[0] } @ARGV or die "exec: $!"; }',
	-- the launcher keeps $w open until it exits
	"close $r; setpgrp($pid, $pid); my $t0 = time;",
	"for my $s (qw(INT TERM HUP)) { $SIG{$s} = sub { kill $s, -$pid } }",
	"waitpid($pid, 0); my $st = $?;",
	-- a spec, or something outside, can kill the jail's sweeper: before the group is stopped, say who was still there
	-- (c0132). pgrep, not ps: ps is setuid, which a jail refuses to run (a launcher a spec starts is jailed). The
	-- watchdog is the group's process whose command line is the launcher's own (a fork, never exec'd)
	"my $swept = ($ENV{PICKMAN_REAP_SWEPT} // '') eq '1' && ($st & 127); my @report;",
	"if ($swept) { my $secs = time - $t0; my $top = $ENV{PICKMAN_REAP_TOP} // '';",
	"my $up = $top !~ /^\\d+$/ ? 'unknown' : kill(0, $top) || $!{EPERM} ? 'alive' : 'gone';",
	"my $g = getpgrp(); my ($me) = map { /^$$ (.*)$/ ? ($1) : () } split /\\n/, `pgrep -lf -a -g $g 2>/dev/null`; $me //= '';",
	"my @left; my $wd = 'gone'; for my $l (split /\\n/, `pgrep -lf -a -g $pid 2>/dev/null`) {",
	"my ($p, $c) = $l =~ /^(\\d+) (.*)$/ or next; if ($me ne '' && $c eq $me) { $wd = \"alive (pid $p)\"; next }",
	'push @left, "tests/run:   $p " . substr($c, 0, 200) . "\\n" }',
	'@report = (sprintf("tests/run: the jail\'s sweeper was killed (signal %d): processes the specs left may still run. Stop and report this.\\n", $st & 127),',
	"sprintf(\"tests/run: who: at %s, %ds after the specs started; launcher %d (the run's top process %s, %s); specs group %d (the sweeper's own pid); watchdog %s; %d other process(es) still in the group%s\\n\",",
	"scalar(localtime), $secs, $$, $top eq '' ? '?' : $top, $up, $pid, $wd, scalar(@left), @left ? ':' : ''), @left) }",
	-- whatever is left in the group, the watchdog included
	"kill 'KILL', -$pid;",
	-- with the specs stopped, unlink every symlink at the top of the cache folder it was given, never following one
	-- and never recursing: a spec may have swapped one in, and unjailed writers run next (c0077). Here, not in the top
	-- Lune: the launcher survives a Ctrl-C or a TERM to the top process alone, so nothing skips this
	"my $c = $ENV{PICKMAN_REAP_CACHE}; if (defined $c && $c ne '' && opendir(my $dh, $c)) {",
	"for my $e (readdir $dh) { unlink \"$c/$e\" if $e ne '.' && $e ne '..' && -l \"$c/$e\" } closedir $dh }",
	-- a spec can kill the jail's sweeper (same sandbox): then its leftovers may live on, so the run fails (c0076)
	"if ($swept) { print STDERR @report; exit 1 }",
	"exit($st & 127 ? 128 + ($st & 127) : $st >> 8);",
}, " ")
fence.REAPER = REAPER

function fence.enter()
	local here = shell("pwd -P")
	if guarded(here) then
		local lock = `{process.env[MARKER]}/.cache/tests-run.lock`
		if fs.isDir(lock) then
			local me = myPid()
			-- the record and its start id are one file, written whole: a reader sees no record, or both
			writeWhole(`{lock}/pid-{me}`, fence.startOf(me) or "", me)
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
	-- The checkout's own .cache and every project home's (c0120 design review 005 F2, code review 004 F3), from the one
	-- owner of that set, fence.sh's pickman_fence_all (code review 005 F2): ceiling, refusals and sentinel now, while
	-- unjailed (the jail lets the run write only its home's .cache); the ceiling again inside the jail's shell, from
	-- the same list.
	local all = process.exec("bash", {
		"-c",
		'. "$1/z-nile/lib/fence.sh" && pickman_fence_all "$1" strict && pickman_fence_dirs "$1"',
		"_",
		ROOT,
	})
	if not all.ok then
		stdio.ewrite(`tests/run: cannot fence {ROOT}'s homes: {all.stderr}refusing. Stop and report this.\n`)
		process.exit(1)
	end
	local fenced: { string } = {}
	for line in string.gmatch(all.stdout, "[^\n]+") do
		table.insert(fenced, line)
	end
	local ceilings = table.concat(fenced, ":")
	-- the guards protect the repository git finds here; finding none refuses, never "nothing to protect" (code review
	-- 002 F1): the tripwire, the protected paths and the fence would all read nothing
	if (git({ "rev-parse", "--path-format=absolute", "--git-common-dir" }) or "") == "" then
		stdio.ewrite(
			`tests/run: {here} is in no git repository (or git can't read it); refusing. Stop and report this.\n`
		)
		process.exit(1)
	end
	-- the tripwire tells fixture writes by their author; that only works while this repository has a real identity
	local email = git({ "config", "user.email" }) or ""
	if string.find(email, FIXTURE_EMAIL, 1, true) then
		local origin = git({ "config", "--show-origin", "user.email" }) or ""
		stdio.ewrite(
			`this repository's git identity is a fixture identity ({email}, from {origin}): a check wrote it. `
				.. "Stop and report this; do not repair the repository yourself (zz-test skill).\n"
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
	if string.sub(jailed, 1, 14) == "outer sandbox " then
		-- the lock code runs here, inside that sandbox: fence.alive must read its refusals as "alive" (review 001 F3)
		process.env.PICKMAN_TEST_JAIL = jailed
	end
	local lock = `{cache}/tests-run.lock`
	takeLock(lock)
	local before = snapshot(cache)
	local argv = {
		"-c",
		'unset PICKMAN_REAP_SWEPT PICKMAN_REAP_CACHE PICKMAN_REAP_TOP; . "$4/z-nile/lib/fence.sh" && { old=$IFS; IFS=:; for d in $5; do pickman_fence_ceiling "$d" || exit 1; done; IFS=$old; } && pickman_fence "$1" specs "$2" && export PICKMAN_TEST_FENCE="$1" PICKMAN_TEST_JAIL="$2" TMPDIR="$3" PATH="$3/bin:$PATH" && shift 5 && exec lune run tests/run -- "$@"',
		"_",
		here,
		jailed,
		runTemp,
		ROOT,
		ceilings,
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
	-- the launcher's own settings (PICKMAN_REAP_*) reach it alone: the bash line above unsets them for the specs
	local r = process.exec("perl", launched, {
		stdio = "forward",
		env = {
			PICKMAN_REAP_CACHE = cache,
			PICKMAN_REAP_SWEPT = if prefix[1] == "sandbox-exec" then "1" else "",
			PICKMAN_REAP_TOP = myPid(), -- named in a killed sweeper's report (c0132)
		},
	})
	-- with the specs stopped, unlink any symlink one swapped in at the top of .cache (review 006 F1); the launcher
	-- did so already, this is belt and braces
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
			`\nREPOSITORY CHANGED during the test run: a check must never touch the real repository (zz-test skill).\n{table.concat(
				changed,
				"\n"
			)}\nStop and report this; do not repair the repository yourself.\n`
		)
		code = if code == 0 then 1 else code
	end
	process.exit(code)
end

return fence
