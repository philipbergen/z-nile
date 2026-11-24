--!strict
-- f0211 acceptance: death, lives and respawn (snake/.tracker/game-design.md, "Death, lives and revives"): a head
-- entering a wall, the border or any snake's body dies, two heads meeting kill both, 3 lives, a 1.5 s wait, a
-- respawn with 4 segments at the free tile farthest from every head, and a 2 s Ready.
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

local function line(x: number, y: number, heading: Maps.Heading, n: number?): { Maps.Tile }
	local v = Maps.step(heading)
	local out = {}
	for i = 0, (n or 4) - 1 do
		table.insert(out, { x = x - v.x * i, y = y - v.y * i })
	end
	return out
end

-- a world of `players` whose snakes are hand-placed (`bodies[i]` with `headings[i]`), alive, with no apples
local function world(
	players: number,
	seed: number,
	bodies: { { Maps.Tile } },
	headings: { Maps.Heading }
): (World.World, Maps.Draw)
	local d = drawOf(seed)
	local w = World.new(players, d)
	for i, s in w.snakes do
		if bodies[i] then
			s.body, s.heading, s.state, s.timer, s.turns = bodies[i], headings[i], "alive", 0, {}
		end
	end
	w.apples = {}
	return w, d
end

local function count(events: { World.Event }, kind: string, id: number?): number
	local n = 0
	for _, e in events do
		if e.kind == kind and (id == nil or (e :: any).id == id) then
			n += 1
		end
	end
	return n
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

-- every placement the respawn may choose for snake `id`: a head and heading whose 4 body tiles are on the board,
-- off walls, snakes and apples, with the 3 tiles ahead on the board and off walls and snakes
local function placements(w: World.World, id: number): { { x: number, y: number, heading: Maps.Heading } }
	local walls = wallKeys(w.layout)
	local snakes, apples = {}, {}
	for _, s in w.snakes do
		if s.id ~= id and (s.state == "ready" or s.state == "alive") then
			for _, b in s.body do
				snakes[`{b.x},{b.y}`] = true
			end
		end
	end
	for _, a in w.apples do
		apples[`{a.x},{a.y}`] = true
	end
	local side = w.layout.side
	local function open(x: number, y: number, body: boolean): boolean
		local k = `{x},{y}`
		return x >= 1
			and y >= 1
			and x <= side
			and y <= side
			and not walls[k]
			and not snakes[k]
			and not (body and apples[k])
	end
	local out = {}
	for y = 1, side do
		for x = 1, side do
			for _, h: Maps.Heading in Maps.HEADINGS do
				local v = Maps.step(h)
				local ok = true
				for i = 0, 3 do
					ok = ok and open(x - v.x * i, y - v.y * i, true)
				end
				for i = 1, 3 do
					ok = ok and open(x + v.x * i, y + v.y * i, false)
				end
				if ok then
					table.insert(out, { x = x, y = y, heading = h })
				end
			end
		end
	end
	return out
end

local function nearestHead(w: World.World, id: number, x: number, y: number): number
	local best = math.huge
	for _, s in w.snakes do
		if s.id ~= id and (s.state == "ready" or s.state == "alive") then
			best = math.min(best, math.abs(s.body[1].x - x) + math.abs(s.body[1].y - y))
		end
	end
	return best
end

local function clearance(w: World.World, x: number, y: number): number
	local side = w.layout.side
	local best = math.min(x, y, side + 1 - x, side + 1 - y)
	for _, wall in w.layout.walls do
		for i = 0, wall.length - 1 do
			local wx, wy =
				if wall.dir == "H" then wall.x + i else wall.x, if wall.dir == "V" then wall.y + i else wall.y
			best = math.min(best, math.max(math.abs(wx - x), math.abs(wy - y)))
		end
	end
	return best
end

-- run snake `id` into the border until it has died `n` times, returning the events of the last death's step
local function kill(w: World.World, d: Maps.Draw, id: number): { World.Event }
	local s = w.snakes[id]
	local side = w.layout.side
	s.body, s.heading, s.state, s.timer, s.turns = line(side, 2, "E"), "E", "alive", 0, {}
	return step(w, d)
end

