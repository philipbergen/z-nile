--!strict
-- Touch: the PICK button (f0126).
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

return t.spec("Touch pick", function(it)
	local box: Touch.Box = {
		textSize = 10,
		margin = 5,
		iconSize = 10,
		barWidth = 40,
		barHeight = 4,
		safeX = 0,
		safeY = 0,
		safeW = 800,
		safeH = 400,
	}

	it("PICK is FIRE's size, one margin left of it, level with it", function()
		local fire, pick = Touch.fireRect(box), Touch.pickRect(box)
		t.expect(pick.w).toBe(fire.w)
		t.expect(pick.h).toBe(fire.h)
		t.expect(pick.y).toBe(fire.y)
		t.expect(pick.x + pick.w + box.margin).toBe(fire.x)
	end)

	it("a point on PICK is the pick zone, and without it the half of the screen", function()
		local pick = Touch.pickRect(box)
		local x, y = pick.x + 1, pick.y + 1
		t.expect(Touch.zone(800, x, y, nil, nil, nil, pick)).toBe("pick")
		t.expect(Touch.zone(800, x, y, nil, nil, nil, nil)).toBe(if x < 400 then "turn" else "look")
	end)
end)
