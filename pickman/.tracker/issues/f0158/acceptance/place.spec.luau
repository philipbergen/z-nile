--!strict
-- f0158 AC3: DangerHud draws the danger ring and decides nothing. It lights the ring from Awareness.glows of the
-- indicators (in view or not), places every dot where Awareness.ring puts it on the ring's screen, colours a lit
-- dot with View.ghostColor of its own ghost and draws it Awareness.RING.lit opaque at its brightness, and an unlit
-- one Awareness.RING.idle. The ring's screen sits in the device's safe area under the HUD (DisplayOrder below the
-- HUD's 1), so the HUD draws over it. The edge glows' boxes are gone; no geometry is done here.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function source(name: string): string
	local node: any = game
	for _, part in { "StarterPlayer", "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(part)
	end
	t.expect(node ~= nil).toBe(true)
	return (string.gsub(node.Source, "%-%-[^\n]*", ""))
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

return t.spec("f0158 ring adapter", function(it)
	it(
		"it lights the ring from the glows of the indicators and places each dot where Awareness.ring says",
		function()
			local src = source("DangerHud")
			t.expect(
				string.find(src, "Awareness%.ring%(%s*Awareness%.glows%(") ~= nil
					or (
						has(src, "Awareness.glows(")
						and string.find(src, "Awareness%.ring%(%s*lit%s*,") ~= nil
					)
			).toBe(true)
			t.expect(string.find(src, "%.Position%s*=%s*UDim2%.fromOffset%(%s*d%.x%s*,%s*d%.y%s*%)") ~= nil)
				.toBe(true)
			t.expect(string.find(src, "%.Size%s*=%s*UDim2%.fromOffset%(%s*d%.w%s*,%s*d%.h%s*%)") ~= nil)
				.toBe(true)
		end
	)

	it("a lit dot is its ghost's colour at the ring's lit opacity, an unlit one the idle opacity", function()
		local src = source("DangerHud")
		t.expect(string.find(src, "View%.ghostColor%(%s*d%.name") ~= nil).toBe(true)
		t.expect(has(src, "Awareness.RING.lit.min")).toBe(true)
		t.expect(has(src, "Awareness.RING.lit.max")).toBe(true)
		t.expect(has(src, "d.brightness")).toBe(true)
		t.expect(has(src, "Awareness.RING.idle")).toBe(true)
	end)

	it("the ring has its own screen in the device's safe area, under the HUD", function()
		local src = source("DangerHud")
		t.expect(string.find(src, "%.ScreenInsets%s*=%s*Enum%.ScreenInsets%.DeviceSafeInsets") ~= nil)
			.toBe(true)
		local orders = {}
		for n in string.gmatch(src, "DisplayOrder%s*=%s*(%-?%d+)") do
			table.insert(orders, tonumber(n) :: number)
		end
		t.expect(#orders).toBe(1)
		t.expect(orders[1] < 1).toBe(true)
		t.expect(has(source("HudView"), "DisplayOrder = 1")).toBe(true)
	end)

	it("the edge glows are gone and the adapter does no geometry", function()
		local src = source("DangerHud")
		for _, word in
			{ "Awareness.glowBox(", "Awareness.edgePoint(", "math.sin", "math.cos", "math.atan", "math.sqrt" }
		do
			t.expect(has(src, word)).toBe(false)
		end
	end)
end)
