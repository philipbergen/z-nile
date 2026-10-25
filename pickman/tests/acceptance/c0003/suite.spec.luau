--!strict
-- c0030 AC2: OpenCloud.runSuite runs a list of runtime scripts and says what the command prints and returns:
-- a script passes only by returning "PASS", every other outcome is a named failure, and one failure
-- doesn't stop the rest.
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

-- the suite: what the command prints and returns for a list of scripts
local function suiteFake(perScript: { { OpenCloud.Response } }): OpenCloud.Config
	-- each script makes a create call and then polls; `perScript[i]` are its two responses
	local queue: { OpenCloud.Response } = {}
	for _, pair in perScript do
		for _, r in pair do
			table.insert(queue, r)
		end
	end
	local i = 0
	return {
		apiKey = KEY,
		universeId = "111",
		placeId = "222",
		base = "https://example.test",
		request = function(_: OpenCloud.Request): OpenCloud.Response
			i += 1
			return queue[i]
		end,
		sleep = function(_: number) end,
	}
end

local function done(value: any): { OpenCloud.Response }
	return { created(), task("COMPLETE", { output = { results = { value } } }) }
end

return t.spec("c0030 OpenCloud.runSuite", function(it)
	it("passes a script only when it returns PASS", function()
		local cfg = suiteFake({ done("PASS") })
		local suite = OpenCloud.runSuite(cfg, 5, { { name = "a.luau", source = "return 'PASS'" } })
		t.expect(suite.passed).toBe(1)
		t.expect(suite.failed).toBe(0)
		t.expect(suite.lines).toEqual({ "PASS a.luau" })
	end)

	it(
		"anything else is a failure that names the script: other values, no value, errors, cancellations",
		function()
			local cases: { { responses: { OpenCloud.Response }, expect: string } } = {
				{ responses = done("nope"), expect = "returned nope" },
				{ responses = done(false), expect = "returned false" },
				{ responses = { created(), task("COMPLETE") }, expect = "returned nil" },
				{
					responses = { created(), task("FAILED", { error = { message = "boom" } }) },
					expect = "boom",
				},
				{ responses = { created(), task("CANCELLED") }, expect = "CANCELLED" },
				{ responses = { respond(403, "denied") }, expect = "403" },
			}
			for _, c in cases do
				local cfg = suiteFake({ c.responses })
				local suite = OpenCloud.runSuite(cfg, 5, { { name = "x.luau", source = "return 1" } })
				t.expect(suite.passed).toBe(0)
				t.expect(suite.failed).toBe(1)
				t.expect(string.find(suite.lines[1], "FAIL x.luau", 1, true) ~= nil).toBe(true)
				t.expect(string.find(suite.lines[1], c.expect, 1, true) ~= nil).toBe(true)
			end
		end
	)

	it("one failure does not stop the others, and the counts add up", function()
		local cfg = suiteFake({ done("PASS"), done("bad"), done("PASS") })
		local suite = OpenCloud.runSuite(cfg, 5, {
			{ name = "a", source = "" },
			{ name = "b", source = "" },
			{ name = "c", source = "" },
		})
		t.expect(suite.passed).toBe(2)
		t.expect(suite.failed).toBe(1)
		t.expect(suite.lines).toEqual({ "PASS a", "FAIL b: returned bad", "PASS c" })
	end)

	it("an empty list passes nothing and fails nothing", function()
		local suite = OpenCloud.runSuite(suiteFake({}), 5, {})
		t.expect(suite.passed).toBe(0)
		t.expect(suite.failed).toBe(0)
	end)
end)
