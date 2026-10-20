--!strict
-- f0102 AC2: which glows light. With the inView option, Awareness.indicators also lists the ghosts inside the field
-- of view (each says whether it is), so a ghost straight ahead behind a wall glows too; without it nothing changes
-- (f0033). Awareness.glows lights one place per sector that has a ghost, in sector order: the nearest ghost along
-- the maze in that sector gives its look, size, brightness and index (its colour); a tie goes to the earlier ghost.
-- Eyes never glow, and neither does a ghost beyond maxDistance.
local Awareness = require("@logic/Awareness")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local PI = math.pi
local HALF_PI = PI / 2
local ASPECT = 16 / 9
local ALL = { inView = true }

local function ghost(x: number, y: number, look: string?): Awareness.Ghost
	return { x = x, y = y, look = (look or "normal") :: any }
end

local function pose(x: number, y: number, yaw: number?): Awareness.Pose
	return { x = x, y = y, yaw = yaw or 0 }
end

local function indicator(index: number, bearing: number, distance: number, look: string?): Awareness.Indicator
	local closeness = 1 - distance / 12
	return {
		index = index,
		bearing = bearing,
		distance = distance,
		size = 0.25 + 0.75 * closeness,
		brightness = 0.3 + 0.7 * closeness,
		look = (look or "normal") :: any,
		inView = false,
	}
end

local function sectors(glows: { Awareness.Glow }): string
	local out = {}
	for _, g in glows do
		table.insert(out, tostring(g.sector))
	end
	return table.concat(out, " ")
end

