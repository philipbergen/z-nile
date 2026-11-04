--!strict
-- f0125: the player is about 10% faster relative to a hunting ghost than in the classic tables, on every level,
-- through one pure function, Session.speeds, that the session's own stepping uses too. The shipped config
-- (Session.GAME_CONFIG) carries the change; the default config keeps the classic tables. Speeds are whole units
-- per tick, so the 10% is judged per level on the rounded numbers, within a unit's worth (about 3% at 30 units).
local Ghosts = require("@logic/Ghosts")
local Levels = require("@logic/Levels")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local UNITS = 120 -- Movement.UNITS: sub-tile units per tile

local LAST = Levels.COUNT + 1 -- one level past the table, which repeats its last row

local function edge(c: Session.Config, level: number): number
	local sp = Session.speeds(c, level)
	return sp.player / sp.ghost
end

return t.spec("f0125 player 10% faster than the ghosts", function(it)
	it(
		"on every level the shipped config's edge over a hunting ghost is the classic edge times 1.07 to 1.13",
		function()
			for level = 1, LAST do
				local gain = edge(Session.GAME_CONFIG, level) / edge(Session.DEFAULT_CONFIG, level)
				t.expect(gain >= 1.07 and gain <= 1.13).toBe(true)
			end
		end
	)

	it("averaged over the table's levels the gain is 9% to 13%", function()
		local sum = 0
		for level = 1, Levels.COUNT do
			sum += edge(Session.GAME_CONFIG, level) / edge(Session.DEFAULT_CONFIG, level)
		end
		local mean = sum / Levels.COUNT
		t.expect(mean >= 1.09 and mean <= 1.13).toBe(true)
	end)

	it("the default config keeps the classic tables exactly", function()
		local base = Session.DEFAULT_CONFIG.movement.speed
		for level = 1, LAST do
			for _, frightened in { false, true } do
				local sp = Session.speeds(Session.DEFAULT_CONFIG, level, frightened)
				t.expect(sp.player).toBe(Levels.playerSpeed(base, level, frightened))
			end
			local sp = Session.speeds(Session.DEFAULT_CONFIG, level)
			t.expect(sp.ghost).toBe(Levels.ghostSpeed(base, level, "normal", 1))
			t.expect(sp.tunnel).toBe(Levels.ghostSpeed(base, level, "tunnel", 1))
			t.expect(sp.frightened).toBe(Levels.ghostSpeed(base, level, "frightened", 1))
		end
	end)

	it("the eyes returning home keep twice level 1's player speed", function()
		for level = 1, LAST do
			t.expect(Session.speeds(Session.GAME_CONFIG, level).eyes)
				.toBe(2 * Session.GAME_CONFIG.movement.speed)
		end
	end)

	it(
		"the player's speed in the shipped config stays within one tile a tick on every level, frightened or not",
		function()
			for level = 1, LAST do
				for _, frightened in { false, true } do
					t.expect(Session.speeds(Session.GAME_CONFIG, level, frightened).player <= 120).toBe(true)
				end
			end
		end
	)

	it("a shipped session's ghosts run at the speeds Session.speeds gives", function()
		local s = Session.new(Maze.layout("classic"), 1, Session.GAME_CONFIG)
		Session.join(s, "p")
		local set = (s :: any).members.p.ghosts :: Ghosts.Set -- each member has its own ghosts
		t.expect(set ~= nil).toBe(true)
		local base = Session.GAME_CONFIG.movement.speed
		for level = 1, LAST do
			local sp = Session.speeds(Session.GAME_CONFIG, level)
			t.expect(Levels.ghostSpeed(base, level, "normal", set.tuning)).toBe(sp.ghost)
			t.expect(Levels.ghostSpeed(base, level, "tunnel", set.tuning)).toBe(sp.tunnel)
			t.expect(Levels.ghostSpeed(base, level, "frightened", set.tuning)).toBe(sp.frightened)
		end
	end)

	-- F1 (design review 001): the ghosts of a running session move exactly the units Session.speeds gives, hunting,
	-- frightened and as eyes, on level 1 and level 5. One step's distance is read along the rails: the progress
	-- gained on the same tile, or the rest of the tile plus the progress on the next one. A step that reverses or
	-- starts in a side tunnel is not counted.
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
		local m = s.maze
		local out: { number } = {}
		for _ = 1, steps do
			local g = Ghosts.ghost(set, "blinky") :: any
			local before = snap(g.walker or g)
			local ok = want(g) and not Ghosts.tunnel(m, Ghosts.occupied(g.walker or g))
			Session.step(s)
			if s.members.p.play.phase ~= "playing" then
				break
			end
			local d = travelled(m, before, snap(g.walker or g))
			if ok and want(g) and d then
				table.insert(out, d)
			end
		end
		return out
	end
	local function allEqual(list: { number }, want: number, at: string)
		t.expect(#list >= 8).toBe(true)
		for _, d in list do
			if d ~= want then
				error(`{at}: a step covered {d} units, want {want}`)
			end
		end
	end

	it(
		"a shipped session's ghosts move exactly the units Session.speeds gives, on level 1 and level 5",
		function()
			for _, level in { 1, 5 } do
				local s = Session.new(Maze.layout("classic"), 1, Session.GAME_CONFIG) :: any
				Session.join(s, "p")
				s.members.p.play.level = level
				local set = s.members.p.ghosts :: Ghosts.Set
				set.level = level
				while s.members.p.play.phase ~= "playing" do
					Session.step(s)
				end
				local sp = Session.speeds(Session.GAME_CONFIG, level)
				allEqual(
					measure(s, set, function(g: any): boolean
						return g.status == "active" and not g.frightened
					end, 30),
					sp.ghost,
					`level {level} hunting`
				)
				Ghosts.power(set, 600)
				Session.step(s) -- the power reverses every ghost: not counted
				allEqual(
					measure(s, set, function(g: any): boolean
						return g.status == "active" and g.frightened
					end, 30),
					sp.frightened,
					`level {level} frightened`
				)
				Ghosts.eat(set, "blinky")
				allEqual(
					measure(s, set, function(g: any): boolean
						return g.status == "eyes"
					end, 12),
					sp.eyes,
					`level {level} eyes`
				)
			end
		end
	)

	-- F3 (design review 001): a tuning that would move a ghost more than a tile in a tick, on any level and kind,
	-- is refused, as checkLevelSpeeds refuses it for the player.
	it(
		"a ghost tuning that would move a ghost more than one tile a tick is refused; the shipped and default configs are not",
		function()
			local classic = Maze.layout("classic")
			local fast = table.clone(Session.GAME_CONFIG) :: any
			fast.movement = { speed = 96, turnBufferTicks = 24 }
			fast.ghostTuning = 1.1 -- level 5's hunting ghost: round(96 * 0.95 / 0.8 * 1.1) = 125 > 120
			t.expect((pcall(Session.new, classic, 1, fast))).toBe(false)
			local untuned = table.clone(fast) :: any
			untuned.ghostTuning = nil -- base 96 untuned: level 5's ghost is 114
			t.expect((pcall(Session.new, classic, 1, untuned))).toBe(true)
			t.expect((pcall(Session.new, classic, 1, Session.GAME_CONFIG))).toBe(true)
			-- both sides of the bound at one base (design review 002 F1): level 5's hunting ghost is round(114 * k)
			local at = table.clone(fast) :: any
			at.ghostTuning = 120 / 114 -- exactly 120: allowed
			t.expect((pcall(Session.new, classic, 1, at))).toBe(true)
			local over = table.clone(fast) :: any
			over.ghostTuning = 121 / 114 -- 121: refused
			t.expect((pcall(Session.new, classic, 1, over))).toBe(false)
			-- faster ghosts are allowed when they stay within a tile: GAME_CONFIG's base with twice the speed
			local double = table.clone(Session.GAME_CONFIG) :: any
			double.ghostTuning = 2 -- level 5's ghost: round(30 * 0.95 / 0.8 * 2) = 71
			t.expect((pcall(Session.new, classic, 1, double))).toBe(true)
		end
	)

	it("a ghost tuning that is not a positive finite number is refused when the session is made", function()
		local classic = Maze.layout("classic")
		for _, bad in { 0, -1, 0 / 0, math.huge, "x" :: any } do
			local c = table.clone(Session.GAME_CONFIG) :: any
			c.ghostTuning = bad
			t.expect((pcall(Session.new, classic, 1, c))).toBe(false)
		end
	end)
end)
