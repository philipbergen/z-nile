--!strict
-- c0210 AC2: the Beta publish's plan over a manifest and the environment, pure (scripts/lib/beta). A fixture manifest
-- lists the five places with their own builds, so the rules here hold whatever build the start place publishes.
local Beta = require("@scripts/lib/beta")
local Experience = require("@scripts/lib/experience")
local Places = require("@arcade/Places")
local t = require("@tests/lib/t")

local KEY = "KEY-NOT-IN-OUTPUT"

local MANIFEST = [[
{
  "places": [
    { "name": "Pickman", "env": ["ROBLOX_BETA_PICKMAN_PLACE_ID", "ROBLOX_BETA_GAME_PLACE_ID"], "build": "pickman", "output": "version" },
    { "name": "Snake", "env": ["ROBLOX_BETA_SNAKE_PLACE_ID"], "build": "snake", "output": "snake_version" },
    { "name": "Invaders", "env": ["ROBLOX_BETA_INVADERS_PLACE_ID"], "build": "invaders", "output": "invaders_version" },
    { "name": "Portal", "env": ["ROBLOX_BETA_PLACE_ID"], "build": "start", "output": "lobby_version" },
    { "name": "Asteroids", "env": ["ROBLOX_BETA_ASTEROIDS_PLACE_ID"], "build": "asteroids", "output": "asteroids_version" }
  ],
  "builds": {
    "pickman": { "project": "p/default.project.json", "runtime": "p/tests/runtime", "attributes": { "LobbyPlaceId": "Portal" } },
    "start": { "project": "s/default.project.json", "attributes": { "GamePlaceId": "Pickman" } },
    "snake": { "project": "sn/default.project.json" },
    "invaders": { "project": "i/default.project.json" },
    "asteroids": { "project": "a/default.project.json" }
  }
}
]]

local function manifest(): Experience.Manifest
	local m, err = Experience.parse(MANIFEST)
	assert(m, err)
	return m :: Experience.Manifest
end

local function env(extra: { [string]: string }): { [string]: string }
	local e: { [string]: string } =
		{ ROBLOX_API_KEY = KEY, ROBLOX_BETA_UNIVERSE_ID = "111", ROBLOX_BETA_PLACE_ID = "222" }
	for k, v in extra do
		e[k] = v
	end
	return e
end

local function plan(extra: { [string]: string }): Beta.Plan
	return Beta.plan(env(extra), manifest()) :: Beta.Plan
end

local function names(p: Beta.Plan): { string }
	local out: { string } = {}
	for _, target in p.targets do
		table.insert(out, `{target.name}@{target.placeId}`)
	end
	return out
end

