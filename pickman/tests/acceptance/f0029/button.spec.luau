--!strict
-- Narrowed by c0182: dropped the three Touch.snapRect cases (d0149 removes the snap button; d0149/acceptance/fold.spec
-- and clear.spec own the circles' minimum target and clearance). Keeps Touch.MIN_TARGET and Touch.blocks.
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

return t.spec("f0029 snap button", function(it)
	it("the minimum touch target is 44 px", function()
		t.expect(Touch.MIN_TARGET).toBe(44)
	end)

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
end)
