--!strict
-- f0214 acceptance: crumbs (snake/.tracker/game-design.md, "Food"): when a snake dies in a shared arena, every
-- other segment of its body becomes a crumb (+1 length, 5 points flat); crumbs stay disjoint from other food,
-- clear under respawned bodies, and reset on map start.
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

local function step(w: World.World, d: Maps.Draw): { World.Event }
	return World.advance(w, 1 / World.speed(w), d)
end

local function countEvents(events: { World.Event }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function hasTile(list: { Maps.Tile }, x: number, y: number): boolean
	for _, tile in list do
		if tile.x == x and tile.y == y then
			return true
		end
	end
	return false
end

return t.spec("f0214 crumbs", function(it)
	it("dying in a shared arena turns every other body segment (odd indices) into a crumb", function()
		local d = drawOf(40)
		local w = World.new(2, d)
		t.expect(w.shared).toBe(true)
		w.apples = {}
		local s1, s2 = w.snakes[1], w.snakes[2]
		-- length 7 heading east into the east border of the 26-tile arena
		s1.body, s1.heading, s1.state, s1.timer = line(26, 10, "E", 7), "E", "alive", 0
		s2.body, s2.heading, s2.state, s2.timer = line(6, 20, "E", 4), "E", "ready", 100

		local events = step(w, d)
		t.expect(s1.state).toBe("dying")
		t.expect(countEvents(events, "crumbs")).toBe(1)
		-- odd indices 1, 3, 5, 7 -> x = 26, 24, 22, 20 on row 10
		t.expect(#w.crumbs).toBe(4)
		for _, x in { 26, 24, 22, 20 } do
			t.expect(hasTile(w.crumbs, x, 10)).toBe(true)
		end
		for _, x in { 25, 23, 21 } do
			t.expect(hasTile(w.crumbs, x, 10)).toBe(false)
		end
	end)

	it("dying in a solo arena drops no crumbs unless shared is true", function()
		local d = drawOf(41)
		local w = World.new(1, d)
		t.expect(w.shared).toBe(false)
		w.apples = {}
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = line(20, 10, "E", 6), "E", "alive", 0
		local e1 = step(w, d)
		t.expect(s.state).toBe("dying")
		t.expect(#w.crumbs).toBe(0)
		t.expect(countEvents(e1, "crumbs")).toBe(0)

		-- flipping w.shared = true enables death crumbs even with 1 snake
		w.shared = true
		s.body, s.heading, s.state, s.timer = line(20, 12, "E", 4), "E", "alive", 0
		local e2 = step(w, d)
		t.expect(#w.crumbs).toBe(2)
		t.expect(countEvents(e2, "crumbs")).toBe(1)
	end)

	it("eating a crumb adds 1 length and scores 5 points flat on any map", function()
		for _, map in { 1, 3 } do
			local d = drawOf(42 + map)
			local w = World.new(1, d)
			World.start(w, { map = map, side = 20, walls = {}, spawns = Maps.spawns(20, 1) }, d)
			w.apples = {}
			local s = w.snakes[1]
			s.body, s.heading, s.state, s.timer = line(5, 10, "E", 4), "E", "alive", 0
			w.crumbs = { { x = 6, y = 10 }, { x = 15, y = 15 } }

			local events = step(w, d)
			t.expect(countEvents(events, "ateCrumb")).toBe(1)
			t.expect(#s.body).toBe(5)
			t.expect(s.score).toBe(5) -- flat 5, never multiplied by map
			t.expect(#w.crumbs).toBe(1)
			t.expect(w.crumbs[1]).toEqual({ x = 15, y = 15 })

			-- next step does not grow further
			step(w, d)
			t.expect(#s.body).toBe(5)
		end
	end)

	it("eating a crumb that reaches the goal clears the map", function()
		local d = drawOf(45)
		local w = World.new(1, d)
		w.apples = {}
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = line(15, 10, "E", Maps.goal(1) - 1), "E", "alive", 0
		w.crumbs = { { x = 16, y = 10 } }

		local events = step(w, d)
		t.expect(w.phase).toBe("clear")
		t.expect(countEvents(events, "cleared")).toBe(1)
		t.expect(s.score).toBe(5 + 100)
	end)

	it("apples, golden apples, and crumbs never overlap each other or solid snakes", function()
		local d = drawOf(46)
		local w = World.new(2, d)
		-- tiny 5x5 board with a snake, an apple, a golden apple, and crumbs filling almost everything
		w.map = 10
		w.layout = { map = 10, side = 5, walls = {}, spawns = {} }
		local s1, s2 = w.snakes[1], w.snakes[2]
		s1.body, s1.heading, s1.state, s1.timer = line(4, 1, "E", 4), "E", "alive", 0
		s2.body, s2.heading, s2.state, s2.timer = line(4, 5, "E", 4), "E", "ready", 100
		w.apples = { { x = 5, y = 1 } }
		w.golden = { x = 1, y = 2, timer = 5 }
		-- fill rows 2..4 with crumbs except (5, 2) and (5, 3)
		w.crumbs = {}
		for y = 2, 4 do
			for x = 1, 5 do
				if not (x == 1 and y == 2) and not (x == 5 and (y == 2 or y == 3)) then
					table.insert(w.crumbs, { x = x, y = y })
				end
			end
		end
		-- snake 1 eats the apple at (5, 1); replacement apples must land only on free tiles (not on crumbs/golden/snakes)
		World.advance(w, 0.25, d)
		local seen: { [string]: boolean } = {}
		for _, s in w.snakes do
			if s.state == "ready" or s.state == "alive" then
				for _, b in s.body do
					seen[`{b.x},{b.y}`] = true
				end
			end
		end
		if w.golden then
			local gk = `{w.golden.x},{w.golden.y}`
			t.expect(seen[gk] == nil).toBe(true)
			seen[gk] = true
		end
		for _, c in w.crumbs do
			local ck = `{c.x},{c.y}`
			t.expect(seen[ck] == nil).toBe(true)
			seen[ck] = true
		end
		t.expect(#w.apples).toBe(#w.snakes + 1)
		for _, a in w.apples do
			local ak = `{a.x},{a.y}`
			t.expect(seen[ak] == nil).toBe(true)
			seen[ak] = true
		end
	end)

	it(
		"death crumbs skip tiles occupied by a survivor's new head, apples, golden apple, or existing crumbs",
		function()
			local d = drawOf(461)
			local w = World.new(2, d)
			-- s1 length 9 heading east into the east border (side = 26): odd pre-step tiles are x = 26, 24, 22, 20, 18 on row 10
			local s1, s2 = w.snakes[1], w.snakes[2]
			s1.body, s1.heading, s1.state, s1.timer = line(26, 10, "E", 9), "E", "alive", 0
			-- s2 heads north onto s1's odd tail (18, 10) on the exact same tick s1 dies
			s2.body, s2.heading, s2.state, s2.timer = line(18, 11, "N", 4), "N", "alive", 0
			-- place an apple on (26, 10), a golden apple on (24, 10), and an existing crumb on (22, 10)
			w.apples = { { x = 26, y = 10 }, { x = 2, y = 2 }, { x = 3, y = 2 } }
			w.golden = { x = 24, y = 10, timer = 5 }
			w.crumbs = { { x = 22, y = 10 } }

			local events = step(w, d)
			t.expect(s1.state).toBe("dying")
			t.expect(s2.state).toBe("alive")
			t.expect(s2.body[1]).toEqual({ x = 18, y = 10 })
			t.expect(countEvents(events, "crumbs")).toBe(1)
			-- only (20, 10) is free among odd tiles 26, 24, 22, 20, 18; existing crumb (22, 10) stays without duplication
			t.expect(#w.crumbs).toBe(2)
			t.expect(hasTile(w.crumbs, 22, 10)).toBe(true)
			t.expect(hasTile(w.crumbs, 20, 10)).toBe(true)
			t.expect(hasTile(w.crumbs, 26, 10)).toBe(false)
			t.expect(hasTile(w.crumbs, 24, 10)).toBe(false)
			t.expect(hasTile(w.crumbs, 18, 10)).toBe(false)
		end
	)

	it("head-on collision on a crumb kills both and leaves the crumb intact", function()
		local d = drawOf(462)
		local w = World.new(2, d)
		w.shared = false
		w.apples = {}
		local s1, s2 = w.snakes[1], w.snakes[2]
		s1.body, s1.heading, s1.state, s1.timer = line(5, 10, "E", 4), "E", "alive", 0
		s2.body, s2.heading, s2.state, s2.timer = line(7, 10, "W", 4), "W", "alive", 0
		w.crumbs = { { x = 6, y = 10 } }

		local events = step(w, d)
		t.expect(countEvents(events, "died")).toBe(2)
		t.expect(countEvents(events, "ateCrumb")).toBe(0)
		t.expect(s1.score).toBe(0)
		t.expect(s2.score).toBe(0)
		t.expect(#w.crumbs).toBe(1)
		t.expect(w.crumbs[1]).toEqual({ x = 6, y = 10 })
	end)

	it("respawning clears crumbs and golden apple under the placed body without scoring", function()
		local d = drawOf(47)
		local w = World.new(1, d)
		w.apples = {}
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = line(20, 10, "E", 4), "E", "alive", 0
		step(w, d) -- dies, waits 1.5 s
		t.expect(s.state).toBe("dying")

		-- find where World.safest will place snake 1 and put a crumb and golden apple on its body tiles
		local spot = World.safest(w, 1)
		t.expect(spot ~= nil).toBe(true)
		local sp = spot :: Maps.Spawn
		local placed = line(sp.x, sp.y, sp.heading, 4)
		w.crumbs = { placed[1], placed[3], { x = 1, y = 1 } }
		w.golden = { x = placed[2].x, y = placed[2].y, timer = 5 }

		-- World.safest still returns the exact same placement (ignores crumbs and golden)
		t.expect(World.safest(w, 1)).toEqual(sp)

		World.advance(w, 1.5, d)
		t.expect(s.state).toBe("ready")
		t.expect(s.score).toBe(0)
		t.expect(#s.body).toBe(4)
		t.expect(w.golden).toBe(nil)
		t.expect(#w.crumbs).toBe(1)
		t.expect(w.crumbs[1]).toEqual({ x = 1, y = 1 })
	end)

	it("starting a new map clears all crumbs", function()
		local d = drawOf(48)
		local w = World.new(2, d)
		w.crumbs = { { x = 2, y = 2 }, { x = 3, y = 3 } }
		World.start(w, Maps.roll(2, 2, d), d)
		t.expect(#w.crumbs).toBe(0)
	end)
end)
