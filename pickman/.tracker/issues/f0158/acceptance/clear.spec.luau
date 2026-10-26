--!strict
-- f0158 AC2: the danger ring never covers the HUD at the screen's edges. On desktop and touch screens, landscape
-- and portrait, no ring dot overlaps the score, level, lives (with three shots) or power-bar blocks (Touch.blocks
-- of Hud.layout), the radar (Hud.radarBox), the touch snap control (Touch.snapRect) or Roblox's touch jump buttons
-- (Hud.jumpButtons).
local Awareness = require("@logic/Awareness")
local Hud = require("@logic/Hud")
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

type Box = { x: number, y: number, w: number, h: number }

local SCREENS = { { 1280, 720 }, { 1920, 1080 }, { 1024, 768 }, { 390, 844 }, { 844, 390 }, { 2560, 1440 } }
local RADAR = (Awareness.RADAR_RADIUS * 2 + 1) * 8 -- DangerHud's CELL

local function overlaps(a: Box, b: Box): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function hudBoxes(w: number, h: number, touch: boolean): { [string]: Box }
	local l = Hud.layout(w, h)
	local b = Touch.blocks(l)
	local out: { [string]: Box } = { score = b.score, level = b.level, lives = b.lives, power = b.power }
	for i, s in Hud.shotIcons(l, 3, 3) do
		out["shot" .. i] = { x = b.lives.x + s.x, y = b.lives.y + s.y, w = s.w, h = s.h }
	end
	out.radar = Hud.radarBox(w, h, RADAR, touch, 0)
	if touch then
		out.snap = Touch.snapRect(l)
		for i, j in Hud.jumpButtons(0, 0, w, h) do
			out["jump" .. i] = j
		end
	end
	return out
end

return t.spec("f0158 the ring clears the HUD", function(it)
	for _, touch in { false, true } do
		it(`no dot overlaps a HUD block ({if touch then "touch" else "desktop"})`, function()
			for _, s in SCREENS do
				local w, h = s[1], s[2]
				local boxes = hudBoxes(w, h, touch)
				for _, d in Awareness.ring({}, w, h) do
					for name, b in boxes do
						if overlaps(d, b) then
							error(`{w}x{h}: a ring dot of sector {d.sector} overlaps {name}`)
						end
					end
				end
			end
		end)
	end
end)
