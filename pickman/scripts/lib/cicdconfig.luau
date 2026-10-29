--!strict
-- The local CICD file (c0172): which places a merge publishes, and the environment those commands
-- receive. Pure. The key is never copied into an error.
local serde = require("@lune/serde")

export type Config = {
	apiKey: string,
	universeId: string,
	cicd: string, -- lobby build, ROBLOX_BETA_PLACE_ID
	cicdGame: string, -- game build, ROBLOX_BETA_GAME_PLACE_ID
}

local CicdConfig = {}

local MAX_ID = 2 ^ 53 - 1

local function digits(value: any, name: string): (string?, string?)
	if type(value) ~= "string" or string.match(value, "^[1-9]%d*$") == nil then
		return nil, `cicd: {name} must be digits`
	end
	local n = tonumber(value)
	if n == nil or n > MAX_ID then
		return nil, `cicd: {name} must be digits`
	end
	return value, nil
end

-- The file's text, or nil and an error that does not contain the key.
function CicdConfig.parse(text: string): (Config?, string?)
	local ok, decoded = pcall(serde.decode, "toml" :: "toml", text)
	if not ok or type(decoded) ~= "table" then
		return nil, "cicd: the config is not valid TOML"
	end
	local doc = decoded :: { [string]: any }
	for key in doc do
		if key ~= "api_key" and key ~= "universe_id" and key ~= "places" then
			return nil, `cicd: unknown key {key}`
		end
	end
	local places = doc.places
	if type(places) ~= "table" then
		return nil, "cicd: places must be a table"
	end
	for key in places :: { [string]: any } do
		if key ~= "cicd" and key ~= "cicd_game" then
			return nil, `cicd: unknown key places.{key}`
		end
	end
	local apiKey = doc.api_key
	if type(apiKey) ~= "string" or apiKey == "" then
		return nil, "cicd: api_key must be a non-empty string"
	end
	local universeId, universeErr = digits(doc.universe_id, "universe_id")
	if universeId == nil then
		return nil, universeErr
	end
	local placeTable = places :: { [string]: any }
	local cicd, cicdErr = digits(placeTable.cicd, "places.cicd")
	if cicd == nil then
		return nil, cicdErr
	end
	local cicdGame, gameErr = digits(placeTable.cicd_game, "places.cicd_game")
	if cicdGame == nil then
		return nil, gameErr
	end
	if cicd == cicdGame then
		return nil, "cicd: places.cicd and places.cicd_game must differ"
	end
	return {
		apiKey = apiKey,
		universeId = universeId :: string,
		cicd = cicd :: string,
		cicdGame = cicdGame :: string,
	},
		nil
end

-- The child environment for deploy-beta and runtime-test. Inherited ROBLOX_* values are cleared, then the
-- four settings come from the file. Anything else is left for the process spawn to inherit.
function CicdConfig.childEnv(parent: { [string]: string? }, config: Config): { [string]: string }
	local env: { [string]: string } = {}
	for key, value in parent do
		if value ~= nil and string.sub(key, 1, 7) == "ROBLOX_" then
			env[key] = ""
		end
	end
	env.ROBLOX_API_KEY = config.apiKey
	env.ROBLOX_BETA_UNIVERSE_ID = config.universeId
	env.ROBLOX_BETA_PLACE_ID = config.cicd
	env.ROBLOX_BETA_GAME_PLACE_ID = config.cicdGame
	-- an inherited Actions output file must not be written by the local publish
	env.GITHUB_OUTPUT = ""
	return env
end

-- The place id at the end of a universe resource's rootPlace, or nil and an error.
function CicdConfig.rootPlaceId(body: string): (string?, string?)
	local ok, decoded = pcall(serde.decode, "json" :: "json", body)
	if not ok or type(decoded) ~= "table" then
		return nil, "cicd: the universe response is not JSON"
	end
	local root = (decoded :: any).rootPlace
	if type(root) ~= "string" then
		return nil, "cicd: the universe response has no rootPlace"
	end
	local id = string.match(root, "places/([1-9]%d*)$")
	if id == nil then
		return nil, "cicd: the universe response has no root place id"
	end
	return id, nil
end

-- Open Cloud's base URL. A loopback override is the test seam; anything else is refused so the key
-- cannot be sent to another host.
function CicdConfig.base(env: { [string]: string? }): (string?, string?)
	local override = env.OPENCLOUD_BASE
	if override == nil or override == "" then
		return "https://apis.roblox.com", nil
	end
	if
		string.match(override, "^http://127%.0%.0%.1:%d+$") == nil
		and string.match(override, "^http://localhost:%d+$") == nil
	then
		return nil, "cicd: OPENCLOUD_BASE may only be a loopback address"
	end
	return override, nil
end

return CicdConfig
