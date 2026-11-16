--!strict
-- f0126 AC1: the Picks feature. Which walls can be marked (interior, clear of the ghost house, next to a walkable
-- tile), three marked at a time by a seeded roll, the wall a player standing on a tile would pick, how long a pick
-- takes (a hunting ghost's time for ten tiles, half for a fast pick), and the boon roll (six boons, even odds).
local Levels = require("@logic/Levels")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Picks = require("@logic/Picks")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
-- a corridor between two thick walls: every wall of rows 1 and 3 from x 1 to 7 can be picked, row 0 and 4 are the
-- edge, and the corridor's ends (x 0 and 8) are on the edge too
local CORRIDOR = Maze.parse({ "#########", "#########", "#.....P.#", "#########", "#########" }, "corridor")
-- the house: its walls and every wall touching a door or house tile (corners included) stay shut
local HOUSE = Maze.parse({
	"#######",
	"#.....#",
	"#.###.#",
	"#.#H#.#",
	"#.#-#.#",
	"#..P..#",
	"#######",
}, "house")
-- only two walls can ever be marked: (2, 2) and (4, 2) (the rest is the edge or has no walkable neighbour)
local SMALL = Maze.parse({ "#######", "#.....#", "#.#P#.#", "#.....#", "#######" }, "small")

local function at(x: number, y: number): Maze.Tile
	return { x = x, y = y }
end

local function list(tiles: { Maze.Tile }): string
	local out = {}
	for _, tile in tiles do
		table.insert(out, `{tile.x},{tile.y}`)
	end
	return table.concat(out, " ")
end

return t.spec("f0126 Picks", function(it)
	it("the wire string is exactly Pick", function()
		t.expect(Picks.INTENT).toBe("Pick")
		t.expect(Picks.isIntent("Pick")).toBe(true)
		for _, v in { "pick", "PICK", "Pick ", "Hop", "Fire", "", 1, true } :: { any } do
			t.expect(Picks.isIntent(v)).toBe(false)
		end
		t.expect(Picks.isIntent({ "Pick" })).toBe(false)
	end)

	it(
		"the tuning is the user's: three marked, ten paces, six boons, a long pill of twice the time",
		function()
			t.expect(Picks.MARKED).toBe(3)
			t.expect(Picks.PACES).toBe(10)
			t.expect(Picks.LONG_PILL_FACTOR).toBe(2)
		end
	)

	it("lists exactly the six boons, in a fixed order", function()
		local names = table.concat(Picks.BOONS :: any, " ")
		t.expect(names).toBe("jumps fastpick pill longpill shot pellets")
		t.expect(function()
			(Picks.BOONS :: any)[7] = "extra"
		end).toThrow()
	end)

	it("an interior wall next to a walkable tile can be picked", function()
		t.expect(Picks.pickable(CORRIDOR, at(1, 1))).toBe(true)
		t.expect(Picks.pickable(CORRIDOR, at(7, 3))).toBe(true)
		t.expect(Picks.pickable(classic, at(2, 2))).toBe(true) -- the block below the top-left corridor
	end)

	it("a wall on the outer edge cannot, even beside a walkable tile", function()
		t.expect(Picks.pickable(CORRIDOR, at(0, 2))).toBe(false)
		t.expect(Picks.pickable(CORRIDOR, at(8, 2))).toBe(false)
		t.expect(Picks.pickable(CORRIDOR, at(3, 0))).toBe(false)
		t.expect(Picks.pickable(classic, at(0, 1))).toBe(false)
		t.expect(Picks.pickable(classic, at(5, 0))).toBe(false)
	end)

	it("a wall with no walkable neighbour cannot (only diagonal ones do not count)", function()
		-- classic (2, 3) is inside the 4 by 3 block: its four neighbours are walls
		t.expect(Maze.kind(classic, at(3, 3))).toBe("wall")
		t.expect(Picks.pickable(classic, at(3, 3))).toBe(false)
	end)

	it("a tile that is not a wall cannot", function()
		t.expect(Picks.pickable(CORRIDOR, at(3, 2))).toBe(false)
		t.expect(Picks.pickable(CORRIDOR, CORRIDOR.spawn)).toBe(false)
		t.expect(Picks.pickable(HOUSE, at(3, 3))).toBe(false) -- the house tile
		t.expect(Picks.pickable(HOUSE, at(3, 4))).toBe(false) -- the door
	end)

	it("no wall touching a door or a house tile, corners included, can be picked", function()
		-- (2, 2) touches the house (3, 3) only at a corner; (2, 3) beside it; (2, 4) beside the door
		for _, tile in { at(2, 2), at(3, 2), at(4, 2), at(2, 3), at(4, 3), at(2, 4), at(4, 4) } do
			t.expect(Picks.pickable(HOUSE, tile)).toBe(false)
		end
		-- on the classic maze: no pickable wall has a door or house tile among its eight neighbours
		for _, tile in Picks.candidates(Picks.new(1), classic) do
			for dy = -1, 1 do
				for dx = -1, 1 do
					local k = Maze.kind(classic, at(tile.x + dx, tile.y + dy))
					t.expect(k ~= "door" and k ~= "house").toBe(true)
				end
			end
		end
		t.expect(Picks.pickable(classic, at(10, 13))).toBe(false) -- the house's west wall, beside a house tile
		t.expect(Picks.pickable(classic, at(12, 12))).toBe(false) -- beside the door (13, 12)
	end)

	it("the classic maze has 342 walls that can be picked", function()
		t.expect(#Picks.candidates(Picks.new(1), classic)).toBe(342)
	end)

	it("the candidates are every pickable wall not yet marked, row-major", function()
		local p = Picks.new(1)
		t.expect(list(Picks.candidates(p, SMALL))).toBe("2,2 4,2")
		p.marked = { at(4, 2) }
		t.expect(list(Picks.candidates(p, SMALL))).toBe("2,2")
		local c = Picks.candidates(Picks.new(1), CORRIDOR)
		t.expect(#c).toBe(14)
		t.expect(list({ c[1], c[7], c[8], c[14] })).toBe("1,1 7,1 1,3 7,3")
	end)

	it("a new set of picks has no marks until it is reset on a maze, then exactly three", function()
		local p = Picks.new(5)
		t.expect(#p.marked).toBe(0)
		t.expect(p.fast).toBe(0)
		Picks.reset(p, CORRIDOR)
		t.expect(#p.marked).toBe(3)
		local seen: { [string]: boolean } = {}
		for _, tile in p.marked do
			t.expect(Picks.pickable(CORRIDOR, tile)).toBe(true)
			t.expect(seen[`{tile.x},{tile.y}`]).toBe(nil) -- three different walls
			seen[`{tile.x},{tile.y}`] = true
		end
	end)

	it("marks only as many as there are candidates", function()
		local p = Picks.new(3)
		Picks.reset(p, SMALL)
		t.expect(#p.marked).toBe(2)
		t.expect(#Picks.mark(p, SMALL)).toBe(0)
	end)

	it("mark tops the marks back up to three and returns what it added", function()
		local p = Picks.new(9)
		Picks.reset(p, CORRIDOR)
		local gone = p.marked[2]
		Picks.unmark(p, gone)
		t.expect(#p.marked).toBe(2)
		t.expect(Picks.isMarked(p, gone)).toBe(false)
		local added = Picks.mark(p, CORRIDOR)
		t.expect(#added).toBe(1)
		t.expect(#p.marked).toBe(3)
		t.expect(Picks.isMarked(p, added[1])).toBe(true)
	end)

	it("a seed marks the same walls every time, and different seeds mark different ones", function()
		local function marks(seed: number): string
			local p = Picks.new(seed)
			Picks.reset(p, classic)
			return list(p.marked)
		end
		t.expect(marks(42)).toBe(marks(42))
		local distinct: { [string]: boolean } = {}
		local n = 0
		for seed = 1, 20 do
			local key = marks(seed)
			if not distinct[key] then
				distinct[key] = true
				n += 1
			end
		end
		t.expect(n >= 18).toBe(true)
	end)

	it("the marks spread over the whole maze, not one corner", function()
		local rows: { [number]: boolean } = {}
		for seed = 1, 60 do
			local p = Picks.new(seed)
			Picks.reset(p, classic)
			for _, tile in p.marked do
				rows[tile.y // 8] = true
			end
		end
		for band = 0, 3 do
			t.expect(rows[band]).toBe(true)
		end
	end)

	it("reset rolls new marks and keeps the banked fast picks", function()
		local p = Picks.new(11)
		Picks.reset(p, classic)
		local first = list(p.marked)
		p.fast = 2
		local changed = false
		for _ = 1, 5 do
			Picks.reset(p, classic)
			changed = changed or list(p.marked) ~= first
			t.expect(#p.marked).toBe(3)
		end
		t.expect(changed).toBe(true)
		t.expect(p.fast).toBe(2)
	end)

	it("the wall picked from a tile is the marked one beside it: ahead, then left, right, behind", function()
		local p = Picks.new(1)
		p.marked = { at(3, 1), at(3, 3) }
		-- facing west on (3, 2): north is right, south is left
		t.expect(list({ Picks.wallBeside(p, CORRIDOR, at(3, 2), "W") :: Maze.Tile })).toBe("3,3")
		t.expect(list({ Picks.wallBeside(p, CORRIDOR, at(3, 2), "E") :: Maze.Tile })).toBe("3,1")
		t.expect(list({ Picks.wallBeside(p, CORRIDOR, at(3, 2), "S") :: Maze.Tile })).toBe("3,3")
		t.expect(list({ Picks.wallBeside(p, CORRIDOR, at(3, 2), "N") :: Maze.Tile })).toBe("3,1")
		p.marked = { at(3, 1) }
		t.expect(list({ Picks.wallBeside(p, CORRIDOR, at(3, 2), "S") :: Maze.Tile })).toBe("3,1") -- behind
		t.expect(Picks.wallBeside(p, CORRIDOR, at(4, 2), "W")).toBe(nil)
		t.expect(Picks.wallBeside(p, CORRIDOR, at(2, 2), "W")).toBe(nil) -- diagonal does not count
	end)

	it("a pick lasts as long as a hunting ghost takes to walk ten tiles, rounded up", function()
		t.expect(Picks.ticks(28, false)).toBe(43) -- level 1: 1200 / 28 = 42.9
		t.expect(Picks.ticks(32, false)).toBe(38)
		t.expect(Picks.ticks(36, false)).toBe(34)
		t.expect(Picks.ticks(30, false)).toBe(40) -- exact: no extra step
		t.expect(Picks.ticks(Levels.ghostSpeed(30, 1, "normal"), false))
			.toBe(math.ceil(Picks.PACES * Movement.UNITS / Levels.ghostSpeed(30, 1, "normal")))
	end)

	it("a fast pick takes half of that, rounded up, and never less than a step", function()
		t.expect(Picks.ticks(28, true)).toBe(22)
		t.expect(Picks.ticks(30, true)).toBe(20)
		t.expect(Picks.ticks(36, true)).toBe(17)
		t.expect(Picks.ticks(10000, true)).toBe(1)
		t.expect(Picks.ticks(10000, false)).toBe(1)
	end)

	it("every boon comes up, each about one time in six", function()
		local counts: { [string]: number } = {}
		local p = Picks.new(2024)
		for _ = 1, 6000 do
			local b = Picks.roll(p)
			counts[b] = (counts[b] or 0) + 1
		end
		for _, b in Picks.BOONS do
			t.expect((counts[b] or 0) > 850 and (counts[b] or 0) < 1150).toBe(true)
		end
		local total = 0
		for _, n in counts do
			total += n
		end
		t.expect(total).toBe(6000)
	end)

	it("a seed rolls the same boons every time; another seed rolls others", function()
		local function rolls(seed: number): string
			local p = Picks.new(seed)
			local out = {}
			for _ = 1, 12 do
				table.insert(out, Picks.roll(p))
			end
			return table.concat(out, " ")
		end
		t.expect(rolls(8)).toBe(rolls(8))
		t.expect(rolls(8) ~= rolls(9)).toBe(true)
	end)
end)
