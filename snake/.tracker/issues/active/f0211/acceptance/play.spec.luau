--!strict
-- f0211 acceptance: the rules played end to end. A simple bot clears map after map on its own, and the board stays
-- consistent through a game of several snakes turning at random.
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

local function key(x: number, y: number): string
	return `{x},{y}`
end

-- every tile a wall or a Ready or alive snake takes
local function blocked(w: World.World): { [string]: boolean }
	local out = {}
	for _, wall in w.layout.walls do
		for i = 0, wall.length - 1 do
			out[key(
				if wall.dir == "H" then wall.x + i else wall.x,
				if wall.dir == "V" then wall.y + i else wall.y
			)] =
				true
		end
	end
	for _, s in w.snakes do
		if s.state == "ready" or s.state == "alive" then
			for _, b in s.body do
				out[key(b.x, b.y)] = true
			end
		end
	end
	return out
end

-- the bot's next turn: the first move of a shortest path to an apple, else any move that stays on open tiles
local function choose(w: World.World, id: number): World.Turn?
	local s = w.snakes[id]
	local side = w.layout.side
	local block = blocked(w)
	block[key(s.body[#s.body].x, s.body[#s.body].y)] = nil -- the tail moves on
	local apples = {}
	for _, a in w.apples do
		apples[key(a.x, a.y)] = true
	end
	local options: { { turn: World.Turn?, heading: Maps.Heading } } = {
		{ turn = nil, heading = s.heading },
		{ turn = "Left", heading = Maps.turn(s.heading, "Left") },
		{ turn = "Right", heading = Maps.turn(s.heading, "Right") },
	}
	local function open(x: number, y: number): boolean
		return x >= 1 and y >= 1 and x <= side and y <= side and not block[key(x, y)]
	end
	local best, bestDist, fallback = nil, math.huge, nil
	for _, o in options do
		local v = Maps.step(o.heading)
		local hx, hy = s.body[1].x + v.x, s.body[1].y + v.y
		if open(hx, hy) then
			fallback = fallback or o
			-- breadth-first from the tile this move enters
			local seen, queue, head, dist = { [key(hx, hy)] = true }, { { hx, hy, 0 } }, 1, nil
			while head <= #queue do
				local q = queue[head]
				head += 1
				if apples[key(q[1], q[2])] then
					dist = q[3]
					break
				end
				for _, h: Maps.Heading in Maps.HEADINGS do
					local u = Maps.step(h)
					local nx, ny = q[1] + u.x, q[2] + u.y
					if open(nx, ny) and not seen[key(nx, ny)] then
						seen[key(nx, ny)] = true
						table.insert(queue, { nx, ny, q[3] + 1 })
					end
				end
			end
			if dist and dist < bestDist then
				best, bestDist = o, dist
			end
		end
	end
	local pick = best or fallback
	return if pick then pick.turn else nil
end

-- the board's invariants after any advance
local function consistent(w: World.World)
	local side = w.layout.side
	local walls = {}
	for _, wall in w.layout.walls do
		for i = 0, wall.length - 1 do
			walls[key(
				if wall.dir == "H" then wall.x + i else wall.x,
				if wall.dir == "V" then wall.y + i else wall.y
			)] =
				true
		end
	end
	local taken = {}
	for _, s in w.snakes do
		t.expect(s.lives >= 0 and s.lives <= 3).toBe(true)
		if s.state == "ready" or s.state == "alive" then
			t.expect(#s.body >= 4).toBe(true)
			for i, b in s.body do
				local k = key(b.x, b.y)
				t.expect(b.x >= 1 and b.y >= 1 and b.x <= side and b.y <= side).toBe(true)
				t.expect(walls[k] == nil and taken[k] == nil).toBe(true)
				taken[k] = true
				if i > 1 then
					local p = s.body[i - 1]
					t.expect(math.abs(p.x - b.x) + math.abs(p.y - b.y)).toBe(1)
				end
			end
			t.expect(#s.turns <= 2).toBe(true)
		end
	end
	for _, a in w.apples do
		local k = key(a.x, a.y)
		t.expect(walls[k] == nil and taken[k] == nil).toBe(true)
		taken[k] = true
	end
	if w.phase == "play" then
		t.expect(#w.apples).toBe(#w.snakes + 1)
	end
end

return t.spec("f0211 play", function(it)
	it("a bot that heads for the nearest apple clears maps 1 to 4 on its own", function()
		for seed = 1, 3 do
			local d = drawOf(seed)
			local w = World.new(1, d)
			local elapsed = 0
			while w.map < 5 and w.phase ~= "over" and elapsed < 600 do
				if w.phase == "play" and w.snakes[1].state == "alive" and #w.snakes[1].turns == 0 then
					local turn = choose(w, 1)
					if turn then
						World.turn(w, 1, turn :: World.Turn)
					end
				end
				local dt = 1 / World.speed(w)
				World.advance(w, dt, d)
				elapsed += dt
				consistent(w)
			end
			if w.map < 5 then
				error(`seed {seed}: the bot reached only map {w.map} ({w.phase}) in {elapsed} s`)
			end
			-- at least 6 + 2k apples on map k (from 4 segments to 10 + 2k), and the four bonuses
			t.expect(w.snakes[1].score >= 10 * 8 + 20 * 10 + 30 * 12 + 40 * 14 + 100 + 200 + 300 + 400)
				.toBe(true)
		end
	end)

	it(
		"the board stays consistent through a game of four snakes, one led by the bot, three turning at random",
		function()
			local d = drawOf(77)
			local turns = drawOf(78)
			local w = World.new(4, d)
			local deaths, eaten = 0, 0
			for _ = 1, 30 * 60 do
				local s1 = w.snakes[1]
				if w.phase == "play" and s1.state == "alive" and #s1.turns == 0 then
					local turn = choose(w, 1)
					if turn then
						World.turn(w, 1, turn :: World.Turn)
					end
				end
				for id = 2, 4 do
					if turns(6) == 1 then
						World.turn(w, id, if turns(2) == 1 then "Left" else "Right")
					end
				end
				for _, e in World.advance(w, 1 / 30, d) do
					if e.kind == "died" then
						deaths += 1
					elseif e.kind == "ate" then
						eaten += 1
					end
				end
				consistent(w)
				if w.phase == "over" then
					break
				end
			end
			-- the run did something: snakes died and ate
			t.expect(deaths > 0).toBe(true)
			t.expect(eaten > 0).toBe(true)
		end
	)
end)
