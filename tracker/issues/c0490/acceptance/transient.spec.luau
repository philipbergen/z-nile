--!strict
-- c0490: Open Cloud task creation and polling retry transient HTTP failures (429 and 5xx) a bounded number
-- of times, with a pause, and fail at once on anything else.
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

-- answers the scripted responses in order, then repeats the last one
local function fake(
	responses: { OpenCloud.Response },
	extra: { retrySeconds: number?, transientSeconds: number? }?
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
	end
	return cfg, calls, naps
end

return t.spec("c0490 transient Open Cloud errors", function(it)
	it("classifies 429 and every 5xx as transient, and nothing else", function()
		for _, code in { 429, 500, 502, 503, 504, 599 } do
			t.expect(OpenCloud.isTransient(code)).toBe(true)
		end
		for _, code in { 200, 201, 400, 401, 403, 404, 408, 409, 499, 600 } do
			t.expect(OpenCloud.isTransient(code)).toBe(false)
		end
	end)

	it("retries a transient failure creating the task, then goes on to poll", function()
		local cfg, calls, naps = fake({ respond(429, "slow down"), respond(503, "down"), created(), done() })
		local run = OpenCloud.execute(cfg, 5, "return 'PASS'")
		t.expect(run.ok).toBe(true)
		t.expect(#calls).toBe(4)
		t.expect(calls[1].method).toBe("POST")
		t.expect(calls[2].method).toBe("POST")
		t.expect(calls[2].body).toBe(calls[1].body) -- the retry sends the same script
		t.expect(calls[3].method).toBe("POST")
		t.expect(calls[4].method).toBe("GET")
		t.expect(#naps).toBe(2) -- one pause per retry, none after success
	end)

	it("retries a transient failure polling the task, and polls the same task again", function()
		local cfg, calls, naps = fake({ created(), respond(502, "bad gateway"), respond(429, "x"), done() })
		local run = OpenCloud.execute(cfg, 5, "return 'PASS'")
		t.expect(run.ok).toBe(true)
		t.expect(#calls).toBe(4)
		t.expect(calls[3].url).toBe(calls[2].url)
		t.expect(calls[4].url).toBe(`https://example.test/cloud/v2/{PATH}`)
		t.expect(#naps).toBe(2)
	end)

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

	it("never retries a failure that is not transient", function()
		for _, code in { 400, 401, 403, 404, 408, 409 } do
			local cfg1, calls1, naps1 = fake({ respond(code, "no") })
			t.expect(function()
				OpenCloud.execute(cfg1, 5, "x")
			end).toThrow(`creating the task failed with HTTP {code}`)
			t.expect(#calls1).toBe(1)
			t.expect(#naps1).toBe(0)
			local cfg2, calls2, naps2 = fake({ created(), respond(code, "no") })
			t.expect(function()
				OpenCloud.execute(cfg2, 5, "x")
			end).toThrow(`polling the task failed with HTTP {code}`)
			t.expect(#calls2).toBe(2)
			t.expect(#naps2).toBe(0)
		end
	end)

	it("retries the statuses at the edges of 5xx, and not the ones just outside", function()
		local cfg1, calls1 = fake({ respond(500, "a"), created(), done() })
		t.expect(OpenCloud.execute(cfg1, 5, "x").ok).toBe(true)
		t.expect(#calls1).toBe(3)
		local cfg2, calls2 = fake({ respond(599, "a"), created(), done() })
		t.expect(OpenCloud.execute(cfg2, 5, "x").ok).toBe(true)
		t.expect(#calls2).toBe(3)
		local cfg3, calls3 = fake({ respond(499, "a"), created(), done() })
		t.expect(function()
			OpenCloud.execute(cfg3, 5, "x")
		end).toThrow("HTTP 499")
		t.expect(#calls3).toBe(1)
	end)

	it(
		"pauses transientSeconds between retries, 5 by default, independent of the 409 retrySeconds",
		function()
			local cfg1, _, naps1 = fake({ respond(503, "a"), created(), done() }, { transientSeconds = 2 })
			OpenCloud.execute(cfg1, 5, "x")
			t.expect(naps1).toEqual({ 2 })
			local cfg2, _, naps2 = fake({ respond(503, "a"), created(), done() })
			OpenCloud.execute(cfg2, 5, "x")
			t.expect(naps2).toEqual({ 5 })
			local cfg3, _, naps3 = fake({ respond(503, "a"), created(), done() }, { retrySeconds = 60 })
			OpenCloud.execute(cfg3, 5, "x")
			t.expect(naps3).toEqual({ 5 }) -- retrySeconds is the publish pause, not this one
		end
	)

	it("counts attempts per request: a long run survives MAX_ATTEMPTS-1 failures at every step", function()
		local flaky = many(MAX - 1, respond(503, "blip"))
		local cfg, calls = fake(join(flaky, { created() }, flaky, { task("PROCESSING") }, flaky, { done() }))
		t.expect(OpenCloud.execute(cfg, 5, "x").ok).toBe(true)
		t.expect(#calls).toBe(3 * (MAX - 1) + 3)
	end)

	it("transient pauses do not use up the timeout for the task itself", function()
		local cfg = fake({ created(), task("PROCESSING"), respond(503, "a"), task("PROCESSING"), done() })
		local run = OpenCloud.execute(cfg, 5, "x", { timeoutSeconds = 6, pollSeconds = 3 })
		t.expect(run.ok).toBe(true)
	end)

	it("a retry that ends in failure still never leaks the API key", function()
		local cfg1 = fake({ respond(503, "x") })
		local cfg2 = fake({ created(), respond(429, "y") })
		for _, cfg in { cfg1, cfg2 } do
			local ok, err = pcall(OpenCloud.execute, cfg, 5, "x")
			t.expect(ok).toBe(false)
			t.expect((string.find(tostring(err), KEY, 1, true))).toBe(nil)
		end
	end)

	it(
		"runSuite retries inside a script, so a blip does not fail it, and a dead service still does",
		function()
			local cfg1, _, _ = fake({ respond(503, "a"), created(), done() })
			local suite1 = OpenCloud.runSuite(cfg1, 5, { { name = "a", source = "x" } })
			t.expect(suite1.passed).toBe(1)
			t.expect(suite1.failed).toBe(0)
			local cfg2 = fake({ respond(503, "gone") })
			local suite2 =
				OpenCloud.runSuite(cfg2, 5, { { name = "a", source = "x" }, { name = "b", source = "y" } })
			t.expect(suite2.failed).toBe(2)
			t.expect(suite2.lines[1]).toBe("FAIL a: opencloud: creating the task failed with HTTP 503: gone")
		end
	)

	it("publish is unchanged: a 5xx still fails at once, and 409 still waits retrySeconds", function()
		local cfg1, calls1, naps1 = fake({ respond(500, "boom") })
		t.expect(function()
			OpenCloud.publish(cfg1, "place")
		end).toThrow("publish failed with HTTP 500: boom")
		t.expect(#calls1).toBe(1)
		t.expect(#naps1).toBe(0)
		local cfg2, calls2, naps2 = fake(
			{ respond(409, "busy"), respond(200, '{"versionNumber":7}') },
			{ retrySeconds = 11 }
		)
		t.expect(OpenCloud.publish(cfg2, "place")).toBe(7)
		t.expect(#calls2).toBe(2)
		t.expect(naps2).toEqual({ 11 })
	end)
end)
