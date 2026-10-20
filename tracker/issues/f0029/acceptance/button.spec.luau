--!strict
-- f0029 AC2: the snap button is at least 44 px and misses the HUD blocks and the forward view.
local Hud = require("@logic/Hud")
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

local function boxOf(width: number, height: number, inset: any?): any
	local row = (Hud.layout :: any)(width, height, inset)
	return {
		textSize = row.textSize,
		margin = row.margin,
		iconSize = row.iconSize,
		barWidth = row.barWidth,
		barHeight = row.barHeight,
		safeX = row.safeX,
		safeY = row.safeY,
		safeW = row.safeW,
		safeH = row.safeH,
	}
end

local function overlaps(
	a: { x: number, y: number, w: number, h: number },
	b: { x: number, y: number, w: number, h: number }
): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function forward(box: any): { x: number, y: number, w: number, h: number }
	local top = box.safeY + box.textSize + 2 * box.margin
	local reach = math.max(box.iconSize, box.barHeight, Touch.MIN_TARGET)
	local bottom = box.safeY + box.safeH - box.margin - reach
	return { x = box.safeX, y = top, w = box.safeW, h = bottom - top }
end

type Sample = {
	width: number,
	height: number,
	inset: any,
	button: { x: number, y: number, w: number, h: number },
}
local SAMPLES: { Sample } = {
	{
		width = 390,
		height = 844,
		inset = { top = 47, bottom = 0, left = 0, right = 0 },
		button = { x = 230, y = 791, w = 44, h = 44 },
	},
	{
		width = 844,
		height = 390,
		inset = { top = 0, bottom = 0, left = 47, right = 0 },
		button = { x = 583, y = 337, w = 44, h = 44 },
	},
	{
		width = 1920,
		height = 1080,
		inset = nil,
		button = { x = 1436, y = 1016, w = 44, h = 44 },
	},
}

return t.spec("f0029 snap button", function(it)
	it("the minimum touch target is 44 px", function()
		t.expect(Touch.MIN_TARGET).toBe(44)
	end)

	it(
		"sample buttons sit left of the power bar, each side 44, and a point in one is the snap zone",
		function()
			for _, sample in SAMPLES do
				local box = boxOf(sample.width, sample.height, sample.inset)
				local button = Touch.snapRect(box)
				t.expect(button).toEqual(sample.button)
				t.expect(button.w >= 44 and button.h >= 44).toBe(true)
				local blocks = Touch.blocks(box)
				for _, name in { "score", "level", "lives", "power" } do
					t.expect(overlaps(button, blocks[name])).toBe(false)
				end
				local view = forward(box)
				t.expect(view.h > 0).toBe(true)
				t.expect(overlaps(button, view)).toBe(false)
				for _, name in { "score", "level", "lives", "power" } do
					t.expect(overlaps(blocks[name], view)).toBe(false)
				end
			end
			local phone = SAMPLES[1].button
			t.expect(Touch.zone(390, phone.x + 1, phone.y + 1, phone)).toBe("snap")
			t.expect(Touch.zone(390, phone.x + 1, phone.y + 1, nil)).toBe("look")
		end
	)

	it("pins the HUD blocks on the notched phone and the wide desktop", function()
		local phone = Touch.blocks(boxOf(390, 844, { top = 47, bottom = 0, left = 0, right = 0 }))
		t.expect(phone.score).toEqual({ x = 9, y = 56, w = 177, h = 18 })
		t.expect(phone.level).toEqual({ x = 204, y = 56, w = 177, h = 18 })
		t.expect(phone.lives).toEqual({ x = 9, y = 817, w = 186, h = 18 })
		t.expect(phone.power).toEqual({ x = 283, y = 828, w = 98, h = 7 })
		local desk = Touch.blocks(boxOf(1920, 1080, nil))
		t.expect(desk.score).toEqual({ x = 20, y = 20, w = 920, h = 40 })
		t.expect(desk.level).toEqual({ x = 980, y = 20, w = 920, h = 40 })
		t.expect(desk.lives).toEqual({ x = 20, y = 1020, w = 940, h = 40 })
		t.expect(desk.power).toEqual({ x = 1500, y = 1044, w = 400, h = 16 })
	end)

	it("the side is the larger of 44 and the icon, never the icon alone when the icon is smaller", function()
		local small = Touch.snapRect({
			textSize = 10,
			margin = 5,
			iconSize = 10,
			barWidth = 40,
			barHeight = 4,
			safeX = 0,
			safeY = 0,
			safeW = 400,
			safeH = 300,
		})
		t.expect(small).toEqual({ x = 306, y = 251, w = 44, h = 44 })
		local grown = Touch.snapRect({
			textSize = 80,
			margin = 10,
			iconSize = 80,
			barWidth = 40,
			barHeight = 8,
			safeX = 10,
			safeY = 20,
			safeW = 500,
			safeH = 400,
		})
		t.expect(grown).toEqual({ x = 370, y = 330, w = 80, h = 80 })
	end)

	it("a narrow safe width stays in the bottom band and overlaps lives", function()
		local box = {
			textSize = 10,
			margin = 5,
			iconSize = 10,
			barWidth = 40,
			barHeight = 4,
			safeX = 0,
			safeY = 0,
			safeW = 100,
			safeH = 300,
		}
		local button = Touch.snapRect(box)
		t.expect(button).toEqual({ x = 6, y = 251, w = 44, h = 44 })
		t.expect(overlaps(button, Touch.blocks(box).lives)).toBe(true)
		local reach = math.max(box.iconSize, box.barHeight, Touch.MIN_TARGET)
		local top = box.safeY + box.textSize + 2 * box.margin
		local bottom = box.safeY + box.safeH - box.margin - reach
		local view = { x = box.safeX, y = top, w = box.safeW, h = bottom - top }
		t.expect(overlaps(button, view)).toBe(false)
	end)
end)
