--!strict
-- c0090 AC3: failures write a replay file that sim.replay reproduces exactly.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local function lcg(s: number): number
	return (s * 1103515245 + 12345) % 2147483648
end
-- A seeded random walker: the replay must reproduce its randomness from the seed.
local Drunk = {
	name = "drunk",
	tickRate = 30,
	new = function(seed: number): any
		return { x = 0, rng = seed, log = {} }
	end,
	step = function(s: any, intents: { any }, _tick: number): { any }
		for _, i in intents do
			table.insert(s.log, i)
		end
		s.rng = lcg(s.rng)
		s.x += if s.rng % 2 == 0 then 1 else -1
		return { { kind = "Moved", x = s.x } }
	end,
	observe = function(s: any): any
		return { x = s.x, log = s.log }
	end,
}

local function failAndGetReplay(seed: number): (string, string)
	local ok, err = pcall(function()
		sim.run(Drunk, {
			seed = seed,
			ticks = 40,
			script = {
				sim.intent(0, "hello"),
				sim.intent(7, { kind = "Turn", dir = "Left" }),
				sim.expect(9, function(_obs: any)
					error("stop here")
				end, "forced"),
				sim.intent(12, "after"),
			},
		})
	end)
	t.expect(ok).toBe(false)
	local msg = tostring(err)
	local path = string.match(msg, "replay: (%S+%.json)")
	if not path then
		error(`no replay path in: {msg}`)
	end
	return path, msg
end

return t.spec("c0090 sim replay", function(it)
	it("a failure writes a replay file under .cache/sim and names it in the message", function()
		local path = failAndGetReplay(42)
		t.expect(string.sub(path, 1, #".cache/sim/")).toBe(".cache/sim/")
		t.expect(fs.isFile(path)).toBe(true)
		local doc = serde.decode("json", fs.readFile(path))
		t.expect(doc.model).toBe("drunk")
		t.expect(doc.seed).toBe(42)
		t.expect(doc.ticks).toBe(40)
		t.expect(doc.steps).toBe(9)
		t.expect(doc.failure.tick).toBe(9)
		t.expect(doc.failure.kind).toBe("expect")
		t.expect(string.find(doc.failure.message, "stop here", 1, true) ~= nil).toBe(true)
		local want: { any } = {
			{ at = 0, intent = "hello" },
			{ at = 7, intent = { kind = "Turn", dir = "Left" } },
			{ at = 12, intent = "after" },
		}
		t.expect(doc.script).toEqual(want)
		t.expect(#doc.states).toBe(10)
	end)

	it("different seeds write different replay files", function()
		local a = failAndGetReplay(1)
		local b = failAndGetReplay(2)
		t.expect(a ~= b).toBe(true)
	end)

	it("sim.replay reproduces the recorded states and events", function()
		local path = failAndGetReplay(7)
		local doc = serde.decode("json", fs.readFile(path))
		local trace = sim.replay(Drunk, path)
		t.expect(trace.seed).toBe(7)
		t.expect(trace.steps).toBe(9)
		t.expect(#trace.states).toBe(10)
		for i = 1, 10 do
			t.expect(trace.states[i]).toEqual(doc.states[i])
		end
		t.expect(#trace.events).toBe(9)
		t.expect(trace.events).toEqual(doc.events)
		-- the tick-7 intent was delivered, the tick-12 one was not (beyond the failure)
		local delivered: { any } = { "hello", { kind = "Turn", dir = "Left" } }
		t.expect(trace.final.log).toEqual(delivered)
	end)

	it("a failure at time 0 can be replayed: the trace holds only the initial state", function()
		local ok, err = pcall(function()
			sim.run(Drunk, { seed = 3, ticks = 5, script = { sim.expect(0, { x = 99 }, "initial") } })
		end)
		t.expect(ok).toBe(false)
		local path = string.match(tostring(err), "replay: (%S+%.json)")
		if not path then
			error(`no replay path in: {err}`)
		end
		local doc = serde.decode("json", fs.readFile(path))
		t.expect(doc.steps).toBe(0)
		local trace = sim.replay(Drunk, path)
		t.expect(trace.steps).toBe(0)
		t.expect(#trace.states).toBe(1)
		t.expect(trace.states[1]).toEqual(doc.states[1])
		t.expect(#trace.events).toBe(0)
	end)

	it("an observation that is not JSON-safe still reports the real failure", function()
		-- @lune/serde refuses integer-keyed tables, so the replay cannot be written
		local Sparse = {
			name = "sparse",
			tickRate = 30,
			new = function(_seed: number): any
				return { n = 0 }
			end,
			step = function(s: any, _intents: { any }, _tick: number): { any }
				s.n += 1
				return {}
			end,
			observe = function(s: any): any
				return { n = s.n, pellets = { [3] = true, [7] = true } }
			end,
		}
		local ok, err = pcall(function()
			sim.run(Sparse, { seed = 1, ticks = 4, script = { sim.expect(2, { n = 5 }, "count") } })
		end)
		t.expect(ok).toBe(false)
		local msg = tostring(err)
		t.expect(string.find(msg, "tick 2", 1, true) ~= nil).toBe(true)
		t.expect(string.find(msg, 'field "n": expected 5, got 2', 1, true) ~= nil).toBe(true)
		t.expect(string.find(msg, "replay: not written", 1, true) ~= nil).toBe(true)
	end)

	it("sim.replay re-runs the model rather than reading the file back", function()
		local path = failAndGetReplay(11)
		local news, steps = 0, 0
		local Counted = table.clone(Drunk)
		Counted.new = function(seed: number): any
			news += 1
			return Drunk.new(seed)
		end
		Counted.step = function(s: any, intents: { any }, tick: number): { any }
			steps += 1
			return Drunk.step(s, intents, tick)
		end
		local trace = sim.replay(Counted, path)
		t.expect(news).toBe(1)
		t.expect(steps).toBe(9)
		t.expect(trace.steps).toBe(9)
	end)

	it("replaying a step error re-runs the failing step with its intents and re-raises", function()
		local Boomer = {
			name = "boomer",
			tickRate = 30,
			new = function(_seed: number): any
				return { n = 0 }
			end,
			step = function(s: any, intents: { any }, _tick: number): { any }
				for _, i in intents do
					if i == "boom" then
						error("wall fell over")
					end
				end
				s.n += 1
				return {}
			end,
			observe = function(s: any): any
				return { n = s.n }
			end,
		}
		local ok, err = pcall(function()
			sim.run(Boomer, { seed = 1, ticks = 10, script = { sim.intent(4, "boom") } })
		end)
		t.expect(ok).toBe(false)
		local path = string.match(tostring(err), "replay: (%S+%.json)")
		if not path then
			error(`no replay path in: {err}`)
		end
		local doc = serde.decode("json", fs.readFile(path))
		t.expect(doc.failure.kind).toBe("step")
		t.expect(doc.steps).toBe(4)
		local rok, rerr = pcall(function()
			sim.replay(Boomer, path)
		end)
		t.expect(rok).toBe(false)
		t.expect(string.find(tostring(rerr), "wall fell over", 1, true) ~= nil).toBe(true)
	end)

	it("sim.replay refuses a replay recorded for another model", function()
		local path = failAndGetReplay(5)
		local Other = table.clone(Drunk)
		Other.name = "other"
		t.expect(function()
			sim.replay(Other, path)
		end).toThrow("model")
	end)
end)
