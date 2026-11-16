--!strict
-- f0209 AC1: the portal is the experience's start place. In the checked-in manifest (portal/experience.json, read only
-- through scripts/lib/experience) the one place that reads ROBLOX_BETA_PLACE_ID publishes the portal's own project,
-- with its runtime folder and no extra attribute, and no place publishes pickman's lobby. The plan for the variables
-- GitHub has (the start place and Pickman's game) sends Pickman's game to its id, told the start place's id, then the
-- portal to the start place, told Pickman's id. Pure: no Rojo, no network. Runs from portal/.
local Beta = require("@scripts/lib/beta")
local Experience = require("@scripts/lib/experience")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local LOBBY = "../pickman/lobby.project.json"
local START = "222"
local GAME = "333"

local function manifest(): Experience.Manifest
	local m, err = Experience.parse(fs.readFile("experience.json"))
	assert(m, `experience.json is refused: {err}`)
	return m :: Experience.Manifest
end

local function startPlace(m: Experience.Manifest): Experience.Place
	local found: Experience.Place? = nil
	for _, p in m.places do
		if table.find(p.env, "ROBLOX_BETA_PLACE_ID") then
			assert(found == nil, "two places read ROBLOX_BETA_PLACE_ID")
			found = p
		end
	end
	assert(found, "no place reads ROBLOX_BETA_PLACE_ID")
	return found :: Experience.Place
end

local function env(extra: { [string]: string }): { [string]: string? }
	local e: { [string]: string? } = {
		ROBLOX_API_KEY = "KEY",
		ROBLOX_BETA_UNIVERSE_ID = "111",
		ROBLOX_BETA_PLACE_ID = START,
	}
	for k, v in extra do
		e[k] = v
	end
	return e
end

-- plain occurrences of a needle with no pattern characters
local function count(text: string, needle: string): number
	assert(not string.find(needle, "[%^%$%(%)%%%.%[%]%*%+%-%?]"), "count takes a plain needle")
	return select(2, string.gsub(text, needle, ""))
end

return t.spec("f0209 the portal is the start place", function(it)
	it("the start place is the Portal place, and it publishes the portal's own project", function()
		local m = manifest()
		local start = startPlace(m)
		t.expect(start.name).toBe("Portal")
		t.expect(start.env).toEqual({ "ROBLOX_BETA_PLACE_ID" })
		local build = m.builds[start.build]
		t.expect(build ~= nil).toBe(true)
		t.expect(build.project).toBe("default.project.json")
		t.expect(fs.isFile(build.project)).toBe(true)
	end)

	it("the portal's build runs the portal's runtime folder, which exists, and adds no attribute", function()
		local m = manifest()
		local build = m.builds[startPlace(m).build]
		t.expect(build.runtime).toBe("tests/runtime")
		t.expect(fs.isDir("tests/runtime")).toBe(true)
		t.expect(build.attributes).toEqual({})
	end)

	it("no place publishes pickman's lobby", function()
		local m = manifest()
		for _, p in m.places do
			t.expect(`{p.name}: {m.builds[p.build].project == LOBBY}`).toBe(`{p.name}: false`)
		end
	end)

	it("the switch is the start place's build: its output keeps its name, lobby_version", function()
		local m = manifest()
		t.expect(startPlace(m).output).toBe("lobby_version")
		local text = fs.readFile("experience.json")
		t.expect(count(text, '"build": "portal"')).toBe(1)
		t.expect(count(text, '"build": "lobby"')).toBe(0)
	end)

	for _, var in { "ROBLOX_BETA_GAME_PLACE_ID", "ROBLOX_BETA_PICKMAN_PLACE_ID" } do
		it(
			`with {var}: Pickman's game first, told the start place's id, then the portal at the start place`,
			function()
				local plan = Beta.plan(env({ [var] = GAME }), manifest()) :: Beta.Plan
				t.expect(#plan.targets).toBe(2)
				local game, portal = plan.targets[1], plan.targets[2]
				t.expect(game.name).toBe("Pickman")
				t.expect(game.placeId).toBe(GAME)
				t.expect(game.output).toBe("version")
				-- the game's way back is the start place's id, which is now the portal's
				t.expect(game.attributes.PortalPlaceId).toBe(tonumber(START))
				if game.attributes.LobbyPlaceId ~= nil then -- pickman reads it until f0187
					t.expect(game.attributes.LobbyPlaceId).toBe(tonumber(START))
				end
				t.expect(portal.name).toBe("Portal")
				t.expect(portal.placeId).toBe(START)
				t.expect(portal.variable).toBe("ROBLOX_BETA_PLACE_ID")
				t.expect(portal.build).toBe(startPlace(manifest()).build)
				t.expect(portal.project).toBe("default.project.json")
				t.expect(portal.runtime).toBe("tests/runtime")
				t.expect(portal.output).toBe("lobby_version")
				t.expect(portal.attributes.PickmanPlaceId).toBe(tonumber(GAME))
				t.expect(portal.attributes.PortalPlaceId).toBe(tonumber(START))
				t.expect(portal.attributes.PaidPlay).toBe("test")
				-- nothing of pickman's lobby: no GamePlaceId, and no way back of its own
				t.expect(portal.attributes.GamePlaceId).toBe(nil)
				t.expect(portal.attributes.LobbyPlaceId).toBe(nil)
			end
		)
	end

	it("with every place set, every game is told the portal's id as PortalPlaceId, its way back", function()
		local plan = Beta.plan(
			env({
				ROBLOX_BETA_PICKMAN_PLACE_ID = GAME,
				ROBLOX_BETA_SNAKE_PLACE_ID = "444",
				ROBLOX_BETA_INVADERS_PLACE_ID = "555",
				ROBLOX_BETA_ASTEROIDS_PLACE_ID = "666",
			}),
			manifest()
		) :: Beta.Plan
		t.expect(#plan.targets).toBe(5)
		for _, target in plan.targets do
			t.expect(`{target.name}: {target.attributes.PortalPlaceId}`).toBe(`{target.name}: {START}`)
		end
		local last = plan.targets[#plan.targets]
		t.expect(`{last.name} {last.placeId} {last.project}`).toBe(`Portal {START} default.project.json`)
	end)

	it("with only the start place set, the portal alone is published and every game's id is 0", function()
		local plan = Beta.plan(env({}), manifest()) :: Beta.Plan
		t.expect(#plan.targets).toBe(1)
		local portal = plan.targets[1]
		t.expect(portal.name).toBe("Portal")
		t.expect(portal.project).toBe("default.project.json")
		for _, attribute in { "PickmanPlaceId", "SnakePlaceId", "InvadersPlaceId", "AsteroidsPlaceId" } do
			t.expect(`{attribute}: {portal.attributes[attribute]}`).toBe(`{attribute}: 0`)
		end
	end)
end)
