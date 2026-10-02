--!strict
-- f0670: the tooling knows the second place: the place library builds either project, the test selector
-- treats a change to the lobby's project file like any change to a place, and the gate builds both.
local fs = require("@lune/fs")
local graph = require("@scripts/lib/graph")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local function isSpec(file: string): boolean
	return string.match(file, "%.spec%.luau$") ~= nil
end

return t.spec("f0670 tooling", function(it)
	it("place.load builds the lobby project apart from the game's, and builds each once", function()
		local lobby = place.load("lobby.project.json")
		local game = place.load()
		t.expect(lobby ~= game).toBe(true)
		t.expect(place.load("lobby.project.json")).toBe(lobby)
		t.expect(place.load("default.project.json")).toBe(game)
		t.expect(lobby:GetService("ServerScriptService"):FindFirstChild("Lobby") ~= nil).toBe(true)
		t.expect(game:GetService("ServerScriptService"):FindFirstChild("Lobby")).toBe(nil)
	end)

	it("place.scripts lists the lobby's scripts too", function()
		local found = false
		for _, s in place.scripts(place.load("lobby.project.json")) do
			if s:GetFullName() == "ServerScriptService.Lobby.Starts" then
				found = true
			end
		end
		t.expect(found).toBe(true)
	end)

	it(
		"a change to lobby.project.json selects the place specs, like a change to default.project.json",
		function()
			local g = graph.build({ "src", "tests" })
			local lobby = graph.affectedSpecs(g, { "lobby.project.json" }, isSpec)
			local game = graph.affectedSpecs(g, { "default.project.json" }, isSpec)
			t.expect(#lobby > 0).toBe(true)
			t.expect(table.concat(lobby, "\n")).toBe(table.concat(game, "\n"))
		end
	)

	it("the gate builds the lobby project too", function()
		local text = fs.readFile("scripts/check.sh")
		-- a stage that is run, not one that is commented out
		local lobby, game = false, false
		for line in string.gmatch(text, "[^\n]+") do
			if string.match(line, "^%s*par_start .*rojo build lobby%.project%.json") then
				lobby = true
			elseif string.match(line, "^%s*par_start .*rojo build default%.project%.json") then
				game = true
			end
		end
		t.expect(lobby).toBe(true)
		t.expect(game).toBe(true)
	end)
end)
