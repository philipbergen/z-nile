--!strict
-- f0027 AC5: touch positions are converted to screen pixels before the fold sees them. InputObject.Position has
-- the GUI inset applied (Roblox: "the inset applied to GUI elements (such as from the top bar) is accounted for in
-- the position"), and GetInsetArea's rects are relative to that same core-UI origin, while every rect the HUD
-- hands Touch (the snap button) and the viewport width are screen pixels (ScreenInsets.None). Touch.toScreen(none,
-- x, y) subtracts GetInsetArea(None).Min. Device: Roblox's documented phone, a 851 x 392 screen whose None area
-- is (-59, -58)-(792, 334) against the core area (0, 0)-(733, 313); HudView's snap button there is
-- { x = 547, y = 318, w = 44, h = 44 } (f0029's layout of that inset).
-- The screen's size comes from the same area: Touch.screenSize(none, fallbackW, fallbackH) is none.Max - none.Min,
-- or the fallback (the camera's ViewportSize) while the area is empty or bad. ViewportSize itself is the device
-- safe area (Roblox: "not equal to the fullscreen area size on displays with cutouts or notches"), 733 x 371 here.
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

-- Added by this issue. The cast keeps the spec type-legal before it exists.
local toScreen = (Touch :: any).toScreen
local screenSize = (Touch :: any).screenSize

local NONE = { Min = { X = -59, Y = -58 }, Max = { X = 792, Y = 334 } }
local WIDTH = 851
local BUTTON = { x = 547, y = 318, w = 44, h = 44 }

return t.spec("f0027 touch positions in screen pixels", function(it)
	it("subtracts the None area's top-left: a finger at screen (550, 320) reports (491, 262)", function()
		local x, y = toScreen(NONE, 491, 262)
		t.expect(x).toBe(550)
		t.expect(y).toBe(320)
	end)

	it("a converted tap on the drawn button is snap; the raw position is not", function()
		local x, y = toScreen(NONE, 491, 262)
		t.expect(Touch.zone(WIDTH, x, y, BUTTON)).toBe("snap")
		t.expect(Touch.zone(WIDTH, 491, 262, BUTTON)).toBe("look")
		-- the button's far corner, converted, is still inside; one pixel further is not
		local fx, fy = toScreen(NONE, 547 + 43 - 59, 318 + 43 - 58)
		t.expect(Touch.zone(WIDTH, fx, fy, BUTTON)).toBe("snap")
		local ox, oy = toScreen(NONE, 547 + 44 - 59, 318 + 20 - 58)
		t.expect(Touch.zone(WIDTH, ox, oy, BUTTON)).toBe("look")
	end)

	it("the half split is on the screen's middle: a finger at screen x 430 looks, at 420 turns", function()
		local lx, ly = toScreen(NONE, 430 - 59, 100 - 58)
		t.expect(Touch.zone(WIDTH, lx, ly, nil)).toBe("look")
		t.expect(Touch.zone(WIDTH, 430 - 59, 100 - 58, nil)).toBe("turn")
		local rx, ry = toScreen(NONE, 420 - 59, 100 - 58)
		t.expect(Touch.zone(WIDTH, rx, ry, nil)).toBe("turn")
	end)

	it("an area with a zero origin, or none at all, leaves the point as it is", function()
		local zero = { Min = { X = 0, Y = 0 }, Max = { X = 733, Y = 313 } }
		local x, y = toScreen(zero, 12, 34)
		t.expect(x).toBe(12)
		t.expect(y).toBe(34)
		local nx, ny = toScreen(nil, 12, 34)
		t.expect(nx).toBe(12)
		t.expect(ny).toBe(34)
	end)

	it("a non-finite origin component counts as 0 on that axis only", function()
		local bad = { Min = { X = 0 / 0, Y = -58 }, Max = { X = 792, Y = 334 } }
		local x, y = toScreen(bad, 12, 34)
		t.expect(x).toBe(12)
		t.expect(y).toBe(92)
		local inf = { Min = { X = -59, Y = -math.huge }, Max = { X = 792, Y = 334 } }
		local ix, iy = toScreen(inf, 12, 34)
		t.expect(ix).toBe(71)
		t.expect(iy).toBe(34)
	end)

	it(
		"the screen size is the None area's size; the device-safe ViewportSize is only the fallback",
		function()
			local w, h = screenSize(NONE, 733, 371)
			t.expect(w).toBe(851)
			t.expect(h).toBe(392)
			local ew, eh = screenSize({ Min = { X = 0, Y = 0 }, Max = { X = 0, Y = 0 } }, 733, 371)
			t.expect(ew).toBe(733)
			t.expect(eh).toBe(371)
			local nw, nh = screenSize(nil, 733, 371)
			t.expect(nw).toBe(733)
			t.expect(nh).toBe(371)
			local bad = { Min = { X = 0 / 0, Y = -58 }, Max = { X = 792, Y = 334 } }
			local bw, bh = screenSize(bad, 733, 371)
			t.expect(bw).toBe(733)
			t.expect(bh).toBe(371)
			local flat = { Min = { X = -59, Y = -58 }, Max = { X = 792, Y = -58 } }
			local fw, fh = screenSize(flat, 733, 371)
			t.expect(fw).toBe(733)
			t.expect(fh).toBe(371)
		end
	)

	it(
		"the half split uses the screen width: screen x 400 turns at 851 and would look at ViewportSize's 733",
		function()
			local w = screenSize(NONE, 733, 371)
			local x, y = toScreen(NONE, 400 - 59, 100 - 58)
			t.expect(x).toBe(400)
			t.expect(Touch.zone(w, x, y, nil)).toBe("turn")
			t.expect(Touch.zone(733, x, y, nil)).toBe("look")
		end
	)

	it("a turn swipe is the same converted or not (only differences count)", function()
		local state = Touch.empty()
		local ctx = { width = WIDTH, snap = nil }
		local x0, y0 = toScreen(NONE, 100, 200)
		local x1, y1 = toScreen(NONE, 20, 200)
		local s1 = Touch.track(state, { id = 1, phase = "begin", x = x0, y = y0 }, ctx)
		local _, effects = Touch.track(s1, { id = 1, phase = "end", x = x1, y = y1 }, ctx)
		t.expect(effects).toEqual({ { kind = "turn", intent = "Left" } })
	end)
end)
