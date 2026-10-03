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
end)
