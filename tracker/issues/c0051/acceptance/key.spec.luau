--!strict
-- c0490: AC8: the API key never appears in an error, after retries or in publish.
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

return t.spec("c0490 the key stays out of errors", function(it)
	it("a retry that ends in failure never leaks the API key", function()
		local cfgs = {
			(fake({ respond(503, "x") })),
			(fake({ created(), respond(429, "y") })),
		}
		for _, cfg in cfgs do
			local ok, err = pcall(OpenCloud.execute, cfg, 5, "x")
			t.expect(ok).toBe(false)
			t.expect((string.find(tostring(err), KEY, 1, true))).toBe(nil)
		end
		local pub = fake({ respond(409, "z"), respond(503, "w") })
		local ok, err = pcall(OpenCloud.publish, pub, "place")
		t.expect(ok).toBe(false)
		t.expect((string.find(tostring(err), KEY, 1, true))).toBe(nil)
	end)
end)
