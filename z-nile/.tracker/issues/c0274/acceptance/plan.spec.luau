--!strict
-- c0274: the takeover's pure rules (z-nile/engine/heartbeat.luau): the atomic plan that swaps the heartbeat branches,
-- the verdict a takeover needs, the refusal that names why a claim is not taken over, whose claim a stamp is, and the
-- text an old owner is told. No I/O, no clock.
local heartbeat = require("@znile/engine/heartbeat")
local t = require("@tests/lib/t")

local A = "preparing-quiet-copper-falcon"
local B = "active-brisk-amber-otter"
local C = "preparing-lucky-violet-heron"
local NOW = 1800000000

local function beat(stamp: string, epoch: number)
	return { stamp = stamp, epoch = epoch, ref = heartbeat.branch(stamp), sha = `sha-{stamp}-{epoch}` }
end

return t.spec("c0274 takeover rules", function(it)
	it(
		"a takeover creates the taker's branch and deletes the old owner's with a lease, in one plan",
		function()
			local plan = heartbeat.takeoverPlan(A, C, NOW, { beat(A, NOW - 2000), beat(B, NOW - 5) })
			t.expect(plan.write)
				.toEqual({ ref = heartbeat.branch(C), subject = heartbeat.subject(C, NOW), lease = "" })
			-- only the old owner's branch goes, with the sha it was read at as its lease
			t.expect(plan.delete).toEqual({ { ref = heartbeat.branch(A), lease = `sha-{A}-{NOW - 2000}` } })
			-- an old owner that never beat has no branch to delete
			t.expect(heartbeat.takeoverPlan(A, C, NOW, {}).delete).toEqual({})
			t.expect(heartbeat.takeoverPlan(A, C, NOW, { beat(B, NOW) }).delete).toEqual({})
		end
	)

	it("a takeover needs an explicit lost verdict judged for the stamp origin still holds", function()
		t.expect(heartbeat.canTakeOver("lost", A, A)).toBe(true)
		t.expect(heartbeat.canTakeOver("lost", A, C)).toBe(false) -- restamped since the verdict
		for _, kind in { "live", "stale", "parked", "nobeat", "unknown" } do
			t.expect(heartbeat.canTakeOver(kind, A, A)).toBe(false)
		end
	end)

	it("the refusal names why: alive, parked, never beaten, or no verdict", function()
		t.expect(heartbeat.takeoverRefusal("c0010", "live", 125, nil))
			.toBe("claim alive: last heartbeat 2m ago, limit 15m")
		t.expect(heartbeat.takeoverRefusal("c0010", "parked", 5000, nil))
			.toBe("claim parked (an open pull request or a dispatcher waiting on questions.md names it)")
		t.expect(heartbeat.takeoverRefusal("c0050", "nobeat", 5000, nil))
			.toBe("c0050 has never beaten: not lost, no takeover")
		-- stale (the pull requests could not be read) and an item with no verdict at all say why it is unknown
		t.expect(heartbeat.takeoverRefusal("c0010", "stale", 5000, "pull requests unreadable: boom"))
			.toBe("no heartbeat verdict: pull requests unreadable: boom")
		t.expect(heartbeat.takeoverRefusal("c0010", "unknown", 0, nil))
			.toBe("no heartbeat verdict: the claim was made after it was judged, or origin/main could not be read")
	end)

	it("whose claim a stamp is: held, unheld, taken over or ended", function()
		t.expect(heartbeat.holds(A, A)).toBe("held")
		t.expect(heartbeat.holds(A, C)).toBe("taken")
		t.expect(heartbeat.holds(A, nil)).toBe("ended")
		t.expect(heartbeat.holds("", A)).toBe("unheld")
		t.expect(heartbeat.holds(nil, A)).toBe("unheld")
		t.expect(heartbeat.holds("", nil)).toBe("unheld")
	end)

	it("the old owner is told its claim was taken over (naming the stamp now) or ended", function()
		t.expect(heartbeat.lostText("c0010", C)).toBe(`c0010's claim was taken over (now {C})`)
		t.expect(heartbeat.lostText("c0010", nil)).toBe("c0010's claim ended")
	end)

	it("stop records the verdict it read, and only a live or parked stop lets a worktree re-adopt", function()
		t.expect(heartbeat.stopNote(B, "live", 5)).toBe(`(claim {B})`)
		t.expect(heartbeat.stopNote(B, "parked", 5000)).toBe(`(claim {B})`)
		t.expect(heartbeat.stopNote(B, "lost", 2130)).toBe(`(claim {B}, lost 35m)`)
		for _, kind in { "stale", "nobeat", "unknown" } do
			t.expect(heartbeat.stopNote(B, kind, 99)).toBe(`(claim {B}, unjudged)`)
		end
		local live = `tracker: stop R0010 Title (claim {B})`
		t.expect(heartbeat.stopAllowsReadopt(live, B)).toBe(true)
		t.expect(heartbeat.stopAllowsReadopt(`tracker: stop R0010 Title (claim {B}, lost 35m)`, B))
			.toBe(false)
		t.expect(heartbeat.stopAllowsReadopt(`tracker: stop R0010 Title (claim {B}, unjudged)`, B))
			.toBe(false)
		t.expect(heartbeat.stopAllowsReadopt(live, "active-other-other-other")).toBe(false)
		t.expect(heartbeat.stopAllowsReadopt(`tracker: R0010 prepared (claim {B})`, B)).toBe(false) -- not a stop
		t.expect(heartbeat.stopAllowsReadopt("", B)).toBe(false) -- no stop commit at all
	end)
end)
