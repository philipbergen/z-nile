--!strict
-- f0210: the way out through the door, and the way back: an eaten ghost is eyes, goes home through the door and
-- comes out again.
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local WAITERS: { Ghosts.Name } = { "pinky", "inky", "clyde" }

local function input(level: number?): Ghosts.Input
	return { player = { x = 1, y = 29 }, heading = "E", level = level or 1, baseSpeed = 30, tickRate = 30 }
end

local function status(set: Ghosts.Set, name: Ghosts.Name): string
	return Ghosts.ghost(set, name).status
end

return t.spec("f0210 leaving and returning", function(it)
	it("a ghost leaves through the door and is active, outside, at the tile above it", function()
		local set = Ghosts.new(classic, 1)
		local left: Ghosts.Event? = nil
		local sawDoor = false
		for _ = 1, 30 do
			for _, e in Ghosts.step(set, input()) do
				if e.kind == "GhostLeft" and e.ghost == "pinky" then
					left = e
				end
			end
			if Maze.kind(classic, Ghosts.occupied(Ghosts.ghost(set, "pinky"))) == "door" then
				sawDoor = true
			end
		end
		t.expect(left ~= nil).toBe(true)
		t.expect(sawDoor).toBe(true)
		local pinky = Ghosts.ghost(set, "pinky")
		t.expect(pinky.status).toBe("active")
		t.expect(Maze.kind(classic, Ghosts.occupied(pinky))).toBe("empty")
	end)
	it("a ghost on its way out walks only on house, door and open tiles, never through a wall", function()
		local set = Ghosts.new(classic, 1, { level = 3 })
		for _ = 1, 80 do
			Ghosts.step(set, input(3))
			for _, name: Ghosts.Name in WAITERS do
				local g = Ghosts.ghost(set, name)
				local o = Ghosts.occupied(g)
				local kind = Maze.kind(classic, { x = o.x % classic.width, y = o.y % classic.height })
				t.expect(kind ~= "wall").toBe(true)
			end
		end
		for _, name: Ghosts.Name in WAITERS do
			t.expect(status(set, name)).toBe("active")
		end
	end)
	it(
		"a ghost that is eaten turns to eyes, goes home through the door and comes out again, not blue",
		function()
			for _, from in { { x = 1, y = 29 }, { x = 26, y = 1 }, { x = 6, y = 5 }, { x = 21, y = 23 } } do
				local set = Ghosts.new(classic, 1, { start = "active" })
				Ghosts.power(set, 900)
				local blinky = Ghosts.ghost(set, "blinky")
				blinky.tile, blinky.progress = { x = from.x, y = from.y }, 0
				t.expect(Maze.passable(classic, from, "player")).toBe(true)
				local points = Ghosts.eat(set, "blinky")
				t.expect(points).toBe(200)
				t.expect(blinky.status).toBe("eyes")
				t.expect(blinky.frightened).toBe(false)
				t.expect(Ghosts.look(set, blinky)).toBe("eyes")
				local sawDoor, revived, left = false, false, false
				for _ = 1, 700 do
					for _, e in Ghosts.step(set, input()) do
						if e.ghost == "blinky" and e.kind == "GhostRevived" then
							revived = true
						elseif e.ghost == "blinky" and e.kind == "GhostLeft" then
							left = true
						end
					end
					local kind = Maze.kind(classic, Ghosts.occupied(blinky))
					if kind == "door" then
						sawDoor = true
					end
					if kind == "wall" then
						error("eyes walked into a wall")
					end
					if left then
						break
					end
				end
				t.expect(sawDoor).toBe(true)
				t.expect(revived).toBe(true)
				t.expect(left).toBe(true)
				t.expect(blinky.status).toBe("active")
				t.expect(blinky.frightened).toBe(false) -- an eaten ghost comes out dangerous, whatever the others are doing
				t.expect(Ghosts.look(set, blinky)).toBe("normal")
			end
		end
	)
	it(
		"a ghost still in the house when the power starts leaves blue, and a ghost eaten and revived does not",
		function()
			local set = Ghosts.new(classic, 1, { level = 3 })
			Ghosts.power(set, 900)
			for _, name: Ghosts.Name in WAITERS do
				t.expect(Ghosts.ghost(set, name).frightened).toBe(true)
			end
			for _ = 1, 80 do
				Ghosts.step(set, input(3))
			end
			for _, name: Ghosts.Name in WAITERS do
				local g = Ghosts.ghost(set, name)
				t.expect(g.status).toBe("active")
				t.expect(g.frightened).toBe(true) -- out of the house, still blue
			end
			-- the one that is eaten and comes back is dangerous among the blue ones
			Ghosts.eat(set, "pinky")
			for _ = 1, 400 do
				Ghosts.step(set, input(3))
			end
			t.expect(Ghosts.ghost(set, "pinky").status).toBe("active")
			t.expect(Ghosts.ghost(set, "pinky").frightened).toBe(false)
			t.expect(Ghosts.ghost(set, "inky").frightened).toBe(true)
			-- a second power pellet turns it blue again: it is a hunting ghost like any other
			Ghosts.power(set, 300)
			t.expect(Ghosts.ghost(set, "pinky").frightened).toBe(true)
		end
	)

	it("eyes run at the eyes' speed even in a tunnel, which slows every other ghost", function()
		local set = Ghosts.new(classic, 1, { start = "active" })
		local blinky = Ghosts.ghost(set, "blinky")
		blinky.tile, blinky.heading, blinky.progress = { x = 3, y = 14 }, "W", 0
		Ghosts.eat(set, "blinky")
		Ghosts.step(set, input())
		t.expect(blinky.progress).toBe(60)
	end)

	it(
		"a ghost that leaves the house blue moves at the frightened speed, one that leaves normal at the hunting speed",
		function()
			local blue = Ghosts.new(classic, 1)
			Ghosts.power(blue, 900)
			Ghosts.step(blue, input()) -- Pinky is released and takes its first step: 19 units at level 1
			t.expect(Ghosts.ghost(blue, "pinky").status).toBe("leaving")
			t.expect(Ghosts.ghost(blue, "pinky").progress).toBe(19)
			local calm = Ghosts.new(classic, 1)
			Ghosts.step(calm, input())
			t.expect(Ghosts.ghost(calm, "pinky").progress).toBe(28)
		end
	)

	it(
		"a ghost eaten before its turn-back leaves the house heading west and does not turn back by itself",
		function()
			local set = Ghosts.new(classic, 1, { start = "active" })
			local blinky = Ghosts.ghost(set, "blinky")
			blinky.tile, blinky.heading, blinky.progress = { x = 6, y = 5 }, "E", 60
			Ghosts.power(set, 30) -- every active ghost is told to turn back at its next centre
			t.expect(blinky.reverse).toBe(true)
			Ghosts.eat(set, "blinky")
			t.expect(blinky.reverse).toBe(false)
			local left = false
			local last: Maze.Heading? = nil
			local reversals, watched = 0, 0
			for _ = 1, 400 do
				for _, e in Ghosts.step(set, input()) do
					if e.kind == "GhostLeft" and e.ghost == "blinky" then
						left = true
					end
				end
				if left then
					watched += 1
					local before: Maze.Heading? = last
					if before and blinky.heading == Maze.opposite(before) then
						reversals += 1
					end
					last = blinky.heading
					if watched >= 100 then
						break -- well before the timetable's next mode change
					end
				end
			end
			t.expect(left).toBe(true)
			t.expect(reversals).toBe(0)
		end
	)

	it("an eaten ghost's eyes run at twice level 1's player speed and ignore a power pellet", function()
		local set = Ghosts.new(classic, 1, { start = "active" })
		local blinky = Ghosts.ghost(set, "blinky")
		blinky.tile, blinky.heading, blinky.progress = { x = 6, y = 5 }, "E", 0
		Ghosts.eat(set, "blinky")
		Ghosts.power(set, 200)
		t.expect(blinky.status).toBe("eyes")
		t.expect(blinky.frightened).toBe(false)
		Ghosts.step(set, input())
		t.expect(blinky.progress).toBe(60)
	end)
end)
