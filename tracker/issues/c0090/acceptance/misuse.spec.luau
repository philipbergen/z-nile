--!strict
-- c0090 AC5: misuse of the harness fails loudly before any step runs.
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local steps = 0
local Counter = {
	name = "counter",
	tickRate = 30,
	new = function(_seed: number): any
		return { n = 0 }
	end,
	step = function(s: any, _intents: { any }, _tick: number): { any }
		steps += 1
		s.n += 1
		return {}
	end,
	observe = function(s: any): any
		return { n = s.n }
	end,
}

local function rejects(opts: any, pattern: string)
	local before = steps
	t.expect(function()
		sim.run(Counter, opts)
	end).toThrow(pattern)
	t.expect(steps).toBe(before) -- validation happens before the first step
end

return t.spec("c0090 sim misuse", function(it)
	it("ticks must be a positive integer", function()
		rejects({ seed = 1, ticks = 0 }, "ticks")
		rejects({ seed = 1, ticks = 2.5 }, "ticks")
		rejects({ seed = 1 }, "ticks")
	end)

	it("seed must be an integer", function()
		rejects({ seed = 1.5, ticks = 3 }, "seed")
		rejects({ ticks = 3 }, "seed")
	end)

	it("script times must be integers from 0", function()
		rejects({ seed = 1, ticks = 3, script = { sim.intent(-1, "x") } }, "at")
		rejects({ seed = 1, ticks = 3, script = { sim.intent(1.5, "x") } }, "at")
	end)

	it("an intent at or beyond the last tick would never be delivered", function()
		rejects({ seed = 1, ticks = 3, script = { sim.intent(3, "x") } }, "beyond")
	end)

	it("an expectation beyond the last tick could never be checked", function()
		rejects({ seed = 1, ticks = 3, script = { sim.expect(4, { n = 4 }) } }, "beyond")
	end)

	it("an expectation at the last tick is allowed", function()
		local trace = sim.run(Counter, { seed = 1, ticks = 3, script = { sim.expect(3, { n = 3 }) } })
		t.expect(trace.final.n).toBe(3)
	end)

	it("a script item must be exactly one of intent or expect", function()
		rejects({ seed = 1, ticks = 3, script = { { at = 1 } } }, "script item 1")
		rejects({
			seed = 1,
			ticks = 3,
			script = { sim.intent(0, "x"), { at = 1, intent = "x", expect = { n = 1 } } },
		}, "script item 2")
	end)

	it("events must carry a string kind", function()
		local Bad = table.clone(Counter)
		Bad.name = "bad"
		Bad.step = function(_s: any, _intents: { any }, _tick: number): { any }
			return { { what = 1 } }
		end
		t.expect(function()
			sim.run(Bad, { seed = 1, ticks = 2 })
		end).toThrow("kind")
	end)
end)
