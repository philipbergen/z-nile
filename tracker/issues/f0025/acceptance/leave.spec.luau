--!strict
-- f0025 AC2: a player who leaves is kept for the classic dying pause and then dropped.
-- GameOver during that window still submits. The pause length is the classic 45, copied as a
-- number so Hiscores does not require Game.
local Game = require("@logic/Game")
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

return t.spec("f0025 disconnect window", function(it)
	it("the window is the classic dying pause", function()
		t.expect(Hiscores.LEAVE_STEPS).toBe(45)
		t.expect(Hiscores.LEAVE_STEPS).toBe(Game.CLASSIC_CONFIG.dyingTicks)
		t.expect(Hiscores.leave(0, false)).toBe("keep")
		t.expect(Hiscores.leave(44, false)).toBe("keep")
		t.expect(Hiscores.leave(45, false)).toBe("drop")
		t.expect(Hiscores.leave(0, true)).toBe("drop")
	end)

	it("forty-four steps away is still in the server, and the next GameOver submits and drops", function()
		local state = Hiscores.newRun()
		for _ = 1, 44 do
			local nextState, sub = Hiscores.onStep(state, {}, false)
			t.expect(sub).toBe(nil)
			t.expect(nextState.drop).toBe(false)
			state = nextState
		end
		t.expect(state.waited).toBe(44)
		local over, sub = Hiscores.onStep(state, { { kind = "GameOver", score = 15, level = 3 } }, false)
		t.expect(sub ~= nil).toBe(true)
		t.expect(sub.score).toBe(15)
		t.expect(sub.level).toBe(3)
		t.expect(sub.run).toBe(1)
		t.expect(over.drop).toBe(true)
	end)

	it("the first step away counts, coming back clears it, and a scoreless GameOver drops", function()
		local away, sub = Hiscores.onStep(Hiscores.newRun(), {}, false)
		t.expect(sub).toBe(nil)
		t.expect(away.waited).toBe(1)
		t.expect(away.drop).toBe(false)
		local back, backSub = Hiscores.onStep(away, {}, true)
		t.expect(backSub).toBe(nil)
		t.expect(back.waited).toBe(0)
		t.expect(back.drop).toBe(false)
		local dropped, missing = Hiscores.onStep(Hiscores.newRun(), { { kind = "GameOver" } }, false)
		t.expect(missing).toBe(nil)
		t.expect(dropped.drop).toBe(true)
		local quiet, ignored =
			Hiscores.onStep(Hiscores.newRun(), { { kind = "gameover", score = 5, level = 1 } }, false)
		t.expect(ignored).toBe(nil)
		t.expect(quiet.drop).toBe(false)
		t.expect(quiet.waited).toBe(1)
	end)
end)
