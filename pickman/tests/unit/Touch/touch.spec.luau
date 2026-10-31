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

	-- f0110: the fire and hop buttons, on one synthetic layout (the hop rectangle is Hud's jump row; its exact
	-- place is buttons.spec's, so these cases check the formulas relative to it)
	local function layoutBox(w: number, h: number): Touch.Box
		return {
			textSize = 10,
			margin = 5,
			iconSize = 10,
			barWidth = 40,
			barHeight = 4,
			safeX = 0,
			safeY = 0,
			safeW = w,
			safeH = h,
		}
	end

	it("the fire button is the hop button's size, one margin to its left", function()
		for _, size in { { 400, 300 }, { 844, 390 }, { 390, 844 } } do
			local box = layoutBox(size[1], size[2])
			local hop, fire = Touch.hopRect(box), Touch.fireRect(box)
			t.expect(fire.w).toBe(hop.w)
			t.expect(fire.h).toBe(hop.w)
			t.expect(fire.x).toBe(hop.x - box.margin - hop.w)
		end
	end)

	it(
		"the fire button is level with the hop button where it clears the snap control, raised where it does not",
		function()
			-- a wide screen: room beside the snap control, so FIRE sits level with JUMP
			local wide = layoutBox(1920, 1080)
			t.expect(Touch.fireRect(wide).y).toBe(Touch.hopRect(wide).y)
			-- a small screen: level would reach the snap control's band, so FIRE rises above it, one margin clear
			local small = layoutBox(400, 300)
			local fire, hop, snap = Touch.fireRect(small), Touch.hopRect(small), Touch.snapRect(small)
			t.expect(fire.y < hop.y).toBe(true)
			t.expect(fire.y + fire.h).toBe(snap.y - small.margin)
		end
	)

	it("Touch.buttons is the snap, fire and hop rectangles, as fresh tables", function()
		local box = layoutBox(844, 390)
		local b = Touch.buttons(box)
		t.expect(b.snap).toEqual(Touch.snapRect(box))
		t.expect(b.fire).toEqual(Touch.fireRect(box))
		t.expect(b.hop).toEqual(Touch.hopRect(box))
		b.hop.x = -1
		t.expect(Touch.hopRect(box).x ~= -1).toBe(true)
	end)

	it("Touch.zone checks snap, then fire, then hop, then the halves", function()
		local r = { x = 10, y = 10, w = 20, h = 20 }
		t.expect(Touch.zone(100, 15, 15, r, r, r)).toBe("snap")
		t.expect(Touch.zone(100, 15, 15, nil, r, r)).toBe("fire")
		t.expect(Touch.zone(100, 15, 15, nil, nil, r)).toBe("hop")
		t.expect(Touch.zone(100, 15, 15, nil, nil, nil)).toBe("turn")
		t.expect(Touch.zone(100, 30, 15, nil, r, nil)).toBe("turn") -- half-open: x + w is outside
	end)
end)
