--!strict
-- c0064 AC1: the publish plan, as pure data. Without the game place's variable Beta publishes the game to the
-- start place as before c0064; with it, the game goes to its own place and the lobby, which is told the game
-- place's id, to the start place. A bad id fails, naming the variable and never the key.
local Beta = require("@scripts/lib/beta")
local t = require("@tests/lib/t")

local BASE: { [string]: string? } = {
	ROBLOX_API_KEY = "KEY-NOT-IN-OUTPUT",
	ROBLOX_BETA_UNIVERSE_ID = "10768553777",
	ROBLOX_BETA_PLACE_ID = "82331952549326",
}

local function env(game: string?): { [string]: string? }
	local e: { [string]: string? } = table.clone(BASE)
	e.ROBLOX_BETA_GAME_PLACE_ID = game
	return e
end

local function plan(game: string?): Beta.Plan
	local p = Beta.plan(env(game))
	assert(p, "configured, so a plan")
	return p
end

-- the game target; in split mode it is told the lobby's id as LobbyPlaceId (f0065's attribute), never a GamePlaceId
local function expectGame(target: Beta.Target, placeId: string, attributes: { [string]: number })
	t.expect(target.place).toBe("game")
	t.expect(target.project).toBe("default.project.json")
	t.expect(target.placeId).toBe(placeId)
	t.expect(target.output).toBe("version")
	t.expect(target.runtime).toBe("tests/runtime")
	t.expect(target.attributes).toEqual(attributes)
end

local function throws(game: string, needle: string)
	local ok, err = pcall(Beta.plan, env(game))
	t.expect(ok).toBe(false)
	t.expect(string.find(tostring(err), needle, 1, true) ~= nil).toBe(true)
	t.expect((string.find(tostring(err), "KEY-NOT-IN-OUTPUT", 1, true))).toBe(nil)
end

return t.spec("c0064 Beta.plan", function(it)
	it("names the game place's variable", function()
		t.expect(Beta.GAME_PLACE_VAR).toBe("ROBLOX_BETA_GAME_PLACE_ID")
	end)

	it("not configured is nil, whatever the game place's variable says", function()
		for _, name in { "ROBLOX_API_KEY", "ROBLOX_BETA_UNIVERSE_ID", "ROBLOX_BETA_PLACE_ID" } do
			local e = env("4815162342")
			e[name] = ""
			t.expect(Beta.plan(e)).toBe(nil)
			e[name] = nil
			t.expect(Beta.plan(e)).toBe(nil)
		end
	end)

	it("without the game place's id: only the game, to the start place, as before, with a notice", function()
		for _, game in { "UNSET", "" } do -- a nil in a table literal is skipped, so a sentinel stands for unset
			local p = plan(if game == "UNSET" then nil else game)
			t.expect(p.split).toBe(false)
			t.expect(#p.targets).toBe(1)
			expectGame(p.targets[1], "82331952549326", {}) -- no lobby to go back to
			t.expect(string.find(p.notice or "", "ROBLOX_BETA_GAME_PLACE_ID", 1, true) ~= nil).toBe(true)
			t.expect(string.find(p.notice or "", "lobby", 1, true) ~= nil).toBe(true)
		end
	end)

	it(
		"with the game place's id: the game to it first, then the lobby to the start place, told the id",
		function()
			local p = plan("4815162342")
			t.expect(p.split).toBe(true)
			t.expect(p.notice).toBe(nil)
			t.expect(#p.targets).toBe(2)
			expectGame(p.targets[1], "4815162342", { LobbyPlaceId = 82331952549326 })
			t.expect(p.targets[2]).toEqual({
				place = "lobby",
				project = "lobby.project.json",
				placeId = "82331952549326",
				attributes = { GamePlaceId = 4815162342 },
				output = "lobby_version",
				runtime = "tests/runtime/lobby",
			})
		end
	)

	it("the lobby is told exactly the id it is given, as a number, up to 2^53-1", function()
		for _, game in { "1", "7", "123456789012345", "9007199254740991" } do
			local lobby = Beta.target(plan(game), "lobby")
			assert(lobby, "split, so a lobby")
			t.expect(lobby.attributes.GamePlaceId).toBe(tonumber(game))
			t.expect(type(lobby.attributes.GamePlaceId)).toBe("number")
			t.expect((Beta.target(plan(game), "game") :: Beta.Target).placeId).toBe(game)
		end
	end)

	it("a game place id that is not a place id fails, naming the variable", function()
		for _, bad in
			{ "0", "007", "-5", "1.5", "12a", "1/../2", " 12", "0x10", "1e9", "9007199254740992", "１２" }
		do
			throws(bad, "ROBLOX_BETA_GAME_PLACE_ID")
		end
	end)

	it("a game place that is the start place fails: the lobby would overwrite the game", function()
		throws("82331952549326", "ROBLOX_BETA_GAME_PLACE_ID")
	end)

	it("a bad start place id still fails as before, naming its variable", function()
		local e = env("4815162342")
		e.ROBLOX_BETA_PLACE_ID = "12a"
		local ok, err = pcall(Beta.plan, e)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "ROBLOX_BETA_PLACE_ID", 1, true) ~= nil).toBe(true)
	end)

	it("target finds a place in the plan, and nil for one it does not publish", function()
		t.expect((Beta.target(plan(nil), "game") :: Beta.Target).placeId).toBe("82331952549326")
		t.expect(Beta.target(plan(nil), "lobby")).toBe(nil)
		t.expect((Beta.target(plan("4815162342"), "lobby") :: Beta.Target).placeId).toBe("82331952549326")
	end)

	it("never changes the environment it reads", function()
		local e = env("4815162342")
		local before = table.clone(e)
		Beta.plan(e)
		t.expect(e).toEqual(before)
	end)
end)
