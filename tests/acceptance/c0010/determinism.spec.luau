--!strict
-- c0090 AC4: determinism checking and seeds.
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local function lcg(s: number): number
	return (s * 1103515245 + 12345) % 2147483648
end
local Drunk = {
	name = "drunk",
	tickRate = 30,
	new = function(seed: number): any
		return { x = 0, rng = seed }
	end,
	step = function(s: any, _intents: { any }, _tick: number): { any }
		s.rng = lcg(s.rng)
		local d = if (s.rng // 65536) % 2 == 0 then 1 else -1
		s.x += d
		return { { kind = "Moved", d = d } }
	end,
	observe = function(s: any): any
		return { x = s.x }
	end,
}

-- Leaks a module-level counter into its state from step 5 on, so two runs with the
-- same seed agree up to time 5 and diverge at time 6.
local leaked = 0
local Leaky = {
	name = "leaky",
	tickRate = 30,
	new = function(_seed: number): any
		return { x = 0 }
	end,
	step = function(s: any, _intents: { any }, tick: number): { any }
		if tick >= 5 then
			leaked += 1
			s.x = leaked
		end
		return {}
	end,
	observe = function(s: any): any
		return { x = s.x }
	end,
}

-- Same states on both runs, but the events differ from step 3 (visible at time 4).
local calls = 0
local EventLeaky = {
	name = "eventleaky",
	tickRate = 30,
	new = function(_seed: number): any
		return {}
	end,
	step = function(_s: any, _intents: { any }, tick: number): { any }
		calls += 1
		if tick == 3 then
			return { { kind = "Ping", n = calls } }
		end
		return {}
	end,
	observe = function(_s: any): any
		return {}
	end,
}

-- Marks every intent it receives as consumed; counts intents that arrive already consumed.
local Consumer = {
	name = "consumer",
	tickRate = 30,
	new = function(_seed: number): any
		return { stale = 0, got = 0 }
	end,
	step = function(s: any, intents: { any }, _tick: number): { any }
		for _, i in intents do
			s.got += 1
			if i.used then
				s.stale += 1
			end
			i.used = true
		end
		return {}
	end,
	observe = function(s: any): any
		return { stale = s.stale, got = s.got }
	end,
}

return t.spec("c0090 sim determinism", function(it)
	it("two runs with the same seed produce identical traces", function()
		local a = sim.run(Drunk, { seed = 9, ticks = 60 })
		local b = sim.run(Drunk, { seed = 9, ticks = 60 })
		t.expect(a.states).toEqual(b.states)
		t.expect(a.events).toEqual(b.events)
	end)

	it("different seeds produce different traces", function()
		local a = sim.run(Drunk, { seed = 1, ticks = 60 })
		local b = sim.run(Drunk, { seed = 2, ticks = 60 })
		t.expect(a.states == b.states).toBe(false)
		local same = true
		for i = 1, #a.states do
			if a.states[i].x ~= b.states[i].x then
				same = false
			end
		end
		t.expect(same).toBe(false)
	end)

	it("assertDeterministic passes a seeded model and returns its trace", function()
		local trace = sim.assertDeterministic(Drunk, { seed = 4, ticks = 90 })
		t.expect(trace.steps).toBe(90)
		t.expect(#trace.states).toBe(91)
	end)

	it("assertDeterministic names the first tick whose state diverged", function()
		local ok, err = pcall(function()
			sim.assertDeterministic(Leaky, { seed = 1, ticks = 20 })
		end)
		t.expect(ok).toBe(false)
		local msg = tostring(err)
		t.expect(string.find(msg, "leaky", 1, true) ~= nil).toBe(true)
		t.expect(string.find(msg, "diverged at tick 6", 1, true) ~= nil).toBe(true)
	end)

	it("each run receives fresh copies of the scripted intents", function()
		local script = { sim.intent(0, { kind = "Turn" }), sim.intent(2, { kind = "Turn" }) }
		local trace = sim.assertDeterministic(Consumer, { seed = 1, ticks = 4, script = script })
		t.expect(trace.final).toEqual({ stale = 0, got = 2 })
		-- the script as written is untouched
		t.expect(script[1].intent).toEqual({ kind = "Turn" })
	end)

	it("assertDeterministic compares the full length of both runs", function()
		-- an impure stopWhen: the first run stops at time 3, the second runs on
		local stops = 0
		local ok, err = pcall(function()
			sim.assertDeterministic(Drunk, {
				seed = 1,
				ticks = 10,
				stopWhen = function(_obs: any, _events: { any }, time: number): boolean
					if time == 3 and stops == 0 then
						stops += 1
						return true
					end
					return false
				end,
			})
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "diverged at tick 4", 1, true) ~= nil).toBe(true)
	end)

	it("assertDeterministic also compares events", function()
		local ok, err = pcall(function()
			sim.assertDeterministic(EventLeaky, { seed = 1, ticks = 10 })
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "diverged at tick 4", 1, true) ~= nil).toBe(true)
	end)
end)
