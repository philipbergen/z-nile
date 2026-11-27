--!strict
-- Narrowed by c0182: dropped the four cases that called the old half-split Touch.zone and swipe fold (replaced by
-- d0149's circles in d0149/acceptance/fold.spec and adapters.spec). Keeps Touch.toScreen and Touch.screenSize.
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

return t.spec("f0027 touch positions in screen pixels", function(it)
	it("subtracts the None area's top-left: a finger at screen (550, 320) reports (491, 262)", function()
		local x, y = toScreen(NONE, 491, 262)
		t.expect(x).toBe(550)
		t.expect(y).toBe(320)
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
end)
