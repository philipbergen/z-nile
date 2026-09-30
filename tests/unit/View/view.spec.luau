--!strict
-- View constants and small behaviours the acceptance specs don't pin.
local Maze = require("@logic/Maze")
local View = require("@logic/View")
local t = require("@tests/lib/t")

return t.spec("View extras", function(it)
	it("has the designed scale", function()
		t.expect(View.SCALE).toEqual({ tileStuds = 8, wallHeight = 10, eyeHeight = 4, fieldOfView = 80 })
		t.expect(View.TURN_SECONDS).toBe(0.12)
		t.expect(View.MOUSE_RADIANS_PER_PIXEL).toBe(0.004)
		t.expect(View.MAX_PITCH).toBeNear(math.rad(80), 1e-12)
	end)

	it("walls on a vertical-only tunnel repeat rows, not columns", function()
		local shaft = Maze.parse({ "#.#", "#P#", "#.#" })
		local rects = View.walls(shaft, 1)
		local rows = {}
		for _, r in rects do
			rows[r.y0] = r
			t.expect(r.x0 >= 0 and r.x1 <= 2).toBe(true)
		end
		t.expect(rows[-1] ~= nil and rows[3] ~= nil).toBe(true)
	end)

	it("approachYaw with maxDelta 0 stays put", function()
		t.expect(View.approachYaw(1, 2, 0)).toBeNear(1, 1e-12)
	end)

	it("the key map is frozen", function()
		t.expect(function()
			(View.KEYS :: any).Q = "Back"
		end).toThrow()
	end)
end)
