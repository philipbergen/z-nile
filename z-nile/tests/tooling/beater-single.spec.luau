--!strict
-- One beater per claim (review-005 F2, F4, F5 and final-review F6 of R0100). A pid file this young names a beater whatever
-- the process table says; the pid file is read again under the start lock, so a command that read "none" before another
-- wrote it starts nothing; the lock is released when the start fails; a second `beat --watch` ends at once when the pid
-- file names a live runner that is not its own; a registry that cannot be read mid-beat is said, not fatal; the commands
-- that tick are one table. A recording `perl` stands in for the detached start. Fixture under .cache/beater-single.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local P = "pickman/.tracker/issues"
local BEATER = "." .. "cache/tracker-beater"
local T0 = os.time()

local h: fakecli.Harness
local wt = ""
local specPid = ""

local function zn(cwd: string, args: { string }, now: number?, extra: { [string]: string }?): fixture.Result
	local env: { [string]: string } =
		{ FAKE_DIR = h.fakes, PATH = `{h.bin}:{process.env.PATH}`, ZN_BEATER = "1" }
	if now then
		env.ZN_NOW = tostring(now)
	end
	for k, v in (extra or {}) :: { [string]: string } do
		env[k] = v
	end
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
local function starts(): number
	if not fs.isFile(`{h.fakes}/beater`) then
		return 0
	end
	local _, n = string.gsub(fs.readFile(`{h.fakes}/beater`), "[^\n]+", "")
	return n
end
local function pidFile(): string
	return `{wt}/{BEATER}/c0010`
end
local function quiet()
	-- a command that has nothing to beat: the mark is not due, so only the beater is looked at
	return zn(wt, { "lessons", "--tags" }, T0 + 5)
end

