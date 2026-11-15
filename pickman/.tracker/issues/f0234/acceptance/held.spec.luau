--!strict
-- f0234 AC1: Hop.held, the eye held at the top of a hop while a run waits for play (the READY pause of a run, a life
-- or a level). With play starting at step `playAt`, the eye stands Hop.RISE above its standing height until half a
-- hop (Hop.TICKS / 2 steps) before it, then comes down the second half of an ordinary hop's arc (one of Hop.TICKS,
-- never the jumps boon's long hop), so it lands exactly at `playAt`, and is 0 from then on. A nil or non-finite
-- input holds nothing.
local Hop = require("@logic/Hop")
local t = require("@tests/lib/t")

local AT = 60 -- play starts at step 60, as a new session's does

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

return t.spec("f0234 the eye held at the top of a hop until play", function(it)
	it("is the top of a hop from long before play until half a hop before it", function()
		for _, left in { 59, 30, 7, Hop.TICKS / 2 + 1e-6, Hop.TICKS / 2 } do
			t.expect(Hop.held(AT, AT - left)).toBe(Hop.RISE)
		end
		t.expect(Hop.held(AT, -1000)).toBe(Hop.RISE)
	end)

	it("comes down the second half of an ordinary hop and lands at play", function()
		-- three steps before play is three quarters of the way through a hop of 12: 4 * 0.75 * 0.25 of the rise
		t.expect(Hop.TICKS).toBe(12)
		t.expect(near(Hop.held(AT, AT - 3), 0.75 * Hop.RISE)).toBe(true)
		for i = 1, 599 do
			local tt = AT - Hop.TICKS / 2 + i / 100
			t.expect(near(Hop.held(AT, tt), Hop.rise(AT - Hop.TICKS, tt))).toBe(true)
		end
		t.expect(Hop.held(AT, AT - 0.001) > 0).toBe(true)
		t.expect(Hop.held(AT, AT)).toBe(0)
	end)

	it("falls steadily, never rising again, and moves at most a hop's own step between frames", function()
		local last = Hop.held(AT, AT - 20)
		local steepest = 0
		for i = 1, 2000 do
			local tt = AT - 20 + i / 100
			local h = Hop.held(AT, tt)
			t.expect(h <= last).toBe(true)
			steepest = math.max(steepest, last - h)
			last = h
		end
		-- a hop's steepest hundredth of a step is at its landing: RISE * 4 / TICKS per step
		t.expect(steepest <= Hop.RISE * 4 / Hop.TICKS / 100 + 1e-9).toBe(true)
	end)

	it("is 0 from the step play starts on", function()
		for _, after in { 0, 0.5, 1, 12, 1000 } do
			t.expect(Hop.held(AT, AT + after)).toBe(0)
		end
	end)

	it("holds nothing with no pause, or with an input that is not a number", function()
		t.expect(Hop.held(nil, 5)).toBe(0)
		t.expect(Hop.held(0 / 0, 5)).toBe(0)
		t.expect(Hop.held(math.huge, 5)).toBe(0)
		t.expect(Hop.held(-math.huge, 5)).toBe(0)
		t.expect(Hop.held(AT, 0 / 0)).toBe(0)
		t.expect(Hop.held(AT, math.huge)).toBe(0)
		t.expect(Hop.held(AT, -math.huge)).toBe(0)
	end)
end)
