--!strict
-- f0310: what the server replicates about the ghosts. Each snapshot and frame carries the four ghosts, in
-- the order of Ghosts.NAMES, with a continuous position, a heading, how to draw it (look and the white half
-- of a blinking flash) and when it last jumped; a session without ghosts replicates exactly what it did.
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local plain = require("@tests/lib/plain")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

local function new(): Session.Session
	local s = Session.new(classic, 1, Session.GAME_CONFIG)
	Session.join(s, "p")
	return s
end

local function playing(s: Session.Session)
	for _ = 1, 61 do
		Session.step(s)
	end
end

local function set(s: Session.Session): Ghosts.Set
	return s.members.p.ghosts :: Ghosts.Set
end

local function listed(s: Session.Session): { Session.GhostSnapshot }
	return Session.snapshot(s, "p").ghosts :: { Session.GhostSnapshot }
end

return t.spec("f0310 ghosts in the snapshot and the frame", function(it)
	it("carries the four ghosts in Ghosts.NAMES order with exactly the documented fields", function()
		local s = new()
		local ghosts = listed(s)
		t.expect(#ghosts).toBe(4)
		for i, g in ghosts do
			t.expect(g.name).toBe(Ghosts.NAMES[i])
			local keys = {}
			for k in g do
				table.insert(keys, k)
			end
			table.sort(keys)
			t.expect(keys).toEqual({ "flash", "heading", "jumpTick", "look", "name", "x", "y" })
		end
	end)

	it("starts with Blinky outside above the door and the others where the house keeps them", function()
		local ghosts = listed(new())
		t.expect(ghosts[1].x).toBe(14)
		t.expect(ghosts[1].y).toBe(11)
		t.expect(ghosts[1].heading).toBe("W")
		t.expect(ghosts[2].x).toBe(13)
		t.expect(ghosts[2].y).toBe(14)
		t.expect(ghosts[3].x).toBe(12)
		t.expect(ghosts[4].x).toBe(15)
		for _, g in ghosts do
			t.expect(g.look).toBe("normal")
			t.expect(g.flash).toBe(false)
			t.expect(g.jumpTick).toBe(-1)
		end
	end)

	it("a position is continuous: the tile plus the progress toward the next, in tile units", function()
		local s = new()
		playing(s)
		local blinky = Ghosts.ghost(set(s), "blinky")
		blinky.tile, blinky.heading, blinky.progress = { x = 6, y = 5 }, "E", 30
		local g = listed(s)[1]
		t.expect(g.x).toBeNear(6.25, 1e-12)
		t.expect(g.y).toBe(5)
		blinky.heading, blinky.progress = "S", 60
		g = listed(s)[1]
		t.expect(g.x).toBe(6)
		t.expect(g.y).toBe(5.5)
	end)

	it("the look follows the ghost: normal, frightened, blinking at the end, eyes once eaten", function()
		local s = new()
		playing(s)
		local ghosts = set(s)
		Ghosts.power(ghosts, 200)
		t.expect(listed(s)[2].look).toBe("frightened")
		ghosts.frightened = 70
		t.expect(listed(s)[2].look).toBe("blinking")
		Ghosts.eat(ghosts, "pinky")
		t.expect(listed(s)[2].look).toBe("eyes")
		t.expect(listed(s)[1].look).toBe("blinking")
		ghosts.frightened = 0
		for _, g in ghosts.ghosts do
			g.frightened = false
		end
		t.expect(listed(s)[1].look).toBe("normal")
	end)

	it("the flash is true only on the white half of a blinking cycle", function()
		local s = new()
		playing(s)
		local ghosts = set(s)
		Ghosts.power(ghosts, 200)
		t.expect(listed(s)[1].flash).toBe(false)
		ghosts.frightened = 63 -- the first white tick of the blinking
		t.expect(listed(s)[1].flash).toBe(true)
		ghosts.frightened = 70
		t.expect(listed(s)[1].flash).toBe(false)
		-- a ghost that is not blinking (a revived one among blue ones) never carries the flash
		ghosts.frightened = 63
		Ghosts.ghost(ghosts, "pinky").frightened = false
		t.expect(listed(s)[1].flash).toBe(true)
		t.expect(listed(s)[2].flash).toBe(false)
	end)

	it(
		"a ghost that wraps through a tunnel, and every ghost after a reset, carry the tick of the jump",
		function()
			local s = new()
			playing(s)
			local blinky = Ghosts.ghost(set(s), "blinky")
			blinky.tile, blinky.heading, blinky.progress, blinky.status =
				{ x = 0, y = 14 }, "W", 110, "active"
			Session.step(s)
			t.expect(listed(s)[1].jumpTick).toBe(s.tick)
			t.expect(listed(s)[2].jumpTick).toBe(-1)
			-- a death and the respawn: everybody is put back, a camera cut for every ghost
			local resetTick = s.tick
			Session.kill(s, "p")
			for _ = 1, 50 do
				Session.step(s)
			end
			for _, g in listed(s) do
				t.expect(g.jumpTick > resetTick).toBe(true)
				t.expect(g.jumpTick <= s.tick).toBe(true)
			end
		end
	)

	it("the frame carries the same ghosts beside the play record, and everything is plain data", function()
		local s = new()
		playing(s)
		local snap = Session.snapshot(s, "p")
		local frame = Session.frame(s, "p")
		t.expect(frame.ghosts).toEqual(snap.ghosts)
		t.expect(type(frame.play)).toBe("table")
		-- c0153: plain data, and a JSON round trip within 1e-9 (Lune's JSON decoder can return a number one ulp off)
		t.expect({ plain.roundTrip(frame, 1e-9) }).toEqual({ true })
		-- four ghosts are a few hundred bytes a step
		t.expect(#serde.encode("json", (frame :: any).ghosts) < 700).toBe(true)
	end)

	it("a session without ghosts replicates exactly what it did before: no ghosts field anywhere", function()
		local s = Session.new(classic, 1)
		Session.join(s, "p")
		t.expect(Session.snapshot(s, "p").ghosts).toBe(nil)
		t.expect(Session.frame(s, "p").ghosts).toBe(nil)
	end)
end)
