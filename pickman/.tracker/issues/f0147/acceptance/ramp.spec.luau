--!strict
-- f0147 AC1: the speed ramp of levels by picked walls. With a ramp (`Levels.RAMP`, shipped in
-- `Session.GAME_CONFIG.ramp`), every level has level 1's rules (frightened time, flashes, the scatter and chase
-- timetable, the house limits and idle time) and only the speeds change: level 1 is 70% of the classic level 1,
-- each level after it 5% faster than the one before, in whole units a step, up to level 34; later levels keep
-- level 34's speeds (the user, 2026-10-31: "Stop at level 34"). The eyes follow the ramp too, never past a tile a
-- step (the user, 2026-10-31: "Follow the ramp"). Without a ramp the classic tables are untouched.
local Ghosts = require("@logic/Ghosts")
local Levels = require("@logic/Levels")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local UNITS = 120 -- Movement.UNITS: sub-tile units per tile
local BASE = 30 -- Movement.DEFAULT_CONFIG.speed: the classic level 1 player
local R = Levels.RAMP
local TUNINGS = { 1, 1 / 1.1 } -- the classic ghosts and f0125's shipped slower ghosts

local function round(v: number): number
	return math.floor(v + 0.5)
end

-- the ramp's own arithmetic, written out here: level 1's classic factor x 0.7 x 1.05^(n-1), n capped at 34
local function ramped(factor: number, level: number): number
	return round(BASE * factor * 0.7 * 1.05 ^ (math.min(level, 34) - 1))
end

local KINDS: { { kind: Levels.GhostSpeed, factor: number } } = {
	{ kind = "normal", factor = 0.75 / 0.8 },
	{ kind = "tunnel", factor = 0.4 / 0.8 },
	{ kind = "frightened", factor = 0.5 / 0.8 },
}

