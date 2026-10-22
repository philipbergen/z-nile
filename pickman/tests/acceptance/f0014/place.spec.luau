--!strict
-- f0130 AC6: the client entry point boots the three client adapters, and they use View.
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

local CLIENT = { "StarterPlayer", "StarterPlayerScripts", "Client" }

local function client(name: string): any
	local path = table.clone(CLIENT)
	table.insert(path, name)
	return find(path)
end

return t.spec("f0130 client place", function(it)
	it("the client Main requires MazeView, Camera and Controls", function()
		local deps = resolved(client("Main"))
		for _, name in { "MazeView", "Camera", "Controls" } do
			local m = client(name)
			t.expect(m and m.ClassName).toBe("ModuleScript")
			t.expect(includes(deps, m)).toBe(true)
		end
	end)

	it("each client adapter uses the View feature", function()
		local view = find({ "ReplicatedStorage", "Shared", "Logic", "View" })
		t.expect(view and view.ClassName).toBe("ModuleScript")
		for _, name in { "MazeView", "Camera", "Controls" } do
			t.expect(includes(resolved(client(name)), view)).toBe(true)
		end
	end)

	it("the client Main signals Ready to the server", function()
		local src = client("Main").Source
		t.expect(string.find(src, "Ready", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "FireServer", 1, true) ~= nil).toBe(true)
	end)
end)
