--!strict
-- Touch: cases beyond the acceptance specs.
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

return t.spec("Touch extras", function(it)
	it("turns an axis swipe and drops a diagonal", function()
		t.expect(Touch.swipe(-60, 0)).toBe("Left")
		t.expect(Touch.swipe(60, 60)).toBe(nil)
	end)

	it("splits the screen in half", function()
		t.expect(Touch.zone(100, 49, 0, nil)).toBe("turn")
		t.expect(Touch.zone(100, 50, 0, nil)).toBe("look")
	end)

	it("places the snap button left of the bar, on a wide and on a narrow safe width", function()
		local box = {
			textSize = 10,
			margin = 5,
			iconSize = 10,
			barWidth = 40,
			barHeight = 4,
			safeX = 0,
			safeY = 0,
			safeW = 400,
			safeH = 300,
		}
		t.expect(Touch.snapRect(box)).toEqual({ x = 306, y = 251, w = 44, h = 44 })
		box.safeW = 100
		t.expect(Touch.snapRect(box)).toEqual({ x = 6, y = 251, w = 44, h = 44 })
	end)

	it("a begin leaves Touch.empty() as it was", function()
		local empty = Touch.empty()
		local next = Touch.track(
			empty,
			{ id = 1, phase = "begin", x = 10, y = 10 },
			{ width = 100, snap = nil }
		)
		t.expect(next.fingers[1].zone).toBe("turn")
		t.expect(empty.fingers[1]).toBe(nil)
	end)
end)
