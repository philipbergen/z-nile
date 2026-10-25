--!strict
-- The Rojo project maps src/ onto the DataModel the way the game expects.
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

return t.spec("place structure", function(it)
	it("Server.Main is a Script", function()
		local main = find({ "ServerScriptService", "Server", "Main" })
		t.expect(main and main.ClassName).toBe("Script")
	end)

	it("Client.Main is a LocalScript", function()
		local main = find({ "StarterPlayer", "StarterPlayerScripts", "Client", "Main" })
		t.expect(main and main.ClassName).toBe("LocalScript")
	end)

	it("Shared.Logic exists", function()
		t.expect(find({ "ReplicatedStorage", "Shared", "Logic" }) ~= nil).toBe(true)
	end)
end)
