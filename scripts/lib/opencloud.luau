--!strict
-- Roblox Open Cloud, the calls pickman needs: publish a built place to an experience (and, from c0030,
-- run a Luau script in a server of a published version). The HTTP call and the sleep are injected so the
-- logic is tested without a network. The API key only ever appears in the `x-api-key` header, never in a
-- message or an error.
local net = require("@lune/net")
local serde = require("@lune/serde")
local task = require("@lune/task")

export type Request = { url: string, method: string, headers: { [string]: string }, body: string? }
export type Response = { statusCode: number, body: string }
export type Http = (Request) -> Response

export type Config = {
	apiKey: string,
	universeId: string,
	placeId: string,
	base: string?, -- default https://apis.roblox.com
	request: Http?,
	sleep: ((seconds: number) -> ())?,
	retrySeconds: number?, -- wait between "Roblox busy" (HTTP 409) retries; default 60
}

local OpenCloud = {}
OpenCloud.BASE = "https://apis.roblox.com"
OpenCloud.MAX_ATTEMPTS = 5

local function defaultRequest(r: Request): Response
	local res = net.request({ url = r.url, method = r.method :: any, headers = r.headers, body = r.body })
	return { statusCode = res.statusCode, body = res.body }
end

local function http(cfg: Config): Http
	return cfg.request or defaultRequest
end

local function nap(cfg: Config, seconds: number)
	if cfg.sleep then
		cfg.sleep(seconds)
	else
		task.wait(seconds)
	end
end

local function base(cfg: Config): string
	return cfg.base or OpenCloud.BASE
end

local function headers(cfg: Config, contentType: string?): { [string]: string }
	local h: { [string]: string } = { ["x-api-key"] = cfg.apiKey }
	if contentType then
		h["Content-Type"] = contentType
	end
	return h
end

-- A configuration from environment variables, or nil when publishing isn't configured (a green skip).
-- Ids must be plain digits: they go into a URL.
function OpenCloud.configFromEnv(env: { [string]: string? }): Config?
	local key, universe, place = env.ROBLOX_API_KEY, env.ROBLOX_BETA_UNIVERSE_ID, env.ROBLOX_BETA_PLACE_ID
	if key == nil or key == "" or universe == nil or universe == "" or place == nil or place == "" then
		return nil
	end
	if not string.match(universe, "^%d+$") then
		error("opencloud: ROBLOX_BETA_UNIVERSE_ID must be digits", 0)
	end
	if not string.match(place, "^%d+$") then
		error("opencloud: ROBLOX_BETA_PLACE_ID must be digits", 0)
	end
	local cfg: Config = { apiKey = key, universeId = universe, placeId = place }
	-- a test seam: a local fake of Roblox. Anything but loopback is refused, so a stray variable can't
	-- send the API key to another host.
	local override = env.OPENCLOUD_BASE
	if override ~= nil and override ~= "" then
		if
			not (
				string.match(override, "^http://127%.0%.0%.1:%d+$")
				or string.match(override, "^http://localhost:%d+$")
			)
		then
			error("opencloud: OPENCLOUD_BASE may only be a loopback address", 0)
		end
		cfg.base = override
	end
	return cfg
end

-- Publishes a built place file to the experience. Returns the new version number. Roblox answers 409
-- while it is busy: that is retried up to MAX_ATTEMPTS times; any other failure is final.
function OpenCloud.publish(cfg: Config, place: string): number
	local url =
		`{base(cfg)}/universes/v1/{cfg.universeId}/places/{cfg.placeId}/versions?versionType=Published`
	for attempt = 1, OpenCloud.MAX_ATTEMPTS do
		local res = http(cfg)({
			url = url,
			method = "POST",
			headers = headers(cfg, "application/octet-stream"),
			body = place,
		})
		if res.statusCode == 200 then
			local ok, decoded = pcall(serde.decode, "json" :: "json", res.body)
			local version = ok and type(decoded) == "table" and (decoded :: any).versionNumber or nil
			if type(version) ~= "number" then
				error(`opencloud: publish answered 200 without a versionNumber: {res.body}`, 0)
			end
			return version
		end
		if res.statusCode == 409 and attempt < OpenCloud.MAX_ATTEMPTS then
			nap(cfg, cfg.retrySeconds or 60)
		else
			error(`opencloud: publish failed with HTTP {res.statusCode}: {res.body}`, 0)
		end
	end
	error("opencloud: publish gave up", 0) -- unreachable: the loop returns or errors
