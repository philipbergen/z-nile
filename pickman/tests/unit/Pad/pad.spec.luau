--!strict
local Pad = require("@logic/Pad")
local t = require("@tests/lib/t")

return t.spec("Pad", function(it)
	it("a push of the left stick turns once", function()
		local s, turn = Pad.steer(Pad.steerStart(), -1, 0)
		t.expect(turn).toBe("Left")
		s, turn = Pad.steer(s, -1, 0)
		t.expect(turn).toBe(nil)
	end)

	it("a resting right stick does not look", function()
		local dx, dy = Pad.look(0.05, -0.05, 0.016)
		t.expect(dx).toBe(0)
		t.expect(dy).toBe(0)
	end)
end)
