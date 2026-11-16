--!strict
-- Blaster: a shot granted outright (f0126's blaster boon).
local Blaster = require("@logic/Blaster")
local t = require("@tests/lib/t")

return t.spec("Blaster gain", function(it)
	it("gains one shot up to the most held, then gains nothing", function()
		local b = Blaster.new(1)
		for n = 1, Blaster.MAX_SHOTS do
			t.expect(Blaster.gain(b)).toBe(true)
			t.expect(b.shots).toBe(n)
		end
		t.expect(Blaster.gain(b)).toBe(false)
		t.expect(b.shots).toBe(Blaster.MAX_SHOTS)
	end)
end)