return t.spec("f0147 the speed ramp", function(it)
	it("Levels.RAMP is ten picks a level, 70% on level 1, 5% more a level, up to level 34", function()
		t.expect(R.picks).toBe(10)
		t.expect(R.first).toBe(0.7)
		t.expect(R.step).toBe(1.05)
		t.expect(R.top).toBe(34)
		t.expect(table.isfrozen(R)).toBe(true)
		t.expect(Session.GAME_CONFIG.ramp).toBe(R)
		t.expect(Session.DEFAULT_CONFIG.ramp).toBe(nil)
	end)

	it("level 1 is 30% slower than the classic level 1, for the player and every ghost", function()
		t.expect(Levels.playerSpeed(BASE, 1, false, R)).toBe(21) -- classic 30
		t.expect(Levels.playerSpeed(BASE, 1, true, R)).toBe(24) -- classic 34 (30 x 1.125 = 33.75)
		t.expect(Levels.ghostSpeed(BASE, 1, "normal", 1, R)).toBe(20) -- classic 28 (28.125)
		t.expect(Levels.ghostSpeed(BASE, 1, "tunnel", 1, R)).toBe(11) -- classic 15 (10.5 rounds up)
		t.expect(Levels.ghostSpeed(BASE, 1, "frightened", 1, R)).toBe(13) -- classic 19 (13.125)
		t.expect(Levels.ghostSpeed(BASE, 1, "eyes", 1, R)).toBe(42) -- classic 60
		-- the shipped config, f0125's slower ghosts included
		local sp = Session.speeds(Session.GAME_CONFIG, 1)
		t.expect(sp.player).toBe(21)
		t.expect(sp.ghost).toBe(18) -- 30 x 0.9375 x 0.7 / 1.1 = 17.9
		t.expect(sp.eyes).toBe(42) -- eyes are never tuned
	end)

	it("every speed on level n is the classic level 1's x 0.7 x 1.05^(n-1), in whole units, up to level 34", function()
		for level = 1, 34 do
			t.expect(Levels.playerSpeed(BASE, level, false, R)).toBe(ramped(1, level))
			t.expect(Levels.playerSpeed(BASE, level, true, R)).toBe(ramped(1.125, level))
			for _, k in TUNINGS do
				for _, g in KINDS do
					t.expect(Levels.ghostSpeed(BASE, level, g.kind, k, R)).toBe(ramped(g.factor * k, level))
				end
			end
			t.expect(Levels.ghostSpeed(BASE, level, "eyes", 1, R)).toBe(ramped(2, level))
		end
	end)

	it(
		"each level up to 34 is faster than the one before: the player and the hunting ghosts in whole units, the tunnel and frightened ghosts on average",
		function()
			for level = 2, 34 do
				for _, frightened in { false, true } do
					local was = Levels.playerSpeed(BASE, level - 1, frightened, R)
					t.expect(Levels.playerSpeed(BASE, level, frightened, R) > was).toBe(true)
				end
				for _, k in TUNINGS do
					local was = Levels.ghostSpeed(BASE, level - 1, "normal", k, R)
					t.expect(Levels.ghostSpeed(BASE, level, "normal", k, R) > was).toBe(true)
					-- the slow tunnel and frightened ghosts (10 to 13 units on level 1) can round to the same unit
					-- the tunnel and frightened ghosts keep the exact ramp (the user, 2026-10-31: "Carry fractions"): their
					-- average speed rises 5% a level, though their whole units can repeat
					t.expect(
						Levels.ghostRate(BASE, level, "tunnel", k, R)
							> Levels.ghostRate(BASE, level - 1, "tunnel", k, R)
					)
						.toBe(true)
					local frightRate = Levels.ghostRate(BASE, level, "frightened", k, R)
					t.expect(frightRate > Levels.ghostRate(BASE, level - 1, "frightened", k, R)).toBe(true)
				end
			end
		end
	)

	it("levels past 34 keep level 34's speeds", function()
		for _, level in { 35, 36, 50, 1000 } do
			for _, frightened in { false, true } do
				t.expect(Levels.playerSpeed(BASE, level, frightened, R))
					.toBe(Levels.playerSpeed(BASE, 34, frightened, R))
			end
			for _, g in KINDS do
				t.expect(Levels.ghostSpeed(BASE, level, g.kind, 1 / 1.1, R))
					.toBe(Levels.ghostSpeed(BASE, 34, g.kind, 1 / 1.1, R))
			end
			t.expect(Levels.rampFactor(R, level)).toBe(Levels.rampFactor(R, 34))
		end
		t.expect(Levels.playerSpeed(BASE, 34, true, R)).toBe(118) -- the fastest step, within a tile
		t.expect(Levels.playerSpeed(BASE, 34, false, R)).toBe(105) -- five times level 1
	end)

	it(
		"in the shipped config every speed but the eyes stays within a tile a step, and the eyes stop at a tile",
		function()
			for level = 1, 40 do
				for _, frightened in { false, true } do
					local sp = Session.speeds(Session.GAME_CONFIG, level, frightened)
					t.expect(sp.player <= UNITS).toBe(true)
					t.expect(sp.ghost <= UNITS and sp.tunnel <= UNITS and sp.frightened <= UNITS).toBe(true)
					t.expect(sp.eyes).toBe(math.min(ramped(2, level), UNITS))
				end
			end
			t.expect(Session.speeds(Session.GAME_CONFIG, 22).eyes).toBe(117) -- the last level under a tile
			t.expect(Session.speeds(Session.GAME_CONFIG, 23).eyes).toBe(UNITS) -- 123 capped
		end
	)

	it("every level has level 1's frightened time, flashes, timetable, house limits and idle time", function()
		local one = Levels.row(1)
		for level = 1, 40 do
			local r = Levels.row(level, R)
			t.expect(r.frightenedSeconds).toBe(one.frightenedSeconds)
			t.expect(r.flashes).toBe(one.flashes)
			t.expect(r.idleSeconds).toBe(one.idleSeconds)
			t.expect(r.dotLimits).toEqual(one.dotLimits)
			t.expect(r.schedule).toEqual(one.schedule)
			t.expect(Levels.frightenedTicks(level, 30, R)).toBe(180) -- 6 s of game time, level 1's
			t.expect(Levels.schedule(level, 30, R)).toEqual(Levels.schedule(1, 30))
			t.expect(table.isfrozen(r)).toBe(true)
		end
		-- the classic level 17 has no frightened time at all; the ramp's level 17 has level 1's
		t.expect(Levels.frightenedTicks(17, 30)).toBe(0)
		t.expect(Levels.frightenedTicks(17, 30, R)).toBe(180)
	end)

	it("without a ramp the classic tables are untouched", function()
		local players = { 30, 34, 34, 34, 38 }
		for level, speed in players do
			t.expect(Levels.playerSpeed(BASE, level)).toBe(speed)
			t.expect(Levels.row(level)).toBe(Levels.ROWS[level])
		end
		t.expect(Levels.playerSpeed(BASE, 21)).toBe(34)
		t.expect(Levels.ghostSpeed(BASE, 1, "eyes")).toBe(60)
		t.expect(Levels.ghostSpeed(BASE, 5, "normal")).toBe(36)
		t.expect(Levels.frightenedTicks(2, 30)).toBe(150)
		local sp = Session.speeds(Session.DEFAULT_CONFIG, 5)
		t.expect(sp.player).toBe(38)
		t.expect(sp.eyes).toBe(60)
	end)

	it("a ramp whose fields are not usable is refused, by Levels and by Session.new", function()
		local bad: { { [string]: any } } = {
			{ picks = 0 },
			{ picks = 2.5 },
			{ top = 0 },
			{ top = math.huge },
			{ first = 0 },
			{ first = 0 / 0 },
			{ step = 0.99 },
			{ step = math.huge },
		}
		local classic = Maze.layout("classic")
		for _, patch in bad do
			local r = table.clone(R) :: any
			for key, value in patch do
				r[key] = value
			end
			t.expect((pcall(Levels.validateRamp, r))).toBe(false)
			local c = table.clone(Session.GAME_CONFIG) :: any
			c.ramp = r
			t.expect((pcall(Session.new, classic, 1, c))).toBe(false)
		end
		t.expect((pcall(Levels.validateRamp, R))).toBe(true)
		-- a ramp whose top level would move the player more than a tile a step is refused
		local far = table.clone(R) :: any
		far.top = 35 -- the frightened player would be 124
		local c = table.clone(Session.GAME_CONFIG) :: any
		c.ramp = far
		t.expect((pcall(Session.new, classic, 1, c))).toBe(false)
		t.expect((pcall(Session.new, classic, 1, Session.GAME_CONFIG))).toBe(true)
	end)

	it("a shipped session's ghosts get the ramp: their speeds are Session.speeds' on every level", function()
		local s = Session.new(Maze.layout("classic"), 1, Session.GAME_CONFIG) :: any
		Session.join(s, "p")
		local set = s.members.p.ghosts :: Ghosts.Set
		t.expect(set.ramp).toBe(R)
		for level = 1, 40 do
			local sp = Session.speeds(Session.GAME_CONFIG, level)
			t.expect(Levels.ghostSpeed(BASE, level, "normal", set.tuning, set.ramp)).toBe(sp.ghost)
			t.expect(Levels.ghostRate(BASE, level, "tunnel", set.tuning, set.ramp)).toBe(sp.tunnel)
			t.expect(Levels.ghostRate(BASE, level, "frightened", set.tuning, set.ramp)).toBe(sp.frightened)
		end
	end)

	-- the ghosts of a running session move the ramp's units a step (f0125's measure, along the rails: the progress
	-- gained on the same tile, or the rest of the tile plus the progress on the next one; a reversing step or one in
	-- a side tunnel is not counted)
	local function snap(w: any): any
		return { tile = { x = w.tile.x, y = w.tile.y }, heading = w.heading, progress = w.progress }
	end
	local function travelled(m: Maze.Maze, a: any, b: any): number?
		if a.tile.x == b.tile.x and a.tile.y == b.tile.y and (a.heading == b.heading or a.progress == 0) then
			return b.progress - a.progress
		end
		local n = Maze.neighbor(m, a.tile, a.heading)
		if n.x == b.tile.x and n.y == b.tile.y then
			return UNITS - a.progress + b.progress
		end
		return nil
	end
	local function measure(s: any, set: Ghosts.Set, want: (g: any) -> boolean, steps: number): { number }
		local out: { number } = {}
		for _ = 1, steps do
			local g = Ghosts.ghost(set, "blinky") :: any
			local before = snap(g.walker or g)
			local ok = want(g) and not Ghosts.tunnel(s.maze, Ghosts.occupied(g.walker or g))
			Session.step(s)
			if s.members.p.play.phase ~= "playing" then
				break
			end
			local d = travelled(s.maze, before, snap(g.walker or g))
			if ok and want(g) and d then
				table.insert(out, d)
			end
		end
		return out
	end
	local function allEqual(list: { number }, want: number, at: string)
		if #list < 6 then
			error(`{at}: only {#list} steps measured`)
		end
		for _, d in list do
			if d ~= want then
				error(`{at}: a step covered {d} units, want {want}`)
			end
		end
	end

	it("a shipped session's ghosts move the ramp's units a step, hunting and as eyes (capped at a tile)", function()
		for _, level in { 1, 8, 30 } do
			local s = Session.new(Maze.layout("classic"), 1, Session.GAME_CONFIG) :: any
			Session.join(s, "p")
			s.members.p.play.level = level
			local set = s.members.p.ghosts :: Ghosts.Set
			set.level = level
			while s.members.p.play.phase ~= "playing" do
				Session.step(s)
			end
			local sp = Session.speeds(Session.GAME_CONFIG, level)
			if level < 30 then
				allEqual(
					measure(s, set, function(g: any): boolean
						return g.status == "active" and not g.frightened
					end, 30),
					sp.ghost,
					`level {level} hunting`
				)
			end
			local blinky = Ghosts.ghost(set, "blinky") :: any
			local w = blinky.walker or blinky
			w.tile, w.progress, w.heading = { x = 1, y = 1 }, 0, "E" -- the far corner: a long way home
			Ghosts.eat(set, "blinky")
			allEqual(
				measure(s, set, function(g: any): boolean
					return g.status == "eyes"
				end, 10),
				sp.eyes,
				`level {level} eyes`
			)
		end
		t.expect(Session.speeds(Session.GAME_CONFIG, 8).ghost).toBe(25)
		t.expect(Session.speeds(Session.GAME_CONFIG, 30).eyes).toBe(UNITS)
	end)

	it("a ramped ghost set keeps level 1's timetable, house limits and flashes on later levels", function()
		local m = Maze.layout("classic")
		local function input(level: number): Ghosts.Input
			return { player = m.spawn, heading = "W", level = level, baseSpeed = BASE, tickRate = 30 }
		end
		-- the first scatter on level 5: level 1's 7 s with the ramp, the classic level 5's 5 s without
		for _, case in
			{
				{ ramp = R :: Levels.Ramp?, first = Levels.schedule(1, 30)[1] },
				{ ramp = nil, first = Levels.schedule(5, 30)[1] },
			}
		do
			local set = Ghosts.new(m, 1, { level = 5, ramp = case.ramp })
			local n = 0
			while set.mode == "scatter" and n < 1000 do
				Ghosts.step(set, input(5))
				n += 1
			end
			t.expect(n - case.first >= 0 and n - case.first <= 1).toBe(true)
		end
		t.expect(Levels.schedule(1, 30)[1]).toBe(210)
		t.expect(Levels.schedule(5, 30)[1]).toBe(150)
		-- Inky waits for level 1's 30 pellets on a ramped level 2; the classic level 2 lets it out at once
		for _, case in { { ramp = R :: Levels.Ramp?, waits = true }, { ramp = nil, waits = false } } do
			local set = Ghosts.new(m, 1, { level = 2, ramp = case.ramp })
			for _ = 1, 20 do
				Ghosts.step(set, input(2))
			end
			t.expect(Ghosts.ghost(set, "inky").status == "house").toBe(case.waits)
		end
		-- level 1's five flashes on a ramped level 9 (the classic level 9 has three)
		local onRamp = Ghosts.new(m, 1, { level = 9, ramp = R })
		Ghosts.power(onRamp, 60) -- 60 ticks left: inside five flashes of 14 ticks, outside three
		t.expect(Ghosts.look(onRamp, Ghosts.ghost(onRamp, "blinky"))).toBe("blinking")
		local classic = Ghosts.new(m, 1, { level = 9 })
		Ghosts.power(classic, 60)
		t.expect(Ghosts.look(classic, Ghosts.ghost(classic, "blinky"))).toBe("frightened")
	end)

	it("with a ramp the tunnel and frightened ghosts move the exact rate on average, carrying the fraction", function()
		-- the rates, unrounded: classic level 1's factor x 0.7 x 1.05^(n-1) x the tuning
		for _, k in TUNINGS do
			for level = 1, 40 do
				local f = 0.7 * 1.05 ^ (math.min(level, 34) - 1)
				t.expect(math.abs(Levels.ghostRate(BASE, level, "tunnel", k, R) - BASE * 0.5 * f * k) < 1e-9).toBe(true)
				t.expect(math.abs(Levels.ghostRate(BASE, level, "frightened", k, R) - BASE * 0.625 * f * k) < 1e-9)
					.toBe(true)
				t.expect(Levels.ghostRate(BASE, level, "normal", k, R))
					.toBe(Levels.ghostSpeed(BASE, level, "normal", k, R))
				t.expect(Levels.ghostRate(BASE, level, "eyes", k, R)).toBe(Levels.ghostSpeed(BASE, level, "eyes", k, R))
			end
		end
		t.expect(Levels.ghostRate(BASE, 5, "frightened")).toBe(Levels.ghostSpeed(BASE, 5, "frightened")) -- no ramp: whole
		-- a frightened ghost on the shipped level 5: 14.5 units a step on average, as 14s and 15s
		local m = Maze.layout("classic")
		local rate = Levels.ghostRate(BASE, 5, "frightened", 1 / 1.1, R)
		t.expect(math.abs(rate - 14.5) < 0.01).toBe(true)
		local set = Ghosts.new(m, 1, { start = "active", level = 5, tuning = 1 / 1.1, ramp = R })
		Ghosts.power(set, 100000)
		local input: Ghosts.Input = { player = m.spawn, heading = "W", level = 5, baseSpeed = BASE, tickRate = 30 }
		local steps: { number } = {}
		for _ = 1, 60 do
			local g = Ghosts.ghost(set, "blinky") :: any
			local before = snap(g.walker or g)
			local inTunnel = Ghosts.tunnel(m, Ghosts.occupied(g.walker or g))
			Ghosts.step(set, input)
			local d = travelled(m, before, snap(g.walker or g))
			if d and not inTunnel and not Ghosts.tunnel(m, Ghosts.occupied(g.walker or g)) then
				table.insert(steps, d)
			end
		end
		t.expect(#steps >= 40).toBe(true)
		local sum, saw = 0, { [14] = 0, [15] = 0 }
		for _, d in steps do
			if d ~= 14 and d ~= 15 then
				error(`a frightened step covered {d} units, want 14 or 15`)
			end
			saw[d] += 1
			sum += d
		end
		t.expect(saw[14] > 0 and saw[15] > 0).toBe(true)
		t.expect(math.abs(sum / #steps - rate) < 0.1).toBe(true)
		-- a hunting ghost through the side tunnel on level 5: 11.6 units a step on average, as 11s and 12s
		local hunt = Ghosts.new(m, 1, { start = "active", level = 5, tuning = 1 / 1.1, ramp = R })
		local blinky = Ghosts.ghost(hunt, "blinky") :: any
		local w = blinky.walker or blinky
		local tunnelRate = Levels.ghostRate(BASE, 5, "tunnel", 1 / 1.1, R)
		local inside: { number } = {}
		for x = 0, m.width - 1 do
			if Ghosts.tunnel(m, { x = x, y = 14 }) and #inside == 0 then
				w.tile, w.progress, w.heading = { x = x, y = 14 }, 0, if x < m.width / 2 then "W" else "E"
				for _ = 1, 8 do
					local before = snap(w)
					Ghosts.step(hunt, input)
					local d = travelled(m, before, snap(w))
					if d and Ghosts.tunnel(m, before.tile) and Ghosts.tunnel(m, Ghosts.occupied(w)) then
						table.insert(inside, d)
					end
				end
			end
		end
		t.expect(#inside >= 3).toBe(true)
		t.expect(table.find(inside, math.floor(tunnelRate)) ~= nil).toBe(true) -- rounding alone would give 12 every step
		for _, d in inside do
			t.expect(d == math.floor(tunnelRate) or d == math.ceil(tunnelRate)).toBe(true)
		end
	end)
end)
