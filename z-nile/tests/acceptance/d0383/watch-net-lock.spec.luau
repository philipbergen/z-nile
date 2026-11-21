--!strict
-- d0383 F3: at most one net per repository. The lock is a file in the main checkout's .cache/watch-net/ holding the
-- holder's pid and start id; a net that finds it held records a rerun request, prints "watch-net: already running" and
-- ends 0; the kick passes that on as success; the running net runs once more at its end when a request was recorded.
-- The rules are pure (lib/watch); the cases below also drive real kicks in a fixture whose stub suite holds on a marker.
local fence = require("@tests/lib/fence")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local process = require("@lune/process")
local procstart = require("@znile/lib/procstart")
local t = require("@tests/lib/t")
local watch = require("@znile/lib/watch")

local has, read, trim = netfix.has, netfix.read, netfix.trim

local function runs(w: netfix.World): string
	return string.gsub(trim(read(`{w.hold}/runs`)), "\n", " ") :: string
end

return t.spec("one net at a time per repository", function(it)
	it("the lock is held by the process that wrote it, and by no other that has its pid", function()
		local text = watch.lockText(4242, "Sat Nov 14 09:00:00 2026")
		t.expect(text).toBe("4242 Sat Nov 14 09:00:00 2026\n")
		t.expect(watch.parseLock(text)).toEqual({ pid = 4242, start = "Sat Nov 14 09:00:00 2026" })
		t.expect(watch.lockHeld(text, "Sat Nov 14 09:00:00 2026")).toBe(true)
		-- the holder is gone
		t.expect(watch.lockHeld(text, nil)).toBe(false)
		-- a later process has the pid
		t.expect(watch.lockHeld(text, "Sun Nov 15 10:00:00 2026")).toBe(false)
		-- nothing parses: nothing holds
		t.expect(watch.lockHeld("", "x")).toBe(false)
		t.expect(watch.lockHeld("garbage", "x")).toBe(false)
		t.expect(watch.parseLock("12\n")).toBe(nil)
	end)

	it("the net's start id is the spec runner's: one script, and it reads a live process", function()
		t.expect(procstart.STARTED).toBe(fence.STARTED)
		local mine = fence.myPid()
		t.expect(procstart.startOf(mine)).toBe(fence.startOf(mine))
		t.expect(procstart.startOf(mine) ~= nil).toBe(true)
		t.expect(procstart.startOf("999999999")).toBe(nil)
	end)

	it("a rerun runs again only while rounds remain", function()
		t.expect(watch.again(true, 1, 4)).toBe(true)
		t.expect(watch.again(true, 4, 4)).toBe(false)
		t.expect(watch.again(false, 1, 4)).toBe(false)
	end)

	it("the kick's files are named by kick, and old kicks' files are pruned by id", function()
		local a = watch.kickFiles("/m/.cache/watch-net", 1700000000, 41)
		local b = watch.kickFiles("/m/.cache/watch-net", 1700000000, 42)
		t.expect(a.id).toBe("1700000000-41")
		t.expect(a.log).toBe("/m/.cache/watch-net/1700000000-41.log")
		t.expect(a.ready ~= b.ready and a.exit ~= b.exit and a.log ~= b.log).toBe(true)
		local names = {
			"0000000003-9.log",
			"0000000001-9.log",
			"0000000001-9.exit",
			"0000000002-9.ready",
			"lock",
			"rerun",
		}
		t.expect(watch.pruneKicks(names, 2)).toEqual({ "0000000001-9.exit", "0000000001-9.log" })
		t.expect(watch.pruneKicks(names, 3)).toEqual({})
	end)

	it(
		"what the kick knows of its net: the marker wins, then the exit, then whether the shell lives",
		function()
			t.expect(watch.startState(true, 1, false)).toBe("ready")
			t.expect(watch.startState(false, 0, false)).toBe("exited")
			t.expect(watch.startState(false, nil, false)).toBe("gone")
			t.expect(watch.startState(false, nil, true)).toBe("waiting")
		end
	)

	local w = netfix.world("d0383-lock", { standing = true })
	netfix.holdOn(w)

	it(
		"two kicks close together never run two suites at once, and the request is honoured exactly once",
		function()
			local one = netfix.kick(w, w.raft)
			t.expect(one.code).toBe(0)
			local log = netfix.logOf(one.stdout) :: string
			t.expect(netfix.waitFor(`{w.hold}/started`)).toBe(true)
			local head = fixture.git(`{w.main}/.worktree/watch-net`, { "rev-parse", "HEAD" })
			-- two more kicks while the first net's suite is held open
			local two = netfix.kick(w, w.f.main)
			local three = netfix.kick(w, w.raft)
			for _, r in { two, three } do
				t.expect(r.code).toBe(0)
				t.expect(has(r.stdout, "watch-net: already running")).toBe(true)
				t.expect(has(r.stdout, "started")).toBe(false)
				t.expect(trim(r.stderr)).toBe("")
			end
			-- one suite so far, the standing worktree unmoved, the first kick's log and files intact
			t.expect(runs(w)).toBe("start")
			t.expect(fixture.git(`{w.main}/.worktree/watch-net`, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(has(read(log), "fast suite")).toBe(true)
			t.expect(fs.isFile((string.gsub(log, "%.log$", ".exit")))).toBe(false)
			t.expect(fs.isFile(`{w.main}/.cache/watch-net/lock`)).toBe(true)
			-- release: the net runs once more for the two requests together, and no third time
			fs.writeFile(`{w.hold}/release`, "go\n")
			t.expect(netfix.settle(log)).toBe("0")
			t.expect(runs(w)).toBe("start end start end")
			t.expect(fs.isFile(`{w.main}/.cache/watch-net/lock`)).toBe(false)
			t.expect(fs.isFile(`{w.main}/.cache/watch-net/rerun`)).toBe(false)
			t.expect(has(read(log), "a rerun was requested")).toBe(true)
		end
	)

	it("a lock whose holder is gone, or whose pid another process has, is taken over", function()
		local dir = `{w.main}/.cache/watch-net`
		local before = runs(w)
		-- a dead holder
		local dead = trim(process.exec("sh", { "-c", "echo $$" }).stdout)
		fs.writeFile(`{dir}/lock`, `{dead} Sat Nov 14 09:00:00 2026\n`)
		local first = netfix.kick(w, w.raft)
		t.expect(first.code).toBe(0)
		t.expect(has(first.stdout, "started")).toBe(true)
		t.expect(netfix.settle(netfix.logOf(first.stdout) :: string)).toBe("0")
		t.expect(runs(w)).toBe(before .. " start end")
		-- a live process (launchd) that is not the net that wrote the lock
		fs.writeFile(`{dir}/lock`, "1 Sat Nov 14 09:00:00 2026\n")
		local second = netfix.kick(w, w.raft)
		t.expect(second.code).toBe(0)
		t.expect(has(second.stdout, "started")).toBe(true)
		t.expect(netfix.settle(netfix.logOf(second.stdout) :: string)).toBe("0")
		t.expect(runs(w)).toBe(before .. " start end start end")
	end)
end)
