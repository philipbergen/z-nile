--!strict
-- f0065 AC4: the game place is wired for the way back. Its remotes are ToLobby (client to server, no arguments)
-- and LobbyStatus (server to client) instead of PlayAgain; the lobby's id is the LobbyPlaceId attribute; the
-- server's Main starts Returns with Sessions.isOver, which asks Logic; the client asks Flow with the server's
-- report and sends the request through FlowView only.
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function find(path: { string }): any
	local node = game
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function server(name: string): any
	return find({ "ServerScriptService", "Server", name })
end

local function client(name: string): any
	return find({ "StarterPlayer", "StarterPlayerScripts", "Client", name })
end

-- a script's source without comments, so a mention in a comment proves nothing
local function source(node: any): string
	local src = string.gsub(node.Source, "%-%-[^\n]*", "")
	return src
end

local function resolved(from: any): { any }
	local out = {}
	for _, spec in place.requireSpecs(from.Source) do
		local target = place.resolveRequire(from, spec)
		if target == nil then
			error(`{from:GetFullName()}: require of "{spec}" does not resolve in the place`)
		end
		table.insert(out, target)
	end
	return out
end

local function includes(list: { any }, target: any): boolean
	return table.find(list, target) ~= nil
end

local function logic(name: string): any
	return find({ "ReplicatedStorage", "Shared", "Logic", name })
end

return t.spec("f0065 the game place's way back", function(it)
	it("the remotes are Ready, Intent, Snapshot, ToLobby and LobbyStatus, and PlayAgain is gone", function()
		local names: { string } = {}
		for _, r in find({ "ReplicatedStorage", "Remotes" }):GetChildren() do
			t.expect(r.ClassName).toBe("RemoteEvent")
			table.insert(names, r.Name)
		end
		table.sort(names)
		t.expect(names).toEqual({ "Intent", "LobbyStatus", "Ready", "Snapshot", "ToLobby" })
	end)

	it("the lobby's id is a number attribute LobbyPlaceId on ServerScriptService, 0 as checked in", function()
		local value = game:GetService("ServerScriptService"):GetAttribute("LobbyPlaceId")
		t.expect(type(value)).toBe("number")
		t.expect(value).toBe(0)
	end)

	it("the server's Main starts Returns with Sessions.isOver", function()
		local returns = server("Returns")
		t.expect(returns and returns.ClassName).toBe("ModuleScript")
		local main = server("Main")
		t.expect(includes(resolved(main), returns)).toBe(true)
		t.expect(includes(resolved(main), server("Sessions"))).toBe(true)
		t.expect(string.find(source(main), "%.start%(%s*Sessions%.isOver%s*%)") ~= nil).toBe(true)
	end)

	it("Returns uses Travel, and Sessions.isOver asks Logic", function()
		t.expect(includes(resolved(server("Returns")), logic("Travel"))).toBe(true)
		local src = source(server("Sessions"))
		t.expect(string.find(src, "function Sessions.isOver(", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "Session.isOver(", 1, true) ~= nil).toBe(true)
	end)

	it("the server no longer starts a new run on request", function()
		for _, name in { "Sessions", "Returns", "Main" } do
			local src = source(server(name))
			t.expect((string.find(src, "playAgain", 1, true))).toBe(nil)
			t.expect((string.find(src, "PlayAgain", 1, true))).toBe(nil)
		end
	end)

	it("Main asks Flow with the server's latest report and frees the mouse by the overlay", function()
		local src = source(client("Main"))
		t.expect(
			string.find(src, "Flow%.overlay%(%s*[%w_]+%.play%s*,%s*[%w_]+%s*,%s*FlowView%.trip%(%s*%)%s*%)")
				~= nil
		).toBe(true)
		t.expect(string.find(src, "Camera%.setCursor%(%s*[%w_]+%.cursor%s*%)") ~= nil).toBe(true)
	end)

	it(
		"FlowView sends ToLobby with no arguments, on a tap or Flow's continue keys, and hears LobbyStatus",
		function()
			local src = source(client("FlowView"))
			t.expect(string.find(src, '"ToLobby"', 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, '"LobbyStatus"', 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "OnClientEvent", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "Flow.CONTINUE_KEYS", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "Flow.isContinueKey(", 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, ".Activated:Connect(", 1, true) ~= nil).toBe(true)
			local calls = 0
			for call in string.gmatch(src, ":FireServer%b()") do
				calls += 1
				t.expect(call).toBe(":FireServer()")
			end
			t.expect(calls >= 1).toBe(true)
			t.expect((string.find(src, "PlayAgain", 1, true))).toBe(nil)
			t.expect((string.find(src, "PLAY AGAIN", 1, true))).toBe(nil)
		end
	)

	it("no other client script talks to the way back", function()
		for _, name in { "Main", "HudView", "Camera", "Controls", "MazeView", "PelletView" } do
			local src = source(client(name))
			t.expect((string.find(src, "ToLobby", 1, true))).toBe(nil)
			t.expect((string.find(src, "TeleportService", 1, true))).toBe(nil)
		end
	end)

	it("the Beta runtime structure check asserts the new remotes and the attribute, not PlayAgain", function()
		local text = fs.readFile("tests/runtime/structure.luau")
		t.expect(string.find(text, '"ToLobby"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, '"LobbyStatus"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, '"LobbyPlaceId"', 1, true) ~= nil).toBe(true)
		t.expect((string.find(text, "PlayAgain", 1, true))).toBe(nil)
	end)
end)