return t.spec("f0102 glows", function(it)
	it("with inView, a ghost ahead in view is listed and says so; one behind says it is not", function()
		local p = pose(10, 23, HALF_PI) -- in the bottom corridor, looking west
		local list = Awareness.indicators(classic, p, { ghost(7, 23), ghost(13, 23) }, ALL)
		t.expect(#list).toBe(2)
		t.expect(list[1].index).toBe(1) -- both 3 tiles away: the tie keeps the input order
		local byIndex: { [number]: Awareness.Indicator } = {}
		for _, ind in list do
			byIndex[ind.index] = ind
		end
		t.expect(byIndex[1].inView).toBe(true)
		t.expect(byIndex[2].inView).toBe(false)
		t.expect(byIndex[1].bearing).toBeNear(0, 1e-9)
		t.expect(byIndex[1].distance).toBe(3)
	end)

	it(
		"without the option nothing changes: a ghost in view gets no indicator, one out of view says so",
		function()
			local p = pose(10, 23, HALF_PI)
			t.expect(#Awareness.indicators(classic, p, { ghost(7, 23) })).toBe(0)
			t.expect(#Awareness.indicators(classic, p, { ghost(7, 23) }, { inView = false })).toBe(0)
			local behind = Awareness.indicators(classic, p, { ghost(13, 23) })
			t.expect(#behind).toBe(1)
			t.expect(behind[1].inView).toBe(false)
		end
	)

	it("the field of view still decides which are in view, with the camera's numbers", function()
		local ghosts = { ghost(7, 23) }
		local inside = Awareness.indicators(classic, pose(10, 23, HALF_PI + math.rad(54)), ghosts, ALL)
		local outside = Awareness.indicators(classic, pose(10, 23, HALF_PI + math.rad(60)), ghosts, ALL)
		t.expect(inside[1].inView).toBe(true)
		t.expect(outside[1].inView).toBe(false)
		local narrow = Awareness.indicators(classic, pose(10, 23, HALF_PI + math.rad(54)), ghosts, {
			inView = true,
			aspect = 1,
		})
		t.expect(narrow[1].inView).toBe(false)
	end)

	it("eyes never glow, and a ghost too far along the maze does not either", function()
		local p = pose(10, 23, HALF_PI)
		t.expect(#Awareness.indicators(classic, p, { ghost(7, 23, "eyes") }, ALL)).toBe(0)
		local q = pose(6, 6, 0)
		t.expect(#Awareness.indicators(classic, q, { ghost(9, 6) }, { inView = true, maxDistance = 4 }))
			.toBe(0)
	end)

	it("one glow per sector with a ghost, in sector order", function()
		local list = {
			indicator(1, PI, 2),
			indicator(2, 0, 5),
			indicator(3, -HALF_PI, 7),
			indicator(4, math.rad(40), 9),
		}
		t.expect(sectors(Awareness.glows(list, ASPECT))).toBe("0 1 4 6")
		t.expect(#Awareness.glows({}, ASPECT)).toBe(0)
	end)

	it("the nearest ghost in a sector lights it: its look, size, brightness and index", function()
		local far = indicator(1, math.rad(10), 9, "normal")
		local near = indicator(2, math.rad(-12), 3, "frightened")
		local glows = Awareness.glows({ far, near }, ASPECT)
		t.expect(#glows).toBe(1)
		local g = glows[1]
		t.expect(g.sector).toBe(0)
		t.expect(g.index).toBe(2)
		t.expect(g.look).toBe("frightened")
		t.expect(g.distance).toBe(3)
		t.expect(g.size).toBe(near.size)
		t.expect(g.brightness).toBe(near.brightness)
		-- the order of the list does not matter
		t.expect(Awareness.glows({ near, far }, ASPECT)[1].index).toBe(2)
	end)

	it("a tie in distance goes to the earlier ghost, whatever order the list is in", function()
		local a = indicator(3, math.rad(80), 4, "normal")
		local b = indicator(1, math.rad(100), 4, "blinking")
		t.expect(Awareness.glows({ a, b }, ASPECT)[1].index).toBe(1)
		t.expect(Awareness.glows({ b, a }, ASPECT)[1].index).toBe(1)
	end)

	it("each glow carries its sector's bearing for the screen's aspect", function()
		local glows =
			Awareness.glows({ indicator(1, math.rad(50), 2), indicator(2, math.rad(-170), 3) }, ASPECT)
		t.expect(glows[1].sector).toBe(1)
		t.expect(glows[1].bearing).toBeNear(Awareness.sectorBearing(1, ASPECT), 1e-12)
		t.expect(glows[2].sector).toBe(4)
		t.expect(glows[2].bearing).toBeNear(PI, 1e-12)
		local square = Awareness.glows({ indicator(1, math.rad(50), 2) }, 1)
		t.expect(square[1].bearing).toBeNear(PI / 4, 1e-12)
	end)

	it("end to end: four ghosts around a player light the places they are in", function()
		-- at 6,5 looking north up the x = 6 corridor: one ahead, one behind, one left and one right along row 5
		local p = pose(6, 5, 0)
		local list =
			Awareness.indicators(classic, p, { ghost(6, 2), ghost(6, 8), ghost(3, 5), ghost(9, 5) }, ALL)
		t.expect(#list).toBe(4)
		local glows = Awareness.glows(list, ASPECT)
		t.expect(sectors(glows)).toBe("0 2 4 6")
		local at: { [number]: number } = {}
		for _, g in glows do
			at[g.sector] = g.index
		end
		t.expect(at[0]).toBe(1)
		t.expect(at[4]).toBe(2)
		t.expect(at[2]).toBe(3)
		t.expect(at[6]).toBe(4)
	end)

	it("each glow carries its nearest ghost's name and flash, so its colour needs no lookup", function()
		-- only inky (third) and clyde (fourth) are close: the glows' places in the output are 1 and 2, not 3 and 4
		local p = pose(6, 5, 0)
		local ghosts: { Awareness.Ghost } = {
			{ x = 20, y = 29, look = "normal", name = "blinky", flash = false },
			{ x = 21, y = 29, look = "normal", name = "pinky", flash = false },
			{ x = 6, y = 2, look = "blinking", name = "inky", flash = true },
			{ x = 6, y = 8, look = "normal", name = "clyde", flash = false },
		}
		local list = Awareness.indicators(classic, p, ghosts, ALL)
		t.expect(#list).toBe(2)
		local glows = Awareness.glows(list, ASPECT)
		t.expect(sectors(glows)).toBe("0 4")
		t.expect(glows[1].name).toBe("inky")
		t.expect(glows[1].flash).toBe(true)
		t.expect(glows[1].index).toBe(3)
		t.expect(glows[2].name).toBe("clyde")
		t.expect(glows[2].flash).toBe(false)
		-- a ghost given without them has none
		local bare = Awareness.glows(Awareness.indicators(classic, p, { ghost(6, 2) }, ALL), ASPECT)
		t.expect(bare[1].name).toBe(nil)
	end)
end)
