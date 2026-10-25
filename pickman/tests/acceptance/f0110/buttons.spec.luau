--!strict
-- f0110 AC1: the touch fire and hop buttons, placed with R0012's touch layout (f0029). The hop button is Roblox's
-- legacy touch jump button (the corner f0029 keeps clear), in the touch GUI's frame, which is the HUD's safe
-- rectangle. The fire button is the same size, one margin left of the hop button, level with it unless that
-- would reach the snap control: then its bottom is one margin above the snap control's top. On every sample
-- screen of f0029 both buttons are at least 44 px, inside the safe rectangle, and miss each other, the snap
-- control, the four HUD blocks, the shot bars and the radar; on the shortest screens (320 px under a 58 px top
-- bar) the radar's clamp wins and the fire button overlaps its bottom, which is accepted and pinned.
local Hud = require("@logic/Hud")
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

-- Added by this issue. Casts keep the spec type-legal before they exist; a missing function fails at the call.
local T = Touch :: any

type Rect = { x: number, y: number, w: number, h: number }

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local SIZE = 120 -- d0105's radar
local ZERO = { top = 0, bottom = 0, left = 0, right = 0 }

-- A sample screen: `inset` the core-UI safe inset (HudView's and the touch GUI's), `device` DangerHud's (nil:
-- the same). `fire` and `hop` are the buttons in screen pixels; `radarOverlap` the accepted overlap of the fire
-- button with the radar, in rows of pixels (0 or nil: none).
type Sample = {
	name: string,
	width: number,
	height: number,
	inset: any,
	device: any?,
	fire: Rect,
	hop: Rect,
	radarOverlap: number?,
}
local SAMPLES: { Sample } = {
	{
		name = "notched phone, portrait",
		width = 390,
		height = 844,
		inset = { top = 47, bottom = 0, left = 0, right = 0 },
		fire = { x = 216, y = 712, w = 70, h = 70 },
		hop = { x = 295, y = 754, w = 70, h = 70 },
	},
	{
		name = "notched phone, landscape",
		width = 844,
		height = 390,
		inset = { top = 0, bottom = 0, left = 47, right = 0 },
		fire = { x = 670, y = 258, w = 70, h = 70 },
		hop = { x = 749, y = 300, w = 70, h = 70 },
	},
	{
		name = "notched phone, landscape, under a 58 px top bar",
		width = 844,
		height = 390,
		inset = { top = 58, bottom = 21, left = 59, right = 59 },
		device = { top = 0, bottom = 21, left = 59, right = 59 },
		fire = { x = 611, y = 237, w = 70, h = 70 },
		hop = { x = 690, y = 279, w = 70, h = 70 },
	},
	{
		name = "small phone, landscape",
		width = 667,
		height = 375,
		inset = nil,
		fire = { x = 493, y = 243, w = 70, h = 70 },
		hop = { x = 572, y = 285, w = 70, h = 70 },
	},
	{
		name = "old phone, landscape",
		width = 480,
		height = 320,
		inset = nil,
		fire = { x = 308, y = 192, w = 70, h = 70 },
		hop = { x = 385, y = 230, w = 70, h = 70 },
	},
	{
		name = "tablet-sized portrait",
		width = 1080,
		height = 1920,
		inset = nil,
		fire = { x = 770, y = 1710, w = 120, h = 120 },
		hop = { x = 910, y = 1710, w = 120, h = 120 },
	},
	{
		name = "touch desktop",
		width = 1920,
		height = 1080,
		inset = nil,
		fire = { x = 1610, y = 870, w = 120, h = 120 },
		hop = { x = 1750, y = 870, w = 120, h = 120 },
	},
	{
		name = "tall narrow phone, portrait",
		width = 360,
		height = 800,
		inset = nil,
		fire = { x = 187, y = 670, w = 70, h = 70 },
		hop = { x = 265, y = 710, w = 70, h = 70 },
	},
	{
		name = "old phone, landscape, under a 58 px top bar",
		width = 480,
		height = 320,
		inset = { top = 58, bottom = 0, left = 0, right = 0 },
		device = ZERO,
		fire = { x = 308, y = 192, w = 70, h = 70 },
		hop = { x = 385, y = 230, w = 70, h = 70 },
		radarOverlap = 14,
	},
	{
		name = "small phone, landscape, under a 58 px top bar",
		width = 568,
		height = 320,
		inset = { top = 58, bottom = 0, left = 0, right = 0 },
		device = ZERO,
		fire = { x = 396, y = 192, w = 70, h = 70 },
		hop = { x = 473, y = 230, w = 70, h = 70 },
		radarOverlap = 14,
	},
}

local function boxOf(row: any): any
	return {
		textSize = row.textSize,
		margin = row.margin,
		iconSize = row.iconSize,
		barWidth = row.barWidth,
		barHeight = row.barHeight,
		safeX = row.safeX,
		safeY = row.safeY,
		safeW = row.safeW,
		safeH = row.safeH,
	}
end

