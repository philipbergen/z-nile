--!strict
-- f0214 acceptance: boost (snake/.tracker/game-design.md, "Movement"): double speed while held, sheds one tail
-- segment every 0.5 s (never below 4) into a crumb, validates inputs, handles half-step collisions, and is
-- frame-rate independent.
local Maps = require("@logic/Maps")
local World = require("@logic/World")
local t = require("@tests/lib/t")

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

local function line(x: number, y: number, heading: Maps.Heading, n: number): { Maps.Tile }
	local v = Maps.step(heading)
	local out = {}
	for i = 0, n - 1 do
		table.insert(out, { x = x - v.x * i, y = y - v.y * i })
	end
	return out
end

local function empty(map: number, side: number, players: number): Maps.Layout
	return { map = map, side = side, walls = {}, spawns = Maps.spawns(side, players) }
end

local function countEvents(events: { World.Event }, kind: string, id: number?): number
	local n = 0
	for _, e in events do
		if e.kind == kind and (id == nil or (e :: any).id == id) then
			n += 1
		end
	end
	return n
end

local function halfStep(w: World.World, d: Maps.Draw): { World.Event }
	return World.advance(w, 1 / (2 * World.speed(w)), d)
end

return t.spec("f0214 boost", function(it)
	it("boosting doubles speed on maps 1, 5, and 13 while non-boosting stays at map speed", function()
		for _, case in { { 1, 4 }, { 5, 5 }, { 13, 7 } } do
			local map, speed = case[1], case[2]
			local d = drawOf(10 + map)
			local w = World.new(2, d)
			World.start(w, empty(map, 26, 2), d)
			w.apples = {}
			local s1, s2 = w.snakes[1], w.snakes[2]
			s1.body, s1.heading, s1.state, s1.timer = line(5, 5, "E", 4), "E", "alive", 0
			s2.body, s2.heading, s2.state, s2.timer = line(5, 15, "E", 4), "E", "alive", 0
			t.expect(World.boost(w, 1, true)).toBe(true)
			World.advance(w, 1, d)
			t.expect(s1.body[1]).toEqual({ x = 5 + speed * 2, y = 5 })
			t.expect(s2.body[1]).toEqual({ x = 5 + speed, y = 15 })
		end
	end)

	it("sheds one tail segment every 0.5 s into a crumb while above 4 segments", function()
		local d = drawOf(20)
		local w = World.new(1, d)
		w.apples = {}
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = line(8, 10, "E", 6), "E", "alive", 0
		t.expect(World.boost(w, 1, true)).toBe(true)

		-- before 0.5 s: no shed yet
		local e1 = World.advance(w, 0.375, d)
		t.expect(#s.body).toBe(6)
		t.expect(#w.crumbs).toBe(0)
		t.expect(countEvents(e1, "shed", 1)).toBe(0)

		-- at 0.5 s: first shed drops a crumb on the vacated tail tile
		local e2 = World.advance(w, 0.125, d)
		t.expect(#s.body).toBe(5)
		t.expect(#w.crumbs).toBe(1)
		t.expect(countEvents(e2, "shed", 1)).toBe(1)
		-- crumb is at the shed tile and matches the shed event
		local shedTile: Maps.Tile? = nil
		for _, e in e2 do
			if e.kind == "shed" then
				shedTile = { x = e.x, y = e.y }
			end
		end
		t.expect(shedTile ~= nil).toBe(true)
		t.expect(w.crumbs[1]).toEqual(shedTile)
		-- shed runs before step at t = 0.5 s: snake was at x = 11..6 (len 6), so tail at (6, 10) is shed first
		t.expect(w.crumbs[1]).toEqual({ x = 6, y = 10 })

		-- at 1.0 s: second shed brings length to 4
		local e3 = World.advance(w, 0.5, d)
		t.expect(#s.body).toBe(4)
		t.expect(#w.crumbs).toBe(2)
		t.expect(countEvents(e3, "shed", 1)).toBe(1)

		-- on map 2 (speed = 4.25, half-step = 1/8.5 ~= 0.11765 s), shed at 0.5 s fires before the 5th half-step (~0.5882 s)
		local d2 = drawOf(202)
		local w2 = World.new(1, d2)
		World.start(w2, empty(2, 20, 1), d2)
		w2.apples = {}
		local s2 = w2.snakes[1]
		s2.body, s2.heading, s2.state, s2.timer = line(8, 10, "E", 6), "E", "alive", 0
		World.boost(w2, 1, true)
		local em2 = World.advance(w2, 0.55, d2)
		t.expect(#s2.body).toBe(5)
		t.expect(#w2.crumbs).toBe(1)
		t.expect(countEvents(em2, "shed", 1)).toBe(1)
		t.expect(s2.shedTimer).toBeNear(0.45, 1e-6)
	end)

	it("never sheds below 4 segments while still moving at double speed", function()
		local d = drawOf(21)
		local w = World.new(1, d)
		w.apples = {}
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = line(4, 10, "E", 4), "E", "alive", 0
		t.expect(World.boost(w, 1, true)).toBe(true)
		local events = World.advance(w, 1.5, d)
		t.expect(#s.body).toBe(4)
		t.expect(#w.crumbs).toBe(0)
		t.expect(countEvents(events, "shed", 1)).toBe(0)
		-- 1.5 s at 8 tiles/s = 12 tiles east: x = 4 + 12 = 16
		t.expect(s.body[1]).toEqual({ x = 16, y = 10 })
	end)

	it("releasing boost restores normal speed and preserves shedTimer against tap-boosting", function()
		local d = drawOf(22)
		local w = World.new(1, d)
		w.apples = {}
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = line(6, 10, "E", 6), "E", "alive", 0

		-- boost for 0.25 s (2 tiles), release for 0.25 s (1 tile), boost for 0.25 s (2 tiles -> cumulative 0.5 s)
		t.expect(World.boost(w, 1, true)).toBe(true)
		World.advance(w, 0.25, d)
		t.expect(#s.body).toBe(6)
		t.expect(s.body[1]).toEqual({ x = 8, y = 10 })

		t.expect(World.boost(w, 1, false)).toBe(true)
		World.advance(w, 0.25, d)
		t.expect(#s.body).toBe(6)
		t.expect(s.body[1]).toEqual({ x = 9, y = 10 })

		t.expect(World.boost(w, 1, true)).toBe(true)
		local events = World.advance(w, 0.25, d)
		t.expect(#s.body).toBe(5)
		t.expect(#w.crumbs).toBe(1)
		t.expect(countEvents(events, "shed", 1)).toBe(1)
		t.expect(s.body[1]).toEqual({ x = 11, y = 10 })
	end)

	it("World.boost validates inputs and respects snake and world state", function()
		local d = drawOf(23)
		local w = World.new(1, d)
		local s = w.snakes[1]
		s.state, s.timer = "alive", 0
		t.expect(World.boost(w, 1, "yes" :: any)).toBe(false)
		t.expect(World.boost(w, 1, nil :: any)).toBe(false)
		t.expect(World.boost(w, 2, true)).toBe(false)
		t.expect(s.boosting).toBe(false)

		s.state = "dying"
		t.expect(World.boost(w, 1, true)).toBe(false)
		s.state = "over"
		t.expect(World.boost(w, 1, true)).toBe(false)

		s.state = "alive"
		w.phase = "clear"
		t.expect(World.boost(w, 1, true)).toBe(false)
		w.phase = "over"
		t.expect(World.boost(w, 1, true)).toBe(false)
	end)

	it("a Ready snake may hold boost without moving or shedding until go", function()
		local d = drawOf(24)
		local w = World.new(1, d)
		w.apples = {}
		local s = w.snakes[1]
		s.body = line(6, 10, "E", 6)
		s.heading = "E"
		local start = table.clone(s.body)
		t.expect(World.boost(w, 1, true)).toBe(true)

		World.advance(w, 1.875, d)
		t.expect(s.state).toBe("ready")
		t.expect(s.body).toEqual(start)
		t.expect(#w.crumbs).toBe(0)

		-- at 2.0 s Ready ends and the full-step moves 1 tile; next 0.125 s half-step moves another tile
		World.advance(w, 0.25, d)
		t.expect(s.state).toBe("alive")
		t.expect(s.body[1]).toEqual({ x = 8, y = 10 })
		t.expect(#s.body).toBe(6)
	end)

	it("death and map start reset boost and shedTimer", function()
		local d = drawOf(25)
		local w = World.new(1, d)
		w.apples = {}
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = line(19, 10, "E", 6), "E", "alive", 0
		World.boost(w, 1, true)
		World.advance(w, 0.25, d) -- moves to 20, then 21 -> dies at border
		t.expect(s.state).toBe("dying")
		t.expect(s.boosting).toBe(false)
		t.expect(s.shedTimer).toBeNear(World.TUNING.boostShedSeconds, 1e-9)

		-- map start also resets boost, shedTimer, and halfStep
		s.state, s.timer, s.boosting, s.shedTimer = "alive", 0, true, 0.1
		w.halfStep = false
		World.start(w, empty(2, 20, 1), d)
		t.expect(s.boosting).toBe(false)
		t.expect(s.shedTimer).toBeNear(World.TUNING.boostShedSeconds, 1e-9)
		t.expect(w.halfStep).toBe(true)
		-- verify a non-boosting alive snake stays put on the first half-step after World.start
		w.apples = {}
		s.body, s.heading, s.state, s.timer = line(8, 10, "E", 4), "E", "alive", 0
		halfStep(w, d)
		t.expect(s.body[1]).toEqual({ x = 8, y = 10 })
	end)

	it("on a half-step a non-boosting snake is solid and boosting head-on kills both", function()
		-- Case 1: boosting snake 1 enters stationary non-boosting snake 2 on a half-step
		local d1 = drawOf(26)
		local w1 = World.new(2, d1)
		w1.apples = {}
		local a1, a2 = w1.snakes[1], w1.snakes[2]
		a1.body, a1.heading, a1.state, a1.timer = line(9, 10, "E", 4), "E", "alive", 0
		a2.body, a2.heading, a2.state, a2.timer = line(10, 7, "N", 4), "N", "alive", 0 -- tail at (10, 10)
		World.boost(w1, 1, true)
		local e1 = halfStep(w1, d1)
		t.expect(countEvents(e1, "died", 1)).toBe(1)
		t.expect(countEvents(e1, "died", 2)).toBe(0)
		t.expect(a2.state).toBe("alive")
		t.expect(a2.body[1]).toEqual({ x = 10, y = 7 })

		-- Case 2: two boosting snakes collide head-on on a half-step -> both die
		local d2 = drawOf(27)
		local w2 = World.new(2, d2)
		w2.apples = {}
		local b1, b2 = w2.snakes[1], w2.snakes[2]
		b1.body, b1.heading, b1.state, b1.timer = line(5, 10, "E", 4), "E", "alive", 0
		b2.body, b2.heading, b2.state, b2.timer = line(7, 10, "W", 4), "W", "alive", 0
		World.boost(w2, 1, true)
		World.boost(w2, 2, true)
		local e2 = halfStep(w2, d2)
		t.expect(countEvents(e2, "died", 1)).toBe(1)
		t.expect(countEvents(e2, "died", 2)).toBe(1)

		-- Case 3: buffered U-turn completes in two half-steps while boosting
		local d3 = drawOf(28)
		local w3 = World.new(1, d3)
		w3.apples = {}
		local c1 = w3.snakes[1]
		c1.body, c1.heading, c1.state, c1.timer = line(10, 10, "E", 4), "E", "alive", 0
		World.boost(w3, 1, true)
		World.turn(w3, 1, "Left")
		World.turn(w3, 1, "Left")
		World.advance(w3, 0.25, d3) -- 2 ticks on map 1 while boosting
		t.expect(c1.state).toBe("alive")
		t.expect(c1.heading).toBe("W")
		t.expect(c1.body[1]).toEqual({ x = 9, y = 9 })
	end)

	it("boosting and shedding are frame-rate independent", function()
		local function snapshot(w: World.World): any
			local s = w.snakes[1]
			return {
				body = s.body,
				heading = s.heading,
				state = s.state,
				boosting = s.boosting,
				crumbs = w.crumbs,
			}
		end
		for _, map in { 1, 2 } do
			local function run(cuts: { number }): World.World
				local d = drawOf(29 + map)
				local w = World.new(1, d)
				if map > 1 then
					World.start(w, empty(map, 20, 1), d)
				end
				w.apples = {}
				local s = w.snakes[1]
				s.body, s.heading, s.state, s.timer = line(8, 10, "E", 7), "E", "alive", 0
				World.boost(w, 1, true)
				local left, i = 1.25, 0
				while left > 1e-12 do
					i += 1
					local dt = math.min(left, cuts[(i - 1) % #cuts + 1])
					World.advance(w, dt, d)
					left -= dt
				end
				return w
			end
			local whole = run({ 1.25 })
			t.expect(#whole.crumbs).toBe(2)
			for _, cuts in { { 1 / 60 }, { 1 / 30 }, { 0.07, 0.013 } } do
				local w = run(cuts)
				t.expect(snapshot(w)).toEqual(snapshot(whole))
				t.expect(math.abs(w.snakes[1].shedTimer - whole.snakes[1].shedTimer) < 1e-6).toBe(true)
			end
		end
	end)
end)
