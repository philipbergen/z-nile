--!strict
-- f0120 AC5: the server clock turns frame times into whole ticks at 30 Hz, independent of frame rate.
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local function total(clock: Session.Clock, dts: { number }): number
	local n = 0
	for _, dt in dts do
		local steps = Session.advance(clock, dt)
		t.expect(steps >= 0 and steps == math.floor(steps)).toBe(true)
		n += steps
	end
	return n
end

local function frames(dt: number, count: number): { number }
	local out = {}
	for i = 1, count do
		out[i] = dt
	end
	return out
end

return t.spec("f0120 server clock", function(it)
	it("defaults to 30 Hz and at most 5 steps per frame", function()
		local c = Session.newClock()
		t.expect(c.rate).toBe(30)
		t.expect(c.maxSteps).toBe(5)
	end)

	it("gives 30 ticks per second at 60, 30, 50 and 144 frames per second", function()
		t.expect(total(Session.newClock(), frames(1 / 60, 60))).toBe(30)
		t.expect(total(Session.newClock(), frames(1 / 30, 90))).toBe(90)
		t.expect(total(Session.newClock(), frames(1 / 50, 100))).toBe(60)
		t.expect(total(Session.newClock(), frames(1 / 144, 144 * 10))).toBe(300)
	end)

	it("gives 30 ticks per second over uneven frames", function()
		local dts = {}
		local sum = 0
		for i = 1, 300 do
			local dt = 0.004 + (i % 7) * 0.003
			dts[i] = dt
			sum += dt
		end
		local n = total(Session.newClock(), dts)
		t.expect(math.abs(n - sum * 30) <= 1).toBe(true)
	end)

	it("caps a long frame at maxSteps and drops the backlog", function()
		local c = Session.newClock()
		t.expect(Session.advance(c, 1.0)).toBe(5)
		t.expect(Session.advance(c, 0)).toBe(0)
		t.expect(Session.advance(c, 1 / 30)).toBe(1)
	end)

	it("ignores zero, negative and NaN frame times", function()
		local c = Session.newClock()
		t.expect(Session.advance(c, 0)).toBe(0)
		t.expect(Session.advance(c, -1)).toBe(0)
		t.expect(Session.advance(c, 0 / 0)).toBe(0)
		t.expect(Session.advance(c, 1 / 30)).toBe(1)
	end)

	it("honours a custom rate and cap", function()
		local c = Session.newClock(10, 2)
		t.expect(Session.advance(c, 0.25)).toBe(2) -- 0.05 s carried over
		t.expect(Session.advance(c, 0.04)).toBe(0)
		t.expect(Session.advance(c, 0.01)).toBe(1)
	end)
end)
