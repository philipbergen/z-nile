--!strict
-- c0030 AC1: OpenCloud.execute runs a Luau script in a server of a published version through the Luau
-- Execution API (the request shapes were proven from CI in prep), waits for it, and reports the result.
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

return t.spec("c0030 OpenCloud.execute", function(it)
	it("creates a task on the published version with the script as JSON, then polls it", function()
		local source = "local a = \"q\"\nreturn 'PASS' -- \\ and unicode \u{2713}"
		local cfg, calls = fake({ created(), task("COMPLETE", { output = { results = { "PASS" } } }) })
		local run = OpenCloud.execute(cfg, 5, source)
		t.expect(calls[1].url)
			.toBe("https://example.test/cloud/v2/universes/111/places/222/versions/5/luau-execution-session-tasks")
		t.expect(calls[1].method).toBe("POST")
		t.expect(calls[1].headers["x-api-key"]).toBe(KEY)
		t.expect(calls[1].headers["Content-Type"]).toBe("application/json")
		local sent = serde.decode("json" :: "json", calls[1].body :: string) :: any
		t.expect(sent.script).toBe(source) -- the script survives JSON intact
		t.expect(calls[2].url).toBe(`https://example.test/cloud/v2/{PATH}`)
		t.expect(calls[2].method).toBe("GET")
		t.expect(calls[2].headers["x-api-key"]).toBe(KEY)
		t.expect(run.ok).toBe(true)
		t.expect(run.state).toBe("COMPLETE")
		t.expect(run.results).toEqual({ "PASS" })
	end)

	it("waits while the task is queued or processing, pausing between polls", function()
		local cfg, calls, naps = fake({
			created(),
			task("QUEUED"),
			task("PROCESSING"),
			task("COMPLETE", { output = { results = { "PASS" } } }),
		})
		local run = OpenCloud.execute(cfg, 5, "return 1", { pollSeconds = 2 })
		t.expect(#calls).toBe(4)
		t.expect(naps).toEqual({ 2, 2 })
		t.expect(run.ok).toBe(true)
	end)

	it("a completed task with no results is still ok, with an empty list", function()
		local cfg = fake({ created(), task("COMPLETE") })
		local run = OpenCloud.execute(cfg, 5, "return")
		t.expect(run.ok).toBe(true)
		t.expect(run.results).toEqual({})
	end)

	it("a failed task is reported with its message, not as success", function()
		local cfg = fake({
			created(),
			task("FAILED", { error = { code = "SCRIPT_ERROR", message = "boom at line 3" } }),
		})
		local run = OpenCloud.execute(cfg, 5, "error('boom')")
		t.expect(run.ok).toBe(false)
		t.expect(run.state).toBe("FAILED")
		t.expect(string.find(run.detail, "boom at line 3", 1, true) ~= nil).toBe(true)
	end)

	it("a cancelled task is not ok", function()
		local cfg = fake({ created(), task("CANCELLED") })
		local run = OpenCloud.execute(cfg, 5, "return 1")
		t.expect(run.ok).toBe(false)
		t.expect(run.state).toBe("CANCELLED")
	end)

	it("gives up after the timeout, not ok, saying what state it was in", function()
		local cfg, calls, naps = fake({ created(), task("PROCESSING") })
		local run = OpenCloud.execute(cfg, 5, "while true do end", { timeoutSeconds = 9, pollSeconds = 3 })
		t.expect(run.ok).toBe(false)
		t.expect(string.find(run.detail, "PROCESSING", 1, true) ~= nil).toBe(true)
		t.expect(#naps).toBe(3) -- 3 + 3 + 3 = the timeout
		t.expect(#calls).toBe(5) -- the create, then a poll at 0, 3, 6 and 9 seconds
	end)

	it("an HTTP failure creating or polling is an error with the status, never a result", function()
		local cfg1 = fake({ respond(403, "nope") })
		local ok1, err1 = pcall(OpenCloud.execute, cfg1, 5, "return 1")
		t.expect(ok1).toBe(false)
		t.expect(string.find(tostring(err1), "403", 1, true) ~= nil).toBe(true)
		local cfg2 = fake({ created(), respond(500, "down") })
		local ok2, err2 = pcall(OpenCloud.execute, cfg2, 5, "return 1")
		t.expect(ok2).toBe(false)
		t.expect(string.find(tostring(err2), "500", 1, true) ~= nil).toBe(true)
	end)

	it("a created task without a path is an error", function()
		local cfg = fake({ respond(200, "{}") })
		t.expect(function()
			OpenCloud.execute(cfg, 5, "return 1")
		end).toThrow("path")
	end)

	it("the API key never appears in an error", function()
		for _, responses in
			{ { respond(403, "x") }, { created(), respond(500, "y") }, { respond(200, "{}") } }
		do
			local cfg = fake(responses)
			local ok, err = pcall(OpenCloud.execute, cfg, 5, "return 1")
			t.expect(ok).toBe(false)
			t.expect((string.find(tostring(err), KEY, 1, true))).toBe(nil)
		end
	end)
end)
