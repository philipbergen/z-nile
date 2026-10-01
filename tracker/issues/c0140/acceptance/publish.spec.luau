--!strict
-- c0140 AC1: OpenCloud.publish puts a built place on the Beta experience through the Place Publishing
-- API, with exactly the request that works against Roblox (its shape was proven from CI in prep), retries
-- only "Roblox busy" and never lets the API key out of the x-api-key header.
local OpenCloud = require("@scripts/lib/opencloud")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local KEY = "SECRET-KEY-0123456789"

local function respond(code: number, body: string): OpenCloud.Response
	return { statusCode = code, body = body }
end

-- a config whose HTTP and sleep are fakes; `calls` and `naps` record what happened
local function fake(responses: { OpenCloud.Response }): (OpenCloud.Config, { OpenCloud.Request }, { number })
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
	return cfg, calls, naps
end

local function message(f: () -> ()): string
	local ok, err = pcall(f :: () -> any)
	t.expect(ok).toBe(false)
	return tostring(err)
end

return t.spec("c0140 OpenCloud.publish", function(it)
	it("posts the place to the versions endpoint, as published, with the key in x-api-key", function()
		local cfg, calls = fake({ respond(200, '{"versionNumber":7}') })
		local version = OpenCloud.publish(cfg, "PLACEBYTES\0\255")
		t.expect(version).toBe(7)
		t.expect(#calls).toBe(1)
		t.expect(calls[1].url)
			.toBe("https://example.test/universes/v1/111/places/222/versions?versionType=Published")
		t.expect(calls[1].method).toBe("POST")
		t.expect(calls[1].headers["x-api-key"]).toBe(KEY)
		t.expect(calls[1].headers["Content-Type"]).toBe("application/octet-stream")
		t.expect(calls[1].body).toBe("PLACEBYTES\0\255") -- the bytes untouched
	end)

	it("the default base is Roblox's API host", function()
		t.expect(OpenCloud.BASE).toBe("https://apis.roblox.com")
		local cfg, calls = fake({ respond(200, '{"versionNumber":1}') })
		cfg.base = nil
		OpenCloud.publish(cfg, "x")
		t.expect(calls[1].url)
			.toBe("https://apis.roblox.com/universes/v1/111/places/222/versions?versionType=Published")
	end)

	it("retries 'Roblox busy' (HTTP 409) with a pause, and succeeds when it clears", function()
		local cfg, calls, naps =
			fake({ respond(409, "busy"), respond(409, "busy"), respond(200, '{"versionNumber":9}') })
		cfg.retrySeconds = 5
		t.expect(OpenCloud.publish(cfg, "x")).toBe(9)
		t.expect(#calls).toBe(3)
		t.expect(naps).toEqual({ 5, 5 })
	end)

	it("the pause between retries defaults to 60 seconds", function()
		local cfg, _, naps = fake({ respond(409, "busy"), respond(200, '{"versionNumber":2}') })
		OpenCloud.publish(cfg, "x")
		t.expect(naps).toEqual({ 60 })
	end)

	it("gives up after exactly 5 attempts of busy", function()
		local cfg, calls, naps = fake({ respond(409, "still busy") })
		local err = message(function()
			OpenCloud.publish(cfg, "x")
		end)
		t.expect(#calls).toBe(5)
		t.expect(#naps).toBe(4) -- no wait after the last attempt
		t.expect(string.find(err, "409", 1, true) ~= nil).toBe(true)
		t.expect(string.find(err, "still busy", 1, true) ~= nil).toBe(true)
	end)

	it("any other failure is final: no retry, and the status and body are reported", function()
		for _, code in { 400, 401, 403, 404, 429, 500, 503 } do
			local cfg, calls, naps =
				fake({ respond(code, '{"errors":[{"code":9009,"message":"WAF Blocked Request"}]}') })
			local err = message(function()
				OpenCloud.publish(cfg, "x")
			end)
			t.expect(#calls).toBe(1)
			t.expect(#naps).toBe(0)
			t.expect(string.find(err, tostring(code), 1, true) ~= nil).toBe(true)
			t.expect(string.find(err, "WAF Blocked Request", 1, true) ~= nil).toBe(true)
		end
	end)

	it("a 200 without a version number is a failure, not a version", function()
		for _, body in { "{}", "not json", '{"versionNumber":"7"}', '{"versionNumber":null}', "" } do
			local cfg = fake({ respond(200, body) })
			local err = message(function()
				OpenCloud.publish(cfg, "x")
			end)
			t.expect(string.find(err, "versionNumber", 1, true) ~= nil).toBe(true)
		end
	end)

	it("the API key is never in an error message", function()
		for _, code in { 400, 403, 409, 500 } do
			local cfg = fake({ respond(code, "body") })
			local err = message(function()
				OpenCloud.publish(cfg, "x")
			end)
			t.expect((string.find(err, KEY, 1, true))).toBe(nil)
		end
		local cfg = fake({ respond(200, "{}") })
		local err = message(function()
			OpenCloud.publish(cfg, "x")
		end)
		t.expect((string.find(err, KEY, 1, true))).toBe(nil)
	end)

	it(
		"the request body for the JSON endpoints is real JSON (sanity for the serde the library uses)",
		function()
			local decoded = serde.decode("json" :: "json", '{"versionNumber":3}') :: any
			t.expect(decoded.versionNumber).toBe(3)
		end
	)
end)
