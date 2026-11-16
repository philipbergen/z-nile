--!strict
-- c0075 AC5: the jail the run really sits in. A command run through the fixture helper can start in a proven fixture
-- and then go anywhere, so the runner's jail, not the helper, is what keeps it out of the real checkout (c0075's
-- problem). The probes are the same on macOS (sandbox-exec) and Linux (bubblewrap), and each runs only after the first
-- case has found a named jail: an unjailed run stops there and never probes the real checkout. Each probe is a file it
-- names itself and removes at once; none rewrites a tracked file, the index, an object or a ref.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0075-live-jail`
local fx = `{base}/fixture`
local jail = process.env.PICKMAN_TEST_JAIL or ""
local tag = string.gsub(process.exec("sh", { "-c", "echo $$" }).stdout, "%s+$", "")

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function named(): boolean
	return jail == "sandbox-exec" or jail == "bwrap" or string.sub(jail, 1, 14) == "outer sandbox "
end

-- stops a case before it probes anything when the run is not in a jail
local function needJail()
	if not named() then
		error(`this run is not jailed ({jail}); not probing the real checkout`)
	end
end

-- the script every probe runs: $1 is the real checkout, $2 a tag unique to this run
local PROBE = table.concat({
	'cd "$1" || exit 90',
	'if : > ".pickman-jail-probe-$2" 2>/dev/null; then rm -f ".pickman-jail-probe-$2"; echo FILE-WRITTEN; fi',
	"if [ -d .git ]; then gd=.git; else gd=$(git rev-parse --path-format=absolute --git-common-dir); fi",
	'if : > "$gd/pickman-jail-probe-$2" 2>/dev/null; then rm -f "$gd/pickman-jail-probe-$2"; echo GITDIR-WRITTEN; fi',
	'if : > "$gd/objects/pickman-jail-probe-$2" 2>/dev/null; then rm -f "$gd/objects/pickman-jail-probe-$2"; echo OBJECTS-WRITTEN; fi',
	"echo DONE",
}, "\n")

local function setUp()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(fx)
	t.expect(process.exec("git", { "init", "-q", "-b", "main", fx }).ok).toBe(true)
end

local function probe(run: (script: string) -> Result): ()
	local r = run(PROBE)
	t.expect(has(r.stdout, "DONE")).toBe(true)
	t.expect(has(r.stdout, "FILE-WRITTEN")).toBe(false)
	t.expect(has(r.stdout, "GITDIR-WRITTEN")).toBe(false)
	t.expect(has(r.stdout, "OBJECTS-WRITTEN")).toBe(false)
end

return t.spec("c0075 specs run in a jail on every platform", function(it)
	it("is told which jail it is in, and never none", function()
		needJail()
		t.expect(process.os == "linux" and jail == "sandbox-exec").toBe(false)
		t.expect(process.os == "macos" and jail == "bwrap").toBe(false)
	end)

	it(
		"a shell command run through the helper cannot write the real checkout or its git directory",
		function()
			needJail()
			setUp()
			probe(function(script)
				return fixture.exec(fx, "sh", { "-c", script, "_", root, tag })
			end)
		end
	)

	it("a script run through the helper gets the same jail", function()
		needJail()
		setUp()
		fs.writeFile(`{fx}/probe.sh`, PROBE)
		probe(function(_)
			return fixture.exec(fx, "sh", { `{fx}/probe.sh`, root, tag })
		end)
	end)

	it("the fixture itself stays fully writable, git included", function()
		needJail()
		setUp()
		fs.writeFile(`{fx}/a.txt`, "a")
		local r = fixture.exec(fx, "sh", {
			"-c",
			"git add a.txt && git -c user.name=c0075 -c user.email=c0075@example.invalid commit -qm first && git log --oneline | wc -l",
		})
		t.expect(r.ok).toBe(true)
		t.expect((string.gsub(r.stdout, "%s+", ""))).toBe("1")
	end)

	it("the run's temp folder is writable", function()
		needJail()
		local temp = process.env.TMPDIR or ""
		t.expect(temp ~= "").toBe(true)
		t.expect(
			process.exec("sh", { "-c", `: > '{temp}/c0075-probe-{tag}' && rm '{temp}/c0075-probe-{tag}'` }).ok
		)
			.toBe(true)
	end)

	it("the shared temp folder does not reach the host: closed on macOS, private on Linux", function()
		needJail()
		local wrote =
			process.exec("sh", { "-c", `: > /tmp/c0075-probe-{tag} && rm /tmp/c0075-probe-{tag}` }).ok
		-- bubblewrap gives a Linux jail its own /tmp, which nothing outside sees; macOS denies the write
		t.expect(wrote).toBe(jail == "bwrap")
	end)

	it("no host socket is reachable on Linux: Docker's, the user's bus, the system bus", function()
		needJail()
		if process.os ~= "linux" or jail ~= "bwrap" then
			return -- the macOS profile leaves them open (a known gap, filed as a follow-up); an outer sandbox is its own
		end
		local runtime = (process.env.XDG_RUNTIME_DIR or "/nonexistent")
		local r = process.exec("perl", {
			"-MIO::Socket::UNIX",
			"-e",
			'for my $p (@ARGV) { print "CONNECTED $p\\n" if IO::Socket::UNIX->new(Peer => $p) }',
			"/run/docker.sock",
			"/var/run/docker.sock",
			`{runtime}/bus`,
			"/run/dbus/system_bus_socket",
		})
		t.expect(r.stdout).toBe("")
		t.expect(process.exec("sh", { "-c", `: > /run/c0075-probe-{tag}` }).ok).toBe(false) -- /run is read-only
	end)

	it("the launcher's settings do not reach the specs", function()
		needJail()
		for _, name in { "PICKMAN_REAP_LOCK", "PICKMAN_REAP_CACHE", "PICKMAN_REAP_SWEPT" } do
			t.expect(process.env[name]).toBe(nil)
		end
	end)

	it(
		"the run's lock names the jail's pid namespace and holds the launcher, not the jailed processes",
		function()
			needJail()
			local lock = `{process.env.PICKMAN_TEST_FENCE or ""}/.cache/tests-run.lock`
			t.expect(fs.isDir(lock)).toBe(true)
			local names = fs.readDir(lock)
			local own = (string.gsub(process.exec("sh", { "-c", "echo $PPID" }).stdout, "%s+", ""))
			local pids = {}
			for _, name in names do
				if string.match(name, "^pid%-%d+$") then
					table.insert(pids, name)
				end
			end
			t.expect(#pids >= 1).toBe(true) -- the launcher's, at least
			if jail == "bwrap" then
				t.expect(table.find(names, "pidns") ~= nil).toBe(true)
				local mine = (
					string.gsub(process.exec("readlink", { "/proc/self/ns/pid" }).stdout, "%s+$", "")
				)
				local theirs = (string.gsub(fs.readFile(`{lock}/pidns`), "%s+$", ""))
				t.expect(string.sub(theirs, 1, 5)).toBe("pid:[") -- a namespace id
				t.expect(theirs == mine).toBe(false) -- the top process is outside this namespace
				t.expect(table.find(names, `pid-{own}`)).toBe(nil) -- nothing inside the jail records its own pid
			else
				t.expect(table.find(names, "pidns")).toBe(nil)
			end
		end
	)
end)
