--!strict
-- f0100 AC2: shots in a Session. A fire intent (Blaster.intent) rides the Intent queue: it counts toward the
-- per-tick limit, and only one is taken a tick. The shot is taken at the start of the player's play in the next
-- step, before anyone moves: one shot is spent, and the first active ghost along the heading from the player's
-- tile is eaten exactly as on contact (its eyes go home, the chain pays the next of 200, 400, 800, 1600), blue or
-- not. A miss spends the shot too. In a pause, with no shot, or without ghosts, nothing happens and nothing is
-- spent. The chain restarts with a power pellet and when the power runs out.
local Blaster = require("@logic/Blaster")
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Pellets = require("@logic/Pellets")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local CORRIDOR = Maze.parse({ "###############", "#            P#", "###############" }, "corridor")

local function new(seed: number?): Session.Session
	local s = Session.new(classic, seed or 1, Session.GAME_CONFIG)
	Session.join(s, "p")
	return s
end

local function ghostsOf(s: Session.Session): Ghosts.Set
	return s.members.p.ghosts :: Ghosts.Set
end

-- in play, with the idle player run west to the wall at 6,23 and stopped there (f0023's helper)
local function settled(s: Session.Session): Session.Session
	for _ = 1, 101 do
		Session.step(s)
	end
	local at = Movement.occupied(s.maze, s.members.p.move)
	assert(at.x == 6 and at.y == 23 and not s.members.p.move.moving, "the player settles at 6,23")
	return s
end

-- every ghost parked in the house, out of every line; then `name` put on a tile, active
local function clearLines(s: Session.Session)
	for _, g in ghostsOf(s).ghosts do
		g.tile, g.progress, g.status, g.frightened, g.reverse = { x = 13, y = 14 }, 0, "house", false, false
	end
	ghostsOf(s).house.idle = -100000 -- nobody leaves the house during the test
end

local function put(
	s: Session.Session,
	name: Ghosts.Name,
	x: number,
	y: number,
	status: Ghosts.Status?
): Ghosts.Ghost
	local g = Ghosts.ghost(ghostsOf(s), name)
	g.tile, g.progress, g.status, g.heading = { x = x, y = y }, 0, status or "active", "N"
	return g
end

local function arm(s: Session.Session, n: number)
	s.members.p.blaster.shots = n
end

local function shots(s: Session.Session): number
	return Session.frame(s, "p").shots :: number
end

local function find(events: { Session.Event }, kind: string): Session.Event?
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

local function fire(s: Session.Session, h: Maze.Heading): { Session.Event }
	local ok, why = Session.submit(s, "p", Blaster.intent(h))
	assert(ok, why)
	return Session.step(s)
end

return t.spec("f0100 shots in a session", function(it)
	it("accepts the four fire intents beside the movement intents, and still nothing else", function()
		local all: { Maze.Heading } = { "N", "E", "S", "W" }
		for _, h: Maze.Heading in all do
			local ok, why = Session.submit(new(), "p", Blaster.intent(h))
			t.expect(ok).toBe(true)
			t.expect(why).toBe(nil)
		end
		local bad: { any } = { "Fire", "fireE", "FireX", "Jump", "Snap", { "FireE" } }
		for _, v in bad do
			local ok, why = Session.submit(new(), "p", v)
			t.expect(ok).toBe(false)
			t.expect(why).toBe("invalid intent")
		end
	end)

	it("a fire counts toward the per-tick limit, and only one is taken a tick", function()
		local s = new()
		for _ = 1, 3 do
			t.expect((Session.submit(s, "p", "Forward"))).toBe(true)
		end
		t.expect((Session.submit(s, "p", Blaster.intent("E")))).toBe(true)
		local ok, why = Session.submit(s, "p", "Forward")
		t.expect(ok).toBe(false)
		t.expect(why).toBe("rate limited")
		local q = new()
		t.expect((Session.submit(q, "p", Blaster.intent("E")))).toBe(true)
		local again, reason = Session.submit(q, "p", Blaster.intent("W"))
		t.expect(again).toBe(false)
		t.expect(reason).toBe("rate limited")
		t.expect((Session.submit(q, "p", "Forward"))).toBe(true) -- movement still has room
		Session.step(q)
		t.expect((Session.submit(q, "p", Blaster.intent("W")))).toBe(true) -- the next tick takes a shot again
	end)

	it(
		"a shot eats the nearest active ghost on the line for the chain's points, and costs one shot",
		function()
			local s = settled(new())
			clearLines(s)
			put(s, "pinky", 11, 23)
			put(s, "blinky", 9, 23)
			arm(s, 3)
			local before = s.members.p.play.score
			local events = fire(s, "E")
			local shot = find(events, "Shot")
			t.expect(shot ~= nil).toBe(true)
			local e = shot :: Session.Event
			t.expect(e.ghost).toBe("blinky")
			t.expect(e.points).toBe(200)
			t.expect(e.heading).toBe("E")
			t.expect(Ghosts.ghost(ghostsOf(s), "blinky").status).toBe("eyes")
			t.expect(Ghosts.ghost(ghostsOf(s), "pinky").status).toBe("active")
			t.expect(s.members.p.play.score).toBe(before + 200)
			t.expect(shots(s)).toBe(2)
			t.expect(find(events, "GhostEaten")).toBe(nil)
		end
	)

	it("shots in a row climb the chain: 200, then 400, then 800", function()
		local s = settled(new())
		clearLines(s)
		put(s, "blinky", 9, 23)
		put(s, "pinky", 12, 23)
		put(s, "inky", 6, 20)
		arm(s, 3)
		local paid = {}
		local order: { Maze.Heading } = { "E", "E", "N" }
		for _, h: Maze.Heading in order do
			local e = find(fire(s, h), "Shot") :: Session.Event
			table.insert(paid, `{e.ghost}:{e.points}`)
		end
		t.expect(table.concat(paid, " ")).toBe("blinky:200 pinky:400 inky:800")
		t.expect(shots(s)).toBe(0)
	end)

	it("a blue ghost that is shot is eaten on the same chain as one eaten on contact", function()
		local s = settled(new())
		clearLines(s)
		local set = ghostsOf(s)
		Ghosts.power(set, 300)
		s.members.p.play.frightened = 300
		Ghosts.eat(set, "clyde") -- one eaten already in this power period: 200
		put(s, "blinky", 9, 23).frightened = true
		arm(s, 1)
		local e = find(fire(s, "E"), "Shot") :: Session.Event
		t.expect(e.ghost).toBe("blinky")
		t.expect(e.points).toBe(400)
		t.expect(Ghosts.ghost(set, "blinky").frightened).toBe(false)
	end)

	it("the chain restarts when the power runs out, so the next shot pays 200", function()
		local s = settled(new())
		clearLines(s)
		local set = ghostsOf(s)
		Ghosts.power(set, 2)
		s.members.p.play.frightened = 2
		Ghosts.eat(set, "clyde")
		Ghosts.eat(set, "inky")
		t.expect(set.chain).toBe(2)
		local ended = false
		for _ = 1, 3 do
			if find(Session.step(s), "FrightenedEnded") then
				ended = true
			end
		end
		t.expect(ended).toBe(true)
		t.expect(set.chain).toBe(0)
		put(s, "blinky", 9, 23)
		arm(s, 1)
		t.expect((find(fire(s, "E"), "Shot") :: Session.Event).points).toBe(200)
	end)

	it("a miss spends the shot and scores nothing", function()
		local s = settled(new())
		clearLines(s)
		put(s, "blinky", 9, 23)
		arm(s, 2)
		local before = s.members.p.play.score
		local e = find(fire(s, "W"), "Shot") :: Session.Event
		t.expect(e ~= nil).toBe(true)
		t.expect(e.ghost).toBe(nil)
		t.expect(e.points).toBe(nil)
		t.expect(e.heading).toBe("W")
		t.expect(shots(s)).toBe(1)
		t.expect(s.members.p.play.score).toBe(before)
		t.expect(Ghosts.ghost(ghostsOf(s), "blinky").status).toBe("active")
	end)

	it("a wall stops the shot: a ghost beyond it on the same row is safe", function()
		local s = settled(new())
		clearLines(s)
		put(s, "blinky", 24, 23)
		arm(s, 1)
		local e = find(fire(s, "E"), "Shot") :: Session.Event
		t.expect(e.ghost).toBe(nil)
		t.expect(Ghosts.ghost(ghostsOf(s), "blinky").status).toBe("active")
		t.expect(shots(s)).toBe(0)
	end)

	it("eyes on the line are passed through, and the active ghost behind them is hit", function()
		local s = settled(new())
		clearLines(s)
		put(s, "pinky", 8, 23, "eyes")
		put(s, "blinky", 13, 23)
		arm(s, 1)
		local e = find(fire(s, "E"), "Shot") :: Session.Event
		t.expect(e.ghost).toBe("blinky")
	end)

	it(
		"the shot is taken before anyone moves: a ghost on the player's own tile is eaten, not a killer",
		function()
			local s = settled(new())
			clearLines(s)
			put(s, "blinky", 6, 23)
			arm(s, 1)
			local lives = s.members.p.play.lives
			local events = fire(s, "N")
			t.expect((find(events, "Shot") :: Session.Event).ghost).toBe("blinky")
			t.expect(find(events, "Caught")).toBe(nil)
			t.expect(s.members.p.play.lives).toBe(lives)
		end
	)

	it("with no shot held, a fire does nothing", function()
		local s = settled(new())
		clearLines(s)
		put(s, "blinky", 9, 23)
		local events = fire(s, "E")
		t.expect(find(events, "Shot")).toBe(nil)
		t.expect(Ghosts.ghost(ghostsOf(s), "blinky").status).toBe("active")
		t.expect(shots(s)).toBe(0)
	end)

	it("a fire in a pause is ignored and spends nothing, and is not kept for when play starts", function()
		local s = new()
		t.expect(s.members.p.play.phase).toBe("ready")
		clearLines(s) -- nobody to meet: a kept fire would show as a Shot (a miss) once play starts
		arm(s, 2)
		local events = fire(s, "W")
		t.expect(find(events, "Shot")).toBe(nil)
		t.expect(shots(s)).toBe(2)
		local shot = false
		for _ = 1, 70 do
			if find(Session.step(s), "Shot") then
				shot = true
			end
		end
		t.expect(s.members.p.play.phase).toBe("playing")
		t.expect(shot).toBe(false)
		t.expect(shots(s)).toBe(2)
	end)

	it("a session without ghosts takes no shot and spends nothing", function()
		local s = Session.new(CORRIDOR, 1, Session.GAME_CONFIG)
		Session.join(s, "p")
		for _ = 1, 61 do
			Session.step(s)
		end
		s.members.p.blaster.shots = 1
		t.expect(find(fire(s, "W"), "Shot")).toBe(nil)
		t.expect(Session.frame(s, "p").shots).toBe(1)
	end)

	it("only the first fire of a tick is taken, and the shot applies once", function()
		local s = settled(new())
		clearLines(s)
		put(s, "blinky", 9, 23)
		put(s, "pinky", 6, 20)
		arm(s, 3)
		Session.submit(s, "p", Blaster.intent("E"))
		Session.submit(s, "p", Blaster.intent("N"))
		local events = Session.step(s)
		local n = 0
		for _, e in events do
			if e.kind == "Shot" then
				n += 1
			end
		end
		t.expect(n).toBe(1)
		t.expect(Ghosts.ghost(ghostsOf(s), "blinky").status).toBe("eyes")
		t.expect(Ghosts.ghost(ghostsOf(s), "pinky").status).toBe("active")
		t.expect(shots(s)).toBe(2)
	end)

	it("a shot ghost comes back by the house like an eaten one, and is dangerous again", function()
		local s = settled(new())
		clearLines(s)
		ghostsOf(s).house.idle = 0
		put(s, "blinky", 9, 23)
		arm(s, 1)
		fire(s, "E")
		local revived = false
		for _ = 1, 600 do
			if find(Session.step(s), "GhostRevived") then
				revived = true
				break
			end
		end
		t.expect(revived).toBe(true)
		t.expect(Ghosts.ghost(ghostsOf(s), "blinky").frightened).toBe(false)
	end)

	it("a moving player shoots from the tile it holds before this step's move, not after it", function()
		-- from the spawn the player runs west along row 23; tile 12 is a junction with a corridor north (12,22 to
		-- 12,21), and 11 has a wall to its north. The step that starts with the player 30 units past the centre of
		-- 12 (still holding 12) moves it on to hold 11: a shot north from 12 hits the ghost at 12,21, from 11 it
		-- would hit the wall.
		local s = new()
		clearLines(s)
		put(s, "blinky", 12, 21)
		arm(s, 1)
		local member = s.members.p
		for x = 7, 13 do
			Pellets.eat(member.pellets, { x = x, y = 23 }) -- no eating pause: whole 30-unit steps
		end
		for _ = 1, 200 do
			if member.move.tile.x == 12 and member.move.tile.y == 23 and member.move.progress == 30 then
				break
			end
			Session.step(s)
		end
		t.expect(`{member.move.tile.x},{member.move.progress},{member.move.heading}`).toBe("12,30,W")
		t.expect(Movement.occupied(s.maze, member.move).x).toBe(12)
		local e = find(fire(s, "N"), "Shot") :: Session.Event
		t.expect(Movement.occupied(s.maze, member.move).x).toBe(11) -- it did move on
		t.expect(e.ghost).toBe("blinky")
		-- and the frame says where the shot started: the junction, not where the player is now
		t.expect((Session.frame(s, "p").shot :: Session.Shot).from).toEqual({ x = 12, y = 23 })
		t.expect(Ghosts.ghost(ghostsOf(s), "blinky").status).toBe("eyes")
	end)

	it("the frame names the latest shot the server took, by its step's tick and heading", function()
		local s = settled(new())
		clearLines(s)
		t.expect(Session.frame(s, "p").shot).toBe(nil)
		arm(s, 2)
		fire(s, "W") -- a miss is a shot taken too
		local frame = Session.frame(s, "p")
		t.expect(frame.shot).toEqual({ tick = frame.tick, heading = "W", from = { x = 6, y = 23 } })
		Session.step(s)
		local later = Session.frame(s, "p")
		t.expect((later.shot :: Session.Shot).tick).toBe(frame.tick) -- the latest, not this step's
		t.expect(later.shot ~= frame.shot).toBe(true) -- a fresh table each frame
		t.expect((later.shot :: Session.Shot).from ~= (frame.shot :: Session.Shot).from).toBe(true);
		((later.shot :: Session.Shot).from :: any).x = 99
		t.expect((Session.frame(s, "p").shot :: Session.Shot).from.x).toBe(6) -- changing it changes nothing
	end)

	it(
		"a fire the server drops leaves the frame's shot alone: none held, a pause, a second fire in a tick",
		function()
			local s = settled(new())
			clearLines(s)
			fire(s, "E") -- none held
			t.expect(Session.frame(s, "p").shot).toBe(nil)
			arm(s, 2)
			Session.submit(s, "p", Blaster.intent("E"))
			Session.submit(s, "p", Blaster.intent("N"))
			Session.step(s)
			local frame = Session.frame(s, "p")
			t.expect(frame.shot).toEqual({ tick = frame.tick, heading = "E", from = { x = 6, y = 23 } })
			t.expect(frame.shots).toBe(1)
			local paused = new()
			arm(paused, 1)
			fire(paused, "E")
			t.expect(Session.frame(paused, "p").shot).toBe(nil)
		end
	)
end)
