--!strict
-- f0190: the exit a ghost takes at a tile centre: the one closest to the target in a straight line, ties up, left,
-- down, right; never back unless dead end; no up on a no-up junction; the door and the house closed unless told otherwise.
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local HEADINGS: { Maze.Heading } = { "N", "E", "S", "W" }
-- an open 5x5 plaza: every tile is a junction, so ties are easy to build
local PLAZA = Maze.parse({ ".....", ".....", "..P..", ".....", "....." }, "plaza")
-- a one-row corridor with a dead end at each side
local CORRIDOR = Maze.parse({ "#######", "#P....#", "#######" }, "corridor")

local function opposite(h: Maze.Heading): Maze.Heading
	return Maze.opposite(h)
end

return t.spec("f0190 ghost exits", function(it)
	it("measures in a straight line, not in blocks", function()
		-- from (6,5) heading east the exits are N, E and S. Target (10,2): the north neighbour is 4 left and 2 up
		-- (20), the east neighbour 3 left and 3 up (18): east is closer in a straight line although both are 6
		-- blocks away, and a tie in blocks would have gone north
		t.expect(Ghosts.pickExit(classic, { x = 6, y = 5 }, "E", { x = 10, y = 2 })).toBe("E")
	end)

	it("takes the exit that is closest to the target in a straight line", function()
		-- from the plaza centre heading east the exits are N, E, S; the target lies far to the south east
		t.expect(Ghosts.pickExit(PLAZA, { x = 2, y = 2 }, "E", { x = 20, y = 20 })).toBe("S")
		t.expect(Ghosts.pickExit(PLAZA, { x = 2, y = 2 }, "E", { x = 20, y = 2 })).toBe("E")
		t.expect(Ghosts.pickExit(PLAZA, { x = 2, y = 2 }, "E", { x = 2, y = -20 })).toBe("N")
	end)
	it("breaks ties in the order up, left, down, right", function()
		-- every neighbour of (2,2) is exactly 1 away from the target (2,2) itself
		local here = { x = 2, y = 2 }
		t.expect(Ghosts.pickExit(PLAZA, here, "E", here)).toBe("N") -- W is behind
		t.expect(Ghosts.pickExit(PLAZA, here, "N", here)).toBe("N") -- S is behind
		t.expect(Ghosts.pickExit(PLAZA, here, "S", here)).toBe("W") -- N is behind: left beats down
		t.expect(Ghosts.pickExit(PLAZA, here, "W", here)).toBe("N") -- E is behind
	end)
	it("never turns back unless it is a dead end", function()
		for _, h: Maze.Heading in HEADINGS do
			local picked = Ghosts.pickExit(PLAZA, { x = 2, y = 2 }, h, { x = 2, y = 2 })
			t.expect(picked ~= opposite(h)).toBe(true)
		end
		-- the corridor's east end: no exit but back
		t.expect(Ghosts.pickExit(CORRIDOR, { x = 5, y = 1 }, "E", { x = 99, y = 1 })).toBe("W")
		t.expect(Ghosts.pickExit(CORRIDOR, { x = 1, y = 1 }, "W", { x = -99, y = 1 })).toBe("E")
	end)
	it("may not go up on a no-up junction, but may elsewhere", function()
		local junction = { x = 12, y = 11 } -- open to N, W and E; wall to the south
		local target = { x = 12, y = -9 }
		t.expect(Ghosts.pickExit(classic, junction, "E", target)).toBe("N")
		t.expect(Ghosts.pickExit(classic, junction, "E", target, { noUp = true })).toBe("E")
		-- another tile with an exit to the north is not restricted
		t.expect(Ghosts.pickExit(classic, { x = 6, y = 8 }, "E", { x = 6, y = -9 }, { noUp = true }))
			.toBe("N")
	end)
	it("keeps out of the door and the house unless told it may enter", function()
		local above = { x = 13, y = 11 } -- the tile above the door
		local inside = { x = 13, y = 14 }
		t.expect(Ghosts.pickExit(classic, above, "W", inside)).toBe("W") -- S is the door: closed
		t.expect(Ghosts.pickExit(classic, above, "W", inside, { house = true })).toBe("S")
	end)
end)
