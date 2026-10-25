--!strict
-- Headless simulation harness. Runs any model (new / step / observe) for N ticks from a script of
-- timed intents and expectations, and returns a trace. See the pickman-test skill, "Simulations".
--
-- Tick semantics: step k moves the world from time k to time k+1; an intent at k is delivered in
-- step k; events returned by step k are visible at time k+1 (stamped tick = k+1).
local fs = require("@lune/fs")
local serde = require("@lune/serde")

export type Event = { [string]: any }
export type Model<State> = {
	name: string,
	tickRate: number,
	new: (seed: number) -> State,
	step: (state: State, intents: { any }, tick: number) -> { Event }?,
	observe: (state: State) -> any,
}
export type Item = { at: number, intent: any?, expect: any?, label: string? }
export type RunOptions = {
	seed: number,
	ticks: number,
	script: { Item }?,
	stopWhen: ((obs: any, events: { Event }, t: number) -> boolean)?,
	record: boolean?,
}
export type Stamped = { tick: number, event: Event }
export type Trace = {
	model: string,
	seed: number,
	ticks: number,
	steps: number,
	stopped: boolean,
	states: { any },
	events: { Stamped },
	final: any,
}

local REPLAY_DIR = ".cache/sim"

local sim = {}

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function show(v: any): string
	local ty = type(v)
	if ty == "string" then
		return string.format("%q", v)
	elseif ty == "table" then
		local ok, encoded = pcall(function()
			return serde.encode("json", v)
		end)
		return if ok then encoded else tostring(v)
	end
	return tostring(v)
end

local function isInteger(v: any): boolean
	return type(v) == "number" and v == math.floor(v) and v == v and math.abs(v) ~= math.huge
end

-- Builders ----------------------------------------------------------------------------------------

function sim.intent(at: number, intent: any): Item
	return { at = at, intent = intent }
end

function sim.expect(at: number, want: { [string]: any } | (obs: any) -> (), label: string?): Item
	return { at = at, expect = want, label = label }
end

-- Validation --------------------------------------------------------------------------------------

local function validate(name: string, opts: RunOptions)
	if type(name) ~= "string" or not string.match(name, "^[%w_-]+$") then
		error("sim: model name must match [%w_-]+", 3)
	end
	if not isInteger(opts.seed) then
		error("sim: seed must be an integer", 3)
	end
	if not isInteger(opts.ticks) or opts.ticks < 1 then
		error("sim: ticks must be a positive integer", 3)
	end
	local script: { Item } = opts.script or {}
	for i, item in script do
		local hasIntent = item.intent ~= nil
		local hasExpect = item.expect ~= nil
		if hasIntent == hasExpect then
			error(`sim: script item {i} must have exactly one of intent or expect`, 3)
		end
		if not isInteger(item.at) or item.at < 0 then
			error(`sim: script item {i}: at must be an integer >= 0`, 3)
		end
		if hasIntent and item.at >= opts.ticks then
			error(
				`sim: script item {i}: intent at {item.at} is beyond the last step (ticks = {opts.ticks}); it would never be delivered`,
				3
			)
		end
		if hasExpect and item.at > opts.ticks then
			error(
				`sim: script item {i}: expectation at {item.at} is beyond the last tick (ticks = {opts.ticks}); it could never be checked`,
				3
			)
		end
	end
end

-- Core --------------------------------------------------------------------------------------------

type FailKind = "expect" | "never" | "step"

-- Returns the trace. `replaying` re-raises step errors unchanged and never writes a replay.
local function execute<S>(model: Model<S>, opts: RunOptions, replaying: boolean): Trace
	local script: { Item } = opts.script or {}
	local record = opts.record ~= false
	local seed, ticks = opts.seed, opts.ticks

	local states: { any } = {}
	local events: { Stamped } = {}
	local steps = 0

	local function fail(kind: FailKind, tick: number, label: string, detail: string): never
		local message = `sim[{model.name}] seed {seed} tick {tick}: {label}: {detail}`
		local path = `{REPLAY_DIR}/{model.name}-seed{seed}-tick{tick}.json`
		local intents = {}
		for _, item in script do
			if item.intent ~= nil then
				table.insert(intents, { at = item.at, intent = item.intent })
			end
		end
		local ok, reason = pcall(function()
			local doc = {
				model = model.name,
				seed = seed,
				ticks = ticks,
				steps = steps,
				failure = { tick = tick, message = message, kind = kind },
				script = intents,
				states = states,
				events = events,
			}
			fs.writeDir(REPLAY_DIR)
			fs.writeFile(path, serde.encode("json", doc))
		end)
		local line = if ok then `replay: {path}` else `replay: not written ({reason})`
		error(`{message}\n{line}`, 0)
	end

	local function check(t: number, obs: any)
		for _, item in script do
			if item.expect ~= nil and item.at == t then
				local label = item.label or "expect"
				local want: any = item.expect
				if type(want) == "function" then
					local ok, err = pcall(want, deepCopy(obs))
					if not ok then
						fail("expect", t, label, tostring(err))
					end
				else
					local keys = {}
					for k in want do
						table.insert(keys, k)
					end
					table.sort(keys, function(a: any, b: any)
						return tostring(a) < tostring(b)
					end)
					for _, k in keys do
						if not deepEqual(want[k], obs[k]) then
							fail(
								"expect",
								t,
								label,
								`field {show(k)}: expected {show(want[k])}, got {show(obs[k])}`
							)
						end
					end
				end
			end
		end
	end

	local state = model.new(seed)
	local obs = deepCopy(model.observe(state))
	if record then
		table.insert(states, deepCopy(obs))
	end
	check(0, obs)

	local stopped = false
	for k = 0, ticks - 1 do
		local intents = {}
		for _, item in script do
			if item.intent ~= nil and item.at == k then
				table.insert(intents, deepCopy(item.intent))
			end
		end

		local ok, result = pcall(model.step, state, intents, k)
		local stepEvents: { Event } = {}
		local problem: string? = nil
		if not ok then
			problem = tostring(result)
		else
			for _, e in (result or {}) :: { Event } do
				if type(e) ~= "table" or type((e :: any).kind) ~= "string" then
					problem = "step returned an event without a string kind"
					break
				end
				table.insert(stepEvents, deepCopy(e))
			end
		end
		if problem then
			if replaying then
				error(if ok then problem else result, 0)
			end
			fail("step", k, "step raised", problem)
		end

		local t = k + 1
		steps = t
		if record then
			for _, e in stepEvents do
				table.insert(events, { tick = t, event = deepCopy(e) })
			end
		end
		obs = deepCopy(model.observe(state))
		if record then
			table.insert(states, deepCopy(obs))
		end
		check(t, obs)

		local stopWhen = opts.stopWhen
		if stopWhen and stopWhen(deepCopy(obs), deepCopy(stepEvents), t) then
			stopped = true
			break
		end
	end

	-- expectations the run never reached (only possible after stopWhen)
	local never: Item? = nil
	for _, item in script do
		if item.expect ~= nil and item.at > steps and (never == nil or item.at < never.at) then
			never = item
		end
	end
	if never then
		fail("never", never.at, never.label or "expect", `never reached (stopped at tick {steps})`)
	end

	return {
		model = model.name,
		seed = seed,
		ticks = ticks,
		steps = steps,
		stopped = stopped,
		states = states,
		events = events,
		final = obs,
	}
