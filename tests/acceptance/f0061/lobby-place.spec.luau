--!strict
-- f0670: the lobby place built from lobby.project.json: what it holds, what it does not, and that the game
-- place is untouched.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local lobby = place.load("lobby.project.json")
local game = place.load()

local function find(root: any, path: { string }): any
	local node = root
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function names(parent: any): { string }
	local out: { string } = {}
	if parent then
		for _, child in parent:GetChildren() do
			table.insert(out, child.Name)
		end
	end
	table.sort(out)
	return out
end

local function includes(list: { any }, target: any): boolean
	for _, v in list do
		if v == target then
			return true
		end
	end
	return false
end

local function requires(from: any): { any }
	local out = {}
	for _, spec in place.requireSpecs(from.Source) do
		local target = place.resolveRequire(from, spec)
		if target == nil then
			error(`{from:GetFullName()}: require of "{spec}" does not resolve in the lobby place`)
		end
		table.insert(out, target)
	end
	return out
end

return t.spec("f0670 lobby place", function(it)
	it("the lobby spawns no characters", function()
		t.expect(lobby:GetService("Players").CharacterAutoLoads).toBe(false)
	end)

	it("its remotes are StartGame and Status, and none of the game's", function()
		t.expect(find(lobby, { "ReplicatedStorage", "Remotes" }).ClassName).toBe("Folder")
		t.expect(names(find(lobby, { "ReplicatedStorage", "Remotes" }))).toEqual({ "StartGame", "Status" })
		t.expect(find(lobby, { "ReplicatedStorage", "Remotes", "StartGame" }).ClassName).toBe("RemoteEvent")
		t.expect(find(lobby, { "ReplicatedStorage", "Remotes", "Status" }).ClassName).toBe("RemoteEvent")
	end)

	it(
		"the destination is a number attribute on ServerScriptService, 0 (not set up) as checked in",
		function()
			local scripts = lobby:GetService("ServerScriptService")
			t.expect(typeof(scripts:GetAttribute("GamePlaceId"))).toBe("number")
			t.expect(scripts:GetAttribute("GamePlaceId")).toBe(0)
		end
	)

	it("the lobby's own scripts are there, and none of the game's adapters", function()
		t.expect(find(lobby, { "ServerScriptService", "Lobby", "Main" }).ClassName).toBe("Script")
		t.expect(find(lobby, { "ServerScriptService", "Lobby", "Starts" }).ClassName).toBe("ModuleScript")
		t.expect(find(lobby, { "StarterPlayer", "StarterPlayerScripts", "Lobby", "Main" }).ClassName)
			.toBe("LocalScript")
		t.expect(find(lobby, { "StarterPlayer", "StarterPlayerScripts", "Lobby", "LobbyView" }).ClassName)
			.toBe("ModuleScript")
		t.expect(find(lobby, { "ServerScriptService", "Server" })).toBe(nil)
		t.expect(find(lobby, { "StarterPlayer", "StarterPlayerScripts", "Client" })).toBe(nil)
	end)

	it("the shared Logic is in the lobby, and holds only ModuleScripts", function()
		t.expect(find(lobby, { "ReplicatedStorage", "Shared", "Logic", "Travel" }).ClassName)
			.toBe("ModuleScript")
		t.expect(find(lobby, { "ReplicatedStorage", "Shared", "Logic", "Lobby" }).ClassName)
			.toBe("ModuleScript")
		for _, d in find(lobby, { "ReplicatedStorage" }):GetDescendants() do
			t.expect(d:IsA("Script") or d:IsA("LocalScript")).toBe(false)
		end
	end)

	it(
		"every require in the lobby's scripts resolves in the built place, and they wire up as designed",
		function()
			local server = find(lobby, { "ServerScriptService", "Lobby" })
			local client = find(lobby, { "StarterPlayer", "StarterPlayerScripts", "Lobby" })
			local logic = find(lobby, { "ReplicatedStorage", "Shared", "Logic" })
			t.expect(includes(requires(server.Main), server.Starts)).toBe(true)
			t.expect(includes(requires(server.Starts), logic.Travel)).toBe(true)
			t.expect(includes(requires(client.Main), client.LobbyView)).toBe(true)
			t.expect(includes(requires(client.LobbyView), logic.Lobby)).toBe(true)
			t.expect(includes(requires(client.LobbyView), logic.Travel)).toBe(true)
			for _, d in lobby:GetDescendants() do
				if d:IsA("LuaSourceContainer") and d.Source ~= "" then
					requires(d)
				end
			end
		end
	)

	it("the game place is untouched: no lobby scripts, remotes or attribute", function()
		t.expect(find(game, { "ServerScriptService", "Lobby" })).toBe(nil)
		t.expect(find(game, { "StarterPlayer", "StarterPlayerScripts", "Lobby" })).toBe(nil)
		t.expect(find(game, { "ReplicatedStorage", "Remotes", "StartGame" })).toBe(nil)
		t.expect(game:GetService("ServerScriptService"):GetAttribute("GamePlaceId")).toBe(nil)
		t.expect(find(game, { "ServerScriptService", "Server", "Main" }).ClassName).toBe("Script")
	end)
end)