-- The radar on a touch screen, in screen pixels, as f0029's jump spec computes it.
local function radarOf(s: Sample): Rect
	local core = s.inset or ZERO
	local d = s.device or core
	local r =
		Hud.radarBox(s.width - d.left - d.right, s.height - d.top - d.bottom, SIZE, true, core.top - d.top)
	return { x = d.left + r.x, y = d.top + r.y, w = r.w, h = r.h }
end

local function inside(a: Rect, box: any): boolean
	return a.x >= box.safeX
		and a.y >= box.safeY
		and a.x + a.w <= box.safeX + box.safeW
		and a.y + a.h <= box.safeY + box.safeH
end

return t.spec("f0110 touch buttons", function(it)
	it("the hop button is Roblox's legacy touch jump button in the safe rectangle", function()
		for _, s in SAMPLES do
			local box = boxOf(Hud.layout(s.width, s.height, s.inset))
			local legacy = Hud.jumpButtons(box.safeX, box.safeY, box.safeW, box.safeH)[1]
			t.expect(T.hopRect(box)).toEqual({ x = legacy.x, y = legacy.y, w = legacy.w, h = legacy.h })
			t.expect(T.hopRect(box)).toEqual(s.hop)
		end
	end)

	it(
		"the fire button is the hop button's size, one margin left of it, and stays clear of the snap band",
		function()
			for _, s in SAMPLES do
				local box = boxOf(Hud.layout(s.width, s.height, s.inset))
				local hop = T.hopRect(box)
				local snap = Touch.snapRect(box)
				local fire = T.fireRect(box)
				t.expect(fire.w).toBe(hop.w)
				t.expect(fire.h).toBe(hop.w)
				t.expect(fire.x).toBe(hop.x - box.margin - hop.w)
				t.expect(fire.y).toBe(math.min(hop.y, snap.y - box.margin - hop.w))
				t.expect(fire).toEqual(s.fire)
			end
		end
	)

	it("level with the hop button where the snap band allows it, raised where it does not", function()
		-- a synthetic box where the snap control sits far below: the fire button stays level with the hop button
		local box = {
			textSize = 20,
			margin = 10,
			iconSize = 20,
			barWidth = 100,
			barHeight = 8,
			safeX = 0,
			safeY = 0,
			safeW = 2000,
			safeH = 1000,
		}
		local hop = T.hopRect(box)
		t.expect(hop).toEqual({ x = 1830, y = 790, w = 120, h = 120 })
		t.expect(T.fireRect(box)).toEqual({ x = 1700, y = 790, w = 120, h = 120 })
		-- the portrait phone: level would reach the snap control (y 791), so it rises to end one margin above
		local phone = boxOf(Hud.layout(390, 844, { top = 47, bottom = 0, left = 0, right = 0 }))
		local fire = T.fireRect(phone)
		t.expect(fire.y < T.hopRect(phone).y).toBe(true)
		t.expect(fire.y + fire.h).toBe(Touch.snapRect(phone).y - phone.margin)
	end)

	it("Touch.buttons is the snap, fire and hop rectangles together", function()
		for _, s in SAMPLES do
			local box = boxOf(Hud.layout(s.width, s.height, s.inset))
			t.expect(T.buttons(box)).toEqual({
				snap = Touch.snapRect(box),
				fire = T.fireRect(box),
				hop = T.hopRect(box),
			})
		end
	end)

	it(
		"on every sample both buttons are at least 44 px, inside the safe rectangle, and miss each other and the HUD",
		function()
			for _, s in SAMPLES do
				local box = boxOf(Hud.layout(s.width, s.height, s.inset))
				local b = T.buttons(box)
				local blocks = Touch.blocks(box)
				-- the most the lives row holds on these screens: five lives and three shots
				local bars: { Rect } = {}
				for _, icon in Hud.shotIcons(box, 5, 3) do
					table.insert(bars, {
						x = blocks.lives.x + icon.x,
						y = blocks.lives.y + icon.y,
						w = icon.w,
						h = icon.h,
					})
				end
				t.expect(overlaps(b.fire, b.hop)).toBe(false)
				for _, name in { "fire", "hop" } do
					local r: Rect = b[name]
					t.expect(math.min(r.w, r.h) >= Touch.MIN_TARGET).toBe(true)
					t.expect(inside(r, box)).toBe(true)
					t.expect(overlaps(r, b.snap)).toBe(false)
					for _, block in { "score", "level", "lives", "power" } do
						t.expect(overlaps(r, blocks[block])).toBe(false)
					end
					for _, bar in bars do
						t.expect(overlaps(r, bar)).toBe(false)
					end
				end
			end
		end
	)

	it(
		"the radar misses both buttons, except the fire button on the shortest screens, by the pinned rows",
		function()
			for _, s in SAMPLES do
				local box = boxOf(Hud.layout(s.width, s.height, s.inset))
				local b = T.buttons(box)
				local radar = radarOf(s)
				t.expect(overlaps(b.hop, radar)).toBe(false)
				local want = s.radarOverlap or 0
				if want == 0 then
					t.expect(overlaps(b.fire, radar)).toBe(false)
				else
					t.expect(overlaps(b.fire, radar)).toBe(true)
					t.expect(radar.y + radar.h - b.fire.y).toBe(want)
				end
			end
		end
	)
end)
