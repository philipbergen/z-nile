--!strict
-- f0110 AC4: a touch ghost hunt end to end, through the public APIs the client and the server use, on a notched
-- portrait phone laid out by Hud.layout and Touch.buttons. A blue ghost eaten on contact drops a shot (a seed
-- whose first roll drops). The right thumb drags the look 300 px to the right (View.look, as Camera.lookBy does),
-- then taps the fire button: Touch's fold says fire, View.aim gives the look's nearest heading, Blaster.intent is
-- what the client sends, Session.submit takes it, and the next step eats the ghost up the corridor on the right.
-- A tap on the hop button is the hop: Hop.INTENT, and the next step starts it. Neither tap turned the player.
local Blaster = require("@logic/Blaster")
local Ghosts = require("@logic/Ghosts")
local Hop = require("@logic/Hop")
local Hud = require("@logic/Hud")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Session = require("@logic/Session")
local Touch = require("@logic/Touch")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local NO_ARROWS: View.Arrows = { up = false, down = false, left = false, right = false }

local function seedThatDrops(): number
	for seed = 1, 1000 do
		if Blaster.drop(Blaster.new(seed)) then
			return seed
		end
	end
	error("no seed drops first")
end

local function find(events: { Session.Event }, kind: string): Session.Event?
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

-- the phone's screen: 390 x 844 with a 47 px notch, and its touch controls
local W, H = 390, 844
local box = Hud.layout(W, H, { top = 47, bottom = 0, left = 0, right = 0 })
-- read at the first call, so a missing Touch.buttons fails inside a case
local function buttonsOf(): any
	return (Touch :: any).buttons(box)
end

type Fold = { state: Touch.State, effects: { any } }

local function feed(f: Fold, event: Touch.Event)
	local buttons = buttonsOf()
	local effects
	f.state, effects = Touch.track(
		f.state,
		event,
		{ width = W, snap = buttons.snap, fire = buttons.fire, hop = buttons.hop } :: any
	)
	for _, e in effects do
		table.insert(f.effects, e)
	end
end

local function centre(r: { x: number, y: number, w: number, h: number }): (number, number)
	return r.x + r.w // 2, r.y + r.h // 2
end

-- a session at 6,23 heading west, every ghost in the house
local function setup(): (Session.Session, any)
	local s = Session.new(classic, seedThatDrops(), Session.GAME_CONFIG)
	Session.join(s, "p")
	for _ = 1, 101 do
		Session.step(s)
	end
	local member = s.members.p
	local set = member.ghosts :: Ghosts.Set
	local at = Movement.occupied(s.maze, member.move)
	t.expect(`{at.x},{at.y}`).toBe("6,23")
	t.expect(member.move.heading).toBe("W")
	for _, g in set.ghosts do
		g.tile, g.progress, g.status, g.frightened = { x = 13, y = 14 }, 0, "house", false
	end
	set.house.idle = -100000
	return s, member
end

return t.spec("f0110 touch hunt", function(it)
	it("eat a ghost, get a shot, drag the look right, tap fire, and the ghost there is eaten", function()
		local s, member = setup()
		local set = member.ghosts :: Ghosts.Set
		Ghosts.power(set, 300)
		member.play.frightened = 300
		local blinky = Ghosts.ghost(set, "blinky")
		blinky.tile, blinky.progress, blinky.status, blinky.frightened = { x = 6, y = 23 }, 0, "active", true
		local eaten = Session.step(s)
		t.expect(find(eaten, "ShotGained") ~= nil).toBe(true)
		t.expect(Session.frame(s, "p").shots).toBe(1)

		-- pinky waits up the corridor on the player's right (heading west, right is north)
		local pinky = Ghosts.ghost(set, "pinky")
		pinky.tile, pinky.progress, pinky.status, pinky.frightened = { x = 6, y = 19 }, 0, "active", false

		local fold: Fold = { state = Touch.empty(), effects = {} }
		-- the look drag on the right half, above the buttons
		local look: View.Look = { yaw = 0, pitch = 0 }
		feed(fold, { id = 1, phase = "begin", x = 250, y = 300 })
		feed(fold, { id = 1, phase = "move", x = 550, y = 300 })
		feed(fold, { id = 1, phase = "end", x = 550, y = 300 })
		for _, e in fold.effects do
			if e.kind == "look" then
				look = View.look(look, e.dx, e.dy)
			end
		end
		fold.effects = {}
		-- the tap on the fire button
		local fx, fy = centre(buttonsOf().fire)
		feed(fold, { id = 2, phase = "begin", x = fx, y = fy })
		feed(fold, { id = 2, phase = "end", x = fx, y = fy })
		t.expect(fold.effects).toEqual({ { kind = "fire" } })
		local heading =
			View.aim(Session.snapshot(s, "p").player.heading, { look = look, spring = false }, NO_ARROWS)
		t.expect(heading).toBe("N")
		local ok, why = Session.submit(s, "p", Blaster.intent(heading))
		t.expect(ok).toBe(true)
		t.expect(why).toBe(nil)
		local score = member.play.score
		local events = Session.step(s)
		local shot = find(events, "Shot") :: Session.Event
		t.expect(shot ~= nil).toBe(true)
		t.expect(shot.ghost).toBe("pinky")
		t.expect(shot.points).toBe(400) -- the second ghost of this power period
		t.expect(pinky.status).toBe("eyes")
		t.expect(member.play.score).toBe(score + 400)
		t.expect(Session.frame(s, "p").shots).toBe(0)
		t.expect(Session.snapshot(s, "p").player.heading).toBe("W")
	end)

	it("a tap on the hop button starts the hop on the next step, and the player keeps going west", function()
		local s = setup()
		t.expect(Session.frame(s, "p").hopped).toBe(nil)
		local fold: Fold = { state = Touch.empty(), effects = {} }
		local hx, hy = centre(buttonsOf().hop)
		feed(fold, { id = 1, phase = "begin", x = hx, y = hy })
		feed(fold, { id = 1, phase = "end", x = hx, y = hy })
		t.expect(fold.effects).toEqual({ { kind = "hop" } })
		local ok, why = Session.submit(s, "p", Hop.INTENT)
		t.expect(ok).toBe(true)
		t.expect(why).toBe(nil)
		local events = Session.step(s)
		t.expect(find(events, "Hopped") ~= nil).toBe(true)
		t.expect(Session.frame(s, "p").hopped).toBe(s.tick)
		t.expect(Session.snapshot(s, "p").player.heading).toBe("W")
	end)
end)
