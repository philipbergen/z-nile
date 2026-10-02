--!strict
-- f0220: a measurable proxy for "the ghosts really hunt". An idle player (no intents at all: it runs west
-- along the bottom corridor and stops at the wall) is caught between 8 and 20 seconds of game time after
-- the run goes into play, whatever the seed, and the whole story is deterministic.
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local MODEL: sim.Model<Session.Session> = {
	name = "idle-player",
	tickRate = Session.TICK_RATE,
	new = function(seed: number): Session.Session
		local s = Session.new(Maze.layout("classic"), seed, Session.GAME_CONFIG)
		Session.join(s, "p")
		return s
	end,
	step = function(s: Session.Session, intents: { any }, _k: number): { sim.Event }?
		for _, i in intents do
			Session.submit(s, "p", i)
		end
		return Session.step(s) :: any
	end,
	observe = function(s: Session.Session): any
		return Session.frame(s, "p")
	end,
}

local READY_TICKS = 60 -- the run is in play from tick 60

return t.spec("scenario: an idle player is caught", function(it)
	it(
		"is caught 8 to 20 seconds of game time after play starts, on every one of 20 seeds, by a named ghost",
		function()
			for _, seed in sim.seeds(20) do
				local trace = sim.run(MODEL, { seed = seed, ticks = sim.ticks(MODEL, 30) })
				local caught = sim.firstTick(trace, "Caught")
				t.expect(caught ~= nil).toBe(true)
				local seconds = ((caught :: number) - READY_TICKS) / Session.TICK_RATE
				t.expect(seconds >= 8).toBe(true)
				t.expect(seconds <= 20).toBe(true)
				local lost = sim.firstTick(trace, "LifeLost")
				t.expect(lost).toBe(caught)
				local who = sim.events(trace, "Caught")[1].event.ghost
				t.expect(table.find({ "blinky", "pinky", "inky", "clyde" }, who) ~= nil).toBe(true)
			end
		end
	)

	it("the same seed tells the same story twice", function()
		sim.assertDeterministic(MODEL, { seed = 3, ticks = sim.ticks(MODEL, 20) })
	end)
end)
