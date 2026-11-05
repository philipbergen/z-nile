--!strict
-- f0102 AC5: the danger HUD draws glows, not arrows, and still decides nothing. It asks Awareness.indicators with
-- the camera's field of view, the screen's aspect and inView, groups them with Awareness.glows, places each at
-- Awareness.edgePoint through Awareness.glowBox and colours it with View.ghostColor of that ghost. The glows live in
-- a ScreenGui of their own in the device's safe area, below the HUD. The ghost bodies use the same colours.
-- Narrowed by c0159 (2026-10-31), because f0158's danger ring replaces the edge glows (decided with the user,
-- 2026-10-26: "Replace edge glows"; its screen is the core-UI safe area, G8). No longer pinned: the calls to
-- Awareness.glows, edgePoint and glowBox, a glow coloured with View.ghostColor of its ghost's name and flash (and
-- so the names and flashes handed to Awareness), and the screen's ScreenInsets (f0158's own spec checks the drawn
-- ring's). Still pinned: DangerHud draws the danger directions from Awareness (Awareness.glows or Awareness.ring),
-- on a screen of its own under the radar, the Flow overlay and the HUD (its DisplayOrder rules), and colours
-- nothing by position. As before, the screen case reads orders, not which screen draws what: dots drawn on the
-- radar's screen, or one screen for both at -1, pass it; f0158's place.spec checks the drawn screens.
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

	it("it draws the danger directions Awareness computes: the edge glows, or f0158's ring", function()
		local src = source("DangerHud")
		t.expect(has(src, "Awareness.glows(") or has(src, "Awareness.ring(")).toBe(true)
	end)

	it("the arrows are gone", function()
		local src = source("DangerHud")
		t.expect(has(src, "▲")).toBe(false)
		t.expect(has(src, ".Rotation")).toBe(false)
	end)

	it(
		"the danger directions have their own screen, under the radar, the Flow overlay and the HUD",
		function()
			local src = source("DangerHud")
			local orders = {}
			for n in string.gmatch(src, "DisplayOrder%s*=%s*(%-?%d+)") do
				table.insert(orders, tonumber(n) :: number)
			end
			t.expect(#orders).toBe(1) -- the glows' screen sets one; the radar's (Danger) keeps the default, 0
			t.expect(orders[1] < 0).toBe(true)
			local flow = string.match(source("FlowView"), "DisplayOrder%s*=%s*(%-?%d+)")
			t.expect(flow == nil or (tonumber(flow) :: number) > orders[1]).toBe(true)
			t.expect(has(source("HudView"), "DisplayOrder = 1")).toBe(true)
		end
	)

	it("DangerHud colours nothing by position", function()
		local src = source("DangerHud")
		t.expect(string.find(src, "snap%.ghosts%[") == nil).toBe(true)
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
