--!strict
-- f0101 AC2: the hop in a Session. "Hop" (Hop.INTENT) is an intent beside the movement and fire intents ("Jump"
-- stays invalid); it counts toward the per-tick limit, one a tick. It starts a hop at the start of the player's
-- play in the step, only in play and only when the last hop has landed and cooled down. While airborne (the steps
-- whose middle has the rise over the wall tops: the 2nd to the 11th after take-off) the player is not caught, passes over a
-- blue ghost without eating it, and eats no pellet, while the rail movement and a shot go on. The frame says when
-- the latest hop started. Leaving play before step 2 forgets it, including a Session.kill between steps; a hop that
-- has reached step 2 is kept until the respawn.
local Blaster = require("@logic/Blaster")
local Ghosts = require("@logic/Ghosts")
local Hop = require("@logic/Hop")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Pellets = require("@logic/Pellets")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

local function new(): Session.Session
	local s = Session.new(classic, 1, Session.GAME_CONFIG)
	Session.join(s, "p")
	return s
end

local function ghostsOf(s: Session.Session): Ghosts.Set
	return s.members.p.ghosts :: Ghosts.Set
end

-- the first tick in play (f0023's helper: 61 steps from a new session)
local function playing(s: Session.Session): Session.Session
	for _ = 1, 60 do
		Session.step(s)
	end
	return s
end

-- in play, the idle player stopped at the wall at 6,23, and every ghost parked in the house for good
local function settled(s: Session.Session): Session.Session
	for _ = 1, 101 do
		Session.step(s)
	end
	local at = Movement.occupied(s.maze, s.members.p.move)
	assert(at.x == 6 and at.y == 23 and not s.members.p.move.moving, "the player settles at 6,23")
	for _, g in ghostsOf(s).ghosts do
		g.tile, g.progress, g.status, g.frightened, g.reverse = { x = 13, y = 14 }, 0, "house", false, false
	end
	ghostsOf(s).house.idle = -100000
	return s
end

local function onPlayer(s: Session.Session, name: Ghosts.Name): Ghosts.Ghost
	local g = Ghosts.ghost(ghostsOf(s), name)
	local at = Movement.occupied(s.maze, s.members.p.move)
	g.tile, g.progress, g.status = { x = at.x, y = at.y }, 0, "active"
	return g
end

local function count(events: { Session.Event }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function hop(s: Session.Session): { Session.Event }
	local ok, why = Session.submit(s, "p", Hop.INTENT)
	assert(ok, why)
	return Session.step(s)
end

-- the cancelled arc would have cleared the walls, and the pause keeps the eye down
local function staysDown(s: Session.Session, started: number)
	t.expect(Hop.rise(started, started + Hop.TICKS / 2) > Hop.CLEARANCE).toBe(true)
	for _ = 1, 12 do
		Session.step(s)
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
	end
end

return t.spec("f0101 the hop in a session", function(it)
	it('accepts "Hop" beside the other intents, and still not "Jump" or any other spelling', function()
		t.expect(Hop.INTENT).toBe("Hop")
		local ok, why = Session.submit(new(), "p", "Hop")
		t.expect(ok).toBe(true)
		t.expect(why).toBe(nil)
		local bad: { any } = { "Jump", "hop", "HOP", "Hop ", { "Hop" }, 1, true }
		for _, v in bad do
			local refused, reason = Session.submit(new(), "p", v)
			t.expect(refused).toBe(false)
			t.expect(reason).toBe("invalid intent")
		end
	end)

	it("a hop counts toward the per-tick limit, and only one is taken a tick", function()
		local s = new()
		for _ = 1, 3 do
			t.expect((Session.submit(s, "p", "Forward"))).toBe(true)
		end
		t.expect((Session.submit(s, "p", Hop.INTENT))).toBe(true)
		local ok, why = Session.submit(s, "p", "Forward")
		t.expect(ok).toBe(false)
		t.expect(why).toBe("rate limited")
		local q = new()
		t.expect((Session.submit(q, "p", Hop.INTENT))).toBe(true)
		local again, reason = Session.submit(q, "p", Hop.INTENT)
		t.expect(again).toBe(false)
		t.expect(reason).toBe("rate limited")
		t.expect((Session.submit(q, "p", "Forward"))).toBe(true)
		Session.step(q)
		t.expect((Session.submit(q, "p", Hop.INTENT))).toBe(true)
	end)

	it("in play a hop starts this step: a Hopped event, and the frame says the tick", function()
		local s = playing(new())
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
		local events = hop(s)
		t.expect(count(events, "Hopped")).toBe(1)
		t.expect(Session.frame(s, "p").hopped).toBe(s.tick)
	end)

	it("outside play a hop does nothing, and is not kept for later", function()
		local s = new()
		local events = hop(s) -- the first tick: the ready phase
		t.expect(count(events, "Hopped")).toBe(0)
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
		for _ = 1, 70 do
			t.expect(count(Session.step(s), "Hopped")).toBe(0)
		end
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
	end)

	it("the next hop starts no sooner than Hop.TICKS + Hop.COOLDOWN steps after the last", function()
		t.expect(Hop.TICKS + Hop.COOLDOWN).toBe(20)
		local s = playing(new())
		hop(s)
		local first = s.tick
		local next: number? = nil
		for _ = 1, 30 do
			if count(hop(s), "Hopped") > 0 then
				next = s.tick
				break
			end
		end
		t.expect(next).toBe(first + 20)
		t.expect(Session.frame(s, "p").hopped).toBe(first + 20)
	end)

	it("an active ghost on the player catches them, except in the 2nd to the 11th step of a hop", function()
		for k = 0, Hop.TICKS + 1 do
			-- the ghost arrives in step k of the hop (step 0 is the take-off, on the ground)
			local s = settled(new())
			t.expect((Session.submit(s, "p", Hop.INTENT))).toBe(true)
			for _ = 1, k do
				Session.step(s)
			end
			onPlayer(s, "blinky")
			local events = Session.step(s)
			-- a catch before step 2 forgets the hop; from step 2 on, the tick is kept
			local started = if k >= 2 then s.tick - k else nil
			t.expect(Session.frame(s, "p").hopped).toBe(started)
			local airborne = k >= 2 and k <= 11
			t.expect(count(events, "Caught")).toBe(if airborne then 0 else 1)
		end
	end)

	it("a blue ghost met while airborne is passed over, not eaten; on the ground it is eaten", function()
		local s = settled(new())
		hop(s)
		Session.step(s) -- step 1: still on the ground
		Ghosts.power(ghostsOf(s), 300)
		local g = onPlayer(s, "pinky")
		g.frightened = true
		local score = s.members.p.play.score
		local events = Session.step(s) -- step 2: airborne
		t.expect(count(events, "GhostEaten")).toBe(0)
		t.expect(count(events, "Caught")).toBe(0)
		t.expect(g.status).toBe("active")
		t.expect(s.members.p.play.score).toBe(score)
		local ground = settled(new())
		Ghosts.power(ghostsOf(ground), 300)
		onPlayer(ground, "pinky").frightened = true
		t.expect(count(Session.step(ground), "GhostEaten")).toBe(1)
	end)

	it(
		"pellets passed over while airborne are not eaten and stay; the player still moves along the rail",
		function()
			-- the same run twice from the first tick in play, the idle player running west over pellets: once
			-- hopping, once not
			local function run(hopping: boolean): (number, number, string, string)
				local s = playing(new())
				if hopping then
					hop(s)
				else
					Session.step(s)
				end
				Session.step(s) -- step 1 of the hop
				local from = Movement.occupied(s.maze, s.members.p.move)
				local eaten = 0
				for _ = 2, 10 do
					eaten += count(Session.step(s), "PelletEaten")
				end
				local at = Movement.occupied(s.maze, s.members.p.move)
				return eaten, Pellets.remaining(s.members.p.pellets), `{from.x},{from.y}`, `{at.x},{at.y}`
			end
			local walked, walkedLeft = run(false)
			local hopped, hoppedLeft, from, at = run(true)
			t.expect(walked > 0).toBe(true) -- the run does cross pellets in those steps
			t.expect(hopped).toBe(0)
			t.expect(hoppedLeft).toBe(walkedLeft + walked)
			t.expect(at ~= from).toBe(true) -- the rail movement goes on underneath
		end
	)

	it("a shot taken while airborne still eats the ghost on the line", function()
		local s = settled(new())
		hop(s)
		for _ = 1, 4 do
			Session.step(s)
		end
		local g = Ghosts.ghost(ghostsOf(s), "blinky")
		g.tile, g.progress, g.status, g.heading = { x = 9, y = 23 }, 0, "active", "N"
		s.members.p.blaster.shots = 1
		t.expect((Session.submit(s, "p", Blaster.intent("E")))).toBe(true)
		local events = Session.step(s) -- step 5 of the hop: airborne
		t.expect(Hop.airborne(Session.frame(s, "p").hopped, s.tick)).toBe(true)
		t.expect(count(events, "Shot")).toBe(1)
		t.expect(g.status).toBe("eyes")
	end)

	it(
		"running head-on into a ghost: a hop 2 to 9 steps before the meeting carries the player over it",
		function()
			-- the idle player runs west along row 23 from its spawn; blinky comes east at it from 7,23
			local function run(hopBefore: number?, meet: number?): (number?, Session.Session)
				local s = playing(new())
				Session.step(s) -- the first tick in play
				for _, g in ghostsOf(s).ghosts do
					g.tile, g.progress, g.status, g.frightened, g.reverse =
						{ x = 13, y = 14 }, 0, "house", false, false
				end
				ghostsOf(s).house.idle = -100000
				local g = Ghosts.ghost(ghostsOf(s), "blinky")
				g.tile, g.progress, g.status, g.heading = { x = 7, y = 23 }, 0, "active", "E"
				for i = 1, 30 do
					if hopBefore and meet and i == meet - hopBefore then
						t.expect((Session.submit(s, "p", Hop.INTENT))).toBe(true)
					end
					if count(Session.step(s), "Caught") > 0 then
						return i, s
					end
				end
				return nil, s
			end
			local meet = run(nil, nil)
			t.expect(meet ~= nil and (meet :: number) > 10).toBe(true) -- a real meeting, with room to hop before it
			t.expect((run(1, meet))).toBe(meet) -- take-off is on the ground
			for d = 2, 9 do
				local caught, s = run(d, meet)
				t.expect(caught).toBe(nil)
				local at = Movement.occupied(s.maze, s.members.p.move)
				t.expect(Ghosts.ghost(ghostsOf(s), "blinky").tile.x > at.x).toBe(true) -- the ghost is behind them now
			end
		end
	)

	it("the ghosts move on exactly as without the hop", function()
		local function run(hopping: boolean): { string }
			local s = settled(new())
			local g = Ghosts.ghost(ghostsOf(s), "blinky")
			g.tile, g.progress, g.status, g.heading = { x = 26, y = 29 }, 0, "active", "W"
			if hopping then
				t.expect((Session.submit(s, "p", Hop.INTENT))).toBe(true)
			end
			local trail = {}
			for _ = 0, Hop.TICKS do
				Session.step(s)
				table.insert(trail, `{g.tile.x},{g.tile.y},{g.progress},{g.heading}`)
			end
			return trail
		end
		local walked, hopped = run(false), run(true)
		t.expect(table.concat(hopped, ";")).toBe(table.concat(walked, ";"))
		t.expect(hopped[2] ~= hopped[11]).toBe(true) -- it does move while the player is airborne
	end)

	it("each player has their own hop", function()
		local s = Session.new(classic, 1, Session.GAME_CONFIG)
		Session.join(s, "p")
		Session.join(s, "q")
		for _ = 1, 101 do
			Session.step(s)
		end
		for _, id in { "p", "q" } do
			local set = s.members[id].ghosts :: Ghosts.Set
			for _, g in set.ghosts do
				g.tile, g.progress, g.status, g.frightened, g.reverse =
					{ x = 13, y = 14 }, 0, "house", false, false
			end
			set.house.idle = -100000
		end
		t.expect((Session.submit(s, "p", Hop.INTENT))).toBe(true)
		Session.step(s) -- p's take-off
		Session.step(s) -- step 1 of p's hop
		t.expect((Session.submit(s, "q", Hop.INTENT))).toBe(true) -- p's cooldown is not q's
		local events = Session.step(s) -- q's take-off, with no ghost on either
		t.expect(count(events, "Caught")).toBe(0)
		t.expect(Session.frame(s, "q").hopped).toBe(s.tick) -- q took off, and was not caught
		t.expect(Session.frame(s, "p").hopped).toBe(s.tick - 2) -- p's hop is untouched
	end)

	it("leaving play before step 2 of a hop forgets it, so the pause does not play the arc", function()
		local takeoff = settled(new())
		t.expect((Session.submit(takeoff, "p", Hop.INTENT))).toBe(true)
		onPlayer(takeoff, "blinky")
		local caughtNow = Session.step(takeoff)
		t.expect(count(caughtNow, "Caught")).toBe(1)
		t.expect(count(caughtNow, "Hopped")).toBe(0)
		t.expect(Session.frame(takeoff, "p").hopped).toBe(nil)
		staysDown(takeoff, takeoff.tick)

		local nextStep = settled(new())
		hop(nextStep) -- the take-off, still in play
		onPlayer(nextStep, "blinky")
		local caughtNext = Session.step(nextStep)
		t.expect(count(caughtNext, "Caught")).toBe(1)
		t.expect(count(caughtNext, "Hopped")).toBe(0)
		t.expect(Session.frame(nextStep, "p").hopped).toBe(nil)
		staysDown(nextStep, nextStep.tick - 1)
	end)

	it("the last pellet, eaten the step after take-off, forgets the hop for the level-clear pause", function()
		local s = playing(new())
		for _, tile in Pellets.tiles(s.members.p.pellets) do
			if not (tile.x == 12 and tile.y == 23) then
				Pellets.eat(s.members.p.pellets, tile)
			end
		end
		t.expect(Pellets.remaining(s.members.p.pellets)).toBe(1)
		hop(s)
		t.expect(Session.frame(s, "p").hopped).toBe(s.tick)
		local events = Session.step(s)
		t.expect(count(events, "LevelCleared")).toBe(1)
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
		for _ = 1, 20 do
			Session.step(s)
			t.expect(Session.frame(s, "p").hopped).toBe(nil)
		end
	end)

	it("a catch on the landing step keeps the hop until the respawn", function()
		local s = settled(new())
		hop(s)
		for _ = 1, 11 do
			Session.step(s)
		end
		onPlayer(s, "blinky")
		t.expect(count(Session.step(s), "Caught")).toBe(1)
		t.expect(Session.frame(s, "p").hopped).toBe(s.tick - 12)
		local ready = false
		for _ = 1, 300 do
			if count(Session.step(s), "Ready") > 0 then
				ready = true
				break
			end
		end
		t.expect(ready).toBe(true)
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
	end)

	it("the last life, caught on take-off, is game over with no hop and no respawn", function()
		local s = settled(new())
		s.members.p.play.lives = 1
		t.expect((Session.submit(s, "p", Hop.INTENT))).toBe(true)
		onPlayer(s, "blinky")
		t.expect(count(Session.step(s), "Hopped")).toBe(0)
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
		local over, sawReady = false, false
		for _ = 1, 80 do
			local events = Session.step(s)
			if count(events, "Ready") > 0 then
				sawReady = true
			end
			if count(events, "GameOver") > 0 then
				over = true
				break
			end
		end
		t.expect(over).toBe(true)
		t.expect(sawReady).toBe(false)
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
		Session.playAgain(s, "p")
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
	end)

	it("a take-off catch forgets only that player's hop", function()
		local s = Session.new(classic, 1, Session.GAME_CONFIG)
		Session.join(s, "p")
		Session.join(s, "q")
		for _ = 1, 101 do
			Session.step(s)
		end
		for _, id in { "p", "q" } do
			local set = s.members[id].ghosts :: Ghosts.Set
			for _, g in set.ghosts do
				g.tile, g.progress, g.status, g.frightened, g.reverse =
					{ x = 13, y = 14 }, 0, "house", false, false
			end
			set.house.idle = -100000
		end
		t.expect((Session.submit(s, "p", Hop.INTENT))).toBe(true)
		Session.step(s)
		Session.step(s) -- p is airborne
		t.expect((Session.submit(s, "q", Hop.INTENT))).toBe(true)
		local at = Movement.occupied(s.maze, s.members.q.move)
		local g = Ghosts.ghost(s.members.q.ghosts :: Ghosts.Set, "blinky")
		g.tile, g.progress, g.status = { x = at.x, y = at.y }, 0, "active"
		local caught = {}
		for _, e in Session.step(s) do
			if e.kind == "Caught" then
				table.insert(caught, e.player)
			end
		end
		t.expect(table.concat(caught, ",")).toBe("q")
		t.expect(Session.frame(s, "q").hopped).toBe(nil)
		t.expect(Session.frame(s, "p").hopped).toBe(s.tick - 2)
	end)

	it("a hop and a shot in one tick both happen, and each counts toward the limit", function()
		local s = settled(new())
		local g = Ghosts.ghost(ghostsOf(s), "blinky")
		g.tile, g.progress, g.status, g.heading = { x = 9, y = 23 }, 0, "active", "N"
		s.members.p.blaster.shots = 1
		t.expect((Session.submit(s, "p", "Forward"))).toBe(true)
		t.expect((Session.submit(s, "p", "Forward"))).toBe(true)
		t.expect((Session.submit(s, "p", Blaster.intent("E")))).toBe(true)
		t.expect((Session.submit(s, "p", Hop.INTENT))).toBe(true)
		local refused, why = Session.submit(s, "p", "Forward")
		t.expect(refused).toBe(false)
		t.expect(why).toBe("rate limited")
		local events = Session.step(s)
		t.expect(count(events, "Shot")).toBe(1)
		t.expect(count(events, "Hopped")).toBe(1)
		t.expect(count(events, "Caught")).toBe(0)
		t.expect(g.status).toBe("eyes")
		t.expect(s.members.p.blaster.shots).toBe(0)
		t.expect(Hop.airborne(Session.frame(s, "p").hopped, s.tick)).toBe(false)
	end)

	it("Session.kill right after take-off forgets the hop, so the pause does not play the arc", function()
		local s = settled(new())
		hop(s)
		local started = s.tick
		t.expect(Session.frame(s, "p").hopped).toBe(started)
		t.expect(count(Session.kill(s, "p"), "LifeLost")).toBe(1)
		Session.step(s)
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
		staysDown(s, started)
	end)

	it(
		"Session.kill after the step after take-off forgets the hop, so the pause does not play the arc",
		function()
			local s = settled(new())
			hop(s)
			local started = s.tick
			Session.step(s) -- still on the ground: the rise is ahead of this step
			t.expect(s.tick).toBe(started + 1)
			t.expect(Session.frame(s, "p").hopped).toBe(started)
			t.expect(Hop.airborne(started, s.tick)).toBe(false)
			t.expect(Hop.rise(started, started + 2) > Hop.CLEARANCE).toBe(true) -- the next step would clear the walls
			t.expect(Hop.rise(started, started + Hop.TICKS / 2)).toBe(Hop.RISE)
			Session.kill(s, "p")
			Session.step(s)
			t.expect(Session.frame(s, "p").hopped).toBe(nil)
			staysDown(s, started)
		end
	)

	it("Session.kill after step 2 of a hop keeps it until the respawn", function()
		local s = settled(new())
		hop(s)
		local started = s.tick
		Session.step(s)
		Session.step(s)
		t.expect(s.tick).toBe(started + 2)
		t.expect(Session.frame(s, "p").hopped).toBe(started)
		t.expect(Hop.airborne(started, s.tick)).toBe(true)
		Session.kill(s, "p")
		Session.step(s)
		t.expect(Session.frame(s, "p").hopped).toBe(started)
		t.expect(Hop.rise(started, s.tick) > Hop.CLEARANCE).toBe(true) -- the death frame is already over the walls
		local ready = false
		for _ = 1, 300 do
			if count(Session.step(s), "Ready") > 0 then
				ready = true
				break
			end
		end
		t.expect(ready).toBe(true)
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
	end)
end)
