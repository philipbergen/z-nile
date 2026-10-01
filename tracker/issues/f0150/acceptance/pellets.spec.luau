--!strict
-- f0150 AC1: Pellets, the pellets of a maze that are still there to eat. Pure state: which tiles
-- hold a pellet, eating one, and putting them all back.
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local t = require("@tests/lib/t")

local TINY = Maze.parse({ "#######", "#.o.P.#", "#######" }, "tiny")

local function tile(x: number, y: number): Maze.Tile
	return { x = x, y = y }
end

return t.spec("f0150 Pellets", function(it)
	it("holds a pellet on every pellet and power tile of the maze, and none elsewhere", function()
		local p = Pellets.new(TINY)
		t.expect(Pellets.total(p)).toBe(4)
		t.expect(Pellets.remaining(p)).toBe(4)
		t.expect(Pellets.at(p, tile(1, 1))).toBe("pellet")
		t.expect(Pellets.at(p, tile(2, 1))).toBe("power")
		t.expect(Pellets.at(p, tile(3, 1))).toBe("pellet")
		t.expect(Pellets.at(p, tile(4, 1))).toBe(nil) -- the spawn has no pellet
		t.expect(Pellets.at(p, tile(5, 1))).toBe("pellet")
		t.expect(Pellets.at(p, tile(0, 1))).toBe(nil) -- a wall
	end)

	it("the classic maze has 240 pellets and 4 power pellets", function()
		local p = Pellets.new(Maze.layout("classic"))
		t.expect(Pellets.total(p)).toBe(244)
		t.expect(#Pellets.tiles(p, "pellet")).toBe(240)
		t.expect(#Pellets.tiles(p, "power")).toBe(4)
		t.expect(Pellets.tiles(p, "power"))
			.toEqual({ { x = 1, y = 3 }, { x = 26, y = 3 }, { x = 1, y = 23 }, { x = 26, y = 23 } })
	end)

	it("eating returns the kind and removes the pellet, and a pellet is never eaten twice", function()
		local p = Pellets.new(TINY)
		t.expect(Pellets.eat(p, tile(3, 1))).toBe("pellet")
		t.expect(Pellets.remaining(p)).toBe(3)
		t.expect(Pellets.at(p, tile(3, 1))).toBe(nil)
		t.expect(Pellets.eat(p, tile(3, 1))).toBe(nil)
		t.expect(Pellets.remaining(p)).toBe(3)
		t.expect(Pellets.eat(p, tile(2, 1))).toBe("power")
		t.expect(Pellets.remaining(p)).toBe(2)
	end)

	it("eating a tile with nothing on it changes nothing", function()
		local p = Pellets.new(TINY)
		t.expect(Pellets.eat(p, tile(4, 1))).toBe(nil) -- the spawn
		t.expect(Pellets.eat(p, tile(0, 0))).toBe(nil) -- a wall
		t.expect(Pellets.remaining(p)).toBe(4)
	end)

	it("a tile outside the maze is an error, not another tile", function()
		local p = Pellets.new(TINY)
		for _, bad in { tile(7, 1), tile(-1, 1), tile(1, 3), tile(1, -1), tile(7, 3) } do
			t.expect(function()
				Pellets.eat(p, bad)
			end).toThrow("bounds")
			t.expect(function()
				Pellets.at(p, bad)
			end).toThrow("bounds")
		end
		t.expect(Pellets.remaining(p)).toBe(4)
	end)

	it("reset puts every pellet back", function()
		local p = Pellets.new(TINY)
		for _, x in { 1, 2, 3, 5 } do
			Pellets.eat(p, tile(x, 1))
		end
		t.expect(Pellets.remaining(p)).toBe(0)
		Pellets.reset(p)
		t.expect(Pellets.remaining(p)).toBe(4)
		t.expect(Pellets.at(p, tile(2, 1))).toBe("power")
		t.expect(Pellets.total(p)).toBe(4)
	end)

	it("tiles lists what is left in row-major order, optionally of one kind", function()
		local p = Pellets.new(Maze.parse({ "#####", "#.#.#", "#...#", "#P#o#", "#####" }, "rows"))
		t.expect(Pellets.tiles(p)).toEqual({
			{ x = 1, y = 1 },
			{ x = 3, y = 1 },
			{ x = 1, y = 2 },
			{ x = 2, y = 2 },
			{ x = 3, y = 2 },
			{ x = 3, y = 3 },
		})
		Pellets.eat(p, tile(2, 2))
		t.expect(#Pellets.tiles(p)).toBe(5)
		t.expect(Pellets.tiles(p, "power")).toEqual({ { x = 3, y = 3 } })
		t.expect(#Pellets.tiles(p, "pellet")).toBe(4)
	end)

	it("two Pellets of the same maze are independent", function()
		local a = Pellets.new(TINY)
		local b = Pellets.new(TINY)
		Pellets.eat(a, tile(1, 1))
		t.expect(Pellets.remaining(a)).toBe(3)
		t.expect(Pellets.remaining(b)).toBe(4)
		Pellets.reset(a)
		Pellets.eat(b, tile(5, 1))
		t.expect(Pellets.remaining(a)).toBe(4)
		t.expect(Pellets.remaining(b)).toBe(3)
	end)

	it("points are 10 and 50, and eating stops the player for 1 and 3 frames of the arcade's 60 fps", function()
		t.expect(Pellets.POINTS.pellet).toBe(10)
		t.expect(Pellets.POINTS.power).toBe(50)
		t.expect(Pellets.STALL_FRAMES.pellet).toBe(1)
		t.expect(Pellets.STALL_FRAMES.power).toBe(3)
		t.expect(Pellets.ARCADE_FPS).toBe(60)
	end)

	it("stallUnits is the distance the pause costs at the player's speed", function()
		-- at 30 units a tick and 30 ticks a second, 1/60 s is 15 units and 3/60 s is 45
		t.expect(Pellets.stallUnits("pellet", 30, 30)).toBe(15)
		t.expect(Pellets.stallUnits("power", 30, 30)).toBe(45)
		t.expect(Pellets.stallUnits("pellet", 34, 30)).toBe(17)
		t.expect(Pellets.stallUnits("power", 34, 30)).toBe(51)
		t.expect(Pellets.stallUnits("pellet", 38, 30)).toBe(19)
		t.expect(Pellets.stallUnits("power", 38, 30)).toBe(57)
		t.expect(Pellets.stallUnits("pellet", 30, 60)).toBe(30) -- a faster tick rate covers more per second
		t.expect(Pellets.stallUnits("pellet", 1, 30)).toBe(0) -- rounds down to whole units
	end)
end)
