--!strict
-- f0145 AC6: the places boot the paid-play adapters, and the documents say what was decided. The game server's Main
-- boots Continues with the sessions; the game client's Main boots OfferView and shows it every frame with Flow's
-- overlay; the lobby server's Main puts Paid in front of Starts (`Paid.start(Starts.start(Paid.allow))`); the lobby
-- client's Main boots PayView after LobbyView. No client script requires Purchases (the store and the purchases are
-- the server's). The remotes are made at run time, so the place files' remote lists stay as they are. game-design.md
-- states the paid play; architecture.md declares Pay, Lobby -> Pay, and the Pay row. Source pins read with comments
-- removed; what they leave to the adapters' running cases (AC5) and to OC1 and OC2: everything the adapters do.
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()
local lobbyPlace = place.load("lobby.project.json")

local function source(root: any, path: { string }): string
	local node = root
	for _, part in path do
		node = node and node:FindFirstChild(part)
	end
	assert(node, `no {table.concat(path, ".")}`)
	return (string.gsub(node.Source, "%-%-[^\n]*", ""))
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

local function remoteNames(root: any): { string }
	local names = {}
	for _, r in root.ReplicatedStorage.Remotes:GetChildren() do
		table.insert(names, r.Name)
	end
	table.sort(names)
	return names
end

return t.spec("f0145 the places and the documents", function(it)
	it(
		"the game server boots Continues with the sessions; the client boots OfferView and shows it each frame",
		function()
			local server = source(gamePlace, { "ServerScriptService", "Server", "Main" })
			t.expect(
				string.find(server, 'require%("%./Continues"%)%.start%(%s*Sessions%.session%s*%)') ~= nil
			)
				.toBe(true)
			local client = source(gamePlace, { "StarterPlayer", "StarterPlayerScripts", "Client", "Main" })
			t.expect(string.find(client, "OfferView%.start%(%)") ~= nil).toBe(true)
			t.expect(string.find(client, "OfferView%.show%(%s*overlay%s*%)") ~= nil).toBe(true)
		end
	)

	it(
		"the lobby server puts Paid in front of Starts; the lobby client boots PayView after LobbyView",
		function()
			local server = source(lobbyPlace, { "ServerScriptService", "Lobby", "Main" })
			t.expect(
				string.find(server, 'Paid%.start%(%s*require%("%./Starts"%)%.start%(%s*Paid%.allow%s*%)%s*%)')
					~= nil
			).toBe(true)
			local client = source(lobbyPlace, { "StarterPlayer", "StarterPlayerScripts", "Lobby", "Main" })
			local view = string.find(client, 'require%("%./LobbyView"%)%.start%(%)')
			local pay = string.find(client, 'require%("%./PayView"%)%.start%(%)')
			t.expect(view ~= nil and pay ~= nil and (view :: number) < (pay :: number)).toBe(true)
		end
	)

	it("no client script requires Purchases; both places keep their remote lists", function()
		for _, spot in
			{
				{ gamePlace, { "StarterPlayer", "StarterPlayerScripts", "Client" } },
				{ lobbyPlace, { "StarterPlayer", "StarterPlayerScripts", "Lobby" } },
			} :: { any }
		do
			local node = spot[1]
			for _, part in spot[2] do
				node = node:FindFirstChild(part)
			end
			for _, script in node:GetChildren() do
				t.expect(has(script.Source, "Shared/Purchases")).toBe(false)
			end
		end
		t.expect(remoteNames(gamePlace)).toEqual({ "Intent", "LobbyStatus", "Ready", "Snapshot", "ToLobby" })
		t.expect(remoteNames(lobbyPlace)).toEqual({ "StartGame", "Status" })
	end)

	it("game-design.md states the paid play; architecture.md declares Pay and Lobby -> Pay", function()
		local design = fs.readFile(".tracker/game-design.md")
		for _, phrase in
			{
				"## Paid play (f0145",
				"one free game per hour",
				"1 Robux",
				"three new lives",
				"lives spent",
				"nothing is charged",
			}
		do
			if not has(design, phrase) then
				error(`game-design.md lacks: {phrase}`)
			end
		end
		local arch = fs.readFile(".tracker/architecture.md")
		local deps = "\n" .. (string.match(arch, "```deps\n(.-)```") or "")
		t.expect(has(deps, "\nLobby -> Pay\n")).toBe(true)
		t.expect(has(arch, "\n| Pay |")).toBe(true)
	end)
end)