end

export type Run = { ok: boolean, state: string, results: { any }, detail: string }

-- Runs a Luau script in a server of a published version and waits for it. `ok` is true when the task
-- completed; `results` are the script's return values. HTTP failures creating or polling raise.
function OpenCloud.execute(
	cfg: Config,
	version: number,
	source: string,
	opts: { timeoutSeconds: number?, pollSeconds: number? }?
): Run
	local timeout = opts and opts.timeoutSeconds or 120
	local poll = opts and opts.pollSeconds or 3
	local create = http(cfg)({
		url = `{base(cfg)}/cloud/v2/universes/{cfg.universeId}/places/{cfg.placeId}/versions/{version}/luau-execution-session-tasks`,
		method = "POST",
		headers = headers(cfg, "application/json"),
		body = serde.encode("json" :: "json", { script = source }),
	})
	if create.statusCode ~= 200 then
		error(`opencloud: creating the task failed with HTTP {create.statusCode}: {create.body}`, 0)
	end
	local created = serde.decode("json" :: "json", create.body) :: any
	local path = created.path
	if type(path) ~= "string" then
		error(`opencloud: the task has no path: {create.body}`, 0)
	end
	local waited = 0
	while true do
		local res = http(cfg)({
			url = `{base(cfg)}/cloud/v2/{path}`,
			method = "GET",
			headers = headers(cfg),
			body = nil,
		})
		if res.statusCode ~= 200 then
			error(`opencloud: polling the task failed with HTTP {res.statusCode}: {res.body}`, 0)
		end
		local polled = serde.decode("json" :: "json", res.body) :: any
		local state = tostring(polled.state)
		if state == "COMPLETE" then
			local output = polled.output
			local results = if type(output) == "table" and type(output.results) == "table"
				then output.results
				else {}
			return { ok = true, state = state, results = results, detail = "" }
		elseif state == "FAILED" or state == "CANCELLED" then
			local err = polled.error
			local detail = if type(err) == "table" then tostring(err.message) else res.body
			return { ok = false, state = state, results = {}, detail = detail }
		end
		if waited >= timeout then
			return { ok = false, state = state, results = {}, detail = `still {state} after {timeout} s` }
		end
		nap(cfg, poll)
		waited += poll
	end
end

export type Script = { name: string, source: string }
export type Suite = { lines: { string }, passed: number, failed: number }

-- Runs each script in a server of the version. A script passes only by returning "PASS"; a task that
-- failed, was cancelled, timed out, returned anything else, or couldn't be run at all is a failure, and
-- the rest still run.
function OpenCloud.runSuite(
	cfg: Config,
	version: number,
	scripts: { Script },
	opts: { timeoutSeconds: number?, pollSeconds: number? }?
): Suite
	local suite: Suite = { lines = {}, passed = 0, failed = 0 }
	for _, s in scripts do
		local ok, run = pcall(OpenCloud.execute, cfg, version, s.source, opts)
		local problem: string? = nil
		if not ok then
			problem = tostring(run)
		elseif not (run :: Run).ok then
			problem = `{(run :: Run).state} {(run :: Run).detail}`
		elseif (run :: Run).results[1] ~= "PASS" then
			problem = `returned {tostring((run :: Run).results[1])}`
		end
		if problem then
			suite.failed += 1
			table.insert(suite.lines, `FAIL {s.name}: {problem}`)
		else
			suite.passed += 1
			table.insert(suite.lines, `PASS {s.name}`)
		end
	end
	return suite
end

return OpenCloud
