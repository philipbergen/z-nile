--!strict
-- A readable story: a player walks the classic maze through Session, as later rafts will.
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local MODEL: sim.Model<Session.Session> = {
	name = "session-walk",
	tickRate = Session.TICK_RATE,
	new = function(seed: number): Session.Session
		local s = Session.new(Maze.layout("classic"), seed)
		Session.join(s, "p1")
		return s
	end,
	step = function(s: Session.Session, intents: { any }, _k: number): { sim.Event }?
		for _, i in intents do
			Session.submit(s, "p1", i)
		end
		return Session.step(s) :: any
	end,
	observe = function(s: Session.Session): any
		return Session.snapshot(s, "p1")
	end,
}

return t.spec("scenario: walking west then north", function(it)
	it("stops at (6,23) after seven tiles, then turns north on request", function()
		local trace = sim.run(MODEL, {
			seed = 1,
			ticks = 40,
			script = {
				sim.expect(28, function(obs: any)
					t.expect(obs.player.x).toBe(6)
					t.expect(obs.player.moving).toBe(false)
				end),
				sim.intent(28, "Right"),
				sim.expect(29, function(obs: any)
					t.expect(obs.player.heading).toBe("N")
					t.expect(obs.player.y).toBe(22.75)
				end),
			},
		})
		t.expect(sim.firstTick(trace, "Stopped")).toBe(28)
	end)
end)
