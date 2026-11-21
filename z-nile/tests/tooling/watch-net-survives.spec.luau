--!strict
-- R0138 review 001 F1: a net does not depend on the checkout that kicked it once it has started (the raft's worktree is
-- deleted minutes after the kick), and a crash in a round gives the lock back. These cases hold a stub suite on a marker
-- (tests/lib/netfix). The quick cases are in watch-net-quick.spec.luau, the hand-off in watch-net-handoff.spec.luau
-- (each file stays under 30 s). The d0383 acceptance specs are sequestered and not edited.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local t = require("@tests/lib/t")
local watch = require("@znile/lib/watch")

local has, read, trim = netfix.has, netfix.read, netfix.trim

local function runs(w: netfix.World): string
	return string.gsub(trim(read(`{w.hold}/runs`)), "\n", " ") :: string
end

return t.spec("a net outlives the worktree that kicked it", function(it)
	local w = netfix.world("r0138-survive", { standing = true })
	netfix.holdOn(w)

	it("a net kicked from a raft's worktree goes on to its rerun after that worktree is removed", function()
		local files = watch.filesDir(w.main)
		local one = netfix.kick(w, w.raft)
		t.expect(one.code).toBe(0)
		local log = netfix.logOf(one.stdout) :: string
		t.expect(netfix.waitFor(`{w.hold}/started`)).toBe(true)
		-- a landing from the main checkout asks for a rerun while the suite is held
		local two = netfix.kick(w, w.f.main)
		t.expect(two.code).toBe(0)
		t.expect(has(two.stdout, "watch-net: already running")).toBe(true)
		-- the raft is finished and its worktree deleted (zz-execute Phase 6, step 4)
		fixture.git(w.f.main, { "worktree", "remove", "--force", w.raft })
		t.expect(fs.isDir(w.raft)).toBe(false)
		fs.writeFile(`{w.hold}/release`, "go\n")
		t.expect(netfix.settle(log)).toBe("0")
		t.expect(runs(w)).toBe("start end start end")
		t.expect(fs.isFile(`{files}/lock`)).toBe(false)
		t.expect(fs.isFile(`{files}/rerun`)).toBe(false)
		t.expect(has(read(log), "a rerun was requested")).toBe(true)
		t.expect(has(read(log), "No such file")).toBe(false)
	end)

	it("a net that throws inside a round gives the lock back, exits non-zero and logs the error", function()
		local v = netfix.world("r0138-throw", { standing = true })
		netfix.holdOn(v)
		local one = netfix.kick(v, v.raft)
		t.expect(one.code).toBe(0)
		local log = netfix.logOf(one.stdout) :: string
		t.expect(netfix.waitFor(`{v.hold}/started`)).toBe(true)
		-- the standing worktree vanishes under the held suite: the round's next git call has no folder to run in
		fixture.git(v.f.main, { "worktree", "remove", "--force", `{v.main}/.worktree/watch-net` })
		fs.writeFile(`{v.hold}/release`, "go\n")
		t.expect(netfix.settle(log)).toBe("1")
		t.expect(fs.isFile(`{watch.filesDir(v.main)}/lock`)).toBe(false)
		t.expect(trim(read(log)) ~= "").toBe(true)
	end)
end)
