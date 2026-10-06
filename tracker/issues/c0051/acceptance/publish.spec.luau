--!strict
-- c0490: AC7: publish retries 409 (retrySeconds) and 429/5xx (transientSeconds) within one MAX_ATTEMPTS budget.
local OpenCloud = require("@scripts/lib/opencloud")
local t = require("@tests/lib/t")

local KEY = "SECRET-KEY-0123456789"
local MAX = OpenCloud.MAX_ATTEMPTS

local function respond(code: number, body: string): OpenCloud.Response
	return { statusCode = code, body = body }
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

return t.spec("c0490 publish retries", function(it)
	it("a transient failure then success publishes, pausing transientSeconds", function()
		local cfg, calls, naps = fake({ respond(503, "blip"), respond(200, '{"versionNumber":7}') })
		t.expect(OpenCloud.publish(cfg, "place")).toBe(7)
		t.expect(#calls).toBe(2)
		t.expect(naps).toEqual({ 5 })
	end)

	it("429 is retried like a 5xx", function()
		local cfg, _, naps = fake(
			{ respond(429, "slow"), respond(200, '{"versionNumber":8}') },
			{ transientSeconds = 2 }
		)
		t.expect(OpenCloud.publish(cfg, "place")).toBe(8)
		t.expect(naps).toEqual({ 2 })
	end)

	it("409 still pauses retrySeconds (60 by default) and a transient failure in between pauses 5", function()
		local cfg, calls, naps =
			fake({ respond(409, "busy"), respond(503, "blip"), respond(200, '{"versionNumber":9}') })
		t.expect(OpenCloud.publish(cfg, "place")).toBe(9)
		t.expect(#calls).toBe(3)
		t.expect(naps).toEqual({ 60, 5 })
	end)

	it("a permanent transient failure makes exactly MAX_ATTEMPTS calls and reports the status", function()
		local cfg, calls, naps = fake({ respond(503, "gone") })
		t.expect(function()
			OpenCloud.publish(cfg, "place")
		end).toThrow("publish failed with HTTP 503: gone")
		t.expect(#calls).toBe(MAX)
		t.expect(#naps).toBe(MAX - 1)
	end)

	it("409 and transient failures share one budget of MAX_ATTEMPTS, not one each", function()
		local cfg, calls, naps = fake({
			respond(409, "busy"),
			respond(503, "blip"),
			respond(409, "busy"),
			respond(503, "blip"),
			respond(409, "busy"),
		}, { retrySeconds = 11, transientSeconds = 3 })
		t.expect(function()
			OpenCloud.publish(cfg, "place")
		end).toThrow("publish failed with HTTP 409: busy")
		t.expect(#calls).toBe(MAX)
		t.expect(naps).toEqual({ 11, 3, 11, 3 })
	end)

	it(
		"publish has no total pause cap beyond MAX_ATTEMPTS: four 409 waits of retrySeconds still happen",
		function()
			local cfg, _, naps = fake({ respond(409, "busy") }, { transientBudgetSeconds = 1 })
			t.expect(function()
				OpenCloud.publish(cfg, "place")
			end).toThrow("HTTP 409")
			t.expect(naps).toEqual({ 60, 60, 60, 60 })
		end
	)
end)
