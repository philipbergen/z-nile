--!strict
-- f0102 AC5: the danger HUD draws glows, not arrows, and still decides nothing. It asks Awareness.indicators with
-- the camera's field of view, the screen's aspect and inView, groups them with Awareness.glows, places each at
-- Awareness.edgePoint through Awareness.glowBox and colours it with View.ghostColor of that ghost. The glows live in
-- a ScreenGui of their own in the device's safe area, below the HUD. The ghost bodies use the same colours.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function client(name: string): any
	local node: any = game
	for _, part in { "StarterPlayer", "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(part)
	end
	t.expect(node ~= nil).toBe(true)
	return node
end

local function source(name: string): string
	local src = string.gsub(client(name).Source, "%-%-[^\n]*", "")
	return src
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

return t.spec("f0102 glow adapters", function(it)
	it("DangerHud lists every close ghost, in view or not, with the camera's numbers", function()
		local src = source("DangerHud")
		local call = string.match(src, "Awareness%.indicators%b()") or ""
		for _, word in { "verticalFieldOfView", "aspect", "inView = true" } do
			t.expect(has(call, word)).toBe(true)
		end
	end)

	it("it draws the glows Awareness computes, where Awareness puts them, in View's colours", function()
		local src = source("DangerHud")
		for _, call in
			{ "Awareness.glows(", "Awareness.edgePoint(", "Awareness.glowBox(", "View.ghostColor(" }
		do
			t.expect(has(src, call)).toBe(true)
		end
	end)

	it("the arrows are gone", function()
		local src = source("DangerHud")
		t.expect(has(src, "▲")).toBe(false)
		t.expect(has(src, ".Rotation")).toBe(false)
	end)

	it("the glows have their own screen, in the device's safe area, under the HUD", function()
		local src = source("DangerHud")
		t.expect(has(src, "Enum.ScreenInsets.DeviceSafeInsets")).toBe(true)
		local orders = {}
		for n in string.gmatch(src, "DisplayOrder%s*=%s*(%-?%d+)") do
			table.insert(orders, tonumber(n) :: number)
		end
		t.expect(#orders >= 1).toBe(true)
		for _, n in orders do
			t.expect(n < 1).toBe(true) -- HudView's is 1
		end
		t.expect(has(source("HudView"), "DisplayOrder = 1")).toBe(true)
	end)

	it("the HUD still does no geometry itself", function()
		local src = source("DangerHud")
		for _, word in
			{ "atan2", "math.atan", "math.sqrt", "math.sin", "math.cos", "Maze.passable", "pathDistance" }
		do
			t.expect(has(src, word)).toBe(false)
		end
	end)

	it("the ghost bodies take their colours from View.ghostColor too, with no table of their own", function()
		local src = source("GhostView")
		t.expect(has(src, "View.ghostColor(")).toBe(true)
		t.expect(has(src, "Color3.fromRGB(255, 0, 0)")).toBe(false)
		t.expect(has(src, "Color3.fromRGB(0, 255, 255)")).toBe(false)
	end)
end)
