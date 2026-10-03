--!strict
-- Awareness: API cases beyond the acceptance specs.
local Awareness = require("@logic/Awareness")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

return t.spec("Awareness extras", function(it)
	it("a point straight ahead has bearing 0", function()
		t.expect(Awareness.bearing({ x = 5, y = 5, yaw = 0 }, 5, 3)).toBeNear(0, 1e-9)
	end)

	it("no ghosts give no indicators and no blips", function()
		local pose = { x = 6, y = 5, yaw = 0 }
		t.expect(#Awareness.indicators(classic, pose, {})).toBe(0)
		t.expect(#Awareness.radar(classic, pose, {}).blips).toBe(0)
	end)

	it("the radar's default radius is the documented one", function()
		t.expect(Awareness.radar(classic, { x = 6, y = 5, yaw = 0 }, {}).radius).toBe(Awareness.RADAR_RADIUS)
	end)

	it("size and brightness follow the distance along the maze, not the straight line", function()
		-- the player at (12,1) faces south; the ghost at (15,1) is 3 tiles away in a straight line but behind the
		-- top-middle wall: 11 tiles by the corridors
		local pose = { x = 12, y = 1, yaw = math.pi }
		local walled = Awareness.indicators(classic, pose, { { x = 15, y = 1, look = "normal" } })
		t.expect(#walled).toBe(1)
		t.expect(walled[1].distance).toBe(11)
		local d = Awareness.DEFAULTS
		local closeness = 1 - 11 / d.maxDistance
		t.expect(walled[1].size).toBeNear(d.minSize + (d.maxSize - d.minSize) * closeness, 1e-9)
		t.expect(walled[1].brightness).toBeNear(d.minBrightness + (1 - d.minBrightness) * closeness, 1e-9)
		-- the same 3 tiles in an open corridor are 3 tiles: a much bigger, brighter arrow
		local open = Awareness.indicators(
			classic,
			{ x = 12, y = 5, yaw = math.pi },
			{ { x = 15, y = 5, look = "normal" } }
		)
		t.expect(open[1].distance).toBe(3)
		t.expect(open[1].size > walled[1].size).toBe(true)
	end)
end)
