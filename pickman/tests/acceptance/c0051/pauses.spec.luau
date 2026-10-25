--!strict
-- c0490: AC5: the pause between transient retries, and AC6: it does not eat the task timeout.
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

return t.spec("c0490 retry pauses", function(it)
	it("creation pauses transientSeconds, 5 by default, independent of the 409 retrySeconds", function()
		local cfg1, _, naps1 = fake({ respond(503, "a"), created(), done() }, { transientSeconds = 2 })
		OpenCloud.execute(cfg1, 5, "x")
		t.expect(naps1).toEqual({ 2 })
		local cfg2, _, naps2 = fake({ respond(503, "a"), created(), done() })
		OpenCloud.execute(cfg2, 5, "x")
		t.expect(naps2).toEqual({ 5 })
		local cfg3, _, naps3 = fake({ respond(503, "a"), created(), done() }, { retrySeconds = 60 })
		OpenCloud.execute(cfg3, 5, "x")
		t.expect(naps3).toEqual({ 5 }) -- retrySeconds is the 409 pause, not this one
	end)

	it("poll retries pause transientSeconds, and the poll interval stays its own", function()
		local cfg, _, naps = fake(
			{ created(), respond(503, "a"), task("PROCESSING"), done() },
			{ transientSeconds = 2 }
		)
		t.expect(OpenCloud.execute(cfg, 5, "x", { pollSeconds = 7 }).ok).toBe(true)
		t.expect(naps).toEqual({ 2, 7 }) -- the blip waits 2 s, the still-processing task 7 s
	end)

	it("transient pauses do not use up the timeout for the task itself", function()
		local cfg = fake({ created(), task("PROCESSING"), respond(503, "a"), task("PROCESSING"), done() })
		local run = OpenCloud.execute(cfg, 5, "x", { timeoutSeconds = 6, pollSeconds = 3 })
		t.expect(run.ok).toBe(true)
	end)
end)
