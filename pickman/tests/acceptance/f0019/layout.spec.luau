--!strict
-- f0180 AC2: Hud.layout sizes the HUD from the viewport in pixels so it stays readable on any screen:
-- whole-pixel sizes, text never under Hud.MIN_TEXT or over Hud.MAX_TEXT, the top band at most 15% of
-- the height, the power bar inside the width, and the same size in portrait as in landscape.
local Hud = require("@logic/Hud")
local t = require("@tests/lib/t")

local SCREENS = { { 1920, 1080 }, { 1280, 720 }, { 667, 375 }, { 375, 667 }, { 3840, 2160 }, { 800, 600 } }

local function whole(v: number): boolean
	return v == v and v == math.floor(v)
end

return t.spec("f0180 Hud.layout", function(it)
	it("the text limits are 14 and 40 pixels", function()
		t.expect(Hud.MIN_TEXT).toBe(14)
		t.expect(Hud.MAX_TEXT).toBe(40)
	end)

	it("every size is a whole number of pixels", function()
		for _, sc in SCREENS do
			local l = Hud.layout(sc[1], sc[2])
			for _, k in { "textSize", "margin", "iconSize", "barWidth", "barHeight" } do
				t.expect(whole((l :: any)[k])).toBe(true)
			end
		end
	end)

	it("text stays within the limits on any screen", function()
		for _, sc in { { 320, 240 }, { 100, 100 }, { 7680, 4320 }, table.unpack(SCREENS) } do
			local l = Hud.layout(sc[1], sc[2])
			t.expect(l.textSize >= Hud.MIN_TEXT and l.textSize <= Hud.MAX_TEXT).toBe(true)
		end
	end)

	it("a phone, a laptop and a desktop get growing text", function()
		local phone = Hud.layout(667, 375).textSize
		local laptop = Hud.layout(1280, 720).textSize
		local desktop = Hud.layout(1920, 1080).textSize
		t.expect(phone < laptop).toBe(true)
		t.expect(laptop < desktop or desktop == Hud.MAX_TEXT).toBe(true)
		t.expect(phone > Hud.MIN_TEXT).toBe(true)
	end)

	it("the top band (text plus a margin above and below) is at most 15% of the height", function()
		for _, sc in SCREENS do
			local l = Hud.layout(sc[1], sc[2])
			t.expect(l.textSize + 2 * l.margin <= 0.15 * sc[2]).toBe(true)
		end
	end)

	it("the power bar and its margins fit the width, and the bar is at least 4 pixels tall", function()
		for _, sc in SCREENS do
			local l = Hud.layout(sc[1], sc[2])
			t.expect(l.barWidth > 0 and l.barWidth + 2 * l.margin <= sc[1]).toBe(true)
			t.expect(l.barHeight >= 4).toBe(true)
		end
	end)

	it("life icons are at least as big as the minimum text", function()
		for _, sc in SCREENS do
			t.expect(Hud.layout(sc[1], sc[2]).iconSize >= Hud.MIN_TEXT).toBe(true)
		end
	end)

	it("portrait and landscape of one screen get the same text size", function()
		t.expect(Hud.layout(375, 667).textSize).toBe(Hud.layout(667, 375).textSize)
		t.expect(Hud.layout(1080, 1920).textSize).toBe(Hud.layout(1920, 1080).textSize)
	end)

	it("a zero, negative, NaN or infinite viewport side counts as 0: the minimum, not an error", function()
		for _, sc in
			{
				{ 0, 0 },
				{ -5, 100 },
				{ 0 / 0, 720 },
				{ 1280, 0 / 0 },
				{ math.huge, 720 },
				{ 1280, math.huge },
			}
		do
			local l = Hud.layout(sc[1], sc[2])
			t.expect(l.textSize).toBe(Hud.MIN_TEXT)
			t.expect(whole(l.margin) and whole(l.barWidth) and whole(l.barHeight)).toBe(true)
		end
	end)
end)
