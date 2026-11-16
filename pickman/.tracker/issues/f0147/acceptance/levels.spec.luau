--!strict
-- f0147 AC2: levels by picked walls in the session. With a ramp, a level ends when its tenth wall pick
-- finishes, never when the last pellet goes (an emptied maze stays empty: the user, 2026-10-25, "Only picks;
-- maze stays empty"); the next level is a fresh maze (the holes close, every pellet is back, new walls are marked,
-- the player back at the start) and counts its picks from 0; a death keeps the level's count. The tenth pick
-- grants the bonanza instead of a rolled boon (the user, 2026-10-31): one more banked faster pick and one more
-- blaster shot at once, and on the next level longer jumps for all of it and, when its play starts, a long ghost
-- pill (twice the power time). Every point scored on level n is worth n times as much, and the extra life comes at
-- 10,000 times the run's starting level. Without a ramp, nothing here changes: the last pellet clears a level.
local Blaster = require("@logic/Blaster")
local Game = require("@logic/Game")
local Ghosts = require("@logic/Ghosts")
local Hop = require("@logic/Hop")
local Hud = require("@logic/Hud")
local Levels = require("@logic/Levels")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Pellets = require("@logic/Pellets")
local Picks = require("@logic/Picks")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

-- f0126's corridor: interior walls above and below, five pellets west of the player
local CORRIDOR = Maze.parse({ "#########", "#########", "#.....P.#", "#########", "#########" }, "corridor")
-- the same without pellets: picks alone, so no pellet can clear a classic level on the way
-- every pellet west of the player, so a run west eats them all
local WEST = Maze.parse({ "#########", "#########", "#.....P #", "#########", "#########" }, "west")
local BARE = Maze.parse({ "#########", "#########", "#     P #", "#########", "#########" }, "bare")
-- the player starts heading west (Movement.spawn), so it runs from the east end
local LONG = Maze.parse(
	{ "##########################", "#                       P#", "##########################" },
	"long"
)
local R = Levels.RAMP

-- the ramp's rules with no pauses and no ghosts (a level clear goes straight to the next level's play)
local RAMPED: Session.Config = { movement = Movement.DEFAULT_CONFIG, maxIntentsPerTick = 4, ramp = R }
local CLASSIC: Session.Config = { movement = Movement.DEFAULT_CONFIG, maxIntentsPerTick = 4 }

local function new(maze: Maze.Maze, config: Session.Config, seed: number?): any
	local s = Session.new(maze, seed or 1, config)
	Session.join(s, "p")
	return s
end

local function has(events: { Session.Event }, kind: string): Session.Event?
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

-- f0126's walk: asks for a pick and steps until one finishes (or `limit` steps pass), turning back at the
-- corridor's ends whenever it stands with no pick under way; returns the events of the finishing step (or nil) and
-- every event on the way
local function pickOnce(s: any, limit: number?): ({ Session.Event }?, { Session.Event })
	local all: { Session.Event } = {}
	Session.submit(s, "p", "Pick")
	for _ = 1, limit or 600 do
		local events = Session.step(s)
		for _, e in events do
			table.insert(all, e)
		end
		if has(events, "WallPicked") then
			return events, all
		end
		if not s.members.p.move.moving and s.members.p.pick == nil then
			Session.submit(s, "p", "Back") -- at an end, after a stop or a finished pick there
		end
		if s.members.p.pick == nil and s.tick % 8 == 0 then
			Session.submit(s, "p", "Pick")
		end
	end
	return nil, all
end

-- n finished picks; returns the events of the last finishing step
local function picks(s: any, n: number): { Session.Event }
	local last: { Session.Event }? = nil
	for i = 1, n do
		local events = pickOnce(s)
		assert(events, `pick {i} of {n} finished`)
		last = events
	end
	return last :: { Session.Event }
end

-- steps until the run is in play on `level` (at most 200 steps)
local function playingOn(s: any, level: number)
	for _ = 1, 200 do
		local play = s.members.p.play
		if play.phase == "playing" and play.level == level then
			return
		end
		Session.step(s)
	end
	error(`never in play on level {level}`)
