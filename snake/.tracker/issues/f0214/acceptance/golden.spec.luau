--!strict
-- f0214 acceptance: golden apples (snake/.tracker/game-design.md, "Food"): every 20 s one appears for 6 s on a
-- free tile, +3 length and 50 x map number points, pauses during MAP CLEAR, resets on map start, and is frame-rate
-- independent.
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

local function goldenIsFree(w: World.World)
	local g = w.golden
	t.expect(g ~= nil).toBe(true)
	local gx, gy = (g :: World.GoldenApple).x, (g :: World.GoldenApple).y
	local side = w.layout.side
	t.expect(gx >= 1 and gy >= 1 and gx <= side and gy <= side).toBe(true)
	for _, wall in w.layout.walls do
		for i = 0, wall.length - 1 do
			local wx = if wall.dir == "H" then wall.x + i else wall.x
			local wy = if wall.dir == "V" then wall.y + i else wall.y
			t.expect(wx == gx and wy == gy).toBe(false)
		end
	end
	for _, s in w.snakes do
		if s.state == "ready" or s.state == "alive" then
			for _, b in s.body do
				t.expect(b.x == gx and b.y == gy).toBe(false)
			end
		end
	end
	for _, a in w.apples do
		t.expect(a.x == gx and a.y == gy).toBe(false)
	end
	for _, c in w.crumbs do
		t.expect(c.x == gx and c.y == gy).toBe(false)
	end
end

