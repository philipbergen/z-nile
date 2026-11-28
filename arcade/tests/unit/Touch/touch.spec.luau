--!strict
-- Touch unit specs: button press/release, swipe, look, reset, and immutability.
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

return t.spec("Touch unit", function(it)
	it("tracks button press/release and releases on reset in ascending id order", function()
		local ctx: Touch.Context = {
			width = 400,
			buttons = {
				{ name = "left", rect = { x = 0, y = 200, w = 80, h = 80 } },
				{ name = "fire", rect = { x = 300, y = 200, w = 80, h = 80 } },
			},
			left = "swipe",
			right = "look",
		}
		local s = Touch.empty()
		local eff: { Touch.Effect }
		s, eff = Touch.track(s, { id = 5, phase = "begin", x = 320, y = 220 }, ctx)
		t.expect(#eff).toBe(1)
		t.expect(eff[1]).toEqual({ kind = "press", name = "fire" })

		s, eff = Touch.track(s, { id = 2, phase = "begin", x = 20, y = 220 }, ctx)
		t.expect(#eff).toBe(1)
		t.expect(eff[1]).toEqual({ kind = "press", name = "left" })

		local s2, rel = Touch.reset(s)
		t.expect((next(s2.fingers))).toBe(nil)
		t.expect(rel).toEqual({
			{ kind = "release", name = "left" },
			{ kind = "release", name = "fire" },
		})
	end)

	it("detects axis-aligned swipes and ignores short or off-cone drags", function()
		t.expect(Touch.swipe(60, 0)).toBe("right")
		t.expect(Touch.swipe(0, 60)).toBe("down")
		t.expect(Touch.swipe(20, 0)).toBe(nil)
		t.expect(Touch.swipe(50, 50)).toBe(nil)
	end)
end)
