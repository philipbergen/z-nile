--!strict
-- c0090 AC1: script delivery, tick semantics and the trace.
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- A 1-D walker on 0..10, starting at 5. Intents: "L", "R", "S" (stop). Bumps at the ends.
local function lcg(s: number): number
	return (s * 1103515245 + 12345) % 2147483648
end
local Walker = {
	name = "walker",
	tickRate = 30,
	new = function(seed: number): any
		return { x = 5, dir = 0, rng = seed, coins = 0, seen = {}, counts = {} }
	end,
	step = function(s: any, intents: { any }, tick: number): { any }
		local events = {}
		table.insert(s.counts, #intents)
		for _, i in intents do
			table.insert(s.seen, `{tick}:{i}`)
			s.dir = if i == "L" then -1 elseif i == "R" then 1 else 0
		end
		local nx = s.x + s.dir
		if nx < 0 or nx > 10 then
			table.insert(events, { kind = "Bump", at = s.x })
			s.dir = 0
		else
			s.x = nx
		end
		s.rng = lcg(s.rng)
		if s.rng % 7 == 0 then
			s.coins += 1
			table.insert(events, { kind = "Coin" })
		end
		return events
	end,
	-- deliberately returns live references (seen, counts): the harness must snapshot
	observe = function(s: any): any
		return { x = s.x, dir = s.dir, coins = s.coins, seen = s.seen, counts = s.counts }
	end,
}

return t.spec("c0090 sim script", function(it)
	it("delivers each intent to the step of its tick, in script order", function()
		local trace = sim.run(Walker, {
			seed = 1,
			ticks = 5,
			script = { sim.intent(0, "R"), sim.intent(3, "L"), sim.intent(3, "S") },
		})
		t.expect(trace.final.seen).toEqual({ "0:R", "3:L", "3:S" })
		t.expect(trace.final.counts).toEqual({ 1, 0, 0, 2, 0 })
	end)

	it("time t is the state after t steps; state 0 is the initial state", function()
		local trace = sim.run(Walker, { seed = 1, ticks = 4, script = { sim.intent(0, "R") } })
		t.expect(trace.steps).toBe(4)
		t.expect(trace.stopped).toBe(false)
		t.expect(#trace.states).toBe(5)
		t.expect(sim.state(trace, 0).x).toBe(5)
		t.expect(sim.state(trace, 1).x).toBe(6)
		t.expect(sim.state(trace, 4).x).toBe(9)
		t.expect(trace.final.x).toBe(9)
		t.expect(trace.model).toBe("walker")
		t.expect(trace.seed).toBe(1)
	end)

	it("sim.state rejects times that were not recorded", function()
		local trace = sim.run(Walker, { seed = 1, ticks = 4 })
		t.expect(function()
			sim.state(trace, 5)
		end).toThrow("tick")
		t.expect(function()
			sim.state(trace, -1)
		end).toThrow("tick")
	end)

	it("stamps events with the time they became visible", function()
		-- from x=5 moving right: x=10 at time 5; step 5 bumps, visible at time 6
		local trace = sim.run(Walker, { seed = 1, ticks = 7, script = { sim.intent(0, "R") } })
		t.expect(sim.events(trace, "Bump")).toEqual({ { tick = 6, event = { kind = "Bump", at = 10 } } })
		t.expect(sim.firstTick(trace, "Bump")).toBe(6)
		t.expect(sim.firstTick(trace, function(e: any)
			return e.kind == "Bump" and e.at == 10
		end)).toBe(6)
		t.expect(sim.firstTick(trace, "Nope")).toBe(nil)
		-- events() without a matcher returns every event in emission order
		local all = sim.events(trace)
		for i = 2, #all do
			t.expect(all[i].tick >= all[i - 1].tick).toBe(true)
		end
		t.expect(#all).toBe(#sim.events(trace, "Bump") + #sim.events(trace, "Coin"))
	end)

	it("records snapshots, not live references", function()
		local trace =
			sim.run(Walker, { seed = 1, ticks = 3, script = { sim.intent(0, "R"), sim.intent(2, "S") } })
		t.expect(sim.state(trace, 0).seen).toEqual({})
		t.expect(sim.state(trace, 1).seen).toEqual({ "0:R" })
		t.expect(sim.state(trace, 3).seen).toEqual({ "0:R", "2:S" })
	end)

	it("converts between seconds and ticks at the model's tick rate", function()
		t.expect(sim.ticks(Walker, 2.5)).toBe(75)
		t.expect(sim.ticks(Walker, 0.05)).toBe(2) -- 1.5 rounds half up
		t.expect(sim.seconds(Walker, 45)).toBe(1.5)
	end)

	it("lists consecutive seeds", function()
		t.expect(sim.seeds(3)).toEqual({ 1, 2, 3 })
		t.expect(sim.seeds(2, 10)).toEqual({ 10, 11 })
	end)

	it("record = false keeps only the final state", function()
		local trace =
			sim.run(Walker, { seed = 1, ticks = 3, record = false, script = { sim.intent(0, "L") } })
		t.expect(#trace.states).toBe(0)
		t.expect(#trace.events).toBe(0)
		t.expect(trace.steps).toBe(3)
		t.expect(trace.final.x).toBe(2)
	end)
end)
