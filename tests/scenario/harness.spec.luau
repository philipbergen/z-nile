--!strict
local Walker = require("@tests/fixtures/sim/walker")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

return t.spec("scenario: walker story", function(it)
	it("walks right, bumps the wall and stops", function()
		local trace = sim.run(Walker, {
			seed = 1,
			ticks = sim.ticks(Walker, 0.5),
			script = {
				sim.expect(0, { x = 5 }, "starts in the middle"),
				sim.intent(0, "R"),
				sim.expect(5, { x = 10, dir = 1 }, "reaches the wall"),
				sim.expect(6, { x = 10, dir = 0 }, "stops after the bump"),
			},
		})
		t.expect(sim.firstTick(trace, "Bump")).toBe(6)
		t.expect(trace.final.x).toBe(10)
	end)

	it("stops early once the wall is hit", function()
		local trace = sim.run(Walker, {
			seed = 1,
			ticks = 100,
			script = { sim.intent(0, "L") },
			stopWhen = function(_obs: any, events: { sim.Event }, _t: number): boolean
				return #events > 0
			end,
		})
		t.expect(trace.stopped).toBe(true)
		t.expect(trace.steps).toBe(6)
	end)

	-- the walker ignores its seed, so this only shows the pattern; leak detection is covered by the c0090 acceptance specs
	it("is deterministic across seeds", function()
		for _, seed in sim.seeds(5) do
			sim.assertDeterministic(Walker, { seed = seed, ticks = 20, script = { sim.intent(2, "R") } })
		end
	end)
end)
