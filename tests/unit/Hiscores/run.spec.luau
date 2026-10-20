--!strict
-- Hiscores run policy: rules the acceptance specs do not pin.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

return t.spec("Hiscores run policy extras", function(it)
	it("once refuses a fraction and a negative run, and leaves the table alone", function()
		local done = { [1] = true }
		local ok, same = Hiscores.once(done, 1.5)
		t.expect(ok).toBe(false)
		t.expect(same).toBe(done)
		local bad, unchanged = Hiscores.once(done, -1)
		t.expect(bad).toBe(false)
		t.expect(unchanged).toBe(done)
	end)

	it("a later scored GameOver in the same events is submitted when the first had no score", function()
		local _, sub: any = Hiscores.onStep(Hiscores.newRun(), {
			{ kind = "GameOver" },
			{ kind = "GameOver", score = 30, level = 2 },
		}, true)
		t.expect(sub.score).toBe(30)
	end)

	it("a player who stays keeps a zero wait and never drops", function()
		local state = Hiscores.newRun()
		for _ = 1, 100 do
			state = Hiscores.onStep(state, {}, true)
			t.expect(state.waited).toBe(0)
			t.expect(state.drop).toBe(false)
		end
	end)

	it("the 45th step away drops, and the play-again state keeps the wait", function()
		local state = Hiscores.newRun()
		for _ = 1, 45 do
			state = Hiscores.onStep(state, {}, false)
		end
		t.expect(state.drop).toBe(true)
		local again = Hiscores.onAgain(state, true)
		t.expect(again.waited).toBe(state.waited)
		t.expect(again.drop).toBe(false)
		t.expect(again.run).toBe(2)
	end)

	it("a closing server waits only while something is pending and the wait has not run out", function()
		t.expect(Hiscores.holdClose(0, 0, 100)).toBe(false)
		t.expect(Hiscores.holdClose(3, 0, 0)).toBe(true)
		t.expect(Hiscores.holdClose(0, 1, Hiscores.CLOSE_WAIT - 0.25)).toBe(true)
		t.expect(Hiscores.holdClose(0, 1, Hiscores.CLOSE_WAIT)).toBe(false)
	end)
end)
