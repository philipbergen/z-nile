--!strict
-- c0490: AC1: which HTTP statuses are transient.
local OpenCloud = require("@scripts/lib/opencloud")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local KEY = "SECRET-KEY-0123456789"
local PATH = "universes/111/places/222/versions/5/luau-execution-sessions/abc/tasks/abc"

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

return t.spec("c0490 which statuses are transient", function(it)
	it("classifies 429 and every 5xx as transient, and nothing else", function()
		for _, code in { 429, 500, 502, 503, 504, 599 } do
			t.expect(OpenCloud.isTransient(code)).toBe(true)
		end
		for _, code in { 200, 201, 400, 401, 403, 404, 408, 409, 499, 600 } do
			t.expect(OpenCloud.isTransient(code)).toBe(false)
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
end)