end

local function frame(s: any): Session.Frame
	return Session.frame(s, "p")
end

return t.spec("f0147 levels by picked walls", function(it)
	it("nine finished picks keep the level; the tenth clears it, and the next level starts", function()
		local s = new(BARE, RAMPED)
		for i = 1, 9 do
			local events = picks(s, 1)
			t.expect(has(events, "LevelCleared")).toBe(nil)
			t.expect(s.members.p.play.level).toBe(1)
			t.expect(frame(s).play.picks).toBe(i)
		end
		local tenth = picks(s, 1)
		local cleared = has(tenth, "LevelCleared")
		t.expect(cleared ~= nil).toBe(true)
		t.expect((cleared :: Session.Event).level).toBe(1)
		t.expect(s.members.p.play.phase).toBe("levelclear")
		local ready = Session.step(s)
		local e = has(ready, "Ready")
		t.expect(e ~= nil and e.reason == "level" and e.level == 2).toBe(true)
		t.expect(frame(s).play.picks).toBe(0)
	end)

	it(
		"the next level is a fresh maze: holes closed, every pellet back, new marks, the player at the start",
		function()
			local s = new(CORRIDOR, RAMPED)
			picks(s, 9)
			t.expect(#(frame(s).walls :: Session.Walls).opened).toBe(9)
			for x = 1, 5 do
				Pellets.eat(s.members.p.pellets, { x = x, y = 2 }) -- whatever the walk left, eaten
			end
			t.expect(Pellets.remaining(s.members.p.pellets)).toBe(0)
			picks(s, 1)
			playingOn(s, 2)
			local f = frame(s)
			local walls = f.walls :: Session.Walls
			t.expect(#walls.opened).toBe(0)
			t.expect(#walls.marked).toBe(Picks.MARKED)
			for _, tile in walls.marked do
				t.expect(Maze.kind(CORRIDOR, tile)).toBe("wall")
			end
			t.expect(Pellets.remaining(s.members.p.pellets)).toBe(Pellets.remaining(Pellets.new(CORRIDOR)))
			local at = Movement.occupied(CORRIDOR, s.members.p.move)
			t.expect(at.x == CORRIDOR.spawn.x and at.y == CORRIDOR.spawn.y).toBe(true)
		end
	)

	it("eating every pellet does not end a ramped level, and the emptied maze stays empty", function()
		local s = new(WEST, RAMPED) -- the player runs west, over all five pellets, to the wall
		local all: { Session.Event } = {}
		for _ = 1, 120 do
			for _, e in Session.step(s) do
				table.insert(all, e)
			end
		end
		t.expect(Pellets.remaining(s.members.p.pellets)).toBe(0)
		t.expect(has(all, "LevelCleared")).toBe(nil)
		t.expect(s.members.p.play.level).toBe(1)
		t.expect(s.members.p.play.phase).toBe("playing")
		for _ = 1, 300 do
			Session.step(s)
		end
		t.expect(Pellets.remaining(s.members.p.pellets)).toBe(0)
		t.expect(s.members.p.play.level).toBe(1)
	end)

	it("without a ramp the last pellet still clears the level, and picks never do", function()
		local s = new(BARE, CLASSIC)
		local tenth = picks(s, 10)
		t.expect(has(tenth, "LevelCleared")).toBe(nil)
		t.expect(s.members.p.play.level).toBe(1)
		t.expect(frame(s).play.picks).toBe(nil)
		t.expect(frame(s).play.picksGoal).toBe(nil)
		local p = new(WEST, CLASSIC) -- the player runs west over all five pellets
		local cleared = false
		for _ = 1, 120 do
			if has(Session.step(p), "LevelCleared") then
				cleared = true
				break
			end
		end
		t.expect(cleared).toBe(true)
	end)

	it("a wasted pick does not count toward the level; a finished one does", function()
		local s = new(BARE, RAMPED)
		Session.submit(s, "p", "Pick")
		local started = false
		for _ = 1, 200 do
			if has(Session.step(s), "PickStarted") then
				started = true
				break
			end
			if not s.members.p.move.moving and s.members.p.pick == nil then
				Session.submit(s, "p", "Back")
			end
			if s.members.p.pick == nil and s.tick % 8 == 0 then
				Session.submit(s, "p", "Pick")
			end
		end
		t.expect(started).toBe(true)
		Session.submit(s, "p", "Back") -- a movement key wastes it
		local stopped = has(Session.step(s), "PickStopped")
		t.expect(stopped ~= nil and stopped.reason == "moved").toBe(true)
		t.expect(frame(s).play.picks).toBe(0)
		picks(s, 1)
		t.expect(frame(s).play.picks).toBe(1)
	end)

	it("a death keeps the level's pick count; a new run starts it at 0", function()
		local s = new(CORRIDOR, RAMPED)
		picks(s, 3)
		Session.kill(s, "p")
		playingOn(s, 1)
		t.expect(frame(s).play.picks).toBe(3)
		t.expect(frame(s).play.picksGoal).toBe(10)
		for _ = 1, 3 do
			Session.kill(s, "p")
			for _ = 1, 5 do
				Session.step(s)
			end
		end
		t.expect(Session.isOver(s, "p")).toBe(true)
		local _, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(true)
		playingOn(s, 1)
		t.expect(frame(s).play.picks).toBe(0)
	end)

	it("the player runs the ramp's speed on each level: 21 units a step on level 1, 22 on level 2", function()
		for level, want in { 21, 22, 23 } do
			local s = new(LONG, RAMPED)
			s.members.p.play.level = level
			Session.step(s)
			local x0 = Movement.position(s.members.p.move)
			Session.step(s)
			local x1 = Movement.position(s.members.p.move)
			t.expect(math.floor(math.abs(x1 - x0) * 120 + 0.5)).toBe(want) -- position is a float of tiles
		end
	end)

	it(
		"a pick lasts ten paces of the level's ramped hunting ghost: 60 steps on level 1, 55 on level 3",
		function()
			for level, want in { [1] = 60, [3] = 55 } do
				local s = new(BARE, RAMPED)
				s.members.p.play.level = level
				local _, all = pickOnce(s)
				local started = has(all, "PickStarted") :: Session.Event
				t.expect(started.ticks).toBe(want)
				t.expect(started.ticks)
					.toBe(Picks.ticks(Levels.ghostSpeed(30, level, "normal", nil, R), false))
			end
		end
	)

	-- the bonanza --------------------------------------------------------------------------------------------------

	it(
		"the tenth pick grants the bonanza, not a rolled boon: a banked faster pick and a shot at once",
		function()
			local s = new(CORRIDOR, RAMPED)
			picks(s, 9)
			s.members.p.picks.fast = 0 -- whatever the first nine rolled: the tenth pick is not a fast one
			local fast = 0
			local shots = s.members.p.blaster.shots
			s.members.p.longHops = false -- whatever the first nine rolled: the tenth must not start them
			local tenth = picks(s, 1)
			local picked = has(tenth, "WallPicked") :: Session.Event
			t.expect(picked.item).toBe("bonanza")
			t.expect(Picks.BONANZA).toBe("bonanza")
			t.expect(s.members.p.picks.fast).toBe(fast + 1)
			t.expect(s.members.p.blaster.shots).toBe(math.min(shots + 1, Blaster.MAX_SHOTS))
			-- nothing a rolled boon does happens in that step
			t.expect(has(tenth, "PelletsBack")).toBe(nil)
			t.expect(has(tenth, "PowerStarted")).toBe(nil)
			t.expect(s.members.p.longHops).toBe(false) -- the long hops wait for the next level
			local f = frame(s)
			t.expect(f.boon ~= nil and (f.boon :: Session.BoonGrant).kind == "bonanza").toBe(true)
			t.expect((f.boon :: Session.BoonGrant).tick).toBe(s.tick)
		end
	)

	it(
		"a tenth pick that spends a banked faster pick still leaves one banked: one spent, one granted",
		function()
			local s = new(BARE, RAMPED)
			picks(s, 9)
			s.members.p.picks.fast = 1
			local tenth = picks(s, 1)
			t.expect((has(tenth, "WallPicked") :: Session.Event).item).toBe("bonanza")
			t.expect(s.members.p.picks.fast).toBe(1)
		end
	)

	it("the bonanza's shot is wasted when three are held", function()
		local s = new(CORRIDOR, RAMPED)
		picks(s, 9)
		s.members.p.blaster.shots = Blaster.MAX_SHOTS
		local tenth = picks(s, 1)
		t.expect(has(tenth, "ShotGained")).toBe(nil)
		t.expect(s.members.p.blaster.shots).toBe(Blaster.MAX_SHOTS)
		local t2 = new(CORRIDOR, RAMPED)
		picks(t2, 9)
		t2.members.p.blaster.shots = 0
		t.expect(has(picks(t2, 1), "ShotGained") ~= nil).toBe(true)
		t.expect(t2.members.p.blaster.shots).toBe(1)
	end)

	it(
		"the next level has long hops from its start, kept over a death, until the following fresh maze",
		function()
			local s = new(CORRIDOR, RAMPED)
			picks(s, 10)
			playingOn(s, 2)
			Session.submit(s, "p", "Hop")
			Session.step(s)
			t.expect(frame(s).hopTicks).toBe(Hop.LONG_TICKS)
			Session.kill(s, "p")
			playingOn(s, 2)
			for _ = 1, Hop.LONG_TICKS + Hop.COOLDOWN do
				Session.step(s)
			end
			Session.submit(s, "p", "Hop")
			Session.step(s)
			t.expect(frame(s).hopTicks).toBe(Hop.LONG_TICKS)
			-- a new run after a game over on level 2: ordinary hops again
			for _ = 1, 3 do
				Session.kill(s, "p")
				for _ = 1, 5 do
					Session.step(s)
				end
			end
			t.expect(Session.isOver(s, "p")).toBe(true)
			local _, ok = Session.playAgain(s, "p")
			t.expect(ok).toBe(true)
			local r = s
			playingOn(r, 1)
			for _ = 1, 3 do
				Session.step(r)
			end
			Session.submit(r, "p", "Hop")
			Session.step(r)
			t.expect(frame(r).hopTicks).toBe(Hop.TICKS)
			t.expect(r.members.p.play.frightened).toBe(0)
		end
	)

	it("when the next level's play starts, a long ghost pill runs: twice level 1's power time", function()
		local s = new(CORRIDOR, RAMPED)
		picks(s, 10)
		local power: Session.Event? = nil
		for _ = 1, 20 do
			local events = Session.step(s)
			power = has(events, "PowerStarted")
			if power then
				break
			end
			t.expect(
				s.members.p.play.phase == "playing"
					and s.members.p.play.level == 2
					and s.members.p.play.frightened > 0
			).toBe(false)
		end
		t.expect(power ~= nil).toBe(true)
		t.expect((power :: Session.Event).ticks).toBe(2 * Levels.frightenedTicks(1, Session.TICK_RATE))
		t.expect((power :: Session.Event).level).toBe(2)
		t.expect(s.members.p.play.frightened).toBe(360)
	end)

	it("the long ghost pill turns the next level's ghosts blue when its play starts, after READY", function()
		local c = table.clone(Session.GAME_CONFIG) :: any
		c.ramp = table.freeze({ picks = 1, first = R.first, step = R.step, top = R.top }) -- one pick clears a level
		local s = new(Maze.layout("classic"), c)
		local p = s.members.p
		p.picks.marked[1] = { x = 13, y = 24 } -- a pickable wall below the spawn: the pick starts at once
		playingOn(s, 1)
		local set = p.ghosts :: Ghosts.Set
		set.house.idle = -100000 -- nobody leaves the house during the test
		local events =
			pickOnce(s, Picks.ticks(Levels.ghostSpeed(30, 1, "normal", set.tuning, c.ramp), false) + 5)
		t.expect(events ~= nil and has(events :: { Session.Event }, "LevelCleared") ~= nil).toBe(true)
		local sawReady = false
		for _ = 1, 200 do
			local step = Session.step(s)
			if has(step, "Ready") then
				sawReady = true
			end
			if has(step, "PowerStarted") then
				break
			end
			t.expect(set.frightened).toBe(0) -- not blue through the level clear and READY
		end
		t.expect(sawReady).toBe(true)
		t.expect(p.play.level).toBe(2)
		t.expect(set.frightened).toBe(360)
		for _, g in set.ghosts do
			t.expect(g.frightened).toBe(true)
		end
	end)

	it(
		"a ghost meeting the player in the step the tenth pick finishes does not kill: the cleared level wins",
		function()
			local c = table.clone(Session.GAME_CONFIG) :: any
			c.ramp = table.freeze({ picks = 1, first = R.first, step = R.step, top = R.top }) -- one pick clears a level
			local s = new(Maze.layout("classic"), c)
			local p = s.members.p
			p.picks.marked[1] = { x = 13, y = 24 } -- below the spawn: the pick starts at once
			playingOn(s, 1)
			local set = p.ghosts :: Ghosts.Set
			for _, g in set.ghosts do
				g.tile, g.progress, g.status, g.frightened, g.reverse =
					{ x = 13, y = 14 }, 0, "house", false, false
			end
			set.house.idle = -100000
			Session.submit(s, "p", "Pick")
			local started: Session.Event? = nil
			for _ = 1, 5 do
				started = has(Session.step(s), "PickStarted")
				if started then
					break
				end
			end
			t.expect(started ~= nil).toBe(true)
			local pick = p.pick :: Session.Pick
			while s.tick < pick.started + pick.ticks - 1 do
				Session.step(s)
			end
			t.expect(p.pick ~= nil).toBe(true) -- one step left
			-- an active, hunting Blinky on the player's own tile, heading away: a catch in the coming step
			local blinky = Ghosts.ghost(set, "blinky") :: any
			local w = blinky.walker or blinky
			local at = Movement.occupied(s.maze, p.move)
			w.tile, w.progress, w.heading = { x = at.x, y = at.y }, 0, "E"
			blinky.status, blinky.frightened, blinky.reverse = "active", false, false
			local lives = p.play.lives
			local events = Session.step(s)
			t.expect(has(events, "LevelCleared") ~= nil).toBe(true)
			t.expect(has(events, "LifeLost")).toBe(nil)
			t.expect(p.play.lives).toBe(lives)
			t.expect(p.play.phase).toBe("levelclear")
			-- the same Blinky one step earlier (no pick finishing) does catch: the case can tell
			local again = new(Maze.layout("classic"), c)
			playingOn(again, 1)
			local other = again.members.p.ghosts :: Ghosts.Set
			local b2 = Ghosts.ghost(other, "blinky") :: any
			local w2 = b2.walker or b2
			local here = Movement.occupied(again.maze, again.members.p.move)
			w2.tile, w2.progress, w2.heading = { x = here.x, y = here.y }, 0, "E"
			b2.status, b2.frightened, b2.reverse = "active", false, false
			t.expect(has(Session.step(again), "LifeLost") ~= nil).toBe(true)
		end
	)

	it("a death on a level the bonanza reached does not start its long ghost pill again", function()
		local s = new(CORRIDOR, RAMPED)
		picks(s, 10)
		local first: Session.Event? = nil
		for _ = 1, 20 do
			first = has(Session.step(s), "PowerStarted")
			if first then
				break
			end
		end
		t.expect(first ~= nil).toBe(true)
		Session.step(s)
		Session.kill(s, "p")
		local again: Session.Event? = nil
		for _ = 1, 30 do
			again = again or has(Session.step(s), "PowerStarted")
		end
		t.expect(again).toBe(nil)
		t.expect(s.members.p.play.frightened).toBe(0)
		t.expect(s.members.p.play.level).toBe(2)
		t.expect(s.members.p.longHops).toBe(true) -- the long hops stay over the death
	end)

	it(
		"with long hops on, a rolled longer-jumps boon still comes up and grants nothing more (the user's choice)",
		function()
			-- the first seed whose first pick on level 2, with the bonanza's long hops on, rolls longer jumps
			local found = false
			for seed = 1, 120 do
				local s = new(BARE, RAMPED, seed)
				local p = s.members.p
				p.play.level = 2
				p.longHops = true
				p.picks.fast = 0
				p.blaster.shots = 0
				local events = pickOnce(s)
				assert(events, `seed {seed}: the pick finished`)
				local picked = has(events :: { Session.Event }, "WallPicked") :: Session.Event
				if picked.item == "jumps" then
					found = true
					local e = events :: { Session.Event }
					t.expect(has(e, "PowerStarted")).toBe(nil)
					t.expect(has(e, "PelletsBack")).toBe(nil)
					t.expect(has(e, "ShotGained")).toBe(nil)
					t.expect(p.picks.fast).toBe(0)
					t.expect(p.blaster.shots).toBe(0)
					t.expect(p.longHops).toBe(true)
					t.expect((frame(s).boon :: Session.BoonGrant).kind).toBe("jumps")
					t.expect(Hud.boonBanner(frame(s).boon, s.tick)).toBe("LONGER JUMPS")
					break
				end
			end
			t.expect(found).toBe(true)
		end
	)

	it("long hops on or off, the same seed rolls the same boon: the roll stays even among the six", function()
		local jumps = 0
		for seed = 1, 40 do
			local items: { string } = {}
			for _, hops in { false, true } do
				local s = new(BARE, RAMPED, seed)
				s.members.p.play.level = 2
				s.members.p.longHops = hops
				local events = pickOnce(s)
				assert(events, `seed {seed}: the pick finished`)
				table.insert(
					items,
					(has(events :: { Session.Event }, "WallPicked") :: Session.Event).item :: string
				)
			end
			if items[1] ~= items[2] then
				error(`seed {seed}: {items[1]} with long hops off, {items[2]} with them on`)
			end
			if items[1] == "jumps" then
				jumps += 1
			end
		end
		t.expect(jumps >= 3).toBe(true)
	end)

	-- the points --------------------------------------------------------------------------------------------------

	it(
		"with a ramp a pellet on level n scores 10 x n and a power pellet 50 x n; without one, as ever",
		function()
			local m = Maze.parse({ "#######", "#o..P.#", "#######" }, "dots")
			for _, level in { 1, 2, 3, 7 } do
				for _, config in { RAMPED, CLASSIC } do
					local s = new(m, config)
					s.members.p.play.level = level -- the player runs west over two pellets and the power pellet
					local got: { [string]: number } = {}
					for _ = 1, 60 do
						for _, e in Session.step(s) do
							if e.kind == "PelletEaten" then
								got[e.item :: string] = e.points :: number
							end
						end
					end
					local n = if config == RAMPED then level else 1
					t.expect(got.pellet).toBe(10 * n)
					t.expect(got.power).toBe(50 * n)
					t.expect(s.members.p.play.score).toBe((2 * 10 + 50) * n)
				end
			end
		end
	)

	it(
		"with a ramp a ghost eaten on level n scores its chain value x n, by contact and by a shot; without one, as ever",
		function()
			for _, case in
				{ { level = 1, ramped = true }, { level = 3, ramped = true }, { level = 3, ramped = false } }
			do
				local level = case.level
				local c = table.clone(Session.GAME_CONFIG) :: any
				if not case.ramped then
					c.ramp = nil -- the shipped rules less the ramp: no multiplier
				end
				local n = if case.ramped then level else 1
				local s = new(Maze.layout("classic"), c)
				local p = s.members.p
				p.play.level = level
				playingOn(s, level)
				local set = p.ghosts :: Ghosts.Set
				for _, g in set.ghosts do
					g.tile, g.progress, g.status, g.frightened, g.reverse =
						{ x = 13, y = 14 }, 0, "house", false, false
				end
				set.house.idle = -100000
				-- a shot along the row: Blinky three tiles west of the player, active
				p.blaster.shots = 1
				local blinky = Ghosts.ghost(set, "blinky") :: any
				local w = blinky.walker or blinky
				w.tile, w.progress, w.heading = { x = 10, y = 23 }, 0, "W"
				blinky.status, blinky.frightened = "active", false
				local before = p.play.score
				Session.submit(s, "p", Blaster.intent("W"))
				local shot = has(Session.step(s), "Shot") :: Session.Event
				t.expect(shot.ghost).toBe("blinky")
				t.expect(shot.points).toBe(200 * n)
				t.expect(p.play.score - before).toBe(200 * n)
				-- by contact: a blue Pinky on the tile ahead of the player, who runs west into it; the chain's second
				local pinky = Ghosts.ghost(set, "pinky") :: any
				local pw = pinky.walker or pinky
				local at = Movement.occupied(s.maze, p.move)
				pw.tile, pw.progress = { x = at.x - 1, y = at.y }, 0
				pinky.status, pinky.frightened = "active", true
				set.frightened = 100
				p.play.frightened = 100
				before = p.play.score
				local eaten: Session.Event? = nil
				local paid = 0 -- every point the steps' events report (a pellet on the way too)
				for _ = 1, 10 do
					local events = Session.step(s)
					for _, e in events do
						if e.kind == "PelletEaten" or e.kind == "GhostEaten" then
							paid += e.points :: number
						end
					end
					eaten = has(events, "GhostEaten")
					if eaten then
						break
					end
				end
				t.expect(eaten ~= nil).toBe(true)
				t.expect((eaten :: Session.Event).points).toBe(400 * n)
				t.expect(p.play.score - before).toBe(paid)
			end
		end
	)

	it(
		"the extra life comes at 10,000 x the run's starting level, counted on the multiplied score",
		function()
			local g = Game.new(Game.IMMEDIATE_CONFIG, R)
			t.expect(g.start).toBe(1)
			t.expect(#Game.addScore(g, 9999)).toBe(0)
			local life = Game.addScore(g, 1)
			t.expect(#life == 1 and life[1].kind == "ExtraLife").toBe(true)
			local h = Game.new(Game.IMMEDIATE_CONFIG, R)
			h.start, h.level = 2, 2
			t.expect(#Game.addScore(h, Game.points(h, 5000))).toBe(0) -- 10,000 on level 2: not yet 20,000
			t.expect(#Game.addScore(h, Game.points(h, 4999))).toBe(0) -- 19,998
			t.expect(#Game.addScore(h, Game.points(h, 1))).toBe(1) -- 20,000
			t.expect(Game.points(h, 10)).toBe(20)
			t.expect(Game.points(Game.new(Game.IMMEDIATE_CONFIG), 10)).toBe(10) -- no ramp: as it is
			-- a new run starts on the starting level again
			local again = Game.new(Game.IMMEDIATE_CONFIG, R)
			again.level, again.phase = 5, "gameover"
			local events, ok = Game.playAgain(again)
			t.expect(ok).toBe(true)
			t.expect(again.level).toBe(1)
			t.expect(events[1].level).toBe(1)
			-- the threshold reads the start, not the level being played
			for _, case in { { start = 1, level = 3, at = 10000 }, { start = 2, level = 5, at = 20000 } } do
				local g2 = Game.new(Game.IMMEDIATE_CONFIG, R)
				g2.start, g2.level = case.start, case.level
				t.expect(#Game.addScore(g2, case.at - 1)).toBe(0)
				t.expect(#Game.addScore(g2, 1)).toBe(1)
			end
			local later = Game.new(Game.IMMEDIATE_CONFIG, R)
			later.start, later.level, later.phase = 3, 6, "gameover" -- f0148 sets the start; a new run begins there
			local again3, ok3 = Game.playAgain(later)
			t.expect(ok3).toBe(true)
			t.expect(later.level).toBe(3)
			t.expect(again3[1].level).toBe(3)
		end
	)
end)