return t.spec("f0214 golden", function(it)
	it("a golden apple appears at 20 s for 6 s on a free tile and repeats every 20 s", function()
		local d = drawOf(30)
		local w = World.new(1, d)
		-- keep the snake Ready so it stays out of the way while we watch the golden apple clock
		w.snakes[1].timer = 100
		w.crumbs = { { x = 10, y = 10 } }

		t.expect(w.golden).toBe(nil)
		local e1 = World.advance(w, 19.5, d)
		t.expect(w.golden).toBe(nil)
		t.expect(countEvents(e1, "goldenSpawned")).toBe(0)

		-- at 20.0 s it spawns with timer = 6
		local e2 = World.advance(w, 0.5, d)
		t.expect(countEvents(e2, "goldenSpawned")).toBe(1)
		goldenIsFree(w)
		t.expect((w.golden :: World.GoldenApple).timer).toBeNear(6, 1e-6)

		-- still there at 25.5 s
		World.advance(w, 5.5, d)
		t.expect(w.golden ~= nil).toBe(true)

		-- expires at 26.0 s
		local e3 = World.advance(w, 0.5, d)
		t.expect(w.golden).toBe(nil)
		t.expect(countEvents(e3, "goldenExpired")).toBe(1)

		-- next one appears at 40.0 s (14 s later)
		World.advance(w, 13.5, d)
		t.expect(w.golden).toBe(nil)
		local e4 = World.advance(w, 0.5, d)
		t.expect(countEvents(e4, "goldenSpawned")).toBe(1)
		goldenIsFree(w)
	end)

	it("on a crowded board golden apple avoids walls, snakes, apples, and crumbs", function()
		-- 5x5 board with wall (2,2)-(4,2), Ready snake at row 1 (1..4), apples at (5,1)&(5,2),
		-- crumbs filling rows 3..5 except (1,2) and (5,5): only 2 free tiles remain
		for trial = 1, 8 do
			local d = drawOf(300 + trial)
			local w = World.new(1, d)
			w.map = 2
			w.layout = {
				map = 2,
				side = 5,
				walls = { { x = 2, y = 2, dir = "H", length = 3 } },
				spawns = {},
			}
			local s = w.snakes[1]
			s.body, s.heading, s.state, s.timer = line(4, 1, "E", 4), "E", "ready", 100
			w.apples = { { x = 5, y = 1 }, { x = 5, y = 2 } }
			w.crumbs = {}
			for y = 3, 5 do
				for x = 1, 5 do
					if not (x == 5 and y == 5) then
						table.insert(w.crumbs, { x = x, y = y })
					end
				end
			end
			w.golden = nil
			w.goldenTimer = 0.25
			local ev = World.advance(w, 0.25, d)
			t.expect(countEvents(ev, "goldenSpawned")).toBe(1)
			goldenIsFree(w)
		end
	end)

	it("expiry runs before spawn and before step at the same instant", function()
		-- simultaneous expiry and spawn (both timers 0): goldenExpired before goldenSpawned, new golden present
		local d1 = drawOf(310)
		local w1 = World.new(1, d1)
		w1.snakes[1].timer = 100
		w1.golden = { x = 5, y = 5, timer = 0 }
		w1.goldenTimer = 0
		local ev1 = World.advance(w1, 0.125, d1)
		local expIdx, spIdx = 0, 0
		for i, e in ev1 do
			if e.kind == "goldenExpired" and expIdx == 0 then
				expIdx = i
			elseif e.kind == "goldenSpawned" and spIdx == 0 then
				spIdx = i
			end
		end
		t.expect(expIdx > 0 and spIdx > expIdx).toBe(true)
		t.expect(w1.golden ~= nil).toBe(true)

		-- snake steps onto golden apple at exact expiry instant (t = 0.25 s): expires before step, not eaten
		local d2 = drawOf(311)
		local w2 = World.new(1, d2)
		w2.apples = {}
		local s2 = w2.snakes[1]
		s2.body, s2.heading, s2.state, s2.timer = line(5, 10, "E", 4), "E", "alive", 0
		w2.golden = { x = 6, y = 10, timer = 0.25 }
		local ev2 = step(w2, d2)
		t.expect(countEvents(ev2, "goldenExpired")).toBe(1)
		t.expect(countEvents(ev2, "ateGolden")).toBe(0)
		t.expect(s2.score).toBe(0)
		t.expect(w2.golden).toBe(nil)
	end)

	it("golden apple repeats on a fixed 20 s cadence even when eaten early", function()
		local d = drawOf(31)
		local w = World.new(1, d)
		w.apples = {}
		local s = w.snakes[1]
		s.state, s.timer = "ready", 100
		World.advance(w, 20, d)
		t.expect(w.golden ~= nil).toBe(true)

		-- place snake just west of the golden apple (or east if at x == 1) and eat it at t = 20.25 s
		local g = w.golden :: World.GoldenApple
		if g.x >= 5 then
			s.body, s.heading, s.state, s.timer = line(g.x - 1, g.y, "E", 4), "E", "alive", 0
		else
			s.body, s.heading, s.state, s.timer = line(g.x + 1, g.y, "W", 4), "W", "alive", 0
		end
		step(w, d)
		t.expect(w.golden).toBe(nil)

		-- freeze snake again and advance to t = 40 s (19.75 s remaining from 20.25 s)
		s.state, s.timer = "ready", 100
		World.advance(w, 19.5, d)
		t.expect(w.golden).toBe(nil)
		local e = World.advance(w, 0.25, d)
		t.expect(countEvents(e, "goldenSpawned")).toBe(1)
		t.expect(w.golden ~= nil).toBe(true)
	end)

	it("eating a golden apple adds 3 length and scores 50 x map", function()
		for _, case in { { 1, 50 }, { 3, 150 } } do
			local map, expectedScore = case[1], case[2]
			local d = drawOf(32 + map)
			local w = World.new(1, d)
			World.start(w, { map = map, side = 20, walls = {}, spawns = Maps.spawns(20, 1) }, d)
			w.apples = {}
			local s = w.snakes[1]
			s.body, s.heading, s.state, s.timer = line(5, 10, "E", 4), "E", "alive", 0
			w.golden = { x = 6, y = 10, timer = 5 }

			local e1 = step(w, d)
			t.expect(countEvents(e1, "ateGolden")).toBe(1)
			t.expect(w.golden).toBe(nil)
			t.expect(s.score).toBe(expectedScore)
			t.expect(#s.body).toBe(5) -- +1 immediately

			step(w, d)
			t.expect(#s.body).toBe(6) -- +2

			step(w, d)
			t.expect(#s.body).toBe(7) -- +3

			step(w, d)
			t.expect(#s.body).toBe(7) -- done growing
		end
	end)

	it("golden apple growth clears the map on the step goal is reached", function()
		local d = drawOf(35)
		local w = World.new(1, d)
		w.apples = {}
		local s = w.snakes[1]
		-- map 1 goal is 12; start at length 10 (2 short) so eat gives 11 and next step gives 12 -> clear!
		s.body, s.heading, s.state, s.timer = line(12, 10, "E", 10), "E", "alive", 0
		w.golden = { x = 13, y = 10, timer = 4 }

		local e1 = step(w, d)
		t.expect(#s.body).toBe(11)
		t.expect(w.phase).toBe("play")
		t.expect(countEvents(e1, "cleared")).toBe(0)

		local e2 = step(w, d)
		t.expect(#s.body).toBe(12)
		t.expect(w.phase).toBe("clear")
		t.expect(countEvents(e2, "cleared")).toBe(1)
		t.expect(s.score).toBe(50 + 100)
	end)

	it("on a full board no golden apple spawns and draw is never called with 0", function()
		local d = drawOf(36)
		local w = World.new(1, d)
		w.map = 5
		w.layout = { map = 5, side = 4, walls = {}, spawns = {} }
		w.apples = {}
		local body = {}
		for y = 4, 1, -1 do
			for i = 1, 4 do
				table.insert(body, { x = if y % 2 == 0 then i else 5 - i, y = y })
			end
		end
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = body, "N", "ready", 100
		w.goldenTimer = 0.25

		local events = World.advance(w, 0.25, d)
		t.expect(w.golden).toBe(nil)
		t.expect(countEvents(events, "goldenSpawned")).toBe(0)
		t.expect(w.goldenTimer).toBeNear(World.TUNING.goldenIntervalSeconds, 1e-6)
	end)

	it("head-on collision on a golden apple kills both and leaves it intact", function()
		local d = drawOf(37)
		local w = World.new(2, d)
		w.apples = {}
		local s1, s2 = w.snakes[1], w.snakes[2]
		s1.body, s1.heading, s1.state, s1.timer = line(5, 10, "E", 4), "E", "alive", 0
		s2.body, s2.heading, s2.state, s2.timer = line(7, 10, "W", 4), "W", "alive", 0
		w.golden = { x = 6, y = 10, timer = 5 }

		local events = step(w, d)
		t.expect(countEvents(events, "died")).toBe(2)
		t.expect(countEvents(events, "ateGolden")).toBe(0)
		t.expect(w.golden ~= nil).toBe(true)
		t.expect((w.golden :: World.GoldenApple).x).toBe(6)
		t.expect((w.golden :: World.GoldenApple).y).toBe(10)
		t.expect(s1.score).toBe(0)
		t.expect(s2.score).toBe(0)
	end)

	it("golden apple timers pause during MAP CLEAR and reset on the next map", function()
		local d = drawOf(38)
		local w = World.new(1, d)
		w.apples = { { x = 16, y = 10 } }
		local s = w.snakes[1]
		s.body, s.heading, s.state, s.timer = line(15, 10, "E", 11), "E", "alive", 0
		w.golden = { x = 5, y = 5, timer = 1.0 }
		w.goldenTimer = 1.0
		step(w, d) -- ticks 0.25 s of play, then clears map 1 -> phase = "clear", timer = 2
		t.expect(w.phase).toBe("clear")

		-- advance 1.5 s (> 0.75 s remaining): neither expires nor ticks during MAP CLEAR
		local e1 = World.advance(w, 1.5, d)
		t.expect(#e1).toBe(0)
		t.expect(w.golden ~= nil).toBe(true)
		t.expect((w.golden :: World.GoldenApple).timer).toBeNear(0.75, 1e-6)
		t.expect(w.goldenTimer).toBeNear(0.75, 1e-6)

		-- finishing MAP CLEAR starts map 2: golden cleared, goldenTimer reset to 20
		World.advance(w, 0.5, d)
		t.expect(w.map).toBe(2)
		t.expect(w.golden).toBe(nil)
		t.expect(w.goldenTimer).toBeNear(World.TUNING.goldenIntervalSeconds, 1e-6)
	end)

	it("golden apple spawn, eat, and expiry are frame-rate independent", function()
		-- (a) non-step-aligned goldenTimer and golden.timer fire before the next step across cuts
		local function runTimers(cuts: { number }, duration: number): (any, number, number?)
			local d = drawOf(39)
			local w = World.new(1, d)
			World.start(w, { map = 2, side = 20, walls = {}, spawns = Maps.spawns(20, 1) }, d)
			w.snakes[1].timer = 100
			w.goldenTimer = 0.3
			local left, i = duration, 0
			local spawned, expired = 0, 0
			while left > 1e-12 do
				i += 1
				local dt = math.min(left, cuts[(i - 1) % #cuts + 1])
				for _, e in World.advance(w, dt, d) do
					if e.kind == "goldenSpawned" then
						spawned += 1
					elseif e.kind == "goldenExpired" then
						expired += 1
					end
				end
				left -= dt
			end
			local gPos = if w.golden then { x = w.golden.x, y = w.golden.y } else nil
			return { spawned = spawned, expired = expired, gPos = gPos },
				w.goldenTimer,
				if w.golden then w.golden.timer else nil
		end

		-- at t = 0.35 s: spawned at 0.3 s -> golden.timer == 5.95, goldenTimer == 19.95
		local whole1, gt1, gLife1 = runTimers({ 0.35 }, 0.35)
		t.expect(whole1.spawned).toBe(1)
		t.expect(gt1).toBeNear(19.95, 1e-6)
		t.expect(gLife1 :: number).toBeNear(5.95, 1e-6)
		for _, cuts in { { 1 / 60 }, { 1 / 30 }, { 0.07, 0.013 } } do
			local res, gt, gLife = runTimers(cuts, 0.35)
			t.expect(res).toEqual(whole1)
			t.expect(gt).toBeNear(gt1, 1e-6)
			t.expect(gLife :: number).toBeNear(gLife1 :: number, 1e-6)
		end

		-- (b) non-step-aligned golden.timer expiry at 0.15 s before a dying snake respawns on its tile at 0.18 s
		local function runExpiry(cuts: { number }): (number, boolean)
			local d = drawOf(391)
			local w = World.new(1, d)
			World.start(w, { map = 2, side = 20, walls = {}, spawns = Maps.spawns(20, 1) }, d)
			w.apples = {}
			local s = w.snakes[1]
			s.state, s.timer = "dying", 0.18
			local sp = World.safest(w, 1) :: Maps.Spawn
			w.golden = { x = sp.x, y = sp.y, timer = 0.15 }
			local left, i, expired = 0.25, 0, 0
			while left > 1e-12 do
				i += 1
				local dt = math.min(left, cuts[(i - 1) % #cuts + 1])
				expired += countEvents(World.advance(w, dt, d), "goldenExpired")
				left -= dt
			end
			return expired, w.golden == nil
		end
		for _, cuts in { { 0.25 }, { 1 / 60 }, { 1 / 30 }, { 0.07, 0.013 } } do
			local expired, gone = runExpiry(cuts)
			t.expect(expired).toBe(1)
			t.expect(gone).toBe(true)
		end

		-- (c) eating a golden apple on map 2 across real frame rates produces identical snake body, score, and golden
		local function runEat(cuts: { number }): any
			local d = drawOf(392)
			local w = World.new(1, d)
			World.start(w, { map = 2, side = 20, walls = {}, spawns = Maps.spawns(20, 1) }, d)
			w.apples = {}
			local s = w.snakes[1]
			s.body, s.heading, s.state, s.timer = line(5, 10, "E", 4), "E", "alive", 0
			w.golden = { x = 7, y = 10, timer = 5 }
			local left, i = 1.0, 0
			while left > 1e-12 do
				i += 1
				local dt = math.min(left, cuts[(i - 1) % #cuts + 1])
				World.advance(w, dt, d)
				left -= dt
			end
			return { body = s.body, score = s.score, golden = w.golden }
		end
		local eatWhole = runEat({ 1.0 })
		t.expect(eatWhole.score).toBe(100)
		t.expect(#eatWhole.body).toBe(7)
		t.expect(eatWhole.golden).toBe(nil)
		for _, cuts in { { 1 / 60 }, { 1 / 30 }, { 0.07, 0.013 } } do
			t.expect(runEat(cuts)).toEqual(eatWhole)
		end
	end)
end)
