--!strict
-- f0120 AC3: a Session driven through the sim harness follows the tick semantics: snapshot.tick is
-- the time, an intent submitted before step k acts in step k, events carry the player's id.
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

local MODEL: sim.Model<Session.Session> = {
	name = "session",
	tickRate = Session.TICK_RATE,
	new = function(seed: number): Session.Session
		local s = Session.new(classic, seed)
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

return t.spec("f0120 session tick semantics", function(it)
	it("runs at 30 ticks per second", function()
		t.expect(Session.TICK_RATE).toBe(30)
	end)

	it("the snapshot at time t has tick = t", function()
		local trace = sim.run(MODEL, { seed = 1, ticks = 10 })
		for tk = 0, 10 do
			t.expect(sim.state(trace, tk).tick).toBe(tk)
		end
	end)

	it("an intent submitted before step k shows at time k + 1", function()
		sim.run(MODEL, {
			seed = 1,
			ticks = 8,
			script = {
				sim.expect(5, function(obs: any)
					t.expect(obs.player.heading).toBe("W")
					t.expect(obs.player.x).toBe(11.75)
				end),
				sim.intent(5, "Back"),
				sim.expect(6, function(obs: any)
					t.expect(obs.player.heading).toBe("E")
					t.expect(obs.player.x).toBe(12)
				end),
			},
		})
	end)

	it("reports movement events with the player's id, stamped with the time they become visible", function()
		local trace = sim.run(MODEL, { seed = 1, ticks = 40 })
		local first = sim.events(trace, "Entered")[1]
		t.expect(first.tick).toBe(2)
		t.expect(first.event.player).toBe("p1")
		t.expect(first.event.x).toBe(12)
		t.expect(first.event.y).toBe(23)
		local stop = sim.events(trace, "Stopped")[1]
		t.expect(stop.tick).toBe(28)
		t.expect(stop.event.player).toBe("p1")
		t.expect(stop.event.x).toBe(6)
		t.expect(stop.event.y).toBe(23)
		t.expect(sim.state(trace, 28).player.moving).toBe(false)
	end)

	it("is deterministic per seed", function()
		for _, seed in sim.seeds(5) do
			sim.assertDeterministic(MODEL, {
				seed = seed,
				ticks = 300,
				script = {
					sim.intent(3, "Right"),
					sim.intent(40, "Left"),
					sim.intent(41, "Back"),
					sim.intent(90, "Right"),
					sim.intent(150, "Left"),
				},
			})
		end
	end)
end)
