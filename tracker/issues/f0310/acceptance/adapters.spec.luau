--!strict
-- f0310: the client adapter that draws the ghosts is a thin ModuleScript in the built place: it blends only
-- through View.interpolateGhosts with the elapsed real time, reads nothing it should not, and the client
-- entry point hands it every snapshot.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function find(path: { string }): any
	local node: any = game
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function source(path: { string }): string
	local node = find(path)
	t.expect(node ~= nil).toBe(true)
	local src = string.gsub(node.Source, "%-%-[^\n]*", "")
	return src
end

local CLIENT = { "StarterPlayer", "StarterPlayerScripts", "Client" }

return t.spec("f0310 ghost adapter", function(it)
	it("GhostView is a ModuleScript beside the other client modules", function()
		local node = find({ "StarterPlayer", "StarterPlayerScripts", "Client", "GhostView" })
		t.expect(node ~= nil).toBe(true)
		t.expect(node.ClassName).toBe("ModuleScript")
	end)

	it(
		"blends through View.interpolateGhosts with View.alpha of the real time since the snapshot arrived, nothing else",
		function()
			local src = source({ CLIENT[1], CLIENT[2], CLIENT[3], "GhostView" })
			local calls = 0
			for call in string.gmatch(src, "View%.interpolateGhosts%b()") do
				calls += 1
				t.expect(
					string.find(
						call,
						"^View%.interpolateGhosts%(%s*prev%s*,%s*snap%s*,%s*View%.alpha%(%s*os%.clock%(%)%s*%-%s*arrived%s*%)%s*%)$"
					) ~= nil
				).toBe(true)
			end
			t.expect(calls).toBe(1)
			t.expect((string.find(src, "TICK_RATE", 1, true))).toBe(nil)
		end
	)

	it("only snapshots that are newer move it forward, as the camera does", function()
		local src = source({ CLIENT[1], CLIENT[2], CLIENT[3], "GhostView" })
		t.expect(string.find(src, "snap%.tick%s*>%s*latest%.tick") ~= nil).toBe(true)
	end)

	it("the client entry point gives every snapshot to the ghost view and starts it", function()
		local src = source({ CLIENT[1], CLIENT[2], CLIENT[3], "Main" })
		t.expect(string.find(src, "GhostView%.push%(%s*snap%s*%)") ~= nil).toBe(true)
		t.expect(string.find(src, "GhostView%.start%(%s*%)") ~= nil).toBe(true)
	end)

	it(
		"it requires the shared Logic only through the ReplicatedStorage alias, and no ServerScriptService",
		function()
			local src = source({ CLIENT[1], CLIENT[2], CLIENT[3], "GhostView" })
			for spec in string.gmatch(src, 'require%(%s*"([^"]+)"%s*%)') do
				t.expect(string.sub(spec, 1, 30)).toBe("@game/ReplicatedStorage/Shared")
			end
			t.expect((string.find(src, "ServerScriptService", 1, true))).toBe(nil)
		end
	)

	it("it decides nothing about the game: no Ghosts module, no scores, no remotes", function()
		local src = source({ CLIENT[1], CLIENT[2], CLIENT[3], "GhostView" })
		for _, word in { "Logic/Ghosts", "FireServer", "OnClientEvent", "play.score" } do
			t.expect((string.find(src, word, 1, true))).toBe(nil)
		end
	end)
end)
