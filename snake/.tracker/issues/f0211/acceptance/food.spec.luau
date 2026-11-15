--!strict
-- f0211 acceptance: apples (snake/.tracker/game-design.md, "Food"): +1 length, 10 x map number points, and always
-- (players + 1) apples on the board, on free tiles.
local Maps = require("@logic/Maps")
local World = require("@logic/World")
local t = require("@tests/lib/t")

-- a seeded stand-in for arcade's Rng.draw (f0203): a whole number in 1..n, and an error for any other n, as
-- Rng.int's misuse is
local function drawOf(seed: number): (n: number) -> number
	local s = seed % 2147483646 + 1
	return function(n: number): number
		if type(n) ~= "number" or n < 1 or n ~= math.floor(n) then
			error(`draw: n must be a whole number of at least 1, got {n}`, 2)
		end
		s = (s * 48271) % 2147483647
		return s % n + 1
	end
end

local function step(w: World.World, d: Maps.Draw): { World.Event }
	return World.advance(w, 1 / World.speed(w), d)
end

local function east(x: number, y: number): { Maps.Tile }
	return { { x = x, y = y }, { x = x - 1, y = y }, { x = x - 2, y = y }, { x = x - 3, y = y } }
end

local function wallKeys(l: Maps.Layout): { [string]: boolean }
	local out = {}
	for _, w in l.walls do
		for i = 0, w.length - 1 do
			local x, y = if w.dir == "H" then w.x + i else w.x, if w.dir == "V" then w.y + i else w.y
			out[`{x},{y}`] = true
		end
	end
	return out
end

-- every apple is on the board, on no wall, no Ready or alive snake and no other apple
local function applesFree(w: World.World)
	local walls = wallKeys(w.layout)
	local taken = {}
	for _, s in w.snakes do
		if s.state == "ready" or s.state == "alive" then
			for _, b in s.body do
				taken[`{b.x},{b.y}`] = true
			end
		end
	end
	for _, a in w.apples do
		local k = `{a.x},{a.y}`
		t.expect(a.x >= 1 and a.y >= 1 and a.x <= w.layout.side and a.y <= w.layout.side).toBe(true)
		t.expect(walls[k] == nil and taken[k] == nil).toBe(true)
		taken[k] = true
	end
end

local function hasEvent(events: { World.Event }, kind: string, id: number): boolean
	for _, e in events do
		if e.kind == kind and (e :: any).id == id then
			return true
		end
	end
	return false
end