return t.spec("one beater per claim", function(it)
	it("sets up a tracker, a worktree that holds c0010 and the shims", function()
		local doc =
			string.gsub(trackerfix.stub("c0010", "c0010", "new-a-b-c"), "design: draft", "design: draft")
		h = fakecli.new("beater-single", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0010/c0010.md`] = doc,
		})
		fs.writeFile(`{h.bin}/gh`, '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n')
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		-- git: a registry read after an armed `rev-parse origin/main` fails (the read that follows the beat's pinned sha)
		local git = fs.readFile(`{h.bin}/git`)
		local shim = '#!/bin/sh\nif [ -f "$FAKE_DIR/armed" ] && [ "$1 $2" = "rev-parse origin/main" ]; then touch "$FAKE_DIR/tripped"; fi\n'
			.. 'if [ -f "$FAKE_DIR/tripped" ] && [ "$1 $2" = "show origin/main:z-nile/projects.toml" ]; then echo "fatal: fake unreadable" >&2; exit 128; fi\n'
		fs.writeFile(`{h.bin}/git`, (string.gsub(git, "^#!/bin/sh\n", shim, 1)))
		local perl = (string.gsub(process.exec("sh", { "-c", "command -v perl" }).stdout, "%s+$", ""))
		specPid = (string.gsub(process.exec("sh", { "-c", "echo $PPID" }).stdout, "%s+$", ""))
		fs.writeFile(`{h.fakes}/livepid`, specPid)
		fs.writeFile(
			`{h.bin}/perl`,
			`#!/bin/sh\ncase "$2" in *setsid*) shift 2; echo "$* M=$ZN_MEASURED" >> "$FAKE_DIR/beater"; cat "$FAKE_DIR/livepid"; exit 0;; esac\nexec {perl} "$@"\n`
		)
		process.exec("chmod", { "+x", `{h.bin}/perl` })
		fs.writeFile(
			`{h.bin}/ps`,
			'#!/bin/sh\nf="$FAKE_DIR/ps.$4"; [ -f "$f" ] || f="$FAKE_DIR/ps.default"; if [ -f "$f" ]; then line=$(cat "$f"); else line="1 lune run"; fi\n'
				.. 'case "$2" in command=) echo "${line#* }";; *) echo "$line";; esac\n'
		)
		process.exec("chmod", { "+x", `{h.bin}/ps` })
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "beater-single" }), "worktree"), "%s+$", ""))
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
		t.expect(starts()).toBe(1)
	end)

	it("a pid file younger than a few seconds counts as running whatever the process table says", function()
		local now = os.time()
		local function text(age: number): string
			return `123 {now - age + heartbeat.BEATER_SECONDS}`
		end
		-- alive, and not listed as a runner of `beat --watch`: the starter's first seconds look like that
		t.expect(heartbeat.beaterRunning(text(2), now, true, false)).toBe(true)
		t.expect(heartbeat.beaterRunning(text(heartbeat.BEATER_YOUNG + 1), now, true, false)).toBe(false) -- a reused pid
		t.expect(heartbeat.beaterRunning(text(600), now, true, true)).toBe(true)
		t.expect(heartbeat.beaterRunning(text(600), now, true, nil)).toBe(true) -- the table cannot be read
		t.expect(heartbeat.beaterRunning(text(2), now, false, false)).toBe(false) -- dead
		t.expect(heartbeat.beaterRunning(`123 {now - 1}`, now, true, true)).toBe(false) -- past its deadline
		t.expect(heartbeat.beaterRunning("junk", now, true, true)).toBe(false)
		-- end to end: the pid answers `kill -0` and is a lune to the process table; young it is a beater, old it is not
		local before = starts()
		fs.writeFile(pidFile(), `{specPid} {os.time() + heartbeat.BEATER_SECONDS}`)
		must(quiet(), "a command with a young pid file")
		t.expect(starts()).toBe(before)
		fs.writeFile(pidFile(), `{specPid} {os.time() + heartbeat.BEATER_SECONDS - 600}`)
		must(quiet(), "a command with an old pid file naming another program")
		t.expect(starts()).toBe(before + 1)
		-- a dead pid in the file: the next command starts a beater
		before = starts()
		fs.writeFile(pidFile(), `999999 {os.time() + 3000}`)
		must(quiet(), "a command with a dead pid in the file")
		t.expect(starts()).toBe(before + 1)
	end)

	it(
		"the pid file is read again under the lock: one written while the command waited starts nothing",
		function()
			fs.removeFile(pidFile())
			local before = starts()
			-- the lock script runs through `sh`: this shim writes a live pid file just before it, as another command would
			local young = `{specPid} {os.time() + heartbeat.BEATER_SECONDS}`
			fs.writeFile(
				`{h.bin}/sh`,
				`#!/bin/sh\ncase "$*" in *'mkdir "$1"'*) printf '%s' '{young}' > "{pidFile()}";; esac\nexec /bin/sh "$@"\n`
			)
			process.exec("chmod", { "+x", `{h.bin}/sh` })
			must(quiet(), "a command whose rival wrote the pid file first")
			fs.removeFile(`{h.bin}/sh`)
			t.expect(starts()).toBe(before)
			t.expect(fs.isDir(`{pidFile()}.lock`)).toBe(false) -- and it let the lock go
		end
	)

	it("the lock is released when the start fails", function()
		-- the pid file's place is a folder, so writing it fails after the beater was started
		fs.removeFile(pidFile())
		fs.writeDir(pidFile())
		local before = starts()
		local r = quiet()
		process.exec("rmdir", { pidFile() })
		t.expect(starts()).toBe(before + 1)
		t.expect(fs.isDir(`{pidFile()}.lock`)).toBe(false)
		t.expect(r.ok).toBe(true)
	end)

	it(
		"a second beat --watch ends at once when the pid file names a live beater that is not its own",
		function()
			-- the process table is unreadable in the spec runner's jail: a fake `ps` answers from <fakes>/ps.<pid> ("<ppid> <command>"),
			-- and a pid it does not know is a lune whose parent is gone. The spec's own process stands in for the live runner.
			local top = TOP
			local runner = `perl x/z-nile/lib/bounded.pl --time 3600 -- {top}/zn beat c0010 --watch`
			local deadline = os.time() + 4
			local env = { ZN_BOUNDED_DEADLINE = tostring(deadline), ZN_BEAT_EVERY = "1" }
			fs.writeFile(`{h.fakes}/ps.{specPid}`, `1 {runner}`)
			fs.writeFile(pidFile(), `{specPid} {os.time() + heartbeat.BEATER_SECONDS - 600}`)
			local dup = zn(wt, { "beat", "c0010", "--watch" }, nil, env)
			t.expect(dup.ok).toBe(true)
			t.expect(string.find(dup.stdout, "another beater runs", 1, true) ~= nil).toBe(true)
			-- the file names this loop's own runner (an ancestor of the engine): the loop runs to its bound
			local engine = "lune"
			fs.writeFile(`{h.fakes}/ps.default`, `{specPid} {engine}`)
			local own = zn(wt, { "beat", "c0010", "--watch" }, nil, env)
			fs.removeFile(`{h.fakes}/ps.default`)
			t.expect(string.find(own.stdout, "another beater runs", 1, true) == nil).toBe(true)
			t.expect(string.find(own.stdout, "stopping before its bound", 1, true) ~= nil).toBe(true)
			-- a pid file naming a program that is not a beater does not stop the loop either
			fs.writeFile(`{h.fakes}/ps.{specPid}`, "1 lune run tests/run")
			local other = zn(wt, { "beat", "c0010", "--watch" }, nil, env)
			t.expect(string.find(other.stdout, "stopping before its bound", 1, true) ~= nil).toBe(true)
			fs.removeFile(`{h.fakes}/ps.{specPid}`)
		end
	)

	it(
		"a registry that cannot be read after the beat pinned main is said, and the command goes on",
		function()
			fs.removeFile(pidFile())
			fs.writeFile(`{h.fakes}/armed`, "1")
			local r = zn(wt, { "lessons", "--tags" }, T0 + 99999)
			fs.removeFile(`{h.fakes}/armed`)
			if fs.isFile(`{h.fakes}/tripped`) then
				fs.removeFile(`{h.fakes}/tripped`)
			end
			t.expect(r.ok).toBe(true) -- a beat never fails the command it rides on
			t.expect(string.find(r.stderr, "no readable", 1, true) ~= nil).toBe(true)
		end
	)

	it("the commands that tick while they run are one table", function()
		local names = {}
		for name in heartbeat.LONG_COMMANDS do
			table.insert(names, name)
		end
		table.sort(names)
		t.expect(names).toEqual({ "check", "dispatch", "done", "land" })
		t.expect(
			string.find(
				fs.readFile(`{TOP}/z-nile/engine/main.luau`),
				"heartbeat.LONG_COMMANDS[name]",
				1,
				true
			) ~= nil
		).toBe(true)
	end)
end)
