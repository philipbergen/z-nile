--!strict
-- f0026 AC4: the board and rank remotes are created in code, not in the place files. The lobby
-- boot path and FlowView's empty FireServer stay as the promoted specs pin them.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local function stripped(path: string): string
	return string.gsub(fs.readFile(path), "%-%-[^\n]*", "")
end

return t.spec("f0026 adapter boundaries", function(it)
	it("the place files do not gain a Board or Rank remote", function()
		local lobby = serde.decode("json", fs.readFile("lobby.project.json"))
		local game = serde.decode("json", fs.readFile("default.project.json"))
		t.expect(lobby.tree.ReplicatedStorage.Remotes.Board).toBe(nil)
		t.expect(lobby.tree.ReplicatedStorage.Remotes.StartGame["$className"]).toBe("RemoteEvent")
		t.expect(lobby.tree.ReplicatedStorage.Remotes.Status["$className"]).toBe("RemoteEvent")
		t.expect(game.tree.ReplicatedStorage.Remotes.Rank).toBe(nil)
		t.expect(game.tree.ReplicatedStorage.Remotes.PlayAgain["$className"]).toBe("RemoteEvent")
	end)

	it("Starts never opens a store, and the lobby Main boots Boards after it", function()
		local starts = stripped("src/lobby/server/Starts.luau")
		t.expect((string.find(starts, "DataStore", 1, true))).toBe(nil)
		t.expect((string.find(starts, "Boards", 1, true))).toBe(nil)
		local main = stripped("src/lobby/server/Main.server.luau")
		local startsAt = string.find(main, "Starts", 1, true)
		local boardsAt = string.find(main, "Boards", 1, true)
		t.expect(startsAt ~= nil and boardsAt ~= nil and startsAt < boardsAt).toBe(true)
		t.expect(fs.isFile("src/lobby/server/Boards.luau")).toBe(true)
		local boards = stripped("src/lobby/server/Boards.luau")
		t.expect(string.find(boards, 'Instance.new("RemoteEvent")', 1, true) ~= nil).toBe(true)
		t.expect(string.find(boards, '"Board"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(boards, "Hiscores.boardId", 1, true) ~= nil).toBe(true)
		t.expect(string.find(boards, "Hiscores.lookup", 1, true) ~= nil).toBe(true)
		t.expect(string.find(boards, "Hiscores.cacheKey", 1, true) ~= nil).toBe(true)
		t.expect((string.find(boards, "SetAsync", 1, true))).toBe(nil)
		t.expect((string.find(boards, "UpdateAsync", 1, true))).toBe(nil)
		t.expect((string.find(boards, "HiscoreStore", 1, true))).toBe(nil)
		local fires = 0
		for _ in string.gmatch(boards, "FireClient") do
			fires += 1
		end
		t.expect(fires >= 2).toBe(true)
		t.expect(string.find(boards, "failed", 1, true) ~= nil).toBe(true)
	end)

	it("the lobby screen looks the board up and does not wait for it", function()
		local view = stripped("src/lobby/client/LobbyView.luau")
		t.expect(string.find(view, 'FindFirstChild("Board")', 1, true) ~= nil).toBe(true)
		t.expect((string.find(view, 'WaitForChild("Board")', 1, true))).toBe(nil)
		t.expect(string.find(view, "Lobby.boardPanel", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, "Lobby.lines", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, "Lobby.boardTitle", 1, true) ~= nil).toBe(true)
		local asks = 0
		for _ in string.gmatch(view, 'FireServer%("all"%)') do
			asks += 1
		end
		t.expect(asks >= 2).toBe(true)
		t.expect(string.find(view, "READ_GAP", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, "failed", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, "task.delay", 1, true) ~= nil).toBe(true)
	end)

	it("FlowView keeps an empty FireServer and hears Rank without waiting for it", function()
		local view = stripped("src/client/FlowView.luau")
		local calls = 0
		for call in string.gmatch(view, ":FireServer%b()") do
			calls += 1
			t.expect(call).toBe(":FireServer()")
		end
		t.expect(calls >= 1).toBe(true)
		t.expect(string.find(view, 'FindFirstChild("Rank")', 1, true) ~= nil).toBe(true)
		t.expect((string.find(view, 'WaitForChild("Rank")', 1, true))).toBe(nil)
		t.expect(string.find(view, "OnClientEvent", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, "Flow.follow", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, "Flow.hearRank", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, "Flow.shownRank", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, 'banner == "GAME OVER"', 1, true) ~= nil).toBe(true)
		local main = stripped("src/client/Main.client.luau")
		t.expect((string.find(main, "Rank", 1, true))).toBe(nil)
		t.expect(string.find(main, "Flow.overlay", 1, true) ~= nil).toBe(true)
	end)

	it("the game server creates Rank in code and starts it before Sessions", function()
		t.expect(fs.isFile("src/server/Ranks.luau")).toBe(true)
		local ranks = stripped("src/server/Ranks.luau")
		t.expect(string.find(ranks, 'Instance.new("RemoteEvent")', 1, true) ~= nil).toBe(true)
		t.expect(string.find(ranks, '"Rank"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(ranks, "FireClient", 1, true) ~= nil).toBe(true)
		t.expect((string.find(ranks, "OnServerEvent", 1, true))).toBe(nil)
		t.expect((string.find(ranks, "FireServer", 1, true))).toBe(nil)
		t.expect(string.find(ranks, "HiscoreStore.listen", 1, true) ~= nil).toBe(true)
		local main = stripped("src/server/Main.server.luau")
		local ranksAt = string.find(main, "Ranks", 1, true)
		local sessionsAt = string.find(main, "Sessions", 1, true)
		t.expect(ranksAt ~= nil and sessionsAt ~= nil and ranksAt < sessionsAt).toBe(true)
	end)
end)