local function refusal(extra: { [string]: string }): string
	local ok, err = pcall(Beta.plan, env(extra), manifest())
	t.expect(ok).toBe(false)
	local text = tostring(err)
	t.expect(string.find(text, KEY, 1, true) == nil).toBe(true)
	return text
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0210 the Beta publish's plan", function(it)
	it("not configured (no key, universe or start place id): no plan", function()
		for _, missing in { "ROBLOX_API_KEY", "ROBLOX_BETA_UNIVERSE_ID", "ROBLOX_BETA_PLACE_ID" } do
			local e = env({ ROBLOX_BETA_PICKMAN_PLACE_ID = "333" })
			e[missing] = ""
			t.expect(Beta.plan(e, manifest())).toBe(nil)
		end
	end)

	it(
		"only the start place set: it alone is published, every other place skipped by name and variable",
		function()
			local p = plan({})
			t.expect(names(p)).toEqual({ "Portal@222" })
			t.expect(p.skipped).toEqual({
				"the Pickman place is not published: set ROBLOX_BETA_PICKMAN_PLACE_ID",
				"the Snake place is not published: set ROBLOX_BETA_SNAKE_PLACE_ID",
				"the Invaders place is not published: set ROBLOX_BETA_INVADERS_PLACE_ID",
				"the Asteroids place is not published: set ROBLOX_BETA_ASTEROIDS_PLACE_ID",
			})
		end
	)

	it("an empty variable is unset", function()
		t.expect(names(plan({ ROBLOX_BETA_SNAKE_PLACE_ID = "", ROBLOX_BETA_PICKMAN_PLACE_ID = "" })))
			.toEqual({
				"Portal@222",
			})
	end)

	it(
		"a place is published from the moment its variable is set; the games in the manifest's order, the start place last",
		function()
			local p = plan({
				ROBLOX_BETA_ASTEROIDS_PLACE_ID = "666",
				ROBLOX_BETA_SNAKE_PLACE_ID = "444",
				ROBLOX_BETA_PICKMAN_PLACE_ID = "333",
			})
			t.expect(names(p)).toEqual({ "Pickman@333", "Snake@444", "Asteroids@666", "Portal@222" })
			t.expect(p.skipped)
				.toEqual({ "the Invaders place is not published: set ROBLOX_BETA_INVADERS_PLACE_ID" })
		end
	)

	it("each target carries its build, project, runtime, output and the variable its id came from", function()
		local p = plan({ ROBLOX_BETA_PICKMAN_PLACE_ID = "333", ROBLOX_BETA_SNAKE_PLACE_ID = "444" })
		local pickman = Beta.target(p, "Pickman") :: Beta.Target
		t.expect(pickman.build).toBe("pickman")
		t.expect(pickman.project).toBe("p/default.project.json")
		t.expect(pickman.runtime).toBe("p/tests/runtime")
		t.expect(pickman.output).toBe("version")
		t.expect(pickman.variable).toBe("ROBLOX_BETA_PICKMAN_PLACE_ID")
		local snake = Beta.target(p, "Snake") :: Beta.Target
		t.expect(snake.project).toBe("sn/default.project.json")
		t.expect(snake.runtime).toBe(nil)
		t.expect(snake.output).toBe("snake_version")
		local start = Beta.target(p, "Portal") :: Beta.Target
		t.expect(start.project).toBe("s/default.project.json")
		t.expect(start.variable).toBe("ROBLOX_BETA_PLACE_ID")
		t.expect(start.output).toBe("lobby_version")
		t.expect(Beta.target(p, "Invaders")).toBe(nil)
	end)

	it("every published place is told every place's id, 0 for a place not published", function()
		local p = plan({ ROBLOX_BETA_PICKMAN_PLACE_ID = "333", ROBLOX_BETA_INVADERS_PLACE_ID = "555" })
		for _, target in p.targets do
			t.expect(target.attributes.PortalPlaceId).toBe(222)
			t.expect(target.attributes.PickmanPlaceId).toBe(333)
			t.expect(target.attributes.SnakePlaceId).toBe(0)
			t.expect(target.attributes.InvadersPlaceId).toBe(555)
			t.expect(target.attributes.AsteroidsPlaceId).toBe(0)
		end
		-- the names are arcade's (f0199): every Places.attribute of Places.NAMES, numbers
		for _, target in p.targets do
			for _, name in Places.NAMES do
				t.expect(type(target.attributes[Places.attribute(name :: Places.Name)])).toBe("number")
			end
		end
	end)

	it("an id at the top of the range is told exactly", function()
		local p = plan({ ROBLOX_BETA_PICKMAN_PLACE_ID = "9007199254740991" })
		t.expect((Beta.target(p, "Portal") :: Beta.Target).attributes.PickmanPlaceId).toBe(9007199254740991)
	end)

	it("a build's extra attributes name a place, told its id or 0", function()
		local p = plan({ ROBLOX_BETA_PICKMAN_PLACE_ID = "333" })
		local pickman = Beta.target(p, "Pickman") :: Beta.Target
		local start = Beta.target(p, "Portal") :: Beta.Target
		t.expect(pickman.attributes.LobbyPlaceId).toBe(222)
		t.expect(pickman.attributes.GamePlaceId).toBe(nil)
		t.expect(start.attributes.GamePlaceId).toBe(333)
		t.expect(start.attributes.LobbyPlaceId).toBe(nil)
		local alone = Beta.target(plan({}), "Portal") :: Beta.Target
		t.expect(alone.attributes.GamePlaceId).toBe(0)
	end)

	it(
		"every published place is in paid play's test mode with no product: PaidPlay test, each catalog id 0",
		function()
			local p = plan({ ROBLOX_BETA_PICKMAN_PLACE_ID = "333" })
			for _, target in p.targets do
				t.expect(target.attributes.PaidPlay).toBe("test")
				for _, attribute in
					{
						"PlayProductId",
						"ContinueProductId",
						"SnakePlayProductId",
						"SnakeReviveProductId",
						"InvadersPlayProductId",
						"InvadersReviveProductId",
						"AsteroidsPlayProductId",
						"AsteroidsReviveProductId",
					}
				do
					t.expect(target.attributes[attribute]).toBe(0)
				end
			end
		end
	)

	-- c0210 design review 001 F7: the attributes the plan writes are exactly those the reader keeps extras off
	it(
		"the attributes every place is told are exactly the reader's reserved names: every place id, PaidPlay, the catalog ids",
		function()
			local told: { string } = {}
			for name in Beta.attributes({}) do
				table.insert(told, name)
			end
			table.sort(told)
			local reserved = table.clone(Experience.reserved())
			table.sort(reserved)
			t.expect(told).toEqual(reserved)
			t.expect(#told).toBe(5 + 1 + 8)
		end
	)

	it("the old ROBLOX_BETA_GAME_PLACE_ID is still Pickman's place id", function()
		local p = plan({ ROBLOX_BETA_GAME_PLACE_ID = "333" })
		t.expect(names(p)).toEqual({ "Pickman@333", "Portal@222" })
		t.expect((Beta.target(p, "Pickman") :: Beta.Target).variable).toBe("ROBLOX_BETA_GAME_PLACE_ID")
		t.expect((Beta.target(p, "Portal") :: Beta.Target).attributes.PickmanPlaceId).toBe(333)
	end)

	it("Pickman's two variables set to the same id: published once, from the first", function()
		local p = plan({ ROBLOX_BETA_GAME_PLACE_ID = "333", ROBLOX_BETA_PICKMAN_PLACE_ID = "333" })
		t.expect(names(p)).toEqual({ "Pickman@333", "Portal@222" })
		t.expect((Beta.target(p, "Pickman") :: Beta.Target).variable).toBe("ROBLOX_BETA_PICKMAN_PLACE_ID")
	end)

	it("Pickman's two variables set to different ids: refused, naming both", function()
		local text = refusal({ ROBLOX_BETA_GAME_PLACE_ID = "333", ROBLOX_BETA_PICKMAN_PLACE_ID = "334" })
		t.expect(has(text, "ROBLOX_BETA_PICKMAN_PLACE_ID")).toBe(true)
		t.expect(has(text, "ROBLOX_BETA_GAME_PLACE_ID")).toBe(true)
	end)

	it("a value that is not a place id is refused, naming its variable and never the key", function()
		for _, bad in
			{
				"0",
				"007",
				"abc",
				" 7",
				"7 ",
				"-5",
				"1e3",
				"0x10",
				"1.5",
				"9007199254740992",
				"99999999999999999999",
			}
		do
			local text = refusal({ ROBLOX_BETA_SNAKE_PLACE_ID = bad })
			t.expect(has(text, "ROBLOX_BETA_SNAKE_PLACE_ID")).toBe(true)
		end
	end)

	it("a bad legacy value is refused too, even when the new variable is set", function()
		local text = refusal({ ROBLOX_BETA_PICKMAN_PLACE_ID = "333", ROBLOX_BETA_GAME_PLACE_ID = "x" })
		t.expect(has(text, "ROBLOX_BETA_GAME_PLACE_ID")).toBe(true)
	end)

	it("a start place id that is not a place id is refused", function()
		local text = refusal({ ROBLOX_BETA_PLACE_ID = "0" })
		t.expect(has(text, "ROBLOX_BETA_PLACE_ID")).toBe(true)
	end)

	it(
		"two places with one id are refused, naming both variables: no project goes to another place's id",
		function()
			local text =
				refusal({ ROBLOX_BETA_SNAKE_PLACE_ID = "444", ROBLOX_BETA_INVADERS_PLACE_ID = "444" })
			t.expect(has(text, "ROBLOX_BETA_SNAKE_PLACE_ID")).toBe(true)
			t.expect(has(text, "ROBLOX_BETA_INVADERS_PLACE_ID")).toBe(true)
			local start = refusal({ ROBLOX_BETA_GAME_PLACE_ID = "222" })
			t.expect(has(start, "ROBLOX_BETA_GAME_PLACE_ID")).toBe(true)
			t.expect(has(start, "ROBLOX_BETA_PLACE_ID")).toBe(true)
		end
	)

	it("a variable the manifest does not name publishes nothing", function()
		t.expect(names(plan({ ROBLOX_BETA_LOBBY_PLACE_ID = "777", ROBLOX_LIVE_PLACE_ID = "888" }))).toEqual({
			"Portal@222",
		})
	end)
end)
