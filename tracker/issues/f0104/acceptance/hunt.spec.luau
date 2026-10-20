--!strict
-- f0104 AC5 (and R0035 RC1): a ghost hunt end to end, through the public APIs the client and the server use. A blue
-- ghost eaten on contact drops a shot (a seed whose first roll drops); the player holds Left (an arrow, not a turn)
-- and presses E: the key map says Fire, View.aim says where, Blaster.intent is what the client sends, Session.submit
-- takes it, and the next step eats the ghost on the chain. The keys never turned the player.
local Blaster = require("@logic/Blaster")
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Session = require("@logic/Session")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

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

return t.spec("f0104 ghost hunt", function(it)
	it("eat a ghost, get a shot, look left with an arrow, press E, and the ghost there is eaten", function()
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

		-- a blue ghost on the player is eaten, and drops a shot
		Ghosts.power(set, 300)
		member.play.frightened = 300
		local blinky = Ghosts.ghost(set, "blinky")
		blinky.tile, blinky.progress, blinky.status, blinky.frightened = { x = 6, y = 23 }, 0, "active", true
		local eaten = Session.step(s)
		t.expect(find(eaten, "GhostEaten") ~= nil).toBe(true)
		t.expect(find(eaten, "ShotGained") ~= nil).toBe(true)
		t.expect(Session.frame(s, "p").shots).toBe(1)

		-- pinky waits up the corridor on the player's right (heading west, right is north)
		local pinky = Ghosts.ghost(set, "pinky")
		pinky.tile, pinky.progress, pinky.status, pinky.frightened = { x = 6, y = 19 }, 0, "active", false

		-- the keys: Right held is an arrow look, E fires; neither turns the player
		t.expect(View.action("Right")).toBe("LookRight")
		t.expect(View.action("E")).toBe("Fire")
		local held =
			View.press({ up = false, down = false, left = false, right = false }, View.action("Right"), true)
		local look: View.Steer = { look = { yaw = 0, pitch = 0 }, spring = false }
		for _ = 1, 3 do
			look = View.steer(look, held, 0, 0, 1 / 60) -- mid-turn: the arrow decides the aim, not the look
		end
		local heading: Maze.Heading = View.aim(Session.snapshot(s, "p").player.heading, look, held)
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
end)
