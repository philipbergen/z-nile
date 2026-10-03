--!strict
-- f0320: the danger HUD is a thin client adapter. All the geometry is Awareness; the adapter reads the
-- replicated snapshot and the camera's pose, draws what Awareness returns, and decides nothing.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()
local CLIENT = { "StarterPlayer", "StarterPlayerScripts", "Client" }

local function find(path: { string }): any
	local node: any = game
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function source(name: string): string
	local node = find({ CLIENT[1], CLIENT[2], CLIENT[3], name })
	t.expect(node ~= nil).toBe(true)
	local src = string.gsub(node.Source, "%-%-[^\n]*", "")
	return src
end

return t.spec("f0320 danger hud adapter", function(it)
	it("DangerHud is a ModuleScript beside the other client modules", function()
		local node = find({ CLIENT[1], CLIENT[2], CLIENT[3], "DangerHud" })
		t.expect(node ~= nil).toBe(true)
		t.expect(node.ClassName).toBe("ModuleScript")
	end)

	it("it draws what Awareness computes: the radar, the indicators and the edge points", function()
		local src = source("DangerHud")
		for _, call in { "Awareness.radar(", "Awareness.indicators(", "Awareness.edgePoint(" } do
			t.expect(string.find(src, call, 1, true) ~= nil).toBe(true)
		end
	end)

	it("it passes the camera's field of view and the screen's aspect to Awareness.indicators", function()
		local src = source("DangerHud")
		local call = string.match(src, "Awareness%.indicators%b()") or ""
		t.expect(string.find(call, "verticalFieldOfView", 1, true) ~= nil).toBe(true)
		t.expect(string.find(call, "aspect", 1, true) ~= nil).toBe(true)
	end)

	it("it does none of the geometry itself: no angles, no path search, no distances", function()
		local src = source("DangerHud")
		for _, word in { "atan2", "math.atan", "math.sqrt", "Maze.passable", "Maze.neighbor", "pathDistance" } do
			t.expect((string.find(src, word, 1, true))).toBe(nil)
		end
	end)

	it("it decides nothing about the game and sends nothing to the server", function()
		local src = source("DangerHud")
		for _, word in { "FireServer", "OnClientEvent", "play.score", "play.lives" } do
			t.expect((string.find(src, word, 1, true))).toBe(nil)
		end
	end)

	it("the camera hands its pose over without a second interpolation", function()
		local src = source("Camera")
		t.expect(string.find(src, "function Camera%.pose%(") ~= nil).toBe(true)
		local calls = 0
		for _ in string.gmatch(src, "View%.interpolate%b()") do
			calls += 1
		end
		t.expect(calls).toBe(1)
	end)

	it("the client entry point gives the HUD every snapshot and the camera's pose, and starts it", function()
		local src = source("Main")
		t.expect(string.find(src, "DangerHud%.push%(%s*snap%s*,") ~= nil).toBe(true)
		t.expect(string.find(src, "DangerHud%.start%(%s*Camera%.pose%s*%)") ~= nil).toBe(true)
	end)
end)
