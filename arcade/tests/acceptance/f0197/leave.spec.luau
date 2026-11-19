--!strict
-- f0197 AC5, copied from pickman's f0025 leave spec: a player who leaves is kept for the title's dying pause and then
-- dropped. GameOver during that window still submits. The window is each title's, passed to `leave` and `onStep`;
-- pickman's is the classic 45 (its dying ticks), `Hiscores.LEAVE_STEPS`, a number here: the library requires no game.
-- The last two cases are f0197's: a title's own window is honoured.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

return t.spec("f0025 disconnect window", function(it)
	it("the window is the classic dying pause", function()
		t.expect(Hiscores.LEAVE_STEPS).toBe(45)
		t.expect(Hiscores.leave(0, false, Hiscores.LEAVE_STEPS)).toBe("keep")
		t.expect(Hiscores.leave(44, false, Hiscores.LEAVE_STEPS)).toBe("keep")
		t.expect(Hiscores.leave(45, false, Hiscores.LEAVE_STEPS)).toBe("drop")
		t.expect(Hiscores.leave(0, true, Hiscores.LEAVE_STEPS)).toBe("drop")
	end)

	it("forty-four steps away is still in the server, and the next GameOver submits and drops", function()
		local state = Hiscores.newRun()
		for _ = 1, 44 do
			local nextState, sub = Hiscores.onStep(state, {}, false, Hiscores.LEAVE_STEPS)
			t.expect(sub).toBe(nil)
			t.expect(nextState.drop).toBe(false)
			state = nextState
		end
		t.expect(state.waited).toBe(44)
		local over, sub: any = Hiscores.onStep(
			state,
			{ { kind = "GameOver", score = 15, level = 3 } },
			false,
			Hiscores.LEAVE_STEPS
		)
		t.expect(sub ~= nil).toBe(true)
		t.expect(sub.score).toBe(15)
		t.expect(sub.level).toBe(3)
		t.expect(sub.run).toBe(1)
		t.expect(over.drop).toBe(true)
	end)

	it("the first step away counts, coming back clears it, and a scoreless GameOver drops", function()
		local away, sub = Hiscores.onStep(Hiscores.newRun(), {}, false, Hiscores.LEAVE_STEPS)
		t.expect(sub).toBe(nil)
		t.expect(away.waited).toBe(1)
		t.expect(away.drop).toBe(false)
		local back, backSub = Hiscores.onStep(away, {}, true, Hiscores.LEAVE_STEPS)
		t.expect(backSub).toBe(nil)
		t.expect(back.waited).toBe(0)
		t.expect(back.drop).toBe(false)
		local dropped, missing =
			Hiscores.onStep(Hiscores.newRun(), { { kind = "GameOver" } }, false, Hiscores.LEAVE_STEPS)
		t.expect(missing).toBe(nil)
		t.expect(dropped.drop).toBe(true)
		local quiet, ignored = Hiscores.onStep(
			Hiscores.newRun(),
			{ { kind = "gameover", score = 5, level = 1 } },
			false,
			Hiscores.LEAVE_STEPS
		)
		t.expect(ignored).toBe(nil)
		t.expect(quiet.drop).toBe(false)
		t.expect(quiet.waited).toBe(1)
	end)

	it("a closing server is held while a run or a drive is pending, and never past the close wait", function()
		t.expect(Hiscores.CLOSE_WAIT).toBe(25)
		t.expect(Hiscores.holdClose(0, 0, 0)).toBe(false)
		t.expect(Hiscores.holdClose(1, 0, 0)).toBe(true)
		t.expect(Hiscores.holdClose(0, 2, 0)).toBe(true)
		t.expect(Hiscores.holdClose(1, 1, 24.75)).toBe(true)
		t.expect(Hiscores.holdClose(1, 1, 25)).toBe(false)
		t.expect(Hiscores.holdClose(0, 1, 30)).toBe(false)
	end)

	it("AC5: leave honours the window it is given, not pickman's", function()
		t.expect(Hiscores.leave(44, false, 45)).toBe("keep")
		t.expect(Hiscores.leave(45, false, 45)).toBe("drop")
		t.expect(Hiscores.leave(9, false, 10)).toBe("keep")
		t.expect(Hiscores.leave(10, false, 10)).toBe("drop")
		t.expect(Hiscores.leave(0, true, 10)).toBe("drop")
		t.expect(Hiscores.leave(60, false, 90)).toBe("keep")
	end)

	it("AC5: onStep drops a departed run at the window it is given", function()
		local short = Hiscores.newRun()
		for _ = 1, 9 do
			short = Hiscores.onStep(short, {}, false, 10)
		end
		t.expect(short.drop).toBe(false)
		short = Hiscores.onStep(short, {}, false, 10)
		t.expect(short.waited).toBe(10)
		t.expect(short.drop).toBe(true)
		local long = Hiscores.newRun()
		for _ = 1, 60 do
			long = Hiscores.onStep(long, {}, false, 90)
		end
		t.expect(long.drop).toBe(false)
	end)
end)
