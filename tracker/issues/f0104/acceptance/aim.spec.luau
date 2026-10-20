--!strict
-- f0104 AC3: where a shot goes. View.aim turns the held arrows' direction (or, with none held, the look's yaw) into
-- the nearest of the four headings, relative to the way the player is heading. Pitch never matters. Exactly half way
-- (up and left, down and right, or a look at exactly 45 degrees) goes ahead or behind, the way of travel.
local Maze = require("@logic/Maze")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local PI = math.pi
local NONE: View.Arrows = { up = false, down = false, left = false, right = false }
local HEADINGS: { Maze.Heading } = { "N", "E", "S", "W" }

local function arrows(keys: string): View.Arrows
	return {
		up = string.find(keys, "U", 1, true) ~= nil,
		down = string.find(keys, "D", 1, true) ~= nil,
		left = string.find(keys, "L", 1, true) ~= nil,
		right = string.find(keys, "R", 1, true) ~= nil,
	}
end

local function looking(yaw: number, pitch: number?): View.Steer
	return { look = { yaw = yaw, pitch = pitch or 0 }, spring = false }
end

return t.spec("f0104 aim", function(it)
	it("the arrows aim ahead, left, right and behind of the heading", function()
		for _, h: Maze.Heading in HEADINGS do
			t.expect(View.aim(h, looking(0), arrows("U"))).toBe(h)
			t.expect(View.aim(h, looking(0), arrows("L"))).toBe(Maze.left(h))
			t.expect(View.aim(h, looking(0), arrows("R"))).toBe(Maze.right(h))
			t.expect(View.aim(h, looking(0), arrows("D"))).toBe(Maze.opposite(h))
		end
		t.expect(View.aim("W", looking(0), arrows("L"))).toBe("S")
		t.expect(View.aim("N", looking(0), arrows("R"))).toBe("E")
	end)

	it("two arrows together aim ahead or behind: the way of travel wins the tie", function()
		for _, h: Maze.Heading in HEADINGS do
			t.expect(View.aim(h, looking(0), arrows("UL"))).toBe(h)
			t.expect(View.aim(h, looking(0), arrows("UR"))).toBe(h)
			t.expect(View.aim(h, looking(0), arrows("DL"))).toBe(Maze.opposite(h))
			t.expect(View.aim(h, looking(0), arrows("DR"))).toBe(Maze.opposite(h))
		end
	end)

	it("held arrows win over the look, even while the look is still turning to them", function()
		t.expect(View.aim("N", looking(0.2), arrows("L"))).toBe("W")
		t.expect(View.aim("N", looking(-PI / 2), arrows("U"))).toBe("N")
	end)

	it("with no arrow held, the look's yaw is rounded to the nearest heading", function()
		local cases: { { number } } = {
			{ 0, 0 },
			{ math.rad(44), 0 },
			{ math.rad(46), 1 },
			{ math.rad(-46), -1 },
			{ math.rad(134), 1 },
			{ math.rad(136), 2 },
			{ math.rad(-136), 2 },
			{ PI, 2 },
			{ -PI, 2 },
			{ math.rad(90), 1 },
			{ math.rad(-90), -1 },
		}
		for _, c in cases do
			local want: Maze.Heading = if c[2] == 0
				then "N"
				elseif c[2] == 1 then "W"
				elseif c[2] == -1 then "E"
				else "S"
			t.expect(View.aim("N", looking(c[1]), NONE)).toBe(want)
		end
	end)

	it("a look exactly half way goes the way of travel, ahead or behind", function()
		t.expect(View.aim("E", looking(PI / 4), NONE)).toBe("E")
		t.expect(View.aim("E", looking(-PI / 4), NONE)).toBe("E")
		t.expect(View.aim("E", looking(3 * PI / 4), NONE)).toBe("W")
		t.expect(View.aim("E", looking(-3 * PI / 4), NONE)).toBe("W")
	end)

	it("the pitch never matters, and a look past a whole turn counts from where it points", function()
		t.expect(View.aim("S", looking(0, 1.2), NONE)).toBe("S")
		t.expect(View.aim("S", looking(PI / 2, -1.2), NONE)).toBe("E")
		t.expect(View.aim("N", looking(2 * PI + 0.1), NONE)).toBe("N")
		t.expect(View.aim("N", looking(-2 * PI + PI / 2), NONE)).toBe("W")
	end)

	it("a look that is not a number aims ahead", function()
		t.expect(View.aim("W", looking(0 / 0), NONE)).toBe("W")
		t.expect(View.aim("W", looking(math.huge), NONE)).toBe("W")
	end)
end)
