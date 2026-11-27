--!strict
-- Narrowed by c0182: dropped the four Touch.pickRect/old Touch.zone cases (d0149 replaces pickRect and half-split
-- zones; d0149/acceptance/fold.spec and clear.spec own them) and b.snap/b.hop from the clearance list. Keeps PICK's
-- one-shot tap effect and >= 44 px / safe-area / HUD-block / radar / pick-bar / banner clearance.
-- f0126 AC11 (touch): the PICK button in Touch's fold, after f0110's FIRE and JUMP (user, 2026-10-25: "PICK button
-- after f0110"). Touch.pickRect is the fire button's size, one margin left of it and level with it, so the row
-- reads PICK, FIRE, JUMP; Touch.buttons carries it beside f0110's three; a finger going down on it is the "pick"
-- zone and emits one pick effect; it clears every other HUD block, both radars and the pick bar and banner.
local Awareness = require("@logic/Awareness")
local Hud = require("@logic/Hud")
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

type Rect = { x: number, y: number, w: number, h: number }

local T = Touch :: any -- f0110's and this issue's additions to Touch, typed loosely so the spec loads before them

local function overlap(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local SCREENS = {
	{ 320, 568 },
	{ 360, 640 },
	{ 360, 800 },
	{ 375, 667 },
	{ 390, 844 },
	{ 480, 320 },
	{ 500, 900 },
	{ 568, 320 },
	{ 667, 375 },
	{ 844, 390 },
	{ 900, 500 },
	{ 1024, 768 },
	{ 1080, 1920 },
	{ 1280, 720 },
	{ 1920, 1080 },
}
local INSETS: { Hud.Inset } = {
	{ top = 0, bottom = 0, left = 0, right = 0 },
	{ top = 0, bottom = 21, left = 47, right = 0 },
	{ top = 0, bottom = 21, left = 0, right = 47 },
	{ top = 47, bottom = 34, left = 0, right = 0 },
}

return t.spec("f0126 the touch PICK button", function(it)
	it("a tap on it emits one pick, on the finger going down, and nothing on its move or lift", function()
		local pick: Rect = { x = 400, y = 300, w = 70, h = 70 }
		local ctx = { width = 800, pick = pick }
		local state = Touch.empty()
		local out: { any } = {}
		local effects
		state, effects = Touch.track(state, { id = 1, phase = "begin", x = 410, y = 310 }, ctx :: any)
		t.expect(effects).toEqual({ { kind = "pick" } })
		state, effects = Touch.track(state, { id = 1, phase = "move", x = 450, y = 340 }, ctx :: any)
		t.expect(effects).toEqual({})
		-- a second finger on the button while the first is down is ignored (one finger per zone)
		state, effects = Touch.track(state, { id = 2, phase = "begin", x = 420, y = 320 }, ctx :: any)
		for _, e in effects do
			table.insert(out, e)
		end
		t.expect(#out == 0 or out[1].kind ~= "pick").toBe(true)
		state, effects = Touch.track(state, { id = 1, phase = "end", x = 450, y = 340 }, ctx :: any)
		t.expect(effects).toEqual({})
		local _, again = Touch.track(state, { id = 3, phase = "begin", x = 410, y = 310 }, ctx :: any)
		t.expect(again).toEqual({ { kind = "pick" } })
	end)

	it(
		"it is at least 44 px, inside the safe area, and clear of every HUD block, both radars and the pick's own bar and banner",
		function()
			local RADAR = (Awareness.RADAR_RADIUS * 2 + 1) * 8
			for _, s in SCREENS do
				for _, inset in INSETS do
					for _, band in { 0, 36, 58 } do
						local l = Hud.layout(s[1], s[2], inset)
						local b = T.buttons(l)
						local p: Rect = b.pick
						t.expect(p.w >= Touch.MIN_TARGET and p.h >= Touch.MIN_TARGET).toBe(true)
						t.expect(p.x >= l.safeX and p.y >= l.safeY).toBe(true)
						t.expect(p.x + p.w <= l.safeX + l.safeW and p.y + p.h <= l.safeY + l.safeH).toBe(true)
						local blocks = Touch.blocks(l)
						local others: { Rect } = {
							blocks.score,
							blocks.level,
							blocks.lives,
							blocks.power,
							b.fire,
							Hud.pickBox(l),
							Hud.boonBox(l),
							Hud.radarBox(s[1], s[2], RADAR, false),
							Hud.radarBox(s[1], s[2], RADAR, true, band),
						}
						for lives = 0, 6 do
							for _, sh in Hud.shotIcons(l, lives, 3) do
								table.insert(others, {
									x = blocks.lives.x + sh.x,
									y = blocks.lives.y + sh.y,
									w = sh.w,
									h = sh.h,
								})
							end
						end
						for _, o in others do
							t.expect(overlap(p, o)).toBe(false)
						end
						-- FIRE stays clear of the pick's bar and banner too
						for _, button in { b.fire } do
							t.expect(overlap(button, Hud.pickBox(l))).toBe(false)
							t.expect(overlap(button, Hud.boonBox(l))).toBe(false)
						end
					end
				end
			end
		end
	)
end)
