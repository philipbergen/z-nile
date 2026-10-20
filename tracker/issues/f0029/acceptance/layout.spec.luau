--!strict
-- f0029 AC1: Hud.layout gains an optional inset. Zero insets match today's numbers.
-- A direct third argument is a type error until the parameter exists, so the call is cast.
local Hud = require("@logic/Hud")
local t = require("@tests/lib/t")

local function laidOut(width: number, height: number, inset: any?): any
	return (Hud.layout :: any)(width, height, inset)
end

local function five(row: any): { number }
	return { row.textSize, row.margin, row.iconSize, row.barWidth, row.barHeight }
end

type Pinned = { width: number, height: number, five: { number } }
local PINNED: { Pinned } = {
	{ width = 1920, height = 1080, five = { 40, 20, 40, 400, 16 } },
	{ width = 1280, height = 720, five = { 32, 16, 32, 320, 13 } },
	{ width = 390, height = 844, five = { 18, 9, 18, 98, 7 } },
	{ width = 844, height = 390, five = { 18, 9, 18, 211, 7 } },
	{ width = 667, height = 375, five = { 17, 9, 17, 167, 7 } },
	{ width = 0, height = 0, five = { 14, 7, 14, 0, 6 } },
}

return t.spec("f0029 insets", function(it)
	it("two arguments still return today's numbers", function()
		for _, sc in PINNED do
			t.expect(five(Hud.layout(sc.width, sc.height))).toEqual(sc.five)
		end
		t.expect(Hud.layout(3840, 2160).barWidth).toBe(400)
	end)

	it("an all-zero inset matches the two-argument layout and reports the full viewport", function()
		local zeros = { top = 0, bottom = 0, left = 0, right = 0 }
		for _, sc in { { 1920, 1080 }, { 1280, 720 }, { 390, 844 }, { 844, 390 } } do
			local plain = Hud.layout(sc[1], sc[2])
			local with = laidOut(sc[1], sc[2], zeros)
			t.expect(five(with)).toEqual(five(plain))
			t.expect(with.safeX).toBe(0)
			t.expect(with.safeY).toBe(0)
			t.expect(with.safeW).toBe(sc[1])
			t.expect(with.safeH).toBe(sc[2])
		end
	end)

	it("a top inset moves the safe origin without changing the text or the bar", function()
		local plain = Hud.layout(390, 844)
		local phone = laidOut(390, 844, { top = 47, bottom = 0, left = 0, right = 0 })
		t.expect(five(phone)).toEqual(five(plain))
		t.expect(phone.textSize).toBe(18)
		t.expect(phone.safeX).toBe(0)
		t.expect(phone.safeY).toBe(47)
		t.expect(phone.safeW).toBe(390)
		t.expect(phone.safeH).toBe(797)
		t.expect(phone.textSize >= Hud.MIN_TEXT).toBe(true)
	end)

	it("a left inset shrinks the bar to the safe width and does not shrink the text", function()
		local plain = Hud.layout(844, 390)
		local land = laidOut(844, 390, { top = 0, bottom = 0, left = 47, right = 0 })
		t.expect(plain.barWidth).toBe(211)
		t.expect(land.barWidth).toBe(199)
		t.expect(land.textSize).toBe(plain.textSize)
		t.expect(land.safeX).toBe(47)
		t.expect(land.safeY).toBe(0)
		t.expect(land.safeW).toBe(797)
		t.expect(land.safeH).toBe(390)
	end)

	it("text follows the full viewport, not the safe area", function()
		local plain = Hud.layout(2000, 400)
		local inset = laidOut(2000, 400, { top = 300, bottom = 0, left = 0, right = 0 })
		t.expect(inset.textSize).toBe(plain.textSize)
		t.expect(inset.textSize).toBe(18)
		t.expect(inset.safeY).toBe(300)
		t.expect(inset.safeH).toBe(100)
	end)

	it("a negative, NaN or infinite inset component counts as 0, and a finite one applies", function()
		local messy = laidOut(1280, 0 / 0, { top = 0 / 0, bottom = -3, left = math.huge, right = 4 })
		t.expect(messy.textSize).toBe(Hud.MIN_TEXT)
		t.expect(messy.safeX).toBe(0)
		t.expect(messy.safeY).toBe(0)
		t.expect(messy.safeW).toBe(1276)
		t.expect(messy.safeH).toBe(0)
		t.expect(messy.barWidth).toBe(319)
		local ignored = laidOut(844, 390, { top = -10, bottom = 0 / 0, left = -1, right = math.huge })
		t.expect(five(ignored)).toEqual(five(Hud.layout(844, 390)))
		t.expect(ignored.safeX).toBe(0)
		t.expect(ignored.safeW).toBe(844)
	end)

	it("a zero, negative, NaN or infinite viewport side still counts as 0", function()
		for _, sc in { { 0, 0 }, { -5, 100 }, { 0 / 0, 720 }, { 1280, 0 / 0 }, { math.huge, 720 } } do
			local row = laidOut(sc[1], sc[2], nil)
			t.expect(row.textSize).toBe(Hud.MIN_TEXT)
			t.expect(row.textSize >= Hud.MIN_TEXT).toBe(true)
			t.expect(row.margin == math.floor(row.margin)).toBe(true)
			t.expect(row.barWidth == math.floor(row.barWidth)).toBe(true)
		end
		local negative = laidOut(-5, 100, nil)
		t.expect(negative.safeW).toBe(0)
		t.expect(negative.safeH).toBe(100)
		t.expect(negative.textSize).toBe(14)
	end)

	it("safeInset reads the device cutout from the None area against the core area", function()
		local safeInset = (Hud :: any).safeInset
		local none = { Min = { X = -59, Y = -58 }, Max = { X = 792, Y = 334 } }
		local core = { Min = { X = 0, Y = 0 }, Max = { X = 733, Y = 313 } }
		t.expect(safeInset(none, core)).toEqual({ left = 59, top = 58, right = 59, bottom = 21 })
		t.expect(safeInset(core, core)).toEqual({ left = 0, top = 0, right = 0, bottom = 0 })
	end)
end)
