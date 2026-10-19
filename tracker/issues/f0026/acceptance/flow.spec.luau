--!strict
-- f0026 AC2: game over gains a rank line without changing the overlay. The line follows the run.
-- The game-over bit is the banner both overlays already have. A rank for a run that has closed
-- does not appear on the next one.
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

	it("a late rank for a closed run is not shown on the next run", function()
		local idle = { over = 0 }
		local tooSoon = hearRank(idle, 2, 5)
		t.expect(tooSoon).toBe(idle)
		local early = hearRank(idle, 1, 3)
		t.expect(shownRank(early, false)).toBe(nil)
		t.expect(shownRank(early, true)).toBe(nil)
		local first = follow(early, true, false)
		t.expect(first.over).toBe(1)
		t.expect(shownRank(first, true)).toBe("ALL-TIME #3")
		local dismissed = follow(first, false, true)
		t.expect(shownRank(dismissed, false)).toBe(nil)
		local late = hearRank(dismissed, 1, 4)
		t.expect(shownRank(late, true)).toBe("ALL-TIME #4")
		local second = follow(late, true, false)
		t.expect(second.over).toBe(2)
		t.expect(shownRank(second, true)).toBe(nil)
		local live = hearRank(second, 2, 1)
		t.expect(shownRank(live, true)).toBe("ALL-TIME #1")
		local stale = hearRank(second, 1, 4)
		t.expect(stale).toBe(second)
		t.expect(shownRank(stale, true)).toBe(nil)
		t.expect(hearRank(live, 2, 0)).toBe(live)
	end)
end)
