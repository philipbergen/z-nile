--!strict
-- c0490: AC4: retrying is bounded per request and, for a task, in total pause time.
local OpenCloud = require("@scripts/lib/opencloud")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local KEY = "SECRET-KEY-0123456789"
local PATH = "universes/111/places/222/versions/5/luau-execution-sessions/abc/tasks/abc"
local MAX = OpenCloud.MAX_ATTEMPTS

local function respond(code: number, body: string): OpenCloud.Response
	return { statusCode = code, body = body }
end

local function created(): OpenCloud.Response
	return respond(200, serde.encode("json" :: "json", { path = PATH, state = "PROCESSING" }))
end

local function task(state: string, extra: { [string]: any }?): OpenCloud.Response
	local body: { [string]: any } = { path = PATH, state = state }
	if extra then
		for k, v in extra do
			body[k] = v
		end
	end
	return respond(200, serde.encode("json" :: "json", body))
end

local function done(): OpenCloud.Response
	return task("COMPLETE", { output = { results = { "PASS" } } })
end

local function many(n: number, r: OpenCloud.Response): { OpenCloud.Response }
	local out: { OpenCloud.Response } = {}
	for _ = 1, n do
		table.insert(out, r)
	end
	return out
end

local function join(...: { OpenCloud.Response }): { OpenCloud.Response }
	local out: { OpenCloud.Response } = {}
	for _, list in { ... } do
		for _, r in list do
			table.insert(out, r)
		end
	end
	return out
end

type Extra = {
	retrySeconds: number?,
	transientSeconds: number?,
	transientBudgetSeconds: number?,
}

-- answers the scripted responses in order, then repeats the last one
local function fake(
	responses: { OpenCloud.Response },
	extra: Extra?
): (OpenCloud.Config, { OpenCloud.Request }, { number })
	local calls: { OpenCloud.Request } = {}
	local naps: { number } = {}
	local cfg: OpenCloud.Config = {
		apiKey = KEY,
		universeId = "111",
		placeId = "222",
		base = "https://example.test",
		request = function(r: OpenCloud.Request): OpenCloud.Response
			table.insert(calls, r)
			return responses[math.min(#calls, #responses)]
		end,
		sleep = function(seconds: number)
			table.insert(naps, seconds)
		end,
	}
	if extra then
		cfg.retrySeconds = extra.retrySeconds
		cfg.transientSeconds = extra.transientSeconds
		cfg.transientBudgetSeconds = extra.transientBudgetSeconds
	end
	return cfg, calls, naps
end

local function sum(list: { number }): number
	local total = 0
	for _, n in list do
		total += n
	end
	return total
end

local function count(list: { number }, value: number): number
	local n = 0
	for _, v in list do
		if v == value then
			n += 1
		end
	end
	return n
end

return t.spec("c0490 retry bounds", function(it)
	it("gives up on a creation that stays transient after exactly MAX_ATTEMPTS requests", function()
		local cfg, calls, naps = fake({ respond(500, "still down") })
		t.expect(function()
			OpenCloud.execute(cfg, 5, "x")
		end).toThrow("creating the task failed with HTTP 500: still down")
		t.expect(#calls).toBe(MAX)
		t.expect(#naps).toBe(MAX - 1) -- no pause after the last attempt
	end)

	it("gives up on a poll that stays transient after exactly MAX_ATTEMPTS requests", function()
		local cfg, calls, naps = fake({ created(), respond(429, "limit") })
		t.expect(function()
			OpenCloud.execute(cfg, 5, "x")
		end).toThrow("polling the task failed with HTTP 429: limit")
		t.expect(#calls).toBe(1 + MAX) -- one creation, then MAX polls
		t.expect(#naps).toBe(MAX - 1)
	end)

	it("counts attempts per request: a long run survives MAX_ATTEMPTS-1 failures at every step", function()
		local flaky = many(MAX - 1, respond(503, "blip"))
		local cfg, calls = fake(join(flaky, { created() }, flaky, { task("PROCESSING") }, flaky, { done() }))
		t.expect(OpenCloud.execute(cfg, 5, "x").ok).toBe(true)
		t.expect(#calls).toBe(3 * (MAX - 1) + 3)
	end)

	it("caps the transient pause time of one execute: the next transient answer is then final", function()
		local cfg, calls, naps = fake(
			{ respond(503, "a"), respond(503, "b"), created(), respond(502, "last") },
			{ transientSeconds = 5, transientBudgetSeconds = 10 }
		)
		t.expect(function()
			OpenCloud.execute(cfg, 5, "x")
		end).toThrow("polling the task failed with HTTP 502: last")
		t.expect(#calls).toBe(4)
		t.expect(naps).toEqual({ 5, 5 }) -- spending exactly the budget is allowed; one more pause is not
	end)

	it("the default cap is 60 seconds of transient pauses per execute", function()
		local flaky = many(MAX - 1, respond(503, "blip"))
		local step = join(flaky, { task("PROCESSING") })
		local cfg, calls, naps = fake(
			join({ created() }, step, step, step, many(1, respond(503, "over"))),
			{ transientSeconds = 5 }
		)
		cfg.sleep = function(seconds: number)
			table.insert(naps, seconds)
		end
		t.expect(function()
			OpenCloud.execute(cfg, 5, "x", { pollSeconds = 7 })
		end).toThrow("polling the task failed with HTTP 503: over")
		t.expect(count(naps, 5)).toBe(12) -- 12 pauses of 5 s = 60 s, and the 13th is refused
		t.expect(sum(naps) - 3 * 7).toBe(60)
		t.expect(#calls).toBe(1 + 3 * MAX + 1)
	end)

	it("the cap is per execute: a second execute on the same config gets a fresh one", function()
		local cfg = fake({
			respond(503, "a"),
			respond(503, "b"),
			created(),
			done(),
			respond(503, "c"),
			respond(503, "d"),
			created(),
			done(),
		}, { transientSeconds = 5, transientBudgetSeconds = 10 })
		t.expect(OpenCloud.execute(cfg, 5, "x").ok).toBe(true)
		t.expect(OpenCloud.execute(cfg, 5, "y").ok).toBe(true)
	end)

	it("a zero budget means the first transient answer is final", function()
		local cfg, calls, naps = fake({ respond(503, "now") }, { transientBudgetSeconds = 0 })
		t.expect(function()
			OpenCloud.execute(cfg, 5, "x")
		end).toThrow("HTTP 503: now")
		t.expect(#calls).toBe(1)
		t.expect(#naps).toBe(0)
	end)
end)
