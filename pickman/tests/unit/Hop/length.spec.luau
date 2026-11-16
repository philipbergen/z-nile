--!strict
-- Hop: a hop of a given length (f0126's long hop).
local Hop = require("@logic/Hop")
local t = require("@tests/lib/t")

return t.spec("Hop length", function(it)
	local function airborneSteps(ticks: number?): number
		local n = 0
		for k = 0, 40 do
			if Hop.airborne(0, k, ticks) then
				n += 1
			end
		end
		return n
	end

	it("a length that is not a whole number of at least 1 is the default hop", function()
		for _, bad in { 0, -3, 2.5, 0 / 0, math.huge } do
			t.expect(airborneSteps(bad)).toBe(airborneSteps(nil))
			t.expect(Hop.canStart(0, Hop.TICKS + Hop.COOLDOWN, bad)).toBe(true)
			t.expect(Hop.canStart(0, Hop.TICKS + Hop.COOLDOWN - 1, bad)).toBe(false)
		end
	end)

	it("the long hop is airborne 15 steps and waits its own length before the next", function()
		t.expect(airborneSteps(Hop.LONG_TICKS)).toBe(15)
		t.expect(Hop.canStart(0, Hop.LONG_TICKS + Hop.COOLDOWN - 1, Hop.LONG_TICKS)).toBe(false)
		t.expect(Hop.canStart(0, Hop.LONG_TICKS + Hop.COOLDOWN, Hop.LONG_TICKS)).toBe(true)
	end)

	it("the long hop rises to the same top as a hop", function()
		local top, longTop = 0, 0
		for k = 0, 40, 0.5 do
			top = math.max(top, Hop.rise(0, k))
			longTop = math.max(longTop, Hop.rise(0, k, Hop.LONG_TICKS))
		end
		t.expect(math.abs(top - longTop) < 0.05).toBe(true)
	end)
end)
