--!strict
-- f0120 AC6: a full server's worth of solo mazes steps far faster than real time.
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

-- Like the server: submit the player's intents, step, and build the snapshot to send.
-- A turn every 5 ticks and a Back every 97 keep the player moving.
local BUSY: sim.Model<Session.Session> = {
	name = "session-busy",
	tickRate = Session.TICK_RATE,
	new = function(seed: number): Session.Session
		local s = Session.new(classic, seed)
		Session.join(s, "p")
		return s
	end,
	step = function(s: Session.Session, _intents: { any }, k: number): { sim.Event }?
		if k % 5 == 0 then
			Session.submit(s, "p", if (k // 5) % 2 == 0 then "Left" else "Right")
		end
		if k % 97 == 0 then
			Session.submit(s, "p", "Back")
		end
		Session.step(s)
		Session.snapshot(s, "p")
		return nil
	end,
	observe = function(s: Session.Session): any
		return Session.snapshot(s, "p")
	end,
}

return t.spec("f0120 session budget", function(it)
	it("the benchmark player is actually moving most of the time", function()
		local trace = sim.run(BUSY, { seed = 1, ticks = 1800 })
		local moving = 0
		for tk = 0, trace.steps do
			if sim.state(trace, tk).player.moving then
				moving += 1
			end
		end
		t.expect(moving > 1500).toBe(true)
	end)

	it("50 players x 60 s of play (1,800 ticks) steps in under 4 s", function()
		-- Prep measured about 0.08 s (0.9 us per player-tick): a margin of about 50x.
		local r = sim.bench(BUSY, { worlds = 50, ticks = 1800 })
		t.expect(r.steps).toBe(90000)
		if r.seconds >= 4 then
			error(`took {r.seconds} s`)
		end
	end)
end)
