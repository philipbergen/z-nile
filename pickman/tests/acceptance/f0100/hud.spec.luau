--!strict
-- f0100 AC4: what the player sees of the blaster. Hud.shotIcons puts one bar per shot after the lives, in the
-- lives row; View.beamEnd says where a shot's beam stops: the far edge of the last open tile before a wall, a door
-- or the house, never drawn across a wrapping row.
local Hud = require("@logic/Hud")
local Maze = require("@logic/Maze")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local DOOR = Maze.parse({ "#####", "#P  #", "#-  #", "#H  #", "#####" }, "door")

local function layout(icon: number, margin: number): Hud.Layout
	-- the shot bars sit in the HUD's own frame: the safe rectangle (R0012) does not move them
	return {
		textSize = icon,
		margin = margin,
		iconSize = icon,
		barWidth = 100,
		barHeight = 4,
		safeX = 0,
		safeY = 0,
		safeW = 1000,
		safeH = 1000,
	}
end

return t.spec("f0100 blaster on screen", function(it)
	it(
		"one bar per shot, after the last life and a margin, half an icon wide and half a margin apart",
		function()
			local l = layout(18, 9)
			t.expect(Hud.shotIcons(l, 3, 2)).toEqual({
				{ x = 81, y = 0, w = 9, h = 18 },
				{ x = 95, y = 0, w = 9, h = 18 },
			})
			t.expect(#Hud.shotIcons(l, 3, 3)).toBe(3)
			t.expect(Hud.shotIcons(l, 3, 3)[3]).toEqual({ x = 109, y = 0, w = 9, h = 18 })
		end
	)

	it("follows the lives: one more life moves the bars one icon and a margin along", function()
		local l = layout(40, 20)
		t.expect(Hud.shotIcons(l, 1, 1)).toEqual({ { x = 60, y = 0, w = 20, h = 40 } })
		t.expect(Hud.shotIcons(l, 2, 1)).toEqual({ { x = 120, y = 0, w = 20, h = 40 } })
		t.expect(Hud.shotIcons(l, 0, 1)).toEqual({ { x = 0, y = 0, w = 20, h = 40 } })
	end)

	it("no shots, no bars; a count that is not a whole number counts down to one", function()
		local l = layout(18, 9)
		t.expect(Hud.shotIcons(l, 3, 0)).toEqual({})
		t.expect(Hud.shotIcons(l, 3, -2)).toEqual({})
		t.expect(Hud.shotIcons(l, 3, 0 / 0)).toEqual({})
		t.expect(Hud.shotIcons(l, 3, math.huge)).toEqual({})
		t.expect(#Hud.shotIcons(l, 3, 2.7)).toBe(2)
		t.expect(Hud.shotIcons(l, 0 / 0, 1)).toEqual({ { x = 0, y = 0, w = 9, h = 18 } })
	end)

	it("half an icon and half a margin round half up", function()
		t.expect(Hud.shotIcons(layout(1, 1), 0, 2)).toEqual({
			{ x = 0, y = 0, w = 1, h = 1 },
			{ x = 2, y = 0, w = 1, h = 1 },
		})
	end)

	it("a beam ends at the far edge of the last open tile before the wall", function()
		t.expect({ View.beamEnd(classic, 6, 23, "E") }).toEqual({ 21.5, 23 })
		t.expect({ View.beamEnd(classic, 6, 23, "W") }).toEqual({ 5.5, 23 })
		t.expect({ View.beamEnd(classic, 6, 23, "N") }).toEqual({ 6, 0.5 })
		t.expect({ View.beamEnd(classic, 6, 23, "S") }).toEqual({ 6, 26.5 })
	end)

	it("starts from the player's continuous position, off the centre line's cross axis", function()
		-- between tiles 9 and 10 heading east: the beam keeps the player's y and ends at the same wall
		t.expect({ View.beamEnd(classic, 9.4, 23, "E") }).toEqual({ 21.5, 23 })
		t.expect({ View.beamEnd(classic, 6, 22.6, "N") }).toEqual({ 6, 0.5 })
	end)

	it("a door stops the beam before it", function()
		t.expect({ View.beamEnd(DOOR, 1, 1, "S") }).toEqual({ 1, 1.5 })
	end)

	it("a wrapping row ends the beam at the maze's edge", function()
		t.expect({ View.beamEnd(classic, 6, 14, "W") }).toEqual({ -0.5, 14 })
		t.expect({ View.beamEnd(classic, 21, 14, "E") }).toEqual({ 27.5, 14 })
	end)
end)
