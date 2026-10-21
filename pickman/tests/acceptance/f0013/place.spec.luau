--!strict
-- f0120 AC7: the built place has no auto-spawned characters, the three remotes, and a server entry
-- point that boots the Sessions adapter, which uses the Session and Maze features.
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
	for _, v in list do
		if v == target then
			return true
		end
	end
	return false
end

return t.spec("f0120 server place", function(it)
	it("does not spawn characters automatically", function()
		t.expect(game:GetService("Players").CharacterAutoLoads).toBe(false)
	end)

	it("has the Ready, Intent and Snapshot RemoteEvents in ReplicatedStorage.Remotes", function()
		t.expect(find({ "ReplicatedStorage", "Remotes" }).ClassName).toBe("Folder")
		t.expect(find({ "ReplicatedStorage", "Remotes", "Ready" }).ClassName).toBe("RemoteEvent")
		t.expect(find({ "ReplicatedStorage", "Remotes", "Intent" }).ClassName).toBe("RemoteEvent")
		t.expect(find({ "ReplicatedStorage", "Remotes", "Snapshot" }).ClassName).toBe("RemoteEvent")
	end)

	it("the server Main requires the Sessions adapter module", function()
		local main = find({ "ServerScriptService", "Server", "Main" })
		local sessions = find({ "ServerScriptService", "Server", "Sessions" })
		t.expect(sessions and sessions.ClassName).toBe("ModuleScript")
		t.expect(includes(resolved(main), sessions)).toBe(true)
	end)

	it("the Sessions adapter uses the Session and Maze features", function()
		local deps = resolved(find({ "ServerScriptService", "Server", "Sessions" }))
		t.expect(includes(deps, find({ "ReplicatedStorage", "Shared", "Logic", "Session" }))).toBe(true)
		t.expect(includes(deps, find({ "ReplicatedStorage", "Shared", "Logic", "Maze" }))).toBe(true)
	end)

	it("sessions start on the client's Ready signal, not on PlayerAdded", function()
		local src = find({ "ServerScriptService", "Server", "Sessions" }).Source
		t.expect(string.find(src, "Ready", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "OnServerEvent", 1, true) ~= nil).toBe(true)
		t.expect((string.find(src, "PlayerAdded", 1, true))).toBe(nil)
	end)
end)
