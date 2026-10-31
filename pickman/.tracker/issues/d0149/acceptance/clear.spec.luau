--!strict
-- d0149 AC2: the touch controls (Touch.buttons: the steer and look circles, FIRE and PICK) fit every screen. Each is
-- at least Touch.MIN_TARGET, inside the HUD's safe rectangle, and clear of each other, of every HUD box and of the
-- danger ring's dots, measured in the frame the game draws each in (as f0158's clear.spec does, review 001 F1
-- there): HudView lays the HUD and the controls out on the whole screen with the core-UI inset (Hud.layout(w, h,
-- core)); the corner radar is DangerHud's (Hud.radarBox in the device safe area, the band top passed), shifted to
-- screen pixels; the ring (f0158, which lands first: decided with the user 2026-10-31) is drawn in the core-UI safe
-- area and shifted by its top-left. The HUD boxes: score, level, lives, three shots and the boost chevron (f0143),
-- the power bar, the radar, f0126's pick bar and boon banner. A circle is measured by its bounding square, so
-- "clear" here is never closer than a real circle would be. The screens are f0158's (f0029's samples, the short
-- screens under a 58 px top bar and their turns, the desktop sizes), all on a touch screen.
local Awareness: any = require("@logic/Awareness")
local Hud: any = require("@logic/Hud") -- f0126's pickBox and boonBox and f0143's boostIcon land before this issue
local Touch: any = require("@logic/Touch")
local t = require("@tests/lib/t")

type Rect = { x: number, y: number, w: number, h: number }
type Inset = { top: number, bottom: number, left: number, right: number }
type Screen = { name: string, width: number, height: number, inset: Inset?, device: Inset? }

-- Decided with the user 2026-10-31: "Accept it (Recommended)": on this screen alone PICK may draw over the ring's
-- dots (as f0158's G10 lets f0126's PICK there); any other overlap fails
local ACCEPTED: { [string]: { [string]: boolean } } = {
	["old phone, landscape, under a 58 px top bar"] = { pick = true },
}
local RADAR = (Awareness.RADAR_RADIUS * 2 + 1) * 8 -- DangerHud's CELL, f0029's SIZE
local ZERO: Inset = { top = 0, bottom = 0, left = 0, right = 0 }
local BAR: Inset = { top = 58, bottom = 0, left = 0, right = 0 } -- Roblox's top bar, core-UI only

local SCREENS: { Screen } = {
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
	{ name = "desktop 1280", width = 1280, height = 720 },
	{ name = "desktop 1024", width = 1024, height = 768 },
	{ name = "desktop 2560", width = 2560, height = 1440 },
}

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function square(c: { x: number, y: number, r: number }): Rect
	return { x = c.x - c.r, y = c.y - c.r, w = 2 * c.r, h = 2 * c.r }
end

local function frame(s: Screen, inset: Inset): (number, number, number, number)
	return inset.left, inset.top, s.width - inset.left - inset.right, s.height - inset.top - inset.bottom
end

local function layout(s: Screen): any
	return Hud.layout(s.width, s.height, s.inset or ZERO)
end

local function controls(s: Screen): { [string]: Rect }
	local b = Touch.buttons(layout(s))
	return { steer = square(b.steer), look = square(b.look), fire = b.fire, pick = b.pick }
end

local function hudBoxes(s: Screen): { [string]: Rect }
	local core = s.inset or ZERO
	local device = s.device or core
	local l = layout(s)
	local b = Touch.blocks(l)
	local out: { [string]: Rect } = { score = b.score, level = b.level, lives = b.lives, power = b.power }
	for i, shot in Hud.shotIcons(l, 3, 3) do
		out["shot" .. i] = { x = b.lives.x + shot.x, y = b.lives.y + shot.y, w = shot.w, h = shot.h }
	end
	local boost = Hud.boostIcon(l, 3, 3)
	out.boost = { x = b.lives.x + boost.x, y = b.lives.y + boost.y, w = boost.w, h = boost.h }
	local fx, fy, fw, fh = frame(s, device)
	local r = Hud.radarBox(fw, fh, RADAR, true, core.top - device.top)
	out.radar = { x = fx + r.x, y = fy + r.y, w = r.w, h = r.h }
	out.pickBar = Hud.pickBox(l)
	out.boonBanner = Hud.boonBox(l)
	return out
end

local function ringDots(s: Screen): { Rect }
	local fx, fy, fw, fh = frame(s, s.inset or ZERO)
	local out: { Rect } = {}
	for _, d in Awareness.ring({}, fw, fh) do
		table.insert(out, { x = fx + d.x, y = fy + d.y, w = d.w, h = d.h })
	end
	return out
end

local function each(check: (s: Screen, name: string, r: Rect) -> string?)
	local fails: { string } = {}
	for _, s in SCREENS do
		local names: { string } = {}
		for name in controls(s) do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local why = check(s, name, controls(s)[name])
			if why then
				table.insert(fails, `{s.name} ({s.width}x{s.height}): {name} {why}`)
			end
		end
	end
	if #fails > 0 then
		error(table.concat(fails, "; "), 0)
	end
end

return t.spec("d0149 the touch controls fit every screen", function(it)
	it("every control is at least 44 px on each side and inside the safe rectangle", function()
		each(function(s, _name, r)
			local l = layout(s)
			if r.w < Touch.MIN_TARGET or r.h < Touch.MIN_TARGET then
				return `is {r.w} x {r.h}`
			end
			if
				r.x < l.safeX
				or r.y < l.safeY
				or r.x + r.w > l.safeX + l.safeW
				or r.y + r.h > l.safeY + l.safeH
			then
				return "leaves the safe rectangle"
			end
			return nil
		end)
	end)

	it("no two controls overlap", function()
		each(function(s, name, r)
			for other, o in controls(s) do
				if other ~= name and overlaps(r, o) then
					return `overlaps {other}`
				end
			end
			return nil
		end)
	end)

	it(
		"no control overlaps a HUD box: the edge blocks, shots, boost, power bar, radar, pick bar or banner",
		function()
			each(function(s, _name, r)
				for box, b in hudBoxes(s) do
					if overlaps(r, b) then
						return `overlaps {box}`
					end
				end
				return nil
			end)
		end
	)

	it(
		"no control overlaps a dot of the danger ring, but PICK on the one screen the user accepted",
		function()
			each(function(s, name, r)
				if (ACCEPTED[s.name] or {})[name] then
					return nil
				end
				for _, d in ringDots(s) do
					if overlaps(r, d) then
						return "overlaps the ring"
					end
				end
				return nil
			end)
		end
	)
end)
