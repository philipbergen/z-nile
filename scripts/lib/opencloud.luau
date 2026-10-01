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

return OpenCloud
