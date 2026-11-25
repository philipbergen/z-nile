--!strict
-- d0434: the fast guard of what `./zn restack --continue` judges before it goes on (design review 001 F5; code review
-- 001 F3, F4, F6, F8). Fixture: `tests/lib/restackfix.luau` under .cache/restack-stray. A layer the run moved or pushed
-- whose branch is back at its tip from before the run is refused, changing nothing, whatever refs/zn/pushed holds, and
-- the way on the refusal names first (`git branch -f <layer> <left>`, then `--continue`) keeps a staged resolution; the
-- second (`--abort`, then a plain restack) puts a pushed layer on the tip it pushed. Any other tip is the worker's change
-- and goes through the walk: a hand rebase during a stop, and a fix finished with `./zn finish`.
local rf = require("@tests/lib/restackfix")
local t = require("@tests/lib/t")

local L1, L2, L3 = rf.L1, rf.L2, rf.L3
local git, has, say, zn = rf.git, rf.has, rf.say, rf.zn

return t.spec("d0434: restack --continue refuses only a layer put back to its old tip", function(it)
	it("sets up three layers on a local origin", function()
		rf.setup("restack-stray")
		t.expect(rf.remoteSha(L3)).toBe(rf.ctx().base[L3])
	end)

	it(
		"--continue refuses a pushed layer back at its old tip, and git branch -f to the tip the run left keeps the staged resolution",
		function()
			local ctx = rf.ctx()
			rf.reset(L1)
			rf.mainMoves({ [rf.BETA] = "main beta\n" }, "main adds beta") -- layer 1 rebased and pushed, layer 2 conflicts
			t.expect(zn({ "restack", "R0010" }).code).toBe(3)
			local left = rf.remoteSha(L1)
			git(ctx.wt, { "update-ref", `refs/heads/{L1}`, ctx.base[L1] }) -- what an older engine or a hand reset leaves
			rf.resolve(rf.BETA, "the worker's resolution\n")
			rf.clearPushes()
			local r = zn({ "restack", "R0010", "--continue" })
			local out = say(r)
			t.expect(r.code).toBe(1)
			for _, part in { L1, left, ctx.base[L1], "c0010: alpha", "git log --oneline", "discards" } do
				t.expect(has(out, part)).toBe(true)
			end
			local moveAt = rf.at(out, `git branch -f {L1} {left}`)
			local continueAt = rf.at(out, "./zn restack R0010 --continue")
			local abortAt = rf.at(out, "./zn restack R0010 --abort")
			t.expect(moveAt ~= nil and continueAt ~= nil and abortAt ~= nil).toBe(true)
			t.expect(
				(moveAt :: number) < (continueAt :: number) and (continueAt :: number) < (abortAt :: number)
			)
				.toBe(true)
			t.expect(has(out, "reset")).toBe(false)
			t.expect(rf.rebasing()).toBe(true) -- nothing was changed
			t.expect(has(git(ctx.wt, { "diff", "--cached", "--name-only" }), rf.BETA)).toBe(true) -- the resolution, still staged
			t.expect(rf.pushes()).toBe(0)
			-- the first way it names, followed literally
			git(ctx.wt, { "branch", "-f", L1, left })
			local done = zn({ "restack", "R0010", "--continue" })
			t.expect(done.code).toBe(0)
			t.expect(rf.remoteSha(L1)).toBe(left)
			t.expect(git(ctx.wt, { "show", `origin/{L2}:{rf.BETA}` })).toBe("the worker's resolution")
			t.expect(rf.remoteSha(L3)).toBe(rf.localSha(L3))
			-- the second way: --abort puts the pushed layer on the tip it pushed
			rf.reset(L1)
			rf.mainMoves({ [rf.BETA] = "main beta\n" }, "main adds beta")
			t.expect(zn({ "restack", "R0010" }).code).toBe(3)
			left = rf.remoteSha(L1)
			git(ctx.wt, { "update-ref", `refs/heads/{L1}`, ctx.base[L1] })
			t.expect(zn({ "restack", "R0010", "--continue" }).code).toBe(1)
			t.expect(zn({ "restack", "R0010", "--abort" }).code).toBe(0)
			t.expect(rf.localSha(L1)).toBe(left)
		end
	)

	it(
		"--continue refuses a resolved layer the run did not push that is back at its old tip, though refs/zn/pushed is that tip",
		function()
			local ctx = rf.ctx()
			rf.reset(L1)
			rf.pushLayer(
				L1,
				{ [rf.SHARED] = "fix\n", ["pickman/src/poison2.luau"] = "p\n" },
				"fix layer 1, poison layer 2"
			)
			t.expect(zn({ "restack", "R0010" }).code).toBe(3)
			rf.resolve(rf.SHARED, "merged\n")
			t.expect(zn({ "restack", "R0010", "--continue" }).code).toBe(1) -- layer 2 red, its resolution kept unpushed
			local resolved = rf.localSha(L2)
			git(ctx.wt, { "update-ref", `refs/heads/{L2}`, ctx.base[L2] })
			local r = zn({ "restack", "R0010", "--continue" })
			t.expect(r.code).toBe(1)
			t.expect(has(say(r), resolved)).toBe(true)
			t.expect(has(say(r), ctx.base[L2])).toBe(true)
			t.expect(has(say(r), `git branch -f {L2} {resolved}`)).toBe(true)
			t.expect(rf.rebasing()).toBe(false) -- no rebase started
			t.expect(rf.localSha(L2)).toBe(ctx.base[L2])
		end
	)

	it(
		"a layer the worker rebased by hand during a stop, or fixed and finished, is the worker's change: --continue goes on with it",
		function()
			local ctx = rf.ctx()
			rf.reset(L1)
			rf.mainMoves({ ["pickman/src/poison2.luau"] = "p\n" }, "main adds poison2") -- layer 1 pushed, layer 2 red
			t.expect(zn({ "restack", "R0010" }).code).toBe(1)
			rf.mainMoves({ ["pickman/src/poison2.luau"] = "" }, "main drops poison2 again")
			git(ctx.wt, { "fetch", "-q", "origin" })
			git(ctx.wt, { "switch", "-q", L1 })
			git(ctx.wt, { "rebase", "-q", "origin/main" }) -- by hand, onto the newest main
			local hand = rf.localSha(L1)
			local r = zn({ "restack", "R0010", "--continue" })
			t.expect(r.code).toBe(0)
			t.expect(rf.remoteSha(L1)).toBe(hand)
			t.expect(git(ctx.wt, { "rev-parse", L2 .. "^" })).toBe(hand)
			t.expect(rf.remoteSha(L3)).toBe(rf.localSha(L3))
			-- the red-check route: a fix on the red tip, ./zn finish, then --continue
			rf.reset(L1)
			rf.mainMoves({ ["pickman/src/poison2.luau"] = "p\n" }, "main adds poison2")
			t.expect(zn({ "restack", "R0010" }).code).toBe(1)
			git(ctx.wt, { "switch", "-q", L2 })
			git(ctx.wt, { "rm", "-q", "pickman/src/poison2.luau" })
			git(ctx.wt, { "commit", "-qm", "R0010: fix layer 2" })
			t.expect(zn({ "finish", "c0020" }).code).toBe(0)
			local finished = rf.localSha(L2)
			git(ctx.wt, { "switch", "-q", L1 })
			local cont = zn({ "restack", "R0010", "--continue" })
			t.expect(cont.code).toBe(0)
			t.expect(rf.remoteSha(L2)).toBe(finished)
			t.expect(rf.remoteSha(L3)).toBe(rf.localSha(L3))
		end
	)

	it(
		"for a layer that is the branch checked out here, the command the refusal prints works as printed (code review 002, probe I)",
		function()
			local ctx = rf.ctx()
			rf.reset(L2) -- the run starts on layer 2 and goes back to it at the red stop
			rf.mainMoves({ ["pickman/src/poison2.luau"] = "p\n" }, "main adds poison2") -- layer 1 pushed, layer 2 red
			t.expect(zn({ "restack", "R0010" }).code).toBe(1)
			local redTip = rf.localSha(L2)
			t.expect(git(ctx.wt, { "branch", "--show-current" })).toBe(L2)
			git(ctx.wt, { "reset", "-q", "--hard", ctx.base[L2] }) -- by hand, on the checked-out layer
			local r = zn({ "restack", "R0010", "--continue" })
			t.expect(r.code).toBe(1)
			local printed = string.match(say(r), "to put it back on the tip the restack left: ([^\n]+)")
			t.expect(printed).toBe(`git switch --detach && git branch -f {L2} {redTip} && git switch {L2}`)
			-- run as printed, one git command at a time (a spec runs no shell string)
			for part in string.gmatch((printed :: string) .. " && ", "(.-) && ") do
				local words: { string } = {}
				for w in string.gmatch(part, "%S+") do
					table.insert(words, w)
				end
				t.expect(table.remove(words, 1)).toBe("git")
				t.expect(rf.try(ctx.wt, words).ok).toBe(true)
			end
			t.expect(rf.localSha(L2)).toBe(redTip)
			t.expect(git(ctx.wt, { "branch", "--show-current" })).toBe(L2)
			t.expect(git(ctx.wt, { "status", "--porcelain" })).toBe("")
			t.expect(zn({ "restack", "R0010", "--continue" }).code).toBe(1) -- red again, as before the hand reset
			t.expect(rf.localSha(L2)).toBe(redTip)
		end
	)
end)
