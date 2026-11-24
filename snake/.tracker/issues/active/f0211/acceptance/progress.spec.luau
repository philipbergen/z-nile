--!strict
-- f0211 acceptance: the map progression (snake/.tracker/game-design.md, "Maps"): reaching the goal length ends the
-- map with a 2 s MAP CLEAR and a 100 x k bonus, then the next map starts with one more wall, every snake back to 4
-- segments at its spawn, and a little more speed.
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

local function line(x: number, y: number, heading: Maps.Heading, n: number): { Maps.Tile }
	local v = Maps.step(heading)
	local out = {}
	for i = 0, n - 1 do
		table.insert(out, { x = x - v.x * i, y = y - v.y * i })
	end
	return out
end

local function find(events: { World.Event }, kind: string): any
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

-- snake `id` hand-placed `n` long going east along row y, ending at x, with an apple just ahead
local function nearGoal(w: World.World, id: number, x: number, y: number, n: number)
	local s = w.snakes[id]
	s.body, s.heading, s.state, s.timer, s.turns = line(x, y, "E", n), "E", "alive", 0, {}
	table.insert(w.apples, { x = x + 1, y = y })
end

return t.spec("f0211 progress", function(it)
	it("reaching the goal length ends the map: MAP CLEAR, with 100 x k on top of the apple", function()
		local d = drawOf(1)
		local w = World.new(1, d)
		w.apples = {}
		nearGoal(w, 1, 15, 10, Maps.goal(1) - 1)
		local events = step(w, d)
		local cleared = find(events, "cleared")
		t.expect(cleared ~= nil).toBe(true)
		t.expect(cleared.map).toBe(1)
		t.expect(cleared.ids).toEqual({ 1 })
		t.expect(w.phase).toBe("clear")
		t.expect(#w.snakes[1].body).toBe(12)
		t.expect(w.snakes[1].score).toBe(10 + 100)
	end)

	it("one tile short of the goal is not a clear", function()
		local d = drawOf(2)
		local w = World.new(1, d)
		w.apples = {}
		nearGoal(w, 1, 15, 10, Maps.goal(1) - 2)
		t.expect(find(step(w, d), "cleared")).toBe(nil)
		t.expect(w.phase).toBe("play")
	end)

	it("MAP CLEAR lasts 2 s: nothing moves and turns are refused", function()
		local d = drawOf(3)
		local w = World.new(1, d)
		w.apples = {}
		nearGoal(w, 1, 15, 10, 11)
		step(w, d)
		local body = table.clone(w.snakes[1].body)
		t.expect(World.turn(w, 1, "Left")).toBe(false)
		local events = World.advance(w, 1.75, d)
		t.expect(#events).toBe(0)
		t.expect(w.phase).toBe("clear")
		t.expect(w.map).toBe(1)
		t.expect(w.snakes[1].body).toEqual(body)
	end)

	it(
		"then the next map starts: one more wall, the snake back to 4 segments at its spawn, Ready, a little faster",
		function()
			local d = drawOf(4)
			local w = World.new(1, d)
			w.snakes[1].lives = 2
			w.apples = {}
			nearGoal(w, 1, 15, 10, 11)
			step(w, d)
			local events = World.advance(w, 2, d)
			t.expect(find(events, "map").map).toBe(2)
			t.expect(w.map).toBe(2)
			t.expect(w.layout.map).toBe(2)
			t.expect(#w.layout.walls).toBe(1)
			t.expect(w.layout.side).toBe(20)
			t.expect(w.phase).toBe("play")
			t.expect(World.speed(w)).toBe(4.25)
			t.expect(World.goal(w)).toBe(14)
			local s = w.snakes[1]
			local sp = w.layout.spawns[1]
			t.expect(s.body).toEqual(line(sp.x, sp.y, sp.heading, 4))
			t.expect(s.state).toBe("ready")
			t.expect(s.score).toBe(110) -- kept
			t.expect(s.lives).toBe(2) -- kept
			t.expect(#w.apples).toBe(2)
		end
	)

	it("the next map plays at its own speed: 17 tiles in 4 s on map 2", function()
		local d = drawOf(9)
		local w = World.new(2, d)
		w.apples = {}
		nearGoal(w, 1, 15, 3, 11)
		step(w, d)
		World.advance(w, 2, d)
		t.expect(w.map).toBe(2)
		World.advance(w, 2, d) -- Ready is over
		local s = w.snakes[1]
		-- along row 2 of the 26-tile arena, far from map 2's wall near the middle
		s.body, s.heading, s.state, s.timer, s.turns = line(5, 2, "E", 4), "E", "alive", 0, {}
		w.apples = {}
		World.advance(w, 4, d)
		t.expect(s.state).toBe("alive")
		t.expect(s.body[1]).toEqual({ x = 22, y = 2 })
	end)

	it("map k clears at 10 + 2k with 100 x k, and map k+1 has k walls", function()
		local d = drawOf(5)
		local w = World.new(1, d)
		World.start(w, Maps.roll(3, 1, d), d)
		w.apples = {}
		-- along the top row, clear of map 3's walls (they keep a tile from the border)
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = line(17, 1, "E", Maps.goal(3) - 1), "E", "alive", 0
		w.apples = { { x = 18, y = 1 } }
		local events = step(w, d)
		t.expect(find(events, "cleared").map).toBe(3)
		t.expect(s.score).toBe(30 + 300)
		World.advance(w, 2, d)
		t.expect(w.map).toBe(4)
		t.expect(#w.layout.walls).toBe(3)
	end)

	it("every snake reaching the goal in the same step clears it and gets the bonus", function()
		local d = drawOf(6)
		local w = World.new(2, d)
		w.apples = {}
		nearGoal(w, 1, 15, 5, 11)
		nearGoal(w, 2, 15, 20, 11)
		local cleared = find(step(w, d), "cleared")
		t.expect(cleared.ids).toEqual({ 1, 2 })
		t.expect(w.snakes[1].score).toBe(110)
		t.expect(w.snakes[2].score).toBe(110)
	end)

	it(
		"the next map places every snake with lives at its own spawn, a dying one too; one with none stays out",
		function()
			local d = drawOf(7)
			local w = World.new(3, d)
			w.apples = {}
			nearGoal(w, 1, 15, 3, 11)
			local s2, s3 = w.snakes[2], w.snakes[3]
			s2.state, s2.timer, s2.lives = "dying", 1, 2
			s3.state, s3.timer, s3.lives = "over", 0, 0
			step(w, d)
			World.advance(w, 2, d)
			t.expect(w.map).toBe(2)
			t.expect(w.layout.side).toBe(Maps.side(3)) -- every snake of the world counts, the one that is out too
			t.expect(#w.apples).toBe(4)
			for id = 1, 2 do
				local sp = w.layout.spawns[id]
				t.expect(w.snakes[id].body).toEqual(line(sp.x, sp.y, sp.heading, 4))
				t.expect(w.snakes[id].state).toBe("ready")
			end
			t.expect(s2.lives).toBe(2)
			t.expect(s3.state).toBe("over")
		end
	)

	it(
		"the arena for the next map is sized from the player count, grown only if its walls do not fit",
		function()
			local d = drawOf(8)
			local w = World.new(4, d)
			t.expect(w.layout.side).toBe(34)
			w.apples = {}
			nearGoal(w, 1, 15, 3, 11)
			step(w, d)
			World.advance(w, 2, d)
			t.expect(w.layout.side).toBe(34)
			t.expect(w.layout.spawns).toEqual(Maps.spawns(34, 4))
		end
	)

	it("a map start forgets waiting turns and growth: the snake starts straight and 4 long", function()
		local d = drawOf(10)
		local w = World.new(1, d)
		w.apples = {}
		nearGoal(w, 1, 15, 10, 11)
		step(w, d)
		local s = w.snakes[1]
		s.turns, s.grow = { "Left" }, 2
		World.advance(w, 2, d)
		t.expect(w.map).toBe(2)
		t.expect(#s.turns).toBe(0)
		t.expect(s.grow).toBe(0)
		local sp = w.layout.spawns[1]
		local v = Maps.step(sp.heading)
		w.apples = {}
		World.advance(w, 2, d) -- Ready is over
		World.advance(w, 1 / World.speed(w), d)
		t.expect(s.body[1]).toEqual({ x = sp.x + v.x, y = sp.y + v.y })
		t.expect(#s.body).toBe(4)
	end)

	it("during MAP CLEAR only its timer runs: a dying snake is placed by the next map, not before", function()
		local d = drawOf(11)
		local w = World.new(2, d)
		w.apples = {}
		nearGoal(w, 1, 15, 5, 11)
		local s2 = w.snakes[2]
		s2.state, s2.timer, s2.lives = "dying", 0.5, 2
		step(w, d)
		t.expect(w.phase).toBe("clear")
		local events = World.advance(w, 2, d)
		local mapAt, placedAt = nil, nil
		for i, e in events do
			if e.kind == "map" and mapAt == nil then
				mapAt = i
			elseif e.kind == "placed" and (e :: any).id == 2 and placedAt == nil then
				placedAt = i
			end
		end
		t.expect(mapAt ~= nil and placedAt ~= nil).toBe(true)
		t.expect((placedAt :: number) > (mapAt :: number)).toBe(true)
		local sp = w.layout.spawns[2]
		t.expect(s2.body[1]).toEqual({ x = sp.x, y = sp.y })
	end)
end)
