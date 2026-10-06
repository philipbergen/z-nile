--!strict
-- c0490: AC3: a failure that is not transient is raised at once.
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

return t.spec("c0490 final failures", function(it)
	it("never retries a task failure that is not transient", function()
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

	it("publish never retries a 4xx other than 409 and 429", function()
		for _, code in { 400, 401, 403, 404, 408 } do
			local cfg, calls, naps = fake({ respond(code, "no") })
			t.expect(function()
				OpenCloud.publish(cfg, "place")
			end).toThrow(`publish failed with HTTP {code}: no`)
			t.expect(#calls).toBe(1)
			t.expect(#naps).toBe(0)
		end
	end)
end)
