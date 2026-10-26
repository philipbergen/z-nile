--!strict
-- f0126 AC3: a pick in the session, server-side. The Pick intent asks for one; the player stops on the next tile
-- centre beside a marked wall and stands there for the pick's time (a hunting ghost's ten tiles: 43 steps on level
-- 1); then the wall opens, a new wall is marked, a boon is granted and the player goes on. A movement key, a hop or
-- leaving play (a death, a cleared level) wastes it. The frame carries the walls, the pick and the latest boon.
--
-- The corridor runs west from the spawn (6, 2) to (1, 2), between two thick walls whose rows 1 and 3 can be picked;
-- the player walks west at 30 units a step, a tile in 4 steps. Which walls are marked is read from the frame.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Picks = require("@logic/Picks")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local CORRIDOR = Maze.parse({ "#########", "#########", "#.....P.#", "#########", "#########" }, "corridor")
local Blaster = require("@logic/Blaster")
local Levels = require("@logic/Levels")

-- level 1's numbers, from the tables (43 steps today: a hunting ghost walks 28 units a step, 1200 / 28 rounded up;
-- the player walks 30 units a step, a tile in 4 steps)
local BASE = Movement.DEFAULT_CONFIG.speed
local PICK_TICKS = Picks.ticks(Levels.ghostSpeed(BASE, 1, "normal"), false)
local SPEED = Levels.playerSpeed(BASE, 1)
local REACH = math.ceil(Movement.UNITS / SPEED) -- steps from one centre to the next
local BUFFER = Movement.DEFAULT_CONFIG.turnBufferTicks

local function key(tile: Maze.Tile): string
	return `{tile.x},{tile.y}`
end

local function marked(s: Session.Session, x: number, y: number): boolean
	for _, tile in (Session.frame(s, "p").walls :: Session.Walls).marked do
		if tile.x == x and tile.y == y then
			return true
		end
	end
	return false
end

-- The first tile west from x (inclusive) with a marked wall beside it, and that wall (south first: left of west).
local function firstStop(s: Session.Session, from: number): (number?, Maze.Tile?)
	for x = from, 1, -1 do
		if marked(s, x, 3) then
			return x, { x = x, y = 3 }
		elseif marked(s, x, 1) then
			return x, { x = x, y = 1 }
		end
	end
	return nil, nil
end

local function new(seed: number, config: Session.Config?): Session.Session
	local s = Session.new(CORRIDOR, seed, config)
	Session.join(s, "p")
	return s
end

-- The first seed (from 1) whose session satisfies `ok`.
local function seedWhere(ok: (Session.Session) -> boolean, config: Session.Config?): number
	for seed = 1, 2000 do
		if ok(new(seed, config)) then
			return seed
		end
	end
	error("no seed found")
end

type Run = { events: { Session.Event }, at: { [string]: number } }

-- Steps n times; records every event and the first tick of each kind.
local function run(s: Session.Session, n: number, script: { [number]: { string } }?): Run
	local r: Run = { events = {}, at = {} }
	for _ = 1, n do
		local next = s.tick + 1
		local raws: { string } = (script and script[next]) or {}
		for _, raw in raws do
			Session.submit(s, "p", raw)
		end
		for _, e in Session.step(s) do
			table.insert(r.events, e)
			if r.at[e.kind] == nil then
				r.at[e.kind] = s.tick
			end
		end
	end
	return r
end

local function count(r: Run, kind: string): number
	local n = 0
	for _, e in r.events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function find(r: Run, kind: string): Session.Event?
	for _, e in r.events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

-- the step in which the player, walking west from the spawn, is on x's centre: 1 for the spawn, REACH a tile after
-- (the step that reaches a centre is cut short there)
local function arrival(x: number): number
	return if x == 6 then 1 else math.ceil((6 - x) * Movement.UNITS / SPEED)
end

local PLAY: Session.Config = {
	movement = Movement.DEFAULT_CONFIG,
	maxIntentsPerTick = 4,
	play = Game.CLASSIC_CONFIG,
}

