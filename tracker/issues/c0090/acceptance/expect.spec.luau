--!strict
-- c0090 AC2: expectations, early stop and failure reporting.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- A 1-D walker on 0..10, starting at 5. Intents: "L", "R", "S". Stops at the ends.
local Walker = {
	name = "walker",
	tickRate = 30,
	new = function(_seed: number): any
		return { x = 5, dir = 0 }
	end,
	step = function(s: any, intents: { any }, _tick: number): { any }?
		for _, i in intents do
			s.dir = if i == "L" then -1 elseif i == "R" then 1 else 0
		end
		s.x = math.clamp(s.x + s.dir, 0, 10)
		return nil -- a step may return nil for "no events"
	end,
	observe = function(s: any): any
		return { x = s.x, dir = s.dir, pos = { x = s.x, y = 0 } }
	end,
}

local function failure(fn: () -> ()): string
	local ok, err = pcall(function()
		fn()
	end)
	t.expect(ok).toBe(false)
	return tostring(err)
end

local function has(text: string, fragment: string)
	if not string.find(text, fragment, 1, true) then
		error(`expected message to contain {fragment}, got: {text}`, 2)
	end
end

-- The replay file a failure message names; the path must be exactly `expected`.
local function replayDoc(msg: string, expected: string): any
	has(msg, `replay: {expected}`)
	return serde.decode("json", fs.readFile(expected))
end