end

function sim.run<S>(model: Model<S>, opts: RunOptions): Trace
	validate(model.name, opts)
	return execute(model, opts, false)
end

-- Trace queries -----------------------------------------------------------------------------------

function sim.state(trace: Trace, t: number): any
	local s = if isInteger(t) then trace.states[t + 1] else nil
	if s == nil then
		error(`sim.state: tick {t} was not recorded`, 2)
	end
	return s
end

local function matcher(match: (string | (Event) -> boolean)?): (Event) -> boolean
	if match == nil then
		return function()
			return true
		end
	elseif type(match) == "string" then
		local kind = match
		return function(e: Event)
			return e.kind == kind
		end
	end
	return match :: (Event) -> boolean
end

function sim.events(trace: Trace, match: (string | (Event) -> boolean)?): { Stamped }
	local f = matcher(match)
	local out = {}
	for _, s in trace.events do
		if f(s.event) then
			table.insert(out, s)
		end
	end
	return out
end

function sim.firstTick(trace: Trace, match: string | (Event) -> boolean): number?
	local f = matcher(match)
	for _, s in trace.events do
		if f(s.event) then
			return s.tick
		end
	end
	return nil
end

function sim.ticks<S>(model: Model<S>, seconds: number): number
	return math.floor(seconds * model.tickRate + 0.5)
end

function sim.seconds<S>(model: Model<S>, ticks: number): number
	return ticks / model.tickRate
end

function sim.seeds(n: number, base: number?): { number }
	local first = base or 1
	local out = {}
	for i = 0, n - 1 do
		table.insert(out, first + i)
	end
	return out
end

-- Determinism -------------------------------------------------------------------------------------

local function bucketEvents(trace: Trace): { [number]: { Event } }
	local out: { [number]: { Event } } = {}
	for _, s in trace.events do
		local list = out[s.tick] or {}
		out[s.tick] = list
		table.insert(list, s.event)
	end
	return out
end

function sim.assertDeterministic<S>(model: Model<S>, opts: RunOptions): Trace
	local o = table.clone(opts)
	o.record = true
	local a = sim.run(model, o)
	local b = sim.run(model, o)
	local ea, eb = bucketEvents(a), bucketEvents(b)
	for t = 0, math.max(#a.states, #b.states) - 1 do
		if not deepEqual(a.states[t + 1], b.states[t + 1]) or not deepEqual(ea[t] or {}, eb[t] or {}) then
			error(`sim[{model.name}] seed {opts.seed}: nondeterministic: diverged at tick {t}`, 0)
		end
	end
	return a
end

-- Replay ------------------------------------------------------------------------------------------

function sim.replay<S>(model: Model<S>, path: string): Trace
	local doc: any = serde.decode("json", fs.readFile(path))
	if doc.model ~= model.name then
		error(`sim.replay: {path} was recorded for model "{doc.model}", not "{model.name}"`, 2)
	end
	local steps: number = doc.steps
	local ticks = if doc.failure.kind == "step" then steps + 1 else steps
	local script: { Item } = {}
	for _, item in doc.script do
		if item.at < ticks then
			table.insert(script, { at = item.at, intent = item.intent })
		end
	end
	return execute(model, { seed = doc.seed, ticks = ticks, script = script, record = true }, true)
end

-- Bench -------------------------------------------------------------------------------------------

function sim.bench<S>(
	model: Model<S>,
	opts: { worlds: number, ticks: number, seed: number? }
): { seconds: number, steps: number }
	local first = opts.seed or 1
	local worlds: { S } = {}
	for i = 0, opts.worlds - 1 do
		table.insert(worlds, model.new(first + i))
	end
	local none: { any } = table.freeze({})
	local step = model.step
	local started = os.clock()
	for k = 0, opts.ticks - 1 do
		for _, w in worlds do
			step(w, none, k)
		end
	end
	return { seconds = os.clock() - started, steps = opts.worlds * opts.ticks }
end

return sim