return t.spec("f0211 food", function(it)
	it("every map starts with players + 1 apples, on free tiles", function()
		for _, players in { 1, 2, 5, 24 } do
			local d = drawOf(players)
			local w = World.new(players, d)
			t.expect(#w.apples).toBe(players + 1)
			applesFree(w)
			-- a map with walls too
			World.start(w, Maps.roll(9, players, d), d)
			t.expect(#w.apples).toBe(players + 1)
			applesFree(w)
		end
	end)

	it("an apple makes the snake 1 longer at once and scores 10 x the map number", function()
		local d = drawOf(1)
		local w = World.new(1, d)
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = east(5, 10), "E", "alive", 0
		w.apples = { { x = 6, y = 10 }, { x = 15, y = 15 } }
		local events = step(w, d)
		t.expect(hasEvent(events, "ate", 1)).toBe(true)
		t.expect(#s.body).toBe(5)
		t.expect(s.body[1]).toEqual({ x = 6, y = 10 })
		t.expect(s.body[5]).toEqual({ x = 2, y = 10 })
		t.expect(s.score).toBe(10)
		-- one apple only: the next step the tail moves again
		step(w, d)
		t.expect(#s.body).toBe(5)
		t.expect(s.body[5]).toEqual({ x = 3, y = 10 })
	end)

	it("on map 3 an apple scores 30", function()
		local d = drawOf(2)
		local w = World.new(1, d)
		World.start(w, { map = 3, side = 20, walls = {}, spawns = Maps.spawns(20, 1) }, d)
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = east(5, 10), "E", "alive", 0
		w.apples = { { x = 6, y = 10 }, { x = 15, y = 15 } }
		step(w, d)
		t.expect(s.score).toBe(30)
		t.expect(#s.body).toBe(5)
	end)

	it("an eaten apple is replaced at once, on a free tile, so players + 1 stay on the board", function()
		for seed = 1, 40 do
			local d = drawOf(seed)
			local w = World.new(2, d)
			World.start(w, Maps.roll(4, 2, d), d)
			local s = w.snakes[1]
			local sp = w.layout.spawns[1]
			s.body, s.heading, s.state, s.timer = east(sp.x, sp.y), "E", "alive", 0
			-- the first apple moves to just ahead of the head (and no other apple is there)
			local kept = { { x = sp.x + 1, y = sp.y } }
			for i = 2, #w.apples do
				local a = w.apples[i]
				if a.x ~= sp.x + 1 or a.y ~= sp.y then
					table.insert(kept, a)
				end
			end
			t.expect(#kept).toBe(3)
			w.apples = kept
			step(w, d)
			t.expect(#s.body).toBe(5)
			t.expect(#w.apples).toBe(3)
			applesFree(w)
		end
	end)

	it("a snake that does not reach an apple does not score or grow", function()
		local d = drawOf(3)
		local w = World.new(1, d)
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = east(5, 10), "E", "alive", 0
		w.apples = { { x = 5, y = 11 }, { x = 15, y = 15 } } -- beside the head, not ahead
		step(w, d)
		t.expect(#s.body).toBe(4)
		t.expect(s.score).toBe(0)
		t.expect(#w.apples).toBe(2)
	end)

	it("with no free tile left, no apple appears and nothing breaks", function()
		local d = drawOf(4)
		local w = World.new(1, d)
		-- map 5: its goal of 20 is out of reach, so the map does not clear
		w.map = 5
		w.layout = { map = 5, side = 4, walls = {}, spawns = {} }
		local s = w.snakes[1]
		-- a serpent filling a 4x4 board but one tile, its head beside the apple on it
		s.body = {
			{ x = 2, y = 4 },
			{ x = 3, y = 4 },
			{ x = 4, y = 4 },
			{ x = 4, y = 3 },
			{ x = 3, y = 3 },
			{ x = 2, y = 3 },
			{ x = 1, y = 3 },
			{ x = 1, y = 2 },
			{ x = 2, y = 2 },
			{ x = 3, y = 2 },
			{ x = 4, y = 2 },
			{ x = 4, y = 1 },
			{ x = 3, y = 1 },
			{ x = 2, y = 1 },
			{ x = 1, y = 1 },
		}
		s.heading, s.state, s.timer = "W", "alive", 0
		w.apples = { { x = 1, y = 4 } }
		World.advance(w, 0.25, d) -- the clock still runs at map 1's step, set by World.new

		t.expect(#s.body).toBe(16)
		t.expect(#w.apples).toBe(0)
	end)

	it("a short count is made up when an apple is eaten: back to players + 1", function()
		local d = drawOf(5)
		local w = World.new(1, d)
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = east(5, 10), "E", "alive", 0
		w.apples = { { x = 6, y = 10 } } -- one short of 2
		step(w, d)
		t.expect(#w.apples).toBe(2)
		applesFree(w)
	end)

	it("apples never land on a snake, even on a crowded board", function()
		for seed = 1, 20 do
			local d = drawOf(seed)
			local w = World.new(1, d)
			-- map 10 (goal 30) on a hand-made 5x5 board: a 20-tile serpent fills rows 1 to 4, its head at (1, 4)
			w.map = 10
			w.layout = { map = 10, side = 5, walls = {}, spawns = {} }
			local body = {}
			for y = 4, 1, -1 do
				for i = 1, 5 do
					table.insert(body, { x = if y % 2 == 0 then i else 6 - i, y = y })
				end
			end
			local s = w.snakes[1]
			s.body, s.heading, s.state, s.timer = body, "S", "alive", 0
			w.apples = { { x = 1, y = 5 } }
			World.advance(w, 0.25, d) -- the clock still runs at map 1's step, set by World.new
			t.expect(#s.body).toBe(21)
			t.expect(#w.apples).toBe(2)
			for _, a in w.apples do
				t.expect(a.y == 5 and a.x >= 2).toBe(true)
			end
		end
	end)
end)
