--!strict
-- d0383: `./zn watch-kick` from any worktree starts a net that runs in the main checkout's standing `.worktree/watch-net`,
-- and returns only once it knows the net started: the net made or reused its worktree (exit 0), or it is known not to
-- have (exit non-zero and the net's own error line on stderr; its start limit passed; its shell was killed; the kick's own
-- backstop passed). The kick's files are per kick, in the main checkout's .cache/watch-net/, and no variable of the
-- kick reaches the net's own suite. Every case drives `./zn` in a throwaway fixture repository under .cache/; the fixture's
-- suite is a stub (tests/lib/netfix) that fails, so a started net ends and changes nothing on the fixture's origin.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local has, read, trim = netfix.has, netfix.read, netfix.trim

local function expectNetIn(w: netfix.World, log: string)
	-- the net names the directory it runs in
	local named = string.match(read(log), "fast suite of every project in (%S+)")
	t.expect(named).toBe(`{w.main}/.worktree/watch-net`)
	t.expect(netfix.netWorktrees(w)).toEqual({ `{w.main}/.worktree/watch-net` })
	t.expect(fs.isDir(`{w.raft}/.worktree/watch-net`)).toBe(false)
end

return t.spec("watch-kick starts the net from any worktree and knows it started", function(it)
	-- one world for the cases that start a net normally; each settles its net before the next kick
	local a = netfix.world("d0383-kick-a", { standing = true, rafts = 2 })

	it("a kick from a raft's worktree runs the net in the main checkout's standing worktree", function()
		local r = netfix.kick(a, a.raft)
		t.expect(r.code).toBe(0)
		local log = netfix.logOf(r.stdout) :: string
		t.expect(log ~= nil).toBe(true)
		-- the files are the main checkout's, named by absolute path, and the raft's .cache holds none
		t.expect(string.sub(log, 1, #`{a.main}/.cache/watch-net/`)).toBe(`{a.main}/.cache/watch-net/`)
		t.expect(fs.isDir(`{a.raft}/.cache/watch-net`)).toBe(false)
		t.expect(fs.isFile(`{a.raft}/.cache/watch-net.log`)).toBe(false)
		t.expect(fs.isFile((string.gsub(log, "%.log$", ".ready")))).toBe(true)
		t.expect(netfix.settle(log)).toBe("0")
		expectNetIn(a, log)
	end)

	it(
		"a second kick, from the main checkout, adds no second worktree on the branch and shares no file",
		function()
			local first = netfix.logOf(netfix.kick(a, a.raft).stdout) :: string
			netfix.settle(first)
			local r = netfix.kick(a, a.f.main)
			t.expect(r.code).toBe(0)
			local second = netfix.logOf(r.stdout) :: string
			t.expect(second ~= first).toBe(true)
			netfix.settle(second)
			expectNetIn(a, second)
			t.expect(has(read(second), "worktree add")).toBe(false)
			-- both logs are still there, each holding its own net's lines
			t.expect(has(read(first), "fast suite")).toBe(true)
			t.expect(has(read(second), "fast suite")).toBe(true)
		end
	)

	it("nothing of the kick's state is in the environment its net's suite runs in", function()
		local r = netfix.kick(a, a.raft)
		t.expect(r.code).toBe(0)
		netfix.settle(netfix.logOf(r.stdout) :: string)
		local env = read(`{a.hold}/env`)
		t.expect(has(env, "PATH=")).toBe(true) -- the stub did dump its environment
		t.expect(has(env, "WATCH_NET_READY")).toBe(false)
		t.expect(has(env, "WATCH_KICK")).toBe(false)
		t.expect(has(env, `{a.main}/.cache/watch-net/`)).toBe(false)
		t.expect(has(env, ".ready")).toBe(false)
	end)

	it("the log outlives the raft worktree that kicked the net", function()
		local r = netfix.kick(a, `{a.main}/.worktree/R9998-fixture`)
		t.expect(r.code).toBe(0)
		local log = netfix.logOf(r.stdout) :: string
		netfix.settle(log)
		fixture.git(a.f.main, { "worktree", "remove", "--force", `{a.main}/.worktree/R9998-fixture` })
		t.expect(fs.isDir(`{a.main}/.worktree/R9998-fixture`)).toBe(false)
		t.expect(has(read(log), "fast suite")).toBe(true)
	end)

	it("a kick with no watch-net worktree yet has created it in the main checkout when it returns", function()
		local w = netfix.world("d0383-kick-create")
		t.expect(netfix.netWorktrees(w)).toEqual({})
		local r = netfix.kick(w, w.raft)
		t.expect(r.code).toBe(0)
		-- no settling: the kick itself waited for the worktree
		t.expect(netfix.netWorktrees(w)).toEqual({ `{w.main}/.worktree/watch-net` })
		t.expect(fs.isDir(`{w.raft}/.worktree/watch-net`)).toBe(false)
		netfix.settle(netfix.logOf(r.stdout) :: string)
	end)

	it("a kick returns once the net has its worktree, while the net's suite still runs", function()
		local w = netfix.world("d0383-kick-running", { standing = true })
		netfix.holdOn(w)
		local r = netfix.kick(w, w.raft)
		t.expect(r.code).toBe(0)
		local log = netfix.logOf(r.stdout) :: string
		-- the suite is held open by its stub: the net has not ended, and ends 0 once released
		t.expect(netfix.waitFor(`{w.hold}/started`)).toBe(true)
		t.expect(fs.isFile((string.gsub(log, "%.log$", ".exit")))).toBe(false)
		t.expect(trim(r.stderr)).toBe("")
		fs.writeFile(`{w.hold}/release`, "go\n")
		t.expect(netfix.settle(log)).toBe("0")
	end)

	it(
		"a net that fails before it has its worktree: its line on stderr, a non-zero exit, from each kick's own files",
		function()
			local w = netfix.world("d0383-kick-early", { standing = true })
			-- the first kick works, and its net ends with an exit file of its own
			local first = netfix.kick(w, w.raft)
			t.expect(first.code).toBe(0)
			local firstLog = netfix.logOf(first.stdout) :: string
			t.expect(netfix.settle(firstLog)).toBe("0")
			local firstLast = string.match(trim(read(firstLog)), "([^\n]*)$") or ""

			-- a plain folder where the worktree was: the next net fails at once
			fixture.git(w.f.main, { "worktree", "remove", "--force", `{w.main}/.worktree/watch-net` })
			fs.writeDir(`{w.main}/.worktree/watch-net`)
			fs.writeFile(`{w.main}/.worktree/watch-net/stray.txt`, "x\n")
			local folder = netfix.kick(w, w.raft)
			t.expect(folder.ok).toBe(false)
			t.expect(has(folder.stderr, "exists and is not a worktree")).toBe(true)
			t.expect(has(folder.stderr, firstLast)).toBe(false) -- not the earlier net's line
			t.expect(has(folder.stdout, "exists and is not a worktree")).toBe(false)
			t.expect(has(folder.stdout, "started")).toBe(false)

			-- the branch held by a worktree elsewhere: the net's `git worktree add` is refused
			fs.removeDir(`{w.main}/.worktree/watch-net`)
			fixture.git(w.f.main, { "worktree", "prune" })
			fixture.git(w.f.main, { "worktree", "add", "-q", `{w.base}/elsewhere`, "watch-net" })
			local added = netfix.kick(w, w.raft)
			t.expect(added.ok).toBe(false)
			t.expect(added.code ~= 0).toBe(true)
			t.expect(has(added.stderr, "worktree add")).toBe(true)
			t.expect(has(added.stderr, "exists and is not a worktree")).toBe(false)
			t.expect(has(added.stdout, "started")).toBe(false)
			-- the earlier kicks' files were not touched
			t.expect(trim(read((string.gsub(firstLog, "%.log$", ".exit"))))).toBe("0")
			t.expect(has(read(firstLog), firstLast)).toBe(true)
		end
	)

	-- the fixture's origin answers through a stub that holds a fetch (mode `hang`: until hold/release, at most 20 s) or
	-- kills the net's shell and then holds (mode `kill`)
	local h = netfix.world("d0383-kick-hang", { standing = true })
	local function stub(mode: string)
		local path = `{h.base}/slow-upload-pack`
		fs.writeFile(
			path,
			"#!/bin/sh\n"
				.. `H='{h.hold}'\n`
				.. `if [ "{mode}" = kill ]; then\n`
				.. `  for _ in $(seq 1 50); do f=$(ls -t '{h.base}'/main/.cache/watch-net/*.pid 2>/dev/null | head -1); [ -n "$f" ] && break; sleep 0.1; done\n`
				.. '  [ -n "$f" ] && kill -9 "$(cat "$f")"\n'
				.. "fi\n"
				.. 'for _ in $(seq 1 200); do [ -f "$H/release" ] && break; sleep 0.1; done\n'
				.. 'exec git-upload-pack "$@"\n'
		)
		process.exec("chmod", { "+x", path })
		fixture.git(h.f.main, { "config", "remote.origin.uploadpack", path })
	end

	it("a net whose start passes its own limit exits with one line, and the kick reports it", function()
		stub("hang")
		local r = netfix.kick(h, h.raft, { "--start", "1", "--wait", "20" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "watch-net: no worktree after 1 s")).toBe(true)
		t.expect(has(r.stdout, "started")).toBe(false)
	end)

	it("a kick whose own backstop passes first fails with a line, and leaves the net to its limit", function()
		stub("hang")
		local r = netfix.kick(h, h.raft, { "--start", "60", "--wait", "2" })
		t.expect(r.ok).toBe(false)
		t.expect(r.code ~= 0).toBe(true)
		t.expect(has(r.stderr, "watch-net: no word from the net after 2 s")).toBe(true)
		t.expect(has(r.stdout, "started")).toBe(false)
		-- let the net go on and end, so nothing holds the next case
		local log = string.match(r.stderr, "log at (%S+%.log)") :: string
		fs.writeFile(`{h.hold}/release`, "go\n")
		t.expect(netfix.settle(log)).toBe("0")
		fs.removeFile(`{h.hold}/release`)
	end)

	it("a net killed before it has its worktree is detected, not waited for", function()
		stub("kill")
		local r = netfix.kick(h, h.raft, { "--start", "60", "--wait", "30" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "watch-net: the net ended before it had its worktree")).toBe(true)
		t.expect(has(r.stderr, "no word from the net")).toBe(false)
		t.expect(has(r.stdout, "started")).toBe(false)
		fs.writeFile(`{h.hold}/release`, "go\n") -- the held stub goes, so nothing is left running
	end)
end)
