--!strict
-- f0130 AC2: world scale and heading conventions: tile (x, y) maps to world X/Z, and a heading's
-- yaw looks along that heading's Maze.delta.
local Maze = require("@logic/Maze")
local View = require("@logic/View")
local t = require("@tests/lib/t")

return t.spec("f0130 world and heading", function(it)
	it("has a sensible world scale", function()
		local s = View.SCALE
		t.expect(s.tileStuds > 0).toBe(true)
		t.expect(s.eyeHeight > 0 and s.eyeHeight < s.wallHeight).toBe(true)
		t.expect(s.fieldOfView >= 1 and s.fieldOfView <= 120).toBe(true)
	end)

	it("maps tile coordinates to world X and Z in studs, tile centres on whole tiles", function()
		local st = View.SCALE.tileStuds
		t.expect({ View.world(0, 0) }).toEqual({ 0, 0 })
		t.expect({ View.world(3, 5) }).toEqual({ 3 * st, 5 * st })
		t.expect({ View.world(-0.5, 27.25) }).toEqual({ -0.5 * st, 27.25 * st })
	end)

	it("a heading's yaw looks along its delta: +x is world +X, +y is world +Z", function()
		-- A Roblox CFrame.Angles(0, yaw, 0) looks along (-sin yaw, 0, -cos yaw).
		local all: { Maze.Heading } = { "N", "E", "S", "W" }
		for _, h: Maze.Heading in all do
			local yaw = View.headingYaw(h)
			local dx, dy = Maze.delta(h)
			t.expect(-math.sin(yaw)).toBeNear(dx, 1e-9)
			t.expect(-math.cos(yaw)).toBeNear(dy, 1e-9)
			t.expect(yaw > -math.pi and yaw <= math.pi).toBe(true)
		end
	end)
end)
