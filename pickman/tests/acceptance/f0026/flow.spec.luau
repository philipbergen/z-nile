--!strict
-- f0026 AC2: game over gains a rank line without changing the overlay. The line follows the run.
-- The game-over bit is the banner both overlays already have, and hearRank takes it too: a rank for a run
-- whose overlay has closed is not kept, and the edge into the next overlay shows only that run's rank.
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
local t = require("@tests/lib/t")

local rankLine = (Flow :: any).rankLine
local follow = (Flow :: any).follow
local hearRank = (Flow :: any).hearRank
local shownRank = (Flow :: any).shownRank

return t.spec("f0026 rank line", function(it)
	it("the game-over detail stays the score and level", function()
		local play: any =
			{ phase = "gameover", level = 4, score = 1200, lives = 0, timer = 0, frightened = 0 }
		local overlay = Flow.overlay(play, Game.CLASSIC_CONFIG)
		t.expect(overlay.banner).toBe("GAME OVER")
		t.expect(overlay.detail).toBe("SCORE 1200   LEVEL 4")
	end)

	it("a whole rank of 1 or more is a line, and Flow does not cap it", function()
		t.expect(rankLine(1)).toBe("ALL-TIME #1")
		t.expect(rankLine(11)).toBe("ALL-TIME #11")
		t.expect(rankLine(0)).toBe(nil)
		t.expect(rankLine(1.5)).toBe(nil)
		t.expect(rankLine(nil)).toBe(nil)
	end)

	it("the run count moves only on the edge into game over", function()
		local view = { over = 0 }
		local entered, was = follow(view, true, false)
		t.expect(entered.over).toBe(1)
		t.expect(was).toBe(true)
		local stayed, still = follow(entered, true, true)
		t.expect(stayed.over).toBe(1)
		t.expect(still).toBe(true)
		t.expect(stayed).toBe(entered)
		local left, now = follow(stayed, false, true)
		t.expect(now).toBe(false)
		t.expect(left.over).toBe(1)
		t.expect(shownRank(left, false)).toBe(nil)
		t.expect(shownRank(left, true)).toBe(nil)
	end)

	it("an early rank waits for its overlay, and a late rank for a closed run is not kept", function()
		local idle = { over = 0 }
		local tooSoon = hearRank(idle, 2, 5, false)
		t.expect(tooSoon).toBe(idle)
		local early = hearRank(idle, 1, 3, false)
		t.expect(shownRank(early, false)).toBe(nil)
		t.expect(shownRank(early, true)).toBe(nil)
		local first = follow(early, true, false)
		t.expect(first.over).toBe(1)
		t.expect(shownRank(first, true)).toBe("ALL-TIME #3")
		t.expect(first.pending).toBe(nil)
		t.expect(first.pendingRun).toBe(nil)
		local dismissed = follow(first, false, true)
		t.expect(shownRank(dismissed, false)).toBe(nil)
		t.expect(shownRank(dismissed, true)).toBe(nil)
		-- the packet for run 1 arrives after its overlay closed: the overlay bit is false, so nothing is kept
		local late = hearRank(dismissed, 1, 4, false)
		t.expect(late).toBe(dismissed)
		local second = follow(late, true, false)
		t.expect(second.over).toBe(2)
		t.expect(shownRank(second, true)).toBe(nil)
		local stale = hearRank(second, 1, 4, true)
		t.expect(stale).toBe(second)
		t.expect(hearRank(second, 4, 4, true)).toBe(second)
	end)

	it("a rank heard while its overlay is up shows, and a rejected rank changes nothing", function()
		local up = follow({ over = 1 }, true, false)
		t.expect(up.over).toBe(2)
		local live = hearRank(up, 2, 1, true)
		t.expect(shownRank(live, true)).toBe("ALL-TIME #1")
		t.expect(shownRank(live, false)).toBe(nil)
		t.expect(hearRank(live, 2, 0, true)).toBe(live)
		t.expect(hearRank(live, 2, nil, true)).toBe(live)
		t.expect(hearRank({ over = 0 }, 0, 2, true).rank).toBe(nil)
	end)

	it("the next run's rank wins even when the closed run's packet arrives after it", function()
		-- run 1's write retried with backoff; run 2's rank is sent first, then run 1's, then run 2's overlay opens
		local closed = follow(follow({ over = 0 }, true, false), false, true)
		t.expect(closed.over).toBe(1)
		local upcoming = hearRank(closed, 2, 9, false)
		t.expect(upcoming.pending).toBe(9)
		t.expect(upcoming.pendingRun).toBe(2)
		t.expect(shownRank(upcoming, false)).toBe(nil)
		local older = hearRank(upcoming, 1, 4, false)
		t.expect(older).toBe(upcoming)
		local opened = follow(older, true, false)
		t.expect(opened.over).toBe(2)
		t.expect(shownRank(opened, true)).toBe("ALL-TIME #9")
		t.expect(opened.pending).toBe(nil)
	end)

	it(
		"the edge into game over sets the rank from the pending slot or to nothing, never keeps the old one",
		function()
			local matched = follow({ over = 1, rank = 4, pending = 9, pendingRun = 2 }, true, false)
			t.expect(matched.over).toBe(2)
			t.expect(matched.rank).toBe(9)
			t.expect(matched.pending).toBe(nil)
			t.expect(matched.pendingRun).toBe(nil)
			local unmatched = follow({ over = 1, rank = 4, pending = 9, pendingRun = 3 }, true, false)
			t.expect(unmatched.over).toBe(2)
			t.expect(unmatched.rank).toBe(nil)
			t.expect(unmatched.pending).toBe(nil)
			t.expect(unmatched.pendingRun).toBe(nil)
			local closing = follow({ over = 2, rank = 9, pending = 5, pendingRun = 3 }, false, true)
			t.expect(closing.rank).toBe(nil)
			t.expect(closing.pending).toBe(5)
			t.expect(closing.pendingRun).toBe(3)
		end
	)
end)