return t.spec("f0126 picks in the session", function(it)
	it("accepts Pick on the Intent remote, and a repeat in one tick too", function()
		local s = new(1)
		for _ = 1, 6 do
			local ok, why = Session.submit(s, "p", "Pick")
			t.expect(ok).toBe(true)
			t.expect(why).toBe(nil)
		end
		local ok, why = Session.submit(s, "p", "pick")
		t.expect(ok).toBe(false)
		t.expect(why).toBe("invalid intent")
		t.expect((Session.submit(s, "p", "Left"))).toBe(true) -- a pick request does not use up the movement limit
	end)

	it("a fresh run shows three marked walls, no holes, no pick and no boon", function()
		local f = Session.frame(new(4), "p")
		local walls = f.walls :: Session.Walls
		t.expect(#walls.marked).toBe(3)
		t.expect(#walls.opened).toBe(0)
		for _, tile in walls.marked do
			t.expect(Picks.pickable(CORRIDOR, tile)).toBe(true)
		end
		t.expect(f.pick).toBe(nil)
		t.expect(f.boon).toBe(nil)
	end)

	it("the player stops on the first centre beside a marked wall and the pick starts there", function()
		for seed = 1, 12 do
			local s = new(seed)
			local stopX, wall = firstStop(s, 6)
			local r = run(s, 30, { [1] = { "Pick" } })
			local started = find(r, "PickStarted") :: Session.Event
			t.expect(started ~= nil).toBe(true)
			t.expect(r.at.PickStarted).toBe(arrival(stopX :: number))
			t.expect(key({ x = started.x :: number, y = started.y :: number })).toBe(key(wall :: Maze.Tile))
			t.expect(started.ticks).toBe(PICK_TICKS)
			local f = Session.frame(s, "p")
			t.expect(f.player.x).toBe(stopX)
			t.expect(f.player.y).toBe(2)
			t.expect(f.player.moving).toBe(false)
			local pick = f.pick :: Session.Pick
			t.expect(key(pick.wall)).toBe(key(wall :: Maze.Tile))
			t.expect(pick.started).toBe(r.at.PickStarted)
			t.expect(pick.ticks).toBe(PICK_TICKS)
		end
	end)

	it(
		"the player stands for the whole pick, and the wall opens exactly PICK_TICKS steps after it began",
		function()
			local s = new(seedWhere(function(c)
				return (firstStop(c, 6)) == 4
			end))
			local _, wall = firstStop(s, 6)
			local r = run(s, arrival(4), { [1] = { "Pick" } })
			t.expect(r.at.PickStarted).toBe(arrival(4))
			local started = r.at.PickStarted
			for _ = 1, PICK_TICKS - 1 do
				local more = run(s, 1)
				t.expect(count(more, "WallPicked")).toBe(0)
				t.expect(Session.frame(s, "p").player.x).toBe(4)
			end
			local last = run(s, 1)
			t.expect(s.tick).toBe(started + PICK_TICKS)
			local picked = find(last, "WallPicked") :: Session.Event
			t.expect(picked ~= nil).toBe(true)
			t.expect(key({ x = picked.x :: number, y = picked.y :: number })).toBe(key(wall :: Maze.Tile))
			t.expect(table.find(Picks.BOONS :: any, picked.item) ~= nil).toBe(true)
		end
	)

	it("a finished pick opens the wall, marks another and grants the boon in the frame", function()
		local s = new(seedWhere(function(c)
			return (firstStop(c, 6)) == 5
		end))
		local _, wall = firstStop(s, 6)
		local r = run(s, arrival(5) + PICK_TICKS, { [1] = { "Pick" } })
		local picked = find(r, "WallPicked") :: Session.Event
		local f = Session.frame(s, "p")
		local walls = f.walls :: Session.Walls
		t.expect(#walls.opened).toBe(1)
		t.expect(key(walls.opened[1])).toBe(key(wall :: Maze.Tile))
		t.expect(#walls.marked).toBe(3)
		for _, tile in walls.marked do
			t.expect(key(tile) ~= key(wall :: Maze.Tile)).toBe(true)
		end
		t.expect(f.pick).toBe(nil)
		local boon = f.boon :: Session.BoonGrant
		t.expect(boon.tick).toBe(arrival(5) + PICK_TICKS)
		t.expect(boon.kind).toBe(picked.item)
		local played = Maze.opened(CORRIDOR, walls.opened)
		t.expect(Maze.kind(played, wall :: Maze.Tile)).toBe("empty")
	end)

	it("after the pick the player goes on along the corridor by itself", function()
		local s = new(seedWhere(function(c)
			return (firstStop(c, 6)) == 5
		end))
		run(s, arrival(5) + PICK_TICKS, { [1] = { "Pick" } })
		-- it sets off in the very step the pick finishes: a step's worth (30 of 120 units) west already
		t.expect(Session.frame(s, "p").player.moving).toBe(true)
		t.expect(Session.frame(s, "p").player.x).toBe(5 - SPEED / Movement.UNITS)
		run(s, REACH - 1)
		t.expect(Session.frame(s, "p").player.x).toBe(4)
	end)

	it("a movement key during the pick wastes it: no wall opens, and the player goes", function()
		for _, raw in { "Back", "Forward", "Left", "Right" } do
			local s = new(seedWhere(function(c)
				return (firstStop(c, 6)) == 5
			end))
			local _, wall = firstStop(s, 6)
			local r = run(s, 80, { [1] = { "Pick" }, [arrival(5) + 10] = { raw } })
			t.expect(count(r, "PickStarted")).toBe(1)
			t.expect(count(r, "WallPicked")).toBe(0)
			local stopped = find(r, "PickStopped") :: Session.Event
			t.expect(stopped.reason).toBe("moved")
			t.expect(r.at.PickStopped).toBe(arrival(5) + 10)
			local f = Session.frame(s, "p")
			t.expect(#(f.walls :: Session.Walls).opened).toBe(0)
			t.expect(marked(s, (wall :: Maze.Tile).x, (wall :: Maze.Tile).y)).toBe(true)
			t.expect(f.player.x ~= 5 or f.player.moving).toBe(true) -- it left, or is on its way
		end
	end)

	it(
		"Forward during the pick sets the player going again, though Forward never restarts a stopped player",
		function()
			local s = new(seedWhere(function(c)
				return (firstStop(c, 6)) == 5
			end))
			run(s, arrival(5) + 10, { [1] = { "Pick" }, [arrival(5) + 10] = { "Forward" } })
			t.expect(Session.frame(s, "p").player.moving).toBe(true)
			t.expect(Session.frame(s, "p").player.x).toBe(5 - SPEED / Movement.UNITS) -- on its way in the step the key arrived
			run(s, 3)
			t.expect(Session.frame(s, "p").player.x).toBe(4)
		end
	)

	it("a hop during the pick wastes it, and the player goes on", function()
		local s = new(seedWhere(function(c)
			return (firstStop(c, 6)) == 5
		end))
		local r = run(s, 90, { [1] = { "Pick" }, [arrival(5) + 10] = { "Hop" } })
		t.expect(count(r, "Hopped")).toBe(1)
		t.expect(count(r, "WallPicked")).toBe(0)
		local stopped = find(r, "PickStopped") :: Session.Event
		t.expect(stopped.reason).toBe("hopped")
		t.expect(r.at.PickStopped).toBe(arrival(5) + 10)
		t.expect(Session.frame(s, "p").player.x < 5).toBe(true)
	end)

	it("a key in the step the pick finishes does not waste it", function()
		local s = new(seedWhere(function(c)
			return (firstStop(c, 6)) == 5
		end))
		local done = arrival(5) + PICK_TICKS
		local r = run(s, done + 2, { [1] = { "Pick" }, [done] = { "Back" } })
		t.expect(count(r, "WallPicked")).toBe(1)
		t.expect(count(r, "PickStopped")).toBe(0)
		t.expect(Session.frame(s, "p").player.heading).toBe("E")
	end)

	it(
		"a Pick pressed during a pick is ignored: once it finishes the player walks on past the next mark",
		function()
			local seed = seedWhere(function(c)
				return (firstStop(c, 6)) == 6 and (firstStop(c, 5)) ~= nil
			end)
			local s = new(seed)
			local r = run(s, 1 + PICK_TICKS + 40, { [1] = { "Pick" }, [20] = { "Pick" }, [40] = { "Pick" } })
			t.expect(count(r, "PickStarted")).toBe(1)
			t.expect(count(r, "WallPicked")).toBe(1)
			-- the control: the same press just after the pick does start the next one
			local again = new(seed)
			local r2 = run(again, 1 + PICK_TICKS + 40, { [1] = { "Pick" }, [2 + PICK_TICKS] = { "Pick" } })
			t.expect(count(r2, "PickStarted")).toBe(2)
		end
	)

	it("no pick starts while a hop is under way, from take-off to landing", function()
		local s = new(seedWhere(function(c)
			return (firstStop(c, 6)) == 6 and (firstStop(c, 5)) ~= nil
		end))
		local r = run(s, 40, { [1] = { "Hop", "Pick" } })
		t.expect(r.at.Hopped).toBe(1)
		t.expect(r.at.PickStarted ~= nil).toBe(true)
		t.expect((r.at.PickStarted :: number) >= 1 + 12).toBe(true) -- Hop.TICKS: landed
	end)

	it("a request lasts as long as a buffered turn, and then lapses", function()
		-- the player stands at the corridor's west end, where no wall is marked, then walks back east past them
		local function setup(): Session.Session
			return new(seedWhere(function(c)
				return not marked(c, 1, 1) and not marked(c, 1, 3) and (firstStop(c, 6)) ~= 6
			end))
		end
		local s = setup()
		run(s, 30) -- west to the end: stopped at (1, 2)
		t.expect(Session.frame(s, "p").player.x).toBe(1)
		local soon = run(s, 80, { [s.tick + 1] = { "Pick" }, [s.tick + 10] = { "Back" } })
		t.expect(count(soon, "PickStarted")).toBe(1)
		local late = setup()
		run(late, 30)
		local r = run(late, 80, { [late.tick + 1] = { "Pick" }, [late.tick + 30] = { "Back" } })
		t.expect(count(r, "PickStarted")).toBe(0)
	end)

	it("a request with no marked wall on the way does nothing", function()
		local s = new(seedWhere(function(c)
			return not marked(c, 1, 1) and not marked(c, 1, 3)
		end))
		run(s, 30)
		local r = run(s, 60, { [s.tick + 1] = { "Pick" } })
		t.expect(count(r, "PickStarted")).toBe(0)
		t.expect(Session.frame(s, "p").player.x).toBe(1)
	end)

	it("a request in a pause is forgotten", function()
		local s = new(
			seedWhere(function(c)
				return (firstStop(c, 6)) ~= nil
			end, PLAY),
			PLAY
		)
		local r = run(s, 150, { [1] = { "Pick" } }) -- "Ready!" lasts 60 steps
		t.expect(count(r, "PickStarted")).toBe(0)
	end)

	it("a death during the pick wastes it; the holes already open and the marks stay", function()
		local seed = seedWhere(function(c)
			return (firstStop(c, 6)) == 5 and (firstStop(c, 4)) ~= nil
		end, PLAY)
		local s = new(seed, PLAY)
		run(s, 60) -- "Ready!"
		local begin = s.tick
		local r = run(s, 5 + PICK_TICKS, { [begin + 1] = { "Pick" } })
		t.expect(count(r, "WallPicked")).toBe(1)
		local holes = key((Session.frame(s, "p").walls :: Session.Walls).opened[1])
		local marks = (Session.frame(s, "p").walls :: Session.Walls).marked
		local r2 = run(s, 20, { [s.tick + 1] = { "Pick" } })
		t.expect(count(r2, "PickStarted")).toBe(1)
		Session.kill(s, "p")
		local r3 = run(s, 200)
		t.expect(count(r3, "WallPicked")).toBe(0)
		t.expect((find(r3, "PickStopped") :: Session.Event).reason).toBe("pause")
		local f = Session.frame(s, "p")
		t.expect(f.pick).toBe(nil)
		t.expect(#(f.walls :: Session.Walls).opened).toBe(1)
		t.expect(key((f.walls :: Session.Walls).opened[1])).toBe(holes)
		local now = (f.walls :: Session.Walls).marked
		t.expect(#now).toBe(3)
		for i, tile in marks do
			t.expect(key(now[i])).toBe(key(tile))
		end
	end)

	it("a new level starts from a fresh maze: no holes and new marks", function()
		local seed = seedWhere(function(c)
			return (firstStop(c, 6)) == 6
		end, PLAY)
		local s = new(seed, PLAY)
		run(s, 60)
		run(s, 2 + PICK_TICKS, { [s.tick + 1] = { "Pick" } })
		t.expect(#(Session.frame(s, "p").walls :: Session.Walls).opened).toBe(1)
		-- the player goes on west eating (5..1, 2), stops at the end, turns back east to the last pellet (7, 2)
		run(s, 30)
		t.expect(Session.frame(s, "p").player.x).toBe(1)
		local r = run(s, 40, { [s.tick + 1] = { "Back" } })
		t.expect(r.at.LevelCleared ~= nil).toBe(true)
		run(s, 70) -- the level-clear pause, then Ready for level 2
		local f = Session.frame(s, "p")
		t.expect(f.play.level).toBe(2)
		local walls = f.walls :: Session.Walls
		t.expect(#walls.opened).toBe(0)
		t.expect(#walls.marked).toBe(3)
		for _, tile in walls.marked do
			t.expect(Maze.kind(CORRIDOR, tile)).toBe("wall")
			t.expect(Picks.pickable(CORRIDOR, tile)).toBe(true)
		end
	end)

	it("the hole is open to walk into: a turn at the pick's centre takes the player into it", function()
		for seed = 1, 400 do
			local s = new(seed)
			local stopX, wall = firstStop(s, 6)
			if stopX and stopX >= 2 then
				local done = arrival(stopX) + PICK_TICKS
				-- the wall is south (left of west) or north (right of west) of the corridor
				local turn = if (wall :: Maze.Tile).y == 3 then "Left" else "Right"
				local r = run(s, done + 8, { [1] = { "Pick" }, [done] = { turn } })
				local entered = false
				for _, e in r.events do
					if
						e.kind == "Entered"
						and e.x == (wall :: Maze.Tile).x
						and e.y == (wall :: Maze.Tile).y
					then
						entered = true
					end
				end
				t.expect(entered).toBe(true)
				local f = Session.frame(s, "p")
				t.expect(f.player.x).toBe((wall :: Maze.Tile).x)
				t.expect(f.player.y).toBe((wall :: Maze.Tile).y)
				t.expect(f.player.moving).toBe(false) -- a one-tile nook: the wall beyond stops the player
				return
			end
		end
		error("no seed")
	end)

	it(
		"a movement key in the step the player would stop wins: no pick starts that step, the key acts",
		function()
			local s = new(seedWhere(function(c)
				return (firstStop(c, 6)) == 6
			end))
			local r = run(s, 1, { [1] = { "Pick", "Back" } })
			t.expect(count(r, "PickStarted")).toBe(0)
			t.expect(Session.frame(s, "p").player.heading).toBe("E")
		end
	)

	it(
		"a request lapses exactly: a mark first in reach on its 24th step is picked, on its 25th it is not",
		function()
			-- the player stands at the west end (1, 2) with no mark beside it and a mark beside (2, 2); a Back sets
			-- them going east, and they are on (2, 2)'s centre REACH - 1 steps after the Back's step
			local function setup(): Session.Session
				return new(seedWhere(function(c)
					return not marked(c, 1, 1)
						and not marked(c, 1, 3)
						and (marked(c, 2, 1) or marked(c, 2, 3))
				end))
			end
			local function picks(backAfter: number): number
				local s = setup()
				run(s, 30)
				t.expect(Session.frame(s, "p").player.x).toBe(1)
				local k = s.tick + 1 -- the request's first step
				local r = run(s, 40, { [k] = { "Pick" }, [k + backAfter] = { "Back" } })
				return count(r, "PickStarted")
			end
			-- a Back in step k + j puts the player on (2, 2)'s centre in step k + j + REACH - 1
			t.expect(picks(BUFFER - REACH)).toBe(1) -- there in step k + BUFFER - 1: the request's last step
			t.expect(picks(BUFFER - REACH + 1)).toBe(0) -- there in step k + BUFFER: lapsed
		end
	)

	it("a new run starts from a fresh maze: no holes and new marks", function()
		local seed = seedWhere(function(c)
			return (firstStop(c, 6)) == 6
		end, PLAY)
		local s = new(seed, PLAY)
		run(s, 60)
		run(s, 2 + PICK_TICKS, { [s.tick + 1] = { "Pick" } })
		t.expect(#(Session.frame(s, "p").walls :: Session.Walls).opened).toBe(1)
		for _ = 1, 3 do
			Session.kill(s, "p")
			run(s, 110)
		end
		t.expect(Session.isOver(s, "p")).toBe(true)
		t.expect(#(Session.frame(s, "p").walls :: Session.Walls).opened).toBe(1) -- kept through the deaths
		local _, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(true)
		run(s, 1)
		local walls = Session.frame(s, "p").walls :: Session.Walls
		t.expect(#walls.opened).toBe(0)
		t.expect(#walls.marked).toBe(3)
		for _, tile in walls.marked do
			t.expect(Maze.kind(CORRIDOR, tile)).toBe("wall")
		end
	end)

	it("firing during the pick does not waste it", function()
		local s = new(seedWhere(function(c)
			return (firstStop(c, 6)) == 5
		end))
		local r = run(s, arrival(5) + PICK_TICKS + 2, {
			[1] = { "Pick" },
			[arrival(5) + 5] = { Blaster.intent("W") },
			[arrival(5) + 20] = { Blaster.intent("N") },
		})
		t.expect(count(r, "PickStopped")).toBe(0)
		t.expect(count(r, "WallPicked")).toBe(1)
	end)

	it("a repeat Pick restarts the request's time", function()
		local s = new(seedWhere(function(c)
			return not marked(c, 1, 1) and not marked(c, 1, 3) and (marked(c, 2, 1) or marked(c, 2, 3))
		end))
		run(s, 30)
		local k = s.tick + 1
		-- pressed again 15 steps in: the Back comes 15 steps after the first request would have lapsed
		local back = 15 + BUFFER - REACH
		local r = run(s, 80, { [k] = { "Pick" }, [k + 15] = { "Pick" }, [k + back] = { "Back" } })
		t.expect(count(r, "PickStarted")).toBe(1)
	end)

	it("a new level marks walls of the fresh maze, not of the one with holes, and new ones", function()
		-- thick walls: rows 1 and 5 can be picked only once a hole in row 2 or 4 is beside them
		local THICK = Maze.parse({
			"#########",
			"#########",
			"#########",
			"#.....P.#",
			"#########",
			"#########",
			"#########",
		}, "thick")
		local changed, levels = 0, 0
		for seed = 1, 40 do
			local s = Session.new(THICK, seed, PLAY)
			Session.join(s, "p")
			run(s, 60)
			local r = run(s, 100, { [s.tick + 1] = { "Pick" } })
			if count(r, "WallPicked") == 1 then
				local before = {}
				for _, tile in (Session.frame(s, "p").walls :: Session.Walls).marked do
					table.insert(before, key(tile))
				end
				-- on west to the end, then back east to the last pellet, through the pause into level 2
				for _ = 1, 400 do
					local now = Session.frame(s, "p")
					if not now.player.moving and now.play.phase == "playing" then
						Session.submit(s, "p", "Back")
					end
					Session.step(s)
					local f = Session.frame(s, "p")
					if f.play.level == 2 and f.play.phase == "playing" then
						break
					end
				end
				local f = Session.frame(s, "p")
				t.expect(f.play.level).toBe(2)
				levels += 1
				local after = {}
				for _, tile in (f.walls :: Session.Walls).marked do
					t.expect(Picks.pickable(THICK, tile)).toBe(true)
					table.insert(after, key(tile))
				end
				table.sort(before)
				table.sort(after)
				if table.concat(before, " ") ~= table.concat(after, " ") then
					changed += 1
				end
			end
		end
		t.expect(levels >= 20).toBe(true)
		t.expect(changed >= levels - 2).toBe(true)
	end)

	it(
		"a Pick holds no place in the per-tick intent limit: accepted after a full tick, and costing none",
		function()
			local full = new(1)
			for _ = 1, 4 do
				t.expect((Session.submit(full, "p", "Left"))).toBe(true)
			end
			t.expect((Session.submit(full, "p", "Left"))).toBe(false) -- the limit is reached
			local ok, why = Session.submit(full, "p", "Pick")
			t.expect(ok).toBe(true)
			t.expect(why).toBe(nil)
			local first = new(1)
			t.expect((Session.submit(first, "p", "Pick"))).toBe(true)
			for _ = 1, 4 do
				t.expect((Session.submit(first, "p", "Left"))).toBe(true)
			end
		end
	)

	it("a new run rolls new marks on the fresh maze", function()
		local THICK = Maze.parse({
			"#########",
			"#########",
			"#########",
			"#.....P.#",
			"#########",
			"#########",
			"#########",
		}, "thick")
		local changed, runs = 0, 0
		for seed = 1, 40 do
			local s = Session.new(THICK, seed, PLAY)
			Session.join(s, "p")
			run(s, 60)
			local r = run(s, 100, { [s.tick + 1] = { "Pick" } })
			if count(r, "WallPicked") == 1 then
				local before = {}
				for _, tile in (Session.frame(s, "p").walls :: Session.Walls).marked do
					table.insert(before, key(tile))
				end
				while not Session.isOver(s, "p") do
					Session.kill(s, "p")
					run(s, 110)
				end
				local _, ok = Session.playAgain(s, "p")
				t.expect(ok).toBe(true)
				run(s, 1)
				runs += 1
				local after = {}
				for _, tile in (Session.frame(s, "p").walls :: Session.Walls).marked do
					t.expect(Picks.pickable(THICK, tile)).toBe(true)
					table.insert(after, key(tile))
				end
				table.sort(before)
				table.sort(after)
				if table.concat(before, " ") ~= table.concat(after, " ") then
					changed += 1
				end
			end
		end
		t.expect(runs >= 20).toBe(true)
		t.expect(changed >= runs - 2).toBe(true)
	end)
end)