return t.spec("c0090 sim expect", function(it)
	it("a partial table expectation ignores fields it does not name", function()
		local trace = sim.run(Walker, {
			seed = 1,
			ticks = 4,
			script = { sim.intent(0, "R"), sim.expect(3, { x = 8 }), sim.expect(4, { x = 9, dir = 1 }) },
		})
		t.expect(trace.final.x).toBe(9)
	end)

	it("a failed expectation names the tick, the label, the field and both values", function()
		local msg = failure(function()
			sim.run(Walker, {
				seed = 3,
				ticks = 6,
				script = { sim.intent(0, "R"), sim.expect(3, { x = 7 }, "three steps right") },
			})
		end)
		has(msg, "walker")
		has(msg, "seed 3")
		has(msg, "tick 3")
		has(msg, "three steps right")
		has(msg, 'field "x": expected 7, got 8')
	end)

	it("table-valued fields are compared deeply, not by reference", function()
		local trace = sim.run(Walker, {
			seed = 1,
			ticks = 2,
			script = { sim.intent(0, "R"), sim.expect(1, { pos = { x = 6, y = 0 } }) },
		})
		t.expect(trace.final.pos).toEqual({ x = 7, y = 0 })
	end)

	it("a failed table-valued field shows both values as compact JSON", function()
		local msg = failure(function()
			sim.run(Walker, {
				seed = 1,
				ticks = 2,
				script = { sim.intent(0, "R"), sim.expect(1, { pos = { x = 7, y = 0 } }, "pos") },
			})
		end)
		has(msg, "tick 1")
		has(msg, 'field "pos"')
		has(msg, '"x":7')
		has(msg, '"x":6')
	end)

	it("a table-valued field must match completely: partial matching is top-level only", function()
		-- the observed pos is { x = 6, y = 0 }; { x = 6 } alone must not match it
		local msg = failure(function()
			sim.run(Walker, {
				seed = 1,
				ticks = 2,
				script = { sim.intent(0, "R"), sim.expect(1, { pos = { x = 6 } }, "sub") },
			})
		end)
		has(msg, "tick 1")
		has(msg, 'field "pos"')
	end)

	it("time 0 expectations check the initial state", function()
		local msg = failure(function()
			sim.run(Walker, { seed = 1, ticks = 2, script = { sim.expect(0, { x = 6 }) } })
		end)
		has(msg, "tick 0")
	end)

	it("a function expectation receives the state at its tick", function()
		local seen: { number } = {}
		sim.run(Walker, {
			seed = 1,
			ticks = 5,
			script = {
				sim.intent(0, "L"),
				sim.expect(2, function(obs: any)
					table.insert(seen, obs.x)
				end),
				sim.expect(5, function(obs: any)
					table.insert(seen, obs.x)
				end),
			},
		})
		t.expect(seen).toEqual({ 3, 0 })
	end)

	it("an error inside a function expectation is a failure at its tick", function()
		local msg = failure(function()
			sim.run(Walker, {
				seed = 1,
				ticks = 5,
				script = {
					sim.expect(2, function(_obs: any)
						error("custom boom")
					end),
				},
			})
		end)
		has(msg, "tick 2")
		has(msg, "custom boom")
	end)

	it("the run stops at the first failing tick", function()
		local msg = failure(function()
			sim.run(Walker, {
				seed = 1,
				ticks = 8,
				script = {
					sim.intent(0, "R"),
					sim.expect(5, { x = 0 }, "late"),
					sim.expect(2, { x = 0 }, "early"),
				},
			})
		end)
		has(msg, "tick 2")
		has(msg, "early")
	end)

	it("stopWhen ends the run early and reports it", function()
		local trace = sim.run(Walker, {
			seed = 1,
			ticks = 30,
			script = { sim.intent(0, "R") },
			stopWhen = function(obs: any, _events: { any }, _t: number): boolean
				return obs.x == 10
			end,
		})
		t.expect(trace.steps).toBe(5)
		t.expect(trace.stopped).toBe(true)
		t.expect(#trace.states).toBe(6)
		t.expect(trace.final.x).toBe(10)
	end)

	it("expectations at the stop tick are checked before the run stops", function()
		local msg = failure(function()
			sim.run(Walker, {
				seed = 1,
				ticks = 30,
				script = { sim.intent(0, "R"), sim.expect(5, { x = 99 }, "at stop") },
				stopWhen = function(obs: any, _events: { any }, _t: number): boolean
					return obs.x == 10
				end,
			})
		end)
		has(msg, "tick 5")
		has(msg, "at stop")
		t.expect(string.find(msg, "never reached", 1, true) == nil).toBe(true)
	end)

	it("stopWhen receives the new time and that step's events", function()
		local Pinger = {
			name = "pinger",
			tickRate = 30,
			new = function(_seed: number): any
				return { n = 0 }
			end,
			step = function(s: any, _intents: { any }, tick: number): { any }
				s.n += 1
				return if tick == 5 then { { kind = "Ping" } } else {}
			end,
			observe = function(s: any): any
				return { n = s.n }
			end,
		}
		local seen: { number } = {}
		local trace = sim.run(Pinger, {
			seed = 1,
			ticks = 30,
			stopWhen = function(_obs: any, events: { any }, time: number): boolean
				table.insert(seen, time)
				return #events > 0
			end,
		})
		t.expect(seen).toEqual({ 1, 2, 3, 4, 5, 6 })
		t.expect(trace.steps).toBe(6)
		t.expect(trace.stopped).toBe(true)
	end)

	it("record = false still checks expectations, and its replay has no states", function()
		local msg = failure(function()
			sim.run(
				Walker,
				{ seed = 1, ticks = 3, record = false, script = { sim.expect(2, { x = 99 }, "unrecorded") } }
			)
		end)
		has(msg, "tick 2")
		has(msg, "unrecorded")
		local doc = replayDoc(msg, ".cache/sim/walker-seed1-tick2.json")
		t.expect(doc.steps).toBe(2)
		t.expect(#doc.states).toBe(0)
	end)

	it("a function expectation gets a copy: mutating it leaves the trace intact", function()
		local trace = sim.run(Walker, {
			seed = 1,
			ticks = 3,
			script = {
				sim.intent(0, "R"),
				sim.expect(2, function(obs: any)
					obs.pos.x = 99
					obs.x = 99
				end),
			},
		})
		t.expect(sim.state(trace, 2).x).toBe(7)
		t.expect(sim.state(trace, 2).pos).toEqual({ x = 7, y = 0 })
	end)

	it("an expectation after an early stop fails as never reached", function()
		local msg = failure(function()
			sim.run(Walker, {
				seed = 1,
				ticks = 30,
				script = { sim.intent(0, "R"), sim.expect(20, { x = 10 }) },
				stopWhen = function(obs: any, _events: { any }, _t: number): boolean
					return obs.x == 10
				end,
			})
		end)
		has(msg, "tick 20")
		has(msg, "never reached")
		-- the replay covers the steps that ran: the run stopped at time 5
		local doc = replayDoc(msg, ".cache/sim/walker-seed1-tick20.json")
		t.expect(doc.steps).toBe(5)
		t.expect(doc.failure.tick).toBe(20)
		t.expect(doc.failure.kind).toBe("never")
		t.expect(#doc.states).toBe(6)
	end)

	it("an error inside step is reported with the step's tick", function()
		local Crashy = table.clone(Walker)
		Crashy.name = "crashy"
		Crashy.step = function(s: any, _intents: { any }, tick: number): { any }?
			if tick == 4 then
				error("wall fell over")
			end
			s.x += 1
			return nil
		end
		local msg = failure(function()
			sim.run(Crashy, { seed = 1, ticks = 10 })
		end)
		has(msg, "crashy")
		has(msg, "tick 4")
		has(msg, "wall fell over")
		-- steps 0..3 completed; the replay holds times 0..4
		local doc = replayDoc(msg, ".cache/sim/crashy-seed1-tick4.json")
		t.expect(doc.steps).toBe(4)
		t.expect(doc.failure.tick).toBe(4)
		t.expect(doc.failure.kind).toBe("step")
		t.expect(#doc.states).toBe(5)
	end)
end)
