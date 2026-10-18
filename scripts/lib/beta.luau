--!strict
-- What the Beta publish does, as pure data (c0064): which places get which build, and the copy of a Rojo
-- project with place ids written into it. scripts/deploy-beta and scripts/runtime-test act on the plan; this
-- file decides it and is tested without Rojo or a network.
local OpenCloud = require("@scripts/lib/opencloud")
local serde = require("@lune/serde")

export type Place = "game" | "lobby"
export type Target = {
	place: Place,
	project: string, -- the Rojo project file, relative to the checkout
	placeId: string, -- digits: where it is published
	attributes: { [string]: number }, -- written on ServerScriptService in the copy that is built
	output: string, -- the name of the version in the deploy's output
	runtime: string, -- the directory of its runtime scripts
}
export type Plan = { split: boolean, targets: { Target }, notice: string? }

local Beta = {}
Beta.GAME_PLACE_VAR = "ROBLOX_BETA_GAME_PLACE_ID"
Beta.MAX_PLACE_ID = 2 ^ 53 - 1

local function placeId(value: string, name: string): number
	local n = tonumber(value)
	if not string.match(value, "^[1-9]%d*$") or n == nil or n > Beta.MAX_PLACE_ID then
		error(`beta: {name} must be a place id: digits, 1 to 2^53-1`, 0)
	end
	return n
end

-- The publish plan from the environment, or nil when publishing is not configured (OpenCloud.configFromEnv).
-- Without ROBLOX_BETA_GAME_PLACE_ID the game place goes to ROBLOX_BETA_PLACE_ID as before c0064 and the lobby
-- is not published (`notice` says so); with it, the game place goes there, told the lobby's id (LobbyPlaceId,
-- f0065), and the lobby, told the game place's id (GamePlaceId), to ROBLOX_BETA_PLACE_ID, the start place. Raises, naming the variable and
-- never the key, on an id that is not a place id or a game place that is the start place.
function Beta.plan(env: { [string]: string? }): Plan?
	local cfg = OpenCloud.configFromEnv(env)
	if cfg == nil then
		return nil
	end
	local start = (cfg :: OpenCloud.Config).placeId
	local game = env[Beta.GAME_PLACE_VAR]
	local gameTarget: Target = {
		place = "game",
		project = "default.project.json",
		placeId = start,
		attributes = {},
		output = "version",
		runtime = "tests/runtime",
	}
	if game == nil or game == "" then
		return {
			split = false,
			targets = { gameTarget },
			notice = `the lobby is not published: set {Beta.GAME_PLACE_VAR} to the game place's id`,
		}
	end
	local id = placeId(game :: string, Beta.GAME_PLACE_VAR)
	if id == placeId(start, "ROBLOX_BETA_PLACE_ID") then
		error(
			`beta: {Beta.GAME_PLACE_VAR} must differ from ROBLOX_BETA_PLACE_ID (the lobby, the start place)`,
			0
		)
	end
	gameTarget.placeId = game :: string
	-- the way back (f0065): the game place is told the lobby's id, as the lobby is told the game's
	gameTarget.attributes = { LobbyPlaceId = placeId(start, "ROBLOX_BETA_PLACE_ID") }
	return {
		split = true,
		targets = {
			gameTarget,
			{
				place = "lobby",
				project = "lobby.project.json",
				placeId = start,
				attributes = { GamePlaceId = id },
				output = "lobby_version",
				runtime = "tests/runtime/lobby",
			},
		},
		notice = nil,
	}
end

-- The target for one place, or nil when the plan does not publish it.
function Beta.target(plan: Plan, place: Place): Target?
	for _, target in plan.targets do
		if target.place == place then
			return target
		end
	end
	return nil
end

local function absolute(dir: string, path: string): string
	if string.sub(path, 1, 1) == "/" then
		return path
	end
	return `{dir}/{path}`
end

local function rewrite(node: any, dir: string)
	for key, value in node do
		if key == "$path" and type(value) == "string" then
			node[key] = absolute(dir, value)
		elseif key == "$path" and type(value) == "table" and type(value.optional) == "string" then
			value.optional = absolute(dir, value.optional)
		elseif type(value) == "table" and string.sub(tostring(key), 1, 1) ~= "$" then
			rewrite(value, dir)
		end
	end
end

-- A copy of a Rojo project (its JSON text) that builds the same place from anywhere: every `$path` made
-- absolute against `dir` (the project file's directory, absolute), and `attributes` set on ServerScriptService
-- beside the ones it has. The text given is not changed.
function Beta.project(text: string, dir: string, attributes: { [string]: number }): string
	local project: any = serde.decode("json" :: "json", text)
	if type(project) ~= "table" or type(project.tree) ~= "table" then
		error("beta: not a Rojo project (no tree)", 0)
	end
	rewrite(project.tree, dir)
	if next(attributes) ~= nil then
		local sss = project.tree.ServerScriptService
		if sss == nil then
			sss = {}
			project.tree.ServerScriptService = sss
		end
		local attrs = sss["$attributes"]
		if attrs == nil then
			attrs = {}
			sss["$attributes"] = attrs
		end
		for name, value in attributes do
			attrs[name] = value
		end
	end
	return serde.encode("json" :: "json", project, true)
end

return Beta
