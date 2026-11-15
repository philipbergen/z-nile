--!strict
-- f0211 acceptance: movement (snake/.tracker/game-design.md, "Movement"): the start, the Ready, one tile per step at
-- the map's speed, Left and Right relative to the heading, two buffered turns, and a clock that does not depend
-- on how time is cut.
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

-- one step of the map's clock
local function step(w: World.World, d: Maps.Draw): { World.Event }
	return World.advance(w, 1 / World.speed(w), d)
end

-- a solo world whose snake is hand-placed, moving, with no apples in the way
local function solo(seed: number, body: { Maps.Tile }, heading: Maps.Heading): (World.World, Maps.Draw)
	local d = drawOf(seed)
	local w = World.new(1, d)
	local s = w.snakes[1]
	s.body, s.heading, s.state, s.timer, s.turns = body, heading, "alive", 0, {}
	w.apples = {}
	return w, d
end

local function east(x: number, y: number): { Maps.Tile }
	return { { x = x, y = y }, { x = x - 1, y = y }, { x = x - 2, y = y }, { x = x - 3, y = y } }
end

-- a hand-made empty arena for map `map`
local function empty(map: number, side: number, players: number): Maps.Layout
	return { map = map, side = side, walls = {}, spawns = Maps.spawns(side, players) }
end

