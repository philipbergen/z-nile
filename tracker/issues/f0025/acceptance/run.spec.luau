--!strict
-- f0025 AC1: a run submits once, from the server's GameOver, using the adapter's run count.
-- A field on the event is not a run id. playAgain starts a new run that may submit again.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

return t.spec("f0025 one submit per run", function(it)
	it("once records the run on a copy and refuses the same run", function()
		local done = {}
		local ok, nextDone = Hiscores.once(done, 1)
		t.expect(ok).toBe(true)
		t.expect(done[1]).toBe(nil)
		t.expect(nextDone[1]).toBe(true)
		local again, same = Hiscores.once(nextDone, 1)
		t.expect(again).toBe(false)
		t.expect(same).toBe(nextDone)
		local bad, unchanged = Hiscores.once(nextDone, 0)
		t.expect(bad).toBe(false)
		t.expect(unchanged).toBe(nextDone)
	end)

	it("the submission uses the state run, never a run carried on the event", function()
		local state = Hiscores.newRun()
		t.expect(state.run).toBe(1)
		t.expect(state.drop).toBe(false)
		local nextState, sub: any =
			Hiscores.onStep(state, { { kind = "GameOver", score = 70, level = 2, run = 99 } }, true)
		t.expect(sub ~= nil).toBe(true)
		t.expect(sub.run).toBe(1)
		t.expect(sub.score).toBe(70)
		t.expect(sub.level).toBe(2)
		t.expect(state.done[1]).toBe(nil)
		t.expect(nextState.done[1]).toBe(true)
		t.expect(nextState.waited).toBe(0)
		local _, second = Hiscores.onStep(nextState, { { kind = "GameOver", score = 999, level = 9 } }, true)
		t.expect(second).toBe(nil)
	end)

	it("two GameOver events in one step submit the first only", function()
		local _, sub: any = Hiscores.onStep(Hiscores.newRun(), {
			{ kind = "GameOver", score = 10, level = 1 },
			{ kind = "GameOver", score = 99, level = 9 },
		}, true)
		t.expect(sub.score).toBe(10)
		t.expect(sub.level).toBe(1)
		t.expect(sub.run).toBe(1)
	end)

	it("a missing score or a different kind does not submit", function()
		local _, missing = Hiscores.onStep(Hiscores.newRun(), { { kind = "GameOver" } }, true)
		t.expect(missing).toBe(nil)
		local _, other =
			Hiscores.onStep(Hiscores.newRun(), { { kind = "Intent", score = 99999, level = 1 } }, true)
		t.expect(other).toBe(nil)
		local _, lower =
			Hiscores.onStep(Hiscores.newRun(), { { kind = "gameover", score = 5, level = 1 } }, true)
		t.expect(lower).toBe(nil)
	end)

	it("two fresh runs for one player both submit run 1: the dedupe dies with the run state", function()
		local first, a: any =
			Hiscores.onStep(Hiscores.newRun(), { { kind = "GameOver", score = 40, level = 1 } }, false)
		t.expect(a ~= nil).toBe(true)
		t.expect(a.run).toBe(1)
		t.expect(first.drop).toBe(true)
		local _, b: any =
			Hiscores.onStep(Hiscores.newRun(), { { kind = "GameOver", score = 90, level = 3 } }, true)
		t.expect(b ~= nil).toBe(true)
		t.expect(b.run).toBe(1)
		t.expect(b.score).toBe(90)
		t.expect(Hiscores.newRun() == Hiscores.newRun()).toBe(false)
	end)

	it("a successful play again is a new run, and a failed one is the same state", function()
		local done =
			Hiscores.onStep(Hiscores.newRun(), { { kind = "GameOver", score = 70, level = 2 } }, true)
		local moved = Hiscores.onAgain(done, true)
		t.expect(moved.run).toBe(2)
		t.expect(moved == done).toBe(false)
		local afterThird, third: any =
			Hiscores.onStep(moved, { { kind = "GameOver", score = 5, level = 1 } }, true)
		t.expect(third ~= nil).toBe(true)
		t.expect(third.run).toBe(2)
		t.expect(third.score).toBe(5)
		local stayed = Hiscores.onAgain(afterThird, false)
		t.expect(stayed.run).toBe(2)
		t.expect(stayed).toBe(afterThird)
		local _, repeatOver = Hiscores.onStep(stayed, { { kind = "GameOver", score = 8, level = 1 } }, true)
		t.expect(repeatOver).toBe(nil)
	end)
end)
