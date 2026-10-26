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

	it("a ghost tuning that is not a positive finite number is refused when the session is made", function()
		local classic = Maze.layout("classic")
		for _, bad in { 0, -1, 0 / 0, math.huge, "x" :: any } do
			local c = table.clone(Session.GAME_CONFIG) :: any
			c.ghostTuning = bad
			t.expect((pcall(Session.new, classic, 1, c))).toBe(false)
		end
	end)
end)
