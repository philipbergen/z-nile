--!strict
-- f0158 AC4: the ring's one warning colour (View.DANGER_COLOR, decided with the user 2026-10-26: "just a red or
-- something to indicate, not a color match") stands out against every wall colour it can sit over: WCAG contrast at
-- least 2.5 against the maze blue (33, 33, 222), f0109's edible green (14, 64, 14), the level-clear white flash and
-- f0126's marked-wall gold (255, 215, 0). It is a red (red channel high, green and blue low). Where View already
-- names a wall colour (f0109's View.wallColor), it must still be the number measured here.
-- Casts keep the spec type-legal on main before f0158 (Awareness.ring, RING, View.DANGER_COLOR) and f0109 (fake.module)
-- exist; a missing member fails at the call.
local View: any = require("@logic/View")
local t = require("@tests/lib/t")

type Rgb = { r: number, g: number, b: number }

local WALLS: { [string]: Rgb } = {
	blue = { r = 33, g = 33, b = 222 },
	edible = { r = 14, g = 64, b = 14 },
	flash = { r = 255, g = 255, b = 255 },
	gold = { r = 255, g = 215, b = 0 },
}

local function lin(c: number): number
	local v = c / 255
	return if v <= 0.04045 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
end
local function luminance(c: Rgb): number
	return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
end
local function contrast(a: Rgb, b: Rgb): number
	local la, lb = luminance(a), luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

return t.spec("f0158 the ring's warning colour", function(it)
	it("View.DANGER_COLOR is a red", function()
		local c = View.DANGER_COLOR
		t.expect(c.r >= 200 and c.g <= 90 and c.b <= 90).toBe(true)
	end)

	it("it has contrast at least 2.5 against every wall colour", function()
		for name, wall in WALLS do
			local k = contrast(View.DANGER_COLOR, wall)
			if k < 2.5 then
				error(`contrast against {name} is {k}`)
			end
		end
	end)

	it("the measured wall colours are View's, where View names them", function()
		local wallColor = (View :: any).wallColor
		if wallColor then
			local function same(a: any, b: Rgb): boolean
				return a.r == b.r and a.g == b.g and a.b == b.b
			end
			t.expect(same(wallColor(false, false), WALLS.blue)).toBe(true)
			t.expect(same(wallColor(false, true), WALLS.edible)).toBe(true)
			t.expect(same(wallColor(true, false), WALLS.flash)).toBe(true)
		end
	end)
end)
