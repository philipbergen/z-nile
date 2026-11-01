--!strict
-- Hud: the pick's bar and the boon's banner (f0126).
local Hud = require("@logic/Hud")
local Picks = require("@logic/Picks")
local t = require("@tests/lib/t")

return t.spec("Hud pick", function(it)
	local pick = { wall = { x = 3, y = 3 }, started = 100, ticks = 40, fast = false }

	it("the bar fills from 0 to 1 over the pick and stays clamped", function()
		t.expect(Hud.pickProgress(nil, 120)).toBe(nil)
		t.expect(Hud.pickProgress(pick, 0 / 0)).toBe(nil)
		t.expect(Hud.pickProgress(pick, 90)).toBe(0)
		t.expect(Hud.pickProgress(pick, 120)).toBe(0.5)
		t.expect(Hud.pickProgress(pick, 200)).toBe(1)
	end)

	it("the banner shows from its step for BOON_TICKS steps, then goes", function()
		local boon = { tick = 50, kind = "shot" :: Picks.Boon }
		t.expect(Hud.boonBanner(boon, 49)).toBe(nil)
		t.expect(Hud.boonBanner(boon, 50)).toBe("BLASTER SHOT")
		t.expect(Hud.boonBanner(boon, 50 + Hud.BOON_TICKS - 1)).toBe("BLASTER SHOT")
		t.expect(Hud.boonBanner(boon, 50 + Hud.BOON_TICKS)).toBe(nil)
		t.expect(Hud.boonBanner(nil, 50)).toBe(nil)
	end)

	it("the bar and the banner sit inside the safe rectangle on a small and a large screen", function()
		for _, size in { { 480, 320 }, { 3840, 2160 } } do
			local l = Hud.layout(size[1], size[2])
			for _, b in { Hud.pickBox(l), Hud.boonBox(l) } do
				t.expect(b.x >= l.safeX and b.x + b.w <= l.safeX + l.safeW).toBe(true)
				t.expect(b.y >= l.safeY and b.y + b.h <= l.safeY + l.safeH).toBe(true)
			end
		end
	end)
end)
