--!strict
-- f0214 acceptance: boost, golden apples, and crumbs working together in multi-snake play with all board and food
-- invariants intact.
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

local function key(x: number, y: number): string
	return `{x},{y}`
end

local function line(x: number, y: number, heading: Maps.Heading, n: number): { Maps.Tile }
	local v = Maps.step(heading)
	local out = {}
	for i = 0, n - 1 do
		table.insert(out, { x = x - v.x * i, y = y - v.y * i })
	end
	return out
end

local function consistent(w: World.World)
	local side = w.layout.side
	local walls: { [string]: boolean } = {}
	for _, wall in w.layout.walls do
		for i = 0, wall.length - 1 do
			walls[key(
				if wall.dir == "H" then wall.x + i else wall.x,
				if wall.dir == "V" then wall.y + i else wall.y
			)] =
				true
		end
	end
	local taken: { [string]: boolean } = {}
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
		end
	end
	for _, a in w.apples do
		local k = key(a.x, a.y)
		t.expect(walls[k] == nil and taken[k] == nil).toBe(true)
		taken[k] = true
	end
	if w.golden then
		local g = w.golden
		local k = key(g.x, g.y)
		t.expect(g.x >= 1 and g.y >= 1 and g.x <= side and g.y <= side).toBe(true)
		t.expect(g.timer > 0 and g.timer <= World.TUNING.goldenLifeSeconds + 1e-6).toBe(true)
		t.expect(walls[k] == nil and taken[k] == nil).toBe(true)
		taken[k] = true
	end
	for _, c in w.crumbs do
		local k = key(c.x, c.y)
		t.expect(c.x >= 1 and c.y >= 1 and c.x <= side and c.y <= side).toBe(true)
		t.expect(walls[k] == nil and taken[k] == nil).toBe(true)
		taken[k] = true
	end
	if w.phase == "play" then
		t.expect(#w.apples).toBe(#w.snakes + 1)
	end
end

return t.spec("f0214 integration", function(it)
	it("four snakes boosting and turning for 60 s keep all board and food invariants", function()
		local d = drawOf(50)
		local act = drawOf(51)
		local w = World.new(4, d)
		local goldenSpawned, crumbsDropped, crumbsEaten = 0, 0, 0
		for _ = 1, 30 * 60 do
			for id = 1, 4 do
				if act(6) == 1 then
					World.turn(w, id, if act(2) == 1 then "Left" else "Right")
				end
				if act(8) == 1 then
					World.boost(w, id, act(2) == 1)
				end
			end
			for _, e in World.advance(w, 1 / 30, d) do
				if e.kind == "goldenSpawned" then
					goldenSpawned += 1
				elseif e.kind == "crumbs" then
					crumbsDropped += 1
				elseif e.kind == "ateCrumb" then
					crumbsEaten += 1
				end
			end
			consistent(w)
			if w.phase == "over" then
				break
			end
		end
		t.expect(goldenSpawned >= 1).toBe(true)
		t.expect(crumbsDropped >= 1).toBe(true)
		t.expect(crumbsEaten >= 1).toBe(true)
	end)

	it("a boosting snake eats a golden apple, sheds a crumb, and a trailing snake eats that crumb", function()
		local d = drawOf(52)
		local w = World.new(2, d)
		w.apples = {}
		local s1, s2 = w.snakes[1], w.snakes[2]
		-- s1 (length 4) boosts east into a golden apple at (10, 10) -> grows +3 over 3 half-steps while shedding at 0.5 s
		s1.body, s1.heading, s1.state, s1.timer = line(9, 10, "E", 4), "E", "alive", 0
		-- s2 sits below row 10, Ready until we steer it onto the shed crumb
		s2.body, s2.heading, s2.state, s2.timer = line(8, 12, "N", 4), "N", "ready", 100
		w.golden = { x = 10, y = 10, timer = 5 }
		World.boost(w, 1, true)

		-- advance 0.625 s (5 half-steps): at 0.125 eats golden (len 5), 0.25 len 6, 0.375 len 7,
		-- at 0.625 s (0.5 s of active boost after reaching len 5 at 0.125 s) sheds 1 segment -> len 6, 1 crumb
		World.advance(w, 0.625, d)
		t.expect(w.golden).toBe(nil)
		t.expect(s1.score).toBe(50)
		t.expect(#s1.body).toBe(6)
		t.expect(#w.crumbs).toBe(1)
		local crumb = w.crumbs[1]

		-- place s2 just south of the shed crumb heading north and step it onto the crumb
		s2.body, s2.heading, s2.state, s2.timer = line(crumb.x, crumb.y + 1, "N", 4), "N", "alive", 0
		World.boost(w, 1, false)
		World.advance(w, 0.25, d)
		t.expect(#s2.body).toBe(5)
		t.expect(s2.score).toBe(5)
		t.expect(#w.crumbs).toBe(0)
	end)
end)
