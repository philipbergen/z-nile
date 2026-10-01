--!strict
-- f0170 AC6: the server adapter plays the real game and replicates frames. It stays thin: the choices
-- are named constants from Session, not decisions of its own.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

-- the adapter's source without comments, so a mention in a comment proves nothing
local function source(): string
	local node: any = game
	for _, name in { "ServerScriptService", "Server", "Sessions" } do
		node = node and node:FindFirstChild(name)
	end
	local src = string.gsub(node.Source, "%-%-[^\n]*", "")
	return src
end

return t.spec("f0170 server adapter", function(it)
	it("creates sessions with Session.GAME_CONFIG as the config argument", function()
		local calls = 0
		for call in string.gmatch(source(), "Session%.new%b()") do
			calls += 1
			t.expect(string.find(call, "Session%.GAME_CONFIG%s*%)$") ~= nil).toBe(true)
		end
		t.expect(calls >= 1).toBe(true)
	end)

	it("sends Session.frame to the client, not the bare snapshot", function()
		local src = source()
		t.expect(string.find(src, ":FireClient%(%s*[%w_%.]+%s*,%s*Session%.frame%(") ~= nil).toBe(true)
		t.expect((string.find(src, "Session.snapshot(", 1, true))).toBe(nil)
	end)

	it("still starts a session only when the client signals Ready", function()
		local src = source()
		t.expect(string.find(src, "Ready", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "OnServerEvent", 1, true) ~= nil).toBe(true)
		t.expect((string.find(src, "PlayerAdded", 1, true))).toBe(nil)
	end)
end)
