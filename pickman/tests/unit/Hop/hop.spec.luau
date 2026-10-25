--!strict
local Hop = require("@logic/Hop")
local t = require("@tests/lib/t")

return t.spec("Hop", function(it)
	it("knows its intent", function()
		t.expect(Hop.isIntent("Hop")).toBe(true)
		t.expect(Hop.isIntent("Jump")).toBe(false)
		t.expect(Hop.isIntent(nil)).toBe(false)
	end)

	it("lands back on the ground and waits the cool-down", function()
		t.expect(Hop.rise(0, Hop.TICKS)).toBe(0)
		t.expect(Hop.canStart(0, Hop.TICKS + Hop.COOLDOWN - 1)).toBe(false)
		t.expect(Hop.canStart(0, Hop.TICKS + Hop.COOLDOWN)).toBe(true)
	end)

	it("is airborne only above the clearance", function()
		t.expect(Hop.airborne(0, Hop.TICKS / 2)).toBe(true)
		t.expect(Hop.airborne(0, 1)).toBe(false)
	end)
end)
