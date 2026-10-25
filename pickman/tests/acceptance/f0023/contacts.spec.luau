--!strict
-- f0220: when the player and a ghost meet. A normal ghost kills; a frightened one is eaten and pays 200,
-- 400, 800, 1600 along one power period; tiles swapped within one tick are a meeting too; eyes and ghosts
-- in the house never touch the player.
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

local function setup(): Ghosts.Set
	local set = Ghosts.new(classic, 1, { start = "active" })
	-- park the ghosts well apart, away from the player
	local spots = { { x = 1, y = 1 }, { x = 26, y = 1 }, { x = 1, y = 29 }, { x = 26, y = 29 } }
	for i, g in set.ghosts do
		g.tile, g.progress = spots[i], 0
	end
	return set
end

local function names(contacts: { Ghosts.Contact }): { string }
	local out = {}
	for _, c in contacts do
		table.insert(out, `{c.name}:{c.kind}`)
	end
	return out
end

return t.spec("f0220 contacts", function(it)
	it("a normal ghost on the player's tile kills", function()
		local set = setup()
		local prev = Ghosts.occupiedTiles(set)
		Ghosts.ghost(set, "inky").tile = { x = 6, y = 5 }
		t.expect(names(Ghosts.contacts(set, prev, { x = 5, y = 5 }, { x = 6, y = 5 })))
			.toEqual({ "inky:kill" })
	end)

	it("swapping tiles within one tick is a meeting, even though they never share a tile", function()
		local set = setup()
		local inky = Ghosts.ghost(set, "inky")
		-- the player goes from 5,5 to 6,5 while the ghost goes from 6,5 to 5,5
		local prev = Ghosts.occupiedTiles(set)
		prev[3] = { x = 6, y = 5 }
		inky.tile = { x = 5, y = 5 }
		t.expect(names(Ghosts.contacts(set, prev, { x = 5, y = 5 }, { x = 6, y = 5 })))
			.toEqual({ "inky:kill" })
		-- standing on the player's old tile without having come from the player's new one is not a meeting
		prev[3] = { x = 4, y = 5 }
		t.expect(names(Ghosts.contacts(set, prev, { x = 5, y = 5 }, { x = 6, y = 5 }))).toEqual({})
	end)

	it("passing on the same side without touching, or following one tile behind, is no meeting", function()
		local set = setup()
		local prev = Ghosts.occupiedTiles(set)
		Ghosts.ghost(set, "clyde").tile = { x = 4, y = 5 }
		prev[4] = { x = 3, y = 5 }
		-- the player moved 5,5 -> 6,5 with the ghost one tile behind
		t.expect(names(Ghosts.contacts(set, prev, { x = 5, y = 5 }, { x = 6, y = 5 }))).toEqual({})
	end)

	it("a frightened ghost is eaten instead; blue and normal ghosts at once give both contacts", function()
		local set = setup()
		local prev = Ghosts.occupiedTiles(set)
		local a, b = Ghosts.ghost(set, "pinky"), Ghosts.ghost(set, "blinky")
		a.tile, a.frightened = { x = 6, y = 5 }, true
		b.tile = { x = 6, y = 5 }
		t.expect(names(Ghosts.contacts(set, prev, { x = 5, y = 5 }, { x = 6, y = 5 }))).toEqual({
			"blinky:kill",
			"pinky:eat",
		})
	end)

	it(
		"a ghost that was eaten and has come back kills while the others are still blue and are eaten",
		function()
			local set = setup()
			Ghosts.power(set, 300)
			Ghosts.eat(set, "blinky")
			local blinky = Ghosts.ghost(set, "blinky")
			blinky.status = "active" -- revived and out again, dangerous (f0210)
			local prev = Ghosts.occupiedTiles(set)
			Ghosts.ghost(set, "pinky").tile = { x = 6, y = 5 }
			blinky.tile = { x = 6, y = 5 }
			t.expect(names(Ghosts.contacts(set, prev, { x = 5, y = 5 }, { x = 6, y = 5 }))).toEqual({
				"blinky:kill",
				"pinky:eat",
			})
		end
	)

	it("eyes, and ghosts still in the house, never touch the player", function()
		local set = setup()
		local prev = Ghosts.occupiedTiles(set)
		local eyes, waiting, leaving =
			Ghosts.ghost(set, "blinky"), Ghosts.ghost(set, "pinky"), Ghosts.ghost(set, "inky")
		for _, g in { eyes, waiting, leaving } do
			g.tile = { x = 6, y = 5 }
		end
		eyes.status, waiting.status, leaving.status = "eyes", "house", "leaving"
		t.expect(names(Ghosts.contacts(set, prev, { x = 5, y = 5 }, { x = 6, y = 5 }))).toEqual({})
	end)

	it("a ghost half way through the wrap meets a player on the other side of the edge", function()
		local set = setup()
		local prev = Ghosts.occupiedTiles(set)
		local clyde = Ghosts.ghost(set, "clyde")
		-- at the east end of the tunnel row heading east, 70 units on: it now occupies the tile on the other side of the edge
		clyde.tile, clyde.heading, clyde.progress = { x = 27, y = 14 }, "E", 70
		t.expect(Ghosts.occupiedTiles(set)[4]).toEqual({ x = 0, y = 14 })
		t.expect(names(Ghosts.contacts(set, prev, { x = 0, y = 14 }, { x = 0, y = 14 })))
			.toEqual({ "clyde:kill" })
		-- and a swap across the edge counts like any other
		prev[4] = { x = 27, y = 14 }
		clyde.tile, clyde.heading, clyde.progress = { x = 27, y = 14 }, "E", 70
		t.expect(names(Ghosts.contacts(set, prev, { x = 0, y = 14 }, { x = 27, y = 14 })))
			.toEqual({ "clyde:kill" })
	end)

	it("eating pays 200, 400, 800, then 1600 for every further ghost of the same power period", function()
		local set = setup()
		Ghosts.power(set, 300)
		t.expect(Ghosts.eat(set, "blinky")).toBe(200)
		t.expect(Ghosts.eat(set, "pinky")).toBe(400)
		t.expect(Ghosts.eat(set, "inky")).toBe(800)
		t.expect(Ghosts.eat(set, "clyde")).toBe(1600)
		-- a fifth eating (a ghost revived and blue again) stays at 1600
		t.expect(Ghosts.eat(set, "blinky")).toBe(1600)
	end)

	it("a new power pellet starts the chain at 200 again", function()
		local set = setup()
		Ghosts.power(set, 300)
		Ghosts.eat(set, "blinky")
		Ghosts.eat(set, "pinky")
		Ghosts.power(set, 300)
		t.expect(Ghosts.eat(set, "inky")).toBe(200)
	end)

	it("an eaten ghost is eyes at once: no longer frightened and no longer a danger", function()
		local set = setup()
		Ghosts.power(set, 300)
		Ghosts.eat(set, "clyde")
		local clyde = Ghosts.ghost(set, "clyde")
		t.expect(clyde.status).toBe("eyes")
		t.expect(clyde.frightened).toBe(false)
		local prev = Ghosts.occupiedTiles(set)
		clyde.tile = { x = 6, y = 5 }
		t.expect(names(Ghosts.contacts(set, prev, { x = 5, y = 5 }, { x = 6, y = 5 }))).toEqual({})
	end)
end)
