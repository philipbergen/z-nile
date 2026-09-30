--!strict
-- c0090 AC6: the bench steps many worlds interleaved, like the server, within a budget.
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local created: { number } = {}
local order: { number } = {}
local Tiny = {
	name = "tiny",
	tickRate = 30,
	new = function(seed: number): any
		table.insert(created, seed)
		return { seed = seed, n = 0 }
	end,
	step = function(s: any, intents: { any }, tick: number): { any }
		if #order < 6 then
			table.insert(order, s.seed)
		end
		if #intents ~= 0 or tick ~= s.n then
			error("bench must pass empty intents and the world's own tick")
		end
		s.n += 1
		return {}
	end,
	observe = function(s: any): any
		return { n = s.n }
	end,
}

return t.spec("c0090 sim bench", function(it)
	it("steps every world once per tick, interleaved, seeded from seed upward", function()
		table.clear(created)
		table.clear(order)
		local result = sim.bench(Tiny, { worlds = 3, ticks = 4, seed = 10 })
		t.expect(created).toEqual({ 10, 11, 12 })
		t.expect(order).toEqual({ 10, 11, 12, 10, 11, 12 })
		t.expect(result.steps).toBe(12)
		t.expect(result.seconds >= 0).toBe(true)
	end)

	it("64 worlds for 60 seconds at 30 Hz stays within the harness budget", function()
		table.clear(created)
		local result = sim.bench(Tiny, { worlds = 64, ticks = 1800, seed = 1 })
		t.expect(result.steps).toBe(64 * 1800)
		t.expect(#created).toBe(64)
		-- harness overhead only; the model is trivial. Generous for slow CI hosts.
		if result.seconds >= 0.5 then
			error(`bench took {result.seconds}s for {result.steps} steps (budget 0.5s)`)
		end
	end)
end)
