--!strict
-- c0196: f0147's HUD pick counter (Hud.picksBox under the score) clears every dot of f0158's danger ring
-- across all 15 sample screens and insets (desktop and touch) at full extent (every sector lit).
local Awareness = require("@logic/Awareness")
local Hud = require("@logic/Hud")
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

type Rect = { x: number, y: number, w: number, h: number }
type Inset = { top: number, bottom: number, left: number, right: number }
type Screen = { name: string, width: number, height: number, inset: Inset? }

local ZERO: Inset = { top = 0, bottom = 0, left = 0, right = 0 }
local BAR: Inset = { top = 58, bottom = 0, left = 0, right = 0 }

local ALL_SECTORS: { Awareness.Indicator } = {}
for k = 0, Awareness.SECTORS - 1 do
	table.insert(ALL_SECTORS, {
		index = k + 1,
		size = 1,
		brightness = 1,
		bearing = k * (math.pi * 2 / Awareness.SECTORS),
		distance = 0,
		look = "normal",
		inView = true,
	})
end

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
	},
	{
		name = "old phone, portrait, under a 58 px top bar",
		width = 320,
		height = 480,
		inset = BAR,
	},
	{
		name = "small phone, portrait, under a 58 px top bar",
		width = 320,
		height = 568,
		inset = BAR,
	},
	{
		name = "small phone, landscape, under a 58 px top bar",
		width = 568,
		height = 320,
		inset = BAR,
	},
	{
		name = "small phone, landscape 667, under a 58 px top bar",
		width = 667,
		height = 375,
		inset = BAR,
	},
	{ name = "desktop 1280", width = 1280, height = 720 },
	{ name = "desktop 1024", width = 1024, height = 768 },
	{ name = "desktop 2560", width = 2560, height = 1440 },
}

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function fullRingDots(s: Screen): { Rect }
	local core = s.inset or ZERO
	local fx, fy = core.left, core.top
	local fw, fh = s.width - core.left - core.right, s.height - core.top - core.bottom
	local dots = Awareness.ring(ALL_SECTORS, fw, fh)
	t.expect(#dots).toBe(Awareness.SECTORS * Awareness.RING.dots)
	local out: { Rect } = {}
	for _, d in dots do
		t.expect(d.lit).toBe(true)
		t.expect(d.w > 0 and d.h > 0).toBe(true)
		table.insert(out, { x = fx + d.x, y = fy + d.y, w = d.w, h = d.h })
	end
	return out
end

return t.spec("c0196 HUD pick counter clears danger ring", function(it)
	it("Hud.picksBox(Touch.blocks(l).score) overlaps no lit danger-ring dot on any f0158 screen", function()
		local hits: { string } = {}
		for _, s in SCREENS do
			local core = s.inset or ZERO
			local l = Hud.layout(s.width, s.height, core)
			local picks = Hud.picksBox(Touch.blocks(l).score)
			t.expect(picks.w > 0 and picks.h > 0).toBe(true)
			for _, d in fullRingDots(s) do
				if overlaps(d, picks) then
					table.insert(hits, `{s.name} ({s.width}x{s.height})`)
					break
				end
			end
		end
		if #hits > 0 then
			error("picksBox overlaps danger ring on: " .. table.concat(hits, "; "), 0)
		end
	end)
end)
