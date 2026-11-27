--!strict
-- Narrowed by c0182: dropped the swipe, drag-look and snap-button cases (replaced by d0149's circles in
-- d0149/acceptance/fold.spec and adapters.spec). Keeps the desktop and notched-phone HUD layout case.
-- f0029 AC4 / R0012 RC1: one synthetic phone session across the three issues.
local Hud = require("@logic/Hud")
local t = require("@tests/lib/t")

local function laidOut(width: number, height: number, inset: any?): any
	return (Hud.layout :: any)(width, height, inset)
end

return t.spec("f0029 phone session", function(it)
	it(
		"1920x1080 with no inset is still today's HUD, and a notched phone moves only the safe rect",
		function()
			local desk = laidOut(1920, 1080, { top = 0, bottom = 0, left = 0, right = 0 })
			t.expect({ desk.textSize, desk.margin, desk.iconSize, desk.barWidth, desk.barHeight }).toEqual({
				40,
				20,
				40,
				400,
				16,
			})
			t.expect(desk.safeX).toBe(0)
			t.expect(desk.safeY).toBe(0)
			local phone = laidOut(390, 844, { top = 47, bottom = 0, left = 0, right = 0 })
			t.expect(phone.textSize).toBe(18)
			t.expect(phone.safeY).toBe(47)
			t.expect(phone.textSize >= Hud.MIN_TEXT).toBe(true)
			local land = laidOut(844, 390, { top = 0, bottom = 0, left = 47, right = 0 })
			t.expect(land.barWidth).toBe(199)
			t.expect(Hud.layout(844, 390).barWidth).toBe(211)
		end
	)
end)
