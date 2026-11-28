--!strict
-- Pad unit specs: hysteresis, horizontal fold, look rate, and tune validation.
local Pad = require("@logic/Pad")
local t = require("@tests/lib/t")

return t.spec("Pad unit", function(it)
	it("steers with hysteresis in both and horizontal modes", function()
		local s = Pad.steerStart()
		local d: Pad.Dir?
		s, d = Pad.steer(s, 0.5, 0)
		t.expect(d).toBe(nil)
		t.expect(s.held).toBe(nil)

		s, d = Pad.steer(s, 0.7, 0)
		t.expect(d).toBe("right")
		t.expect(s.held).toBe("right")

		local hTune = Pad.tune({ axes = "horizontal" })
		local hs = Pad.steerStart()
		hs, d = Pad.steer(hs, -0.7, 0.9, hTune)
		t.expect(d).toBe("left")
		t.expect(hs.held).toBe("left")
	end)

	it("computes squared look rates and tracks active gamepad", function()
		local dyaw, dpitch = Pad.look(1, 0, 0.5)
		t.expect(dyaw).toBeNear(-1.5, 1e-6)
		t.expect(dpitch).toBeNear(0, 1e-6)
		t.expect(Pad.track("Gamepad1", "Gamepad2", 0.4)).toBe("Gamepad2")
		t.expect(Pad.track("Gamepad1", "Gamepad2", 0.39)).toBe("Gamepad1")
	end)

	it("refuses invalid tunings", function()
		t.expect(function()
			Pad.tune({ off = 0.6, on = 0.6 })
		end).toThrow("Pad.tune")
	end)
end)