return t.spec("f0211 deaths", function(it)
	it("a head entering the border dies: a life is lost and the snake is off the board", function()
		local w, d = world(1, 1, { line(20, 10, "E") }, { "E" })
		local events = step(w, d)
		local s = w.snakes[1]
		t.expect(count(events, "died", 1)).toBe(1)
		t.expect(s.state).toBe("dying")
		t.expect(s.lives).toBe(2)
		for _, e in events do
			if e.kind == "died" then
				t.expect({ e.x, e.y }).toEqual({ 21, 10 })
			end
		end
		-- the other three borders too
		local borders: { { x: number, y: number, heading: Maps.Heading } } = {
			{ x = 1, y = 10, heading = "W" },
			{ x = 10, y = 1, heading = "N" },
			{ x = 10, y = 20, heading = "S" },
		}
		for _, case in borders do
			local w2, d2 = world(1, 2, { line(case.x, case.y, case.heading) }, { case.heading })
			t.expect(count(step(w2, d2), "died", 1)).toBe(1)
		end
	end)

	it("a head entering a wall dies", function()
		local d = drawOf(3)
		local w = World.new(1, d)
		World.start(w, {
			map = 2,
			side = 20,
			walls = { { x = 8, y = 8, dir = "V", length = 4 } },
			spawns = Maps.spawns(20, 1),
		}, d)
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = line(6, 10, "E"), "E", "alive", 0
		w.apples = {}
		t.expect(count(step(w, d), "died", 1)).toBe(0)
		t.expect(count(step(w, d), "died", 1)).toBe(1)
		t.expect(s.lives).toBe(2)
	end)

	it("a head entering its own body dies", function()
		local body = {
			{ x = 5, y = 5 },
			{ x = 6, y = 5 },
			{ x = 6, y = 4 },
			{ x = 5, y = 4 },
			{ x = 4, y = 4 },
			{ x = 4, y = 3 },
		}
		local w, d = world(1, 4, { body }, { "W" })
		World.turn(w, 1, "Right") -- W turns to N, into (5, 4)
		t.expect(count(step(w, d), "died", 1)).toBe(1)
	end)

	it("a head may enter the tile its own tail leaves in the same step", function()
		local body = { { x = 5, y = 5 }, { x = 5, y = 6 }, { x = 6, y = 6 }, { x = 6, y = 5 } }
		local w, d = world(1, 5, { body }, { "N" })
		World.turn(w, 1, "Right") -- N turns to E, into the tail's (6, 5)
		t.expect(count(step(w, d), "died", 1)).toBe(0)
		t.expect(w.snakes[1].body[1]).toEqual({ x = 6, y = 5 })
	end)

	it("a head entering another snake's body dies, and only that snake", function()
		local w, d = world(2, 6, { line(9, 9, "E"), line(10, 8, "N") }, { "E", "N" })
		-- snake 2 moves to (10, 7)..(10, 10); snake 1 enters (10, 9), its third segment
		local events = step(w, d)
		t.expect(count(events, "died", 1)).toBe(1)
		t.expect(count(events, "died", 2)).toBe(0)
		t.expect(w.snakes[2].state).toBe("alive")
	end)

	it("two heads entering one tile kill both", function()
		local w, d = world(2, 7, { line(5, 5, "E"), line(7, 5, "W") }, { "E", "W" })
		local events = step(w, d)
		t.expect(count(events, "died", 1)).toBe(1)
		t.expect(count(events, "died", 2)).toBe(1)
	end)

	it("two heads swapping tiles kill both", function()
		local w, d = world(2, 8, { line(5, 5, "E"), line(6, 5, "W") }, { "E", "W" })
		local events = step(w, d)
		t.expect(count(events, "died", 1)).toBe(1)
		t.expect(count(events, "died", 2)).toBe(1)
	end)

	it(
		"a head may enter the tile another snake's tail leaves in the same step, unless that snake grows",
		function()
			local w, d = world(2, 9, { line(5, 5, "E"), line(6, 2, "N") }, { "E", "N" })
			-- snake 2 is (6, 2)..(6, 5) going north: its tail leaves (6, 5) as snake 1 enters it
			local events = step(w, d)
			t.expect(count(events, "died")).toBe(0)
			t.expect(w.snakes[1].body[1]).toEqual({ x = 6, y = 5 })
			-- the same, with an apple in front of snake 2: its tail stays and snake 1 dies
			local w2, d2 = world(2, 9, { line(5, 5, "E"), line(6, 2, "N") }, { "E", "N" })
			w2.apples = { { x = 6, y = 1 } }
			local events2 = step(w2, d2)
			t.expect(count(events2, "died", 1)).toBe(1)
			t.expect(count(events2, "died", 2)).toBe(0)
			t.expect(#w2.snakes[2].body).toBe(5)
		end
	)

	it("a Ready snake is solid: a head entering it dies, and the Ready snake does not", function()
		local w, d = world(2, 10, { line(9, 9, "E") }, { "E" })
		local s2 = w.snakes[2]
		s2.body, s2.heading, s2.state, s2.timer = line(10, 8, "N"), "N", "ready", 2
		local events = step(w, d)
		t.expect(count(events, "died", 1)).toBe(1)
		t.expect(count(events, "died", 2)).toBe(0)
		t.expect(s2.state).toBe("ready")
		t.expect(s2.body).toEqual(line(10, 8, "N"))
	end)

	it("a dying snake is off the board: another may pass where it died", function()
		local w, d = world(2, 11, { line(26, 10, "E"), line(24, 12, "N") }, { "E", "N" })
		step(w, d) -- snake 1 dies at the border of the 26-tile arena, its body (23..26, 10) gone
		t.expect(w.snakes[1].state).toBe("dying")
		local events = step(w, d) -- snake 2 enters (24, 10)
		t.expect(count(events, "died", 2)).toBe(0)
		t.expect(w.snakes[2].body[1]).toEqual({ x = 24, y = 10 })
	end)

	it(
		"a death waits 1.5 s, then the snake respawns with 4 segments, Ready for 2 s, on the same map",
		function()
			local w, d = world(1, 12, { line(20, 10, "E") }, { "E" })
			step(w, d)
			local s = w.snakes[1]
			t.expect(count(World.advance(w, 1.25, d), "placed", 1)).toBe(0)
			t.expect(s.state).toBe("dying")
			t.expect(count(World.advance(w, 0.25, d), "placed", 1)).toBe(1)
			t.expect(s.state).toBe("ready")
			t.expect(#s.body).toBe(4)
			t.expect(w.map).toBe(1)
			local placed = table.clone(s.body)
			t.expect(count(World.advance(w, 1.75, d), "go", 1)).toBe(0)
			t.expect(s.body).toEqual(placed)
			t.expect(count(World.advance(w, 0.25, d), "go", 1)).toBe(1)
			t.expect(s.state).toBe("alive")
			t.expect(s.lives).toBe(2)
		end
	)

	it("turns are refused while dying, and a death forgets the buffered ones", function()
		local w, d = world(1, 13, { line(10, 1, "E") }, { "E" })
		t.expect(World.turn(w, 1, "Left")).toBe(true) -- E turns to N, out of the top
		t.expect(World.turn(w, 1, "Left")).toBe(true) -- still waiting when the snake dies
		t.expect(count(step(w, d), "died", 1)).toBe(1)
		t.expect(#w.snakes[1].turns).toBe(0)
		t.expect(World.turn(w, 1, "Left")).toBe(false)
		World.advance(w, 1.5, d)
		t.expect(w.snakes[1].state).toBe("ready")
		t.expect(#w.snakes[1].turns).toBe(0)
	end)

	it("3 lives: the third death is game over, and a solo game then stands still", function()
		local d = drawOf(14)
		local w = World.new(1, d)
		local s = w.snakes[1]
		for life = 3, 1, -1 do
			t.expect(s.lives).toBe(life)
			local events = kill(w, d, 1)
			t.expect(count(events, "died", 1)).toBe(1)
			t.expect(count(events, "over", 1)).toBe(if life == 1 then 1 else 0)
			if life > 1 then
				World.advance(w, 1.5, d)
				t.expect(s.state).toBe("ready")
			end
		end
		t.expect(s.lives).toBe(0)
		t.expect(s.state).toBe("over")
		t.expect(w.phase).toBe("over")
		t.expect(World.turn(w, 1, "Left")).toBe(false)
		local before = table.clone(w.apples)
		t.expect(#World.advance(w, 30, d)).toBe(0)
		t.expect(s.state).toBe("over")
		t.expect(w.apples).toEqual(before)
	end)

	it("with two snakes, one snake's game over leaves the other playing", function()
		local d = drawOf(15)
		local w = World.new(2, d)
		for _ = 1, 3 do
			kill(w, d, 1)
			World.advance(w, 1.5, d)
		end
		t.expect(w.snakes[1].state).toBe("over")
		t.expect(w.phase).toBe("play")
		World.advance(w, 1, d)
		t.expect(w.snakes[1].state).toBe("over") -- an over snake never respawns
		t.expect(w.phase).toBe("play")
	end)

	it("a respawn takes the free tile farthest from every other snake's head", function()
		for seed = 1, 12 do
			local d = drawOf(seed * 13)
			local w = World.new(2, d)
			World.start(w, Maps.roll(1 + seed % 6, 2, d), d)
			-- snake 2 stands Ready (solid, still) at a rolled placement, so the board does not move meanwhile
			local s2 = w.snakes[2]
			local spots = placements(w, 2)
			local p2 = spots[d(#spots)]
			s2.body, s2.heading, s2.state, s2.timer = line(p2.x, p2.y, p2.heading), p2.heading, "ready", 100
			kill(w, d, 1)
			local events = World.advance(w, 1.5, d)
			local s1 = w.snakes[1]
			t.expect(count(events, "placed", 1)).toBe(1)
			t.expect(s1.state).toBe("ready")
			-- the placement is one of the allowed ones (snake 1 itself is off the board while it waited)...
			local stash = s1.body
			s1.state = "dying"
			local allowed = placements(w, 1)
			s1.state = "ready"
			local best, chosen = -1, nil
			for _, p in allowed do
				best = math.max(best, nearestHead(w, 1, p.x, p.y))
				if p.x == stash[1].x and p.y == stash[1].y and p.heading == s1.heading then
					chosen = p
				end
			end
			t.expect(chosen ~= nil).toBe(true)
			t.expect(s1.body).toEqual(line(stash[1].x, stash[1].y, s1.heading))
			-- ...and no allowed one is farther from snake 2's head
			t.expect(nearestHead(w, 1, stash[1].x, stash[1].y)).toBe(best)
		end
	end)

	it(
		"with no other snake on the board, a respawn takes the tile farthest from the walls and the border",
		function()
			for seed = 1, 8 do
				local d = drawOf(seed * 17)
				local w = World.new(1, d)
				World.start(w, Maps.roll(seed, 1, d), d)
				kill(w, d, 1)
				World.advance(w, 1.5, d)
				local s = w.snakes[1]
				t.expect(s.state).toBe("ready")
				s.state = "dying"
				local best = -1
				for _, p in placements(w, 1) do
					best = math.max(best, clearance(w, p.x, p.y))
				end
				s.state = "ready"
				t.expect(clearance(w, s.body[1].x, s.body[1].y)).toBe(best)
			end
		end
	)

	it("with no free placement, a dying snake waits and tries again later", function()
		local w, d = world(1, 16, { line(20, 10, "E") }, { "E" })
		step(w, d)
		w.layout = { map = 1, side = 6, walls = {}, spawns = {} } -- no 7-tile strip fits in 6
		local events = World.advance(w, 5, d)
		t.expect(count(events, "placed", 1)).toBe(0)
		t.expect(w.snakes[1].state).toBe("dying")
		w.layout = { map = 1, side = 20, walls = {}, spawns = Maps.spawns(20, 1) }
		t.expect(count(World.advance(w, 0.5, d), "placed", 1)).toBe(1)
	end)

	it("while dying, a snake keeps the body it died with", function()
		local w, d = world(1, 17, { line(20, 10, "E") }, { "E" })
		step(w, d)
		t.expect(w.snakes[1].state).toBe("dying")
		t.expect(w.snakes[1].body).toEqual(line(20, 10, "E"))
	end)

	it("an out snake's body stays as it died and is off the board", function()
		local d = drawOf(18)
		local w = World.new(2, d)
		for _ = 1, 3 do
			kill(w, d, 1)
			World.advance(w, 1.5, d)
		end
		local s1, s2 = w.snakes[1], w.snakes[2]
		local side = w.layout.side
		t.expect(s1.state).toBe("over")
		t.expect(s1.body).toEqual(line(side, 2, "E"))
		-- snake 2 enters (side - 1, 2), a tile of the out body, and lives
		s2.body, s2.heading, s2.state, s2.timer, s2.turns = line(side - 1, 3, "N"), "N", "alive", 0, {}
		w.apples = {}
		t.expect(count(step(w, d), "died", 2)).toBe(0)
		t.expect(s2.body[1]).toEqual({ x = side - 1, y = 2 })
	end)

	it(
		"on a crowded board, World.safest returns an allowed placement farthest from every other head",
		function()
			local found = 0
			for seed = 1, 40 do
				local d = drawOf(seed * 7 + 3)
				local w = World.new(6, d)
				w.layout = { map = 1, side = 9, walls = {}, spawns = {} }
				w.apples = {}
				for _, s in w.snakes do
					s.state, s.timer = "dying", 100
				end
				-- five other snakes stand Ready at rolled placements, and a dozen apples lie about
				for id = 2, 6 do
					local spots = placements(w, id)
					if #spots > 0 then
						local p = spots[d(#spots)]
						local s = w.snakes[id]
						s.body, s.heading, s.state, s.timer =
							line(p.x, p.y, p.heading), p.heading, "ready", 100
					end
				end
				for _ = 1, 12 do
					table.insert(w.apples, { x = d(9), y = d(9) })
				end
				local allowed = placements(w, 1)
				local got = World.safest(w, 1)
				if #allowed == 0 then
					t.expect(got).toBe(nil)
				else
					found += 1
					t.expect(got ~= nil).toBe(true)
					local g = got :: Maps.Spawn
					local best, inside = -1, false
					for _, p in allowed do
						best = math.max(best, nearestHead(w, 1, p.x, p.y))
						inside = inside or (p.x == g.x and p.y == g.y and p.heading == g.heading)
					end
					t.expect(inside).toBe(true)
					t.expect(nearestHead(w, 1, g.x, g.y)).toBe(best)
				end
			end
			t.expect(found >= 10).toBe(true)
		end
	)
end)
