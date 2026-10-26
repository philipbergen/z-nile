--!strict
-- f0158 AC2: the danger ring and the HUD at the screen's edges, each measured in the frame the game draws it in
-- (review 001 F1). HudView lays the HUD out on the whole screen with the core-UI safe inset
-- (Hud.layout(w, h, core)): the score, level, lives (with three shots) and power-bar blocks (Touch.blocks), the
-- snap control (Touch.snapRect) and, on a touch screen, Roblox's jump buttons (Hud.jumpButtons on the core frame)
-- are in screen pixels. The radar is DangerHud's corner map (Hud.radarBox in the device safe area, the band top
-- passed), shifted to screen pixels as f0029 does. The ring's screen is the core-UI safe area too (G8, decided with
-- the user 2026-10-26: "Centre below top bar"): its dots (Awareness.ring of that frame's size) are shifted by the
-- frame's top-left. Every f0029 sample screen (tests/acceptance/f0029/jump.spec.luau's SAMPLES, copied below) is
-- checked, plus the short screens under a 58 px top bar (480 x 320 and 320 x 568) and their turns, on desktop (no
-- touch controls) and on touch. No dot may overlap a box unless ACCEPTED names that screen and box.
-- f0110's FIRE and HOP buttons (Touch.buttons) are not on main: whichever of f0110 and f0158 lands second adds
-- them to the touch boxes here, on every screen (review 001 F5).
-- Casts keep the spec type-legal on main before f0158 (Awareness.ring, RING, View.DANGER_COLOR) and f0109 (fake.module)
-- exist; a missing member fails at the call.
local Awareness: any = require("@logic/Awareness")
local Hud = require("@logic/Hud")
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

type Rect = { x: number, y: number, w: number, h: number }
type Inset = { top: number, bottom: number, left: number, right: number }
type Screen = { name: string, width: number, height: number, inset: Inset?, device: Inset? }

local ACCEPTED: { [string]: { [string]: boolean } } = {} -- screen name -> box names the user accepted under dots
local RADAR = (Awareness.RADAR_RADIUS * 2 + 1) * 8 -- DangerHud's CELL, f0029's SIZE
local ZERO: Inset = { top = 0, bottom = 0, left = 0, right = 0 }
local BAR: Inset = { top = 58, bottom = 0, left = 0, right = 0 } -- Roblox's top bar, core-UI only

local SCREENS: { Screen } = {
	-- f0029's SAMPLES
	{
		name = "notched phone, portrait",
		width = 390,
		height = 844,
		inset = { top = 47, bottom = 0, left = 0, right = 0 },
	},
	{
		name = "notched phone, landscape",
		width = 844,
		height = 390,
		inset = { top = 0, bottom = 0, left = 47, right = 0 },
	},
	{
		name = "notched phone, landscape, under a 58 px top bar",
		width = 844,
		height = 390,
		inset = { top = 58, bottom = 21, left = 59, right = 59 },
		device = { top = 0, bottom = 21, left = 59, right = 59 },
	},
	{ name = "small phone, landscape", width = 667, height = 375 },
	{ name = "old phone, landscape", width = 480, height = 320 },
	{ name = "tablet-sized portrait", width = 1080, height = 1920 },
	{ name = "touch desktop", width = 1920, height = 1080 },
	-- the short screens under a 58 px top bar, and their turns
	{
		name = "old phone, landscape, under a 58 px top bar",
		width = 480,
		height = 320,
		inset = BAR,
		device = ZERO,
	},
	{
		name = "old phone, portrait, under a 58 px top bar",
		width = 320,
		height = 480,
		inset = BAR,
		device = ZERO,
	},
	{
		name = "small phone, portrait, under a 58 px top bar",
		width = 320,
		height = 568,
		inset = BAR,
		device = ZERO,
	},
	{
		name = "small phone, landscape, under a 58 px top bar",
		width = 568,
		height = 320,
		inset = BAR,
		device = ZERO,
	},
	{
		name = "small phone, landscape 667, under a 58 px top bar",
		width = 667,
		height = 375,
		inset = BAR,
		device = ZERO,
	},
	-- desktop sizes
	{ name = "desktop 1280", width = 1280, height = 720 },
	{ name = "desktop 1024", width = 1024, height = 768 },
	{ name = "desktop 2560", width = 2560, height = 1440 },
}

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- a safe area's frame in screen pixels: x, y, w, h
local function frame(s: Screen, inset: Inset): (number, number, number, number)
	return inset.left, inset.top, s.width - inset.left - inset.right, s.height - inset.top - inset.bottom
end

local function hudBoxes(s: Screen, touch: boolean): { [string]: Rect }
	local core = s.inset or ZERO
	local device = s.device or core
	local l = Hud.layout(s.width, s.height, core)
	local b = Touch.blocks(l)
	local out: { [string]: Rect } = { score = b.score, level = b.level, lives = b.lives, power = b.power }
	for i, shot in Hud.shotIcons(l, 3, 3) do
		out["shot" .. i] = { x = b.lives.x + shot.x, y = b.lives.y + shot.y, w = shot.w, h = shot.h }
	end
	local fx, fy, fw, fh = frame(s, device)
	local r = Hud.radarBox(fw, fh, RADAR, touch, core.top - device.top)
	out.radar = { x = fx + r.x, y = fy + r.y, w = r.w, h = r.h }
	if touch then
		out.snap = Touch.snapRect(l)
		for i, j in Hud.jumpButtons(l.safeX, l.safeY, l.safeW, l.safeH) do
			out["jump" .. i] = j
		end
	end
	return out
end

local function ringDots(s: Screen): { Rect }
	local fx, fy, fw, fh = frame(s, s.inset or ZERO) -- the core-UI safe area (G8)
	local out: { Rect } = {}
	for _, d in Awareness.ring({}, fw, fh) do
		table.insert(out, { x = fx + d.x, y = fy + d.y, w = d.w, h = d.h })
	end
	return out
end

return t.spec("f0158 the ring clears the HUD", function(it)
	for _, touch in { false, true } do
		it(
			`no dot overlaps a HUD box it is not allowed to ({if touch then "touch" else "desktop"})`,
			function()
				local hits: { string } = {}
				for _, s in SCREENS do
					local boxes = hudBoxes(s, touch)
					local seen: { [string]: boolean } = {}
					for _, d in ringDots(s) do
						for name, b in boxes do
							if not seen[name] and overlaps(d, b) and not (ACCEPTED[s.name] or {})[name] then
								seen[name] = true
								table.insert(hits, `{s.name} ({s.width}x{s.height}): {name}`)
							end
						end
					end
				end
				if #hits > 0 then
					error("ring dots over: " .. table.concat(hits, "; "), 0)
				end
			end
		)
	end

	it("every dot is inside the screen", function()
		for _, s in SCREENS do
			for _, d in ringDots(s) do
				t.expect(d.x >= 0 and d.y >= 0).toBe(true)
				t.expect(d.x + d.w <= s.width and d.y + d.h <= s.height).toBe(true)
			end
		end
	end)
end)
