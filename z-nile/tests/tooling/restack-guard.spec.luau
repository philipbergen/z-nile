--!strict
-- d0434: the fast guard of what `./zn restack --abort` and a plain restack keep (design review 001 F4, F6; code review 001
-- F1, F2, F5, F7, F8). Fixture: `tests/lib/restackfix.luau` under .cache/restack-guard. `--abort` puts a pushed layer
-- that was rebased again back on the tip it pushed, whichever layer the run started on; a plain restack over a stopped
-- run's marker starts its record from where it finds each branch, so a later `--abort` keeps a commit the worker made in
-- between, and prints every branch it moved; a plain restack that stops before it writes its marker (a failed fetch, a
-- dirty worktree) leaves the stopped run's marker as it was; a refused push names the way on, and it works.
local rf = require("@tests/lib/restackfix")
local t = require("@tests/lib/t")

local L1, L2, L3 = rf.L1, rf.L2, rf.L3
local git, has, say, zn = rf.git, rf.has, rf.say, rf.zn

return t.spec("d0434: restack --abort and a plain restack keep what the worker has", function(it)
	it("sets up three layers on a local origin", function()
		rf.setup("restack-guard")
		t.expect(rf.remoteSha(L3)).toBe(rf.ctx().base[L3])
	end)

	it(
		"--abort puts a pushed layer that was rebased again back on the tip it pushed, when the run started on another layer",
		function()
			local base = rf.ctx().base
			rf.reset(L3) -- the run starts on layer 3, so layer 1 is not the branch the abort is on
			rf.mainMoves({ [rf.BETA] = "main beta\n" }, "main adds beta") -- layer 1 rebases and is pushed, layer 2 conflicts
			t.expect(zn({ "restack", "R0010" }).code).toBe(3)
			local pushedOne = rf.remoteSha(L1)
			t.expect(pushedOne ~= base[L1]).toBe(true)
			rf.mainMoves({ ["pickman/src/poison1.luau"] = "poison\n" }, "main adds poison1") -- the second pass is red
			git(rf.ctx().wt, { "fetch", "-q", "origin" })
			rf.resolve(rf.BETA, "merged beta\n")
			local red = zn({ "restack", "R0010", "--continue" })
			t.expect(red.code).toBe(1)
			t.expect(has(say(red), "check.sh failed")).toBe(true)
			local redTip = rf.localSha(L1)
			t.expect(redTip ~= pushedOne).toBe(true)
			local aborted = zn({ "restack", "R0010", "--abort" })
			t.expect(aborted.code).toBe(0)
			t.expect(git(rf.ctx().wt, { "branch", "--show-current" })).toBe(L3)
			t.expect(rf.localSha(L1)).toBe(pushedOne)
			t.expect(rf.remoteSha(L1)).toBe(pushedOne)
			t.expect(rf.localSha(L2)).toBe(base[L2])
			t.expect(rf.localSha(L3)).toBe(base[L3])
			-- the abort names the branch it moved, with the tip it was on and the tip it is on now
			t.expect(has(say(aborted), `{L1}: {redTip} -> {pushedOne}`)).toBe(true)
		end
	)

	it(
		"--abort after a plain restack keeps a commit the worker made on a pushed layer between the runs (code review 001 F1)",
		function()
			rf.reset(L1)
			rf.mainMoves({ ["pickman/src/poison2.luau"] = "p\n" }, "main adds poison2") -- layer 1 pushed, layer 2 red
			t.expect(zn({ "restack", "R0010" }).code).toBe(1)
			local pushedOne = rf.remoteSha(L1)
			git(rf.ctx().wt, { "switch", "-q", L1 })
			local mine = rf.commit(
				rf.ctx().wt,
				"pickman/src/poison1.luau",
				"p\n",
				"R0010: the worker's fix (still red)"
			)
			t.expect(zn({ "restack", "R0010" }).code).toBe(1) -- stops at layer 1: its check is red
			local aborted = zn({ "restack", "R0010", "--abort" })
			t.expect(aborted.code).toBe(0)
			t.expect(rf.localSha(L1)).toBe(mine)
			t.expect(rf.remoteSha(L1)).toBe(pushedOne)
			t.expect(has(rf.holders(mine), `refs/heads/{L1}`)).toBe(true)
			-- the same when the second run stops because layer 1's check did not start (exit 75)
			rf.reset(L1)
			rf.mainMoves({ ["pickman/src/poison2.luau"] = "p\n" }, "main adds poison2")
			t.expect(zn({ "restack", "R0010" }).code).toBe(1)
			git(rf.ctx().wt, { "switch", "-q", L1 })
			mine = rf.commit(
				rf.ctx().wt,
				"pickman/src/busy1.luau",
				"b\n",
				"R0010: the worker's commit on layer 1"
			)
			t.expect(zn({ "restack", "R0010" }).code).toBe(75)
			t.expect(zn({ "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(rf.localSha(L1)).toBe(mine)
		end
	)

	it(
		"--abort after a plain restack keeps a resolution a red check kept on its branch (code review 001 F2, probe B)",
		function()
			rf.reset(L1)
			rf.pushLayer(
				L1,
				{ [rf.SHARED] = "fix\n", ["pickman/src/poison2.luau"] = "p\n" },
				"fix layer 1, poison layer 2"
			)
			t.expect(zn({ "restack", "R0010" }).code).toBe(3)
			rf.resolve(rf.SHARED, "merged\n")
			t.expect(zn({ "restack", "R0010", "--continue" }).code).toBe(1) -- layer 2 red: the resolution stays, unpushed
			local resolved = rf.localSha(L2)
			t.expect(zn({ "restack", "R0010" }).code).toBe(1) -- nothing fixed: red again
			t.expect(zn({ "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(rf.localSha(L2)).toBe(resolved)
		end
	)

	it(
		"a refused push names --abort then restack; a plain restack that cannot fetch leaves the stopped run's marker, so that way still works",
		function()
			local ctx = rf.ctx()
			rf.reset(L1)
			rf.pushLayer(L1, { [rf.SHARED] = "fix\n" }, "fix layer 1")
			t.expect(zn({ "restack", "R0010" }).code).toBe(3) -- layer 2 conflicts on shared.luau
			rf.otherPushes(L3, "pickman/src/theirs.luau") -- another clone fast-forwards layer 3 before the continue
			rf.resolve(rf.SHARED, "merged\n")
			local refused = say(zn({ "restack", "R0010", "--continue" }))
			local abortAt = rf.at(refused, "./zn restack R0010 --abort")
			local plainAt = rf.at(refused, "then ./zn restack R0010")
			t.expect(abortAt ~= nil and plainAt ~= nil and (abortAt :: number) < (plainAt :: number))
				.toBe(true)
			local pushedTwo = rf.remoteSha(L2)
			t.expect(pushedTwo).toBe(rf.localSha(L2))
			local before = rf.marker()
			local url = git(ctx.wt, { "remote", "get-url", "origin" })
			git(ctx.wt, { "remote", "set-url", "origin", `{ctx.f.base}/nowhere.git` })
			local failed = zn({ "restack", "R0010" })
			git(ctx.wt, { "remote", "set-url", "origin", url })
			t.expect(failed.code).toBe(1)
			t.expect(rf.marker()).toBe(before) -- byte for byte
			local aborted = zn({ "restack", "R0010", "--abort" })
			t.expect(aborted.code).toBe(0)
			t.expect(has(say(aborted), L2)).toBe(true) -- the first run's push is still named
			t.expect(has(say(aborted), "nothing had been pushed")).toBe(false)
			t.expect(rf.localSha(L3)).toBe(ctx.base[L3])
			local again = zn({ "restack", "R0010" })
			t.expect(again.code).toBe(0)
			t.expect(rf.remoteSha(L3)).toBe(rf.localSha(L3))
			t.expect(git(ctx.wt, { "show", `{L3}:pickman/src/theirs.luau` })).toBe("theirs")
			t.expect(rf.remoteSha(L2)).toBe(pushedTwo)
		end
	)

	it(
		"a plain restack refuses a dirty worktree and leaves a stopped run's marker byte for byte, an unrecorded push included",
		function()
			local ctx = rf.ctx()
			rf.reset(L1)
			rf.pushLayer(L1, { ["pickman/src/poison2.luau"] = "p\n" }, "layer 1 poisons layer 2's check")
			t.expect(zn({ "restack", "R0010" }).code).toBe(1) -- layer 2 red
			-- a push the marker says was started and origin never got: a reconcile ahead of the refusal would drop the line
			rf.setMarker(rf.marker() .. `pushing {L3} {ctx.M0}\n`)
			local before = rf.marker()
			t.expect(has(before, `pushing {L3} `)).toBe(true)
			rf.write(ctx.wt, "pickman/src/alpha.luau", "dirty\n")
			local r = zn({ "restack", "R0010" })
			t.expect(r.code).toBe(1)
			t.expect(has(say(r), "not clean")).toBe(true)
			t.expect(rf.marker()).toBe(before)
			git(ctx.wt, { "checkout", "--", "pickman/src/alpha.luau" })
		end
	)

	it(
		"a plain restack that cannot fetch changes nothing, so a push a killed run left unrecorded is found later: --abort keeps it and the next restack finishes (code review 002, probe K)",
		function()
			local ctx = rf.ctx()
			rf.reset(L1)
			rf.pushLayer(L1, { ["pickman/src/alpha.luau"] = "alpha 2\n" }, "alpha changed") -- layers 2 and 3 rebase cleanly
			t.expect(rf.znWith({ "restack", "R0010" }, { ZN_RESTACK_KILL = "after-push" }).ok).toBe(false)
			local two = rf.remoteSha(L2)
			t.expect(two ~= ctx.base[L2] and two == rf.localSha(L2)).toBe(true) -- the push landed
			local before = rf.marker()
			t.expect(has(before, `pushing {L2} {two}`)).toBe(true)
			local url = git(ctx.wt, { "remote", "get-url", "origin" })
			git(ctx.wt, { "remote", "set-url", "origin", `{ctx.f.base}/nowhere.git` })
			local failed = zn({ "restack", "R0010" })
			git(ctx.wt, { "remote", "set-url", "origin", url })
			t.expect(failed.code).toBe(1)
			t.expect(rf.marker()).toBe(before) -- the pushing line too
			local aborted = zn({ "restack", "R0010", "--abort" })
			t.expect(aborted.code).toBe(0)
			t.expect(has(say(aborted), `{L2} stay as pushed`)).toBe(true)
			t.expect(rf.localSha(L2)).toBe(two)
			local again = zn({ "restack", "R0010" })
			t.expect(again.code).toBe(0)
			t.expect(has(say(again), "restacked R0010")).toBe(true)
			t.expect(rf.remoteSha(L2)).toBe(two)
			t.expect(rf.remoteSha(L3)).toBe(rf.localSha(L3))
		end
	)
end)