return t.spec("f0211 moves", function(it)
	it(
		"a new world is map 1: every snake has 4 segments at its own spawn, 3 lives, no score, and is Ready",
		function()
			local w = World.new(3, drawOf(1))
			t.expect(w.map).toBe(1)
			t.expect(w.phase).toBe("play")
			t.expect(w.layout.side).toBe(Maps.side(3))
			t.expect(#w.snakes).toBe(3)
			for i, s in w.snakes do
				local sp = w.layout.spawns[i]
				t.expect(s.id).toBe(i)
				t.expect(#s.body).toBe(4)
				t.expect(s.body[1]).toEqual({ x = sp.x, y = sp.y })
				t.expect(s.heading).toBe(sp.heading)
				local d = Maps.step(sp.heading)
				for k = 2, 4 do
					t.expect(s.body[k]).toEqual({ x = sp.x - d.x * (k - 1), y = sp.y - d.y * (k - 1) })
				end
				t.expect(s.lives).toBe(3)
				t.expect(s.score).toBe(0)
				t.expect(s.state).toBe("ready")
			end
		end
	)

	it("a Ready snake stays put for 2 s, then moves", function()
		local d = drawOf(2)
		local w = World.new(1, d)
		local start = table.clone(w.snakes[1].body)
		World.advance(w, 1.9, d)
		t.expect(w.snakes[1].state).toBe("ready")
		t.expect(w.snakes[1].body).toEqual(start)
		local events = World.advance(w, 0.5, d)
		t.expect(w.snakes[1].state).toBe("alive")
		-- straight on along its heading: 1 or 2 steps in the half second, however the clock is phased
		local v = Maps.step(w.snakes[1].heading)
		local dx, dy = w.snakes[1].body[1].x - start[1].x, w.snakes[1].body[1].y - start[1].y
		local ahead = dx * v.x + dy * v.y
		t.expect(ahead >= 1 and ahead <= 2).toBe(true)
		t.expect(dx * v.y - dy * v.x).toBe(0)
		local went = false
		for _, e in events do
			went = went or (e.kind == "go" and e.id == 1)
		end
		t.expect(went).toBe(true)
	end)

	it("an alive snake moves one tile per step, 4 tiles a second on map 1, its body following", function()
		local w, d = solo(3, east(5, 10), "E")
		World.advance(w, 0.5, d)
		t.expect(w.snakes[1].body).toEqual(east(7, 10))
		World.advance(w, 0.5, d)
		t.expect(w.snakes[1].body).toEqual(east(9, 10))
	end)

	it("on map k it moves at the map's speed: 5 tiles a second on map 5, 7 on map 13 and later", function()
		for _, case in { { 5, 5 }, { 13, 7 }, { 20, 7 } } do
			local d = drawOf(4)
			local w = World.new(1, d)
			World.start(w, empty(case[1], 20, 1), d)
			t.expect(World.speed(w)).toBe(case[2])
			local s = w.snakes[1]
			s.body, s.heading, s.state, s.timer = east(5, 10), "E", "alive", 0
			w.apples = {}
			World.advance(w, 1, d)
			t.expect(s.body[1]).toEqual({ x = 5 + case[2], y = 10 })
		end
	end)

	it("a turn is Left or Right of the heading, and waits for the next step", function()
		local w, d = solo(5, east(10, 10), "E")
		t.expect(World.turn(w, 1, "Left")).toBe(true)
		t.expect(w.snakes[1].heading).toBe("E")
		step(w, d)
		t.expect(w.snakes[1].heading).toBe("N")
		t.expect(w.snakes[1].body[1]).toEqual({ x = 10, y = 9 })
		step(w, d)
		t.expect(w.snakes[1].body[1]).toEqual({ x = 10, y = 8 })
		t.expect(World.turn(w, 1, "Right")).toBe(true)
		step(w, d)
		t.expect(w.snakes[1].heading).toBe("E")
		t.expect(w.snakes[1].body[1]).toEqual({ x = 11, y = 8 })
	end)

	it("a quick Left, Left makes a U-turn over two tiles", function()
		local w, d = solo(6, east(10, 10), "E")
		t.expect(World.turn(w, 1, "Left")).toBe(true)
		t.expect(World.turn(w, 1, "Left")).toBe(true)
		step(w, d)
		t.expect(w.snakes[1].body[1]).toEqual({ x = 10, y = 9 })
		step(w, d)
		t.expect(w.snakes[1].body[1]).toEqual({ x = 9, y = 9 })
		t.expect(w.snakes[1].heading).toBe("W")
		step(w, d)
		t.expect(w.snakes[1].state).toBe("alive")
		t.expect(w.snakes[1].body)
			.toEqual({ { x = 8, y = 9 }, { x = 9, y = 9 }, { x = 10, y = 9 }, { x = 10, y = 10 } })
	end)

	it("up to two turns wait; a third is dropped", function()
		local w, d = solo(7, east(10, 10), "E")
		t.expect(World.turn(w, 1, "Left")).toBe(true)
		t.expect(World.turn(w, 1, "Right")).toBe(true)
		t.expect(World.turn(w, 1, "Left")).toBe(false)
		step(w, d) -- Left: N
		step(w, d) -- Right: E
		step(w, d) -- straight on: the third was dropped
		t.expect(w.snakes[1].body[1]).toEqual({ x = 12, y = 9 })
		t.expect(w.snakes[1].heading).toBe("E")
		-- once a turn is used, another fits
		t.expect(World.turn(w, 1, "Left")).toBe(true)
		t.expect(World.turn(w, 1, "Left")).toBe(true)
		step(w, d)
		t.expect(World.turn(w, 1, "Right")).toBe(true)
	end)

	it("there is no Back: anything but Left or Right is not a turn", function()
		local w, d = solo(8, east(10, 10), "E")
		t.expect(World.turn(w, 1, "Back" :: any)).toBe(false)
		t.expect(World.turn(w, 1, "Up" :: any)).toBe(false)
		t.expect(World.turn(w, 2, "Left")).toBe(false) -- no such snake
		step(w, d)
		t.expect(w.snakes[1].body[1]).toEqual({ x = 11, y = 10 })
	end)

	it("a Ready snake may buffer its first turns", function()
		local d = drawOf(9)
		local w = World.new(1, d)
		local head = table.clone(w.snakes[1].body[1])
		local heading: Maps.Heading = w.snakes[1].heading
		t.expect(World.turn(w, 1, "Left")).toBe(true)
		World.advance(w, 2, d)
		while w.snakes[1].body[1].x == head.x and w.snakes[1].body[1].y == head.y do
			step(w, d)
		end
		local left: Maps.Heading = Maps.turn(heading, "Left")
		local v = Maps.step(left)
		t.expect(w.snakes[1].body[1]).toEqual({ x = head.x + v.x, y = head.y + v.y })
	end)

	it("the same draws and turns give the same game, however the time is cut", function()
		-- spend `total` seconds in slices taken from `cuts` in turn, the last one cut short to land on `total`
		local function spend(w: World.World, d: Maps.Draw, total: number, cuts: { number })
			local left, i = total, 0
			while left > 0 do
				i += 1
				local dt = math.min(left, cuts[(i - 1) % #cuts + 1])
				World.advance(w, dt, d)
				left -= dt
			end
		end
		local function run(cuts: { number }): World.World
			local d = drawOf(11)
			local w = World.new(2, d)
			spend(w, d, 3, cuts)
			World.turn(w, 1, "Left")
			World.turn(w, 2, "Right")
			spend(w, d, 3, cuts)
			return w
		end
		local whole = run({ 6 })
		for _, cuts in { { 1 / 64 }, { 1 / 32, 0.125, 0.375, 0.0625 }, { 0.5 } } do
			local w = run(cuts)
			t.expect(w.snakes).toEqual(whole.snakes)
			t.expect(w.apples).toEqual(whole.apples)
		end
	end)

	it("a Ready snake moves on the step its Ready ends: at 2 s on map 1, the 8th step", function()
		local d = drawOf(12)
		local w = World.new(1, d)
		local s = w.snakes[1]
		local start = table.clone(s.body[1])
		local v = Maps.step(s.heading)
		World.advance(w, 2, d)
		t.expect(s.state).toBe("alive")
		t.expect(s.body[1]).toEqual({ x = start.x + v.x, y = start.y + v.y })
	end)

	it("real frame rates give the same game: 1/60, 1/30, 0.1 and a ragged pair, on maps 1 and 2", function()
		-- the game, not the float timers: those may differ by rounding, within 1e-6 s
		local function game(w: World.World): any
			local snakes = {}
			for _, s in w.snakes do
				table.insert(snakes, {
					body = s.body,
					heading = s.heading,
					state = s.state,
					lives = s.lives,
					score = s.score,
					turns = s.turns,
					grow = s.grow,
				})
			end
			return { map = w.map, phase = w.phase, apples = w.apples, snakes = snakes }
		end
		local function spend(
			w: World.World,
			d: Maps.Draw,
			total: number,
			cuts: { number },
			at: number
		): number
			local left, i = total, at
			while left > 1e-12 do
				i += 1
				local dt = math.min(left, cuts[(i - 1) % #cuts + 1])
				World.advance(w, dt, d)
				left -= dt
			end
			return i
		end
		-- 40 s of play; at every 0.25 s mark each snake may turn, from its own seeded draw
		local function play(players: number, map: number, cuts: { number }): (World.World, number)
			local d = drawOf(21 + players * 10 + map)
			local turns = drawOf(99 + players * 10 + map)
			local w = World.new(players, d)
			if map > 1 then
				World.start(w, Maps.roll(map, players, d), d)
			end
			local deaths, i = 0, 0
			for _ = 1, 160 do
				i = spend(w, d, 0.25, cuts, i)
				for id = 1, players do
					if turns(4) == 1 then
						World.turn(w, id, if turns(2) == 1 then "Left" else "Right")
					end
				end
			end
			for _, s in w.snakes do
				deaths += 3 - s.lives
			end
			return w, deaths
		end
		for _, case in { { 1, 1 }, { 3, 1 }, { 1, 2 }, { 3, 2 } } do
			local whole, deaths = play(case[1], case[2], { 0.25 })
			t.expect(deaths > 0).toBe(true) -- deaths, waits and Readies happened on the way
			for _, cuts in { { 1 / 60 }, { 1 / 30 }, { 0.1 }, { 0.07, 0.013 } } do
				local w = play(case[1], case[2], cuts)
				t.expect(game(w)).toEqual(game(whole))
				for id, s in w.snakes do
					t.expect(math.abs(s.timer - whole.snakes[id].timer) < 1e-6).toBe(true)
				end
			end
		end
	end)
end)
