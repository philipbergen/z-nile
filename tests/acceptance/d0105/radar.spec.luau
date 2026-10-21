--!strict
-- d0105 AC1, AC2: radarBox is the radar's rectangle in pixels. Bottom-right, one layout margin in from
-- the right, and the power bar's height plus two margins up from the bottom. The 120-pixel radar (f0033's
-- 15 tiles at 8 pixels) then clears the power bar, the lives row and the level label.
local Hud = require("@logic/Hud")
local t = require("@tests/lib/t")

-- The function is added by this raft. Casting keeps the spec type-legal before it exists; a missing
-- function then fails at the call, which is the pre-implementation failure.
local radarBox = (Hud :: any).radarBox

local SIZE = 120

type Rect = { x: number, y: number, w: number, h: number }

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function hudRects(width: number, height: number): { bar: Rect, lives: Rect, level: Rect }
	local l = Hud.layout(width, height)
	return {
		bar = {
			x = width - (l.barWidth + l.margin),
			y = height - (l.barHeight + l.margin),
			w = l.barWidth,
			h = l.barHeight,
		},
		lives = { x = l.margin, y = height - (l.iconSize + l.margin), w = width / 2, h = l.iconSize },
		level = { x = width / 2 + l.margin, y = l.margin, w = width / 2 - 2 * l.margin, h = l.textSize },
	}
end

local VIEWS = {
	{ 480, 320 },
	{ 667, 375 },
	{ 800, 600 },
	{ 1280, 720 },
	{ 1920, 1080 },
	{ 1080, 1920 },
	{ 3840, 2160 },
}

return t.spec("d0105 radar box", function(it)
	it("layout's numbers are unchanged, so the bar and the labels stay where f0019 put them", function()
		local l = Hud.layout(1280, 720)
		t.expect({
			textSize = l.textSize,
			margin = l.margin,
			iconSize = l.iconSize,
			barWidth = l.barWidth,
			barHeight = l.barHeight,
		}).toEqual({
			textSize = 32,
			margin = 16,
			iconSize = 32,
			barWidth = 320,
			barHeight = 13,
		})
	end)

	it("on a 1280 by 720 screen the 120-pixel radar sits at x 1144, y 555", function()
		t.expect(radarBox(1280, 720, SIZE)).toEqual({ x = 1144, y = 555, w = SIZE, h = SIZE })
	end)

	it("on a 1920 by 1080 screen it sits at x 1780, y 904", function()
		t.expect(radarBox(1920, 1080, SIZE)).toEqual({ x = 1780, y = 904, w = SIZE, h = SIZE })
	end)

	it("on a 480 by 320 screen it sits at x 353, y 180", function()
		t.expect(radarBox(480, 320, SIZE)).toEqual({ x = 353, y = 180, w = SIZE, h = SIZE })
	end)

	it("a zero, negative or non-finite size is an empty square on that same corner", function()
		local corner = { x = 1264, y = 675, w = 0, h = 0 }
		t.expect(radarBox(1280, 720, 0)).toEqual(corner)
		t.expect(radarBox(1280, 720, -3)).toEqual(corner)
		t.expect(radarBox(1280, 720, 0 / 0)).toEqual(corner)
		t.expect(radarBox(1280, 720, math.huge)).toEqual(corner)
	end)

	it("its right edge matches the margin, and its bottom is one margin above the power bar", function()
		for _, v in VIEWS do
			local w, h = v[1], v[2]
			local l = Hud.layout(w, h)
			local b = radarBox(w, h, SIZE)
			local bar = hudRects(w, h).bar
			t.expect(b.x + b.w).toBe(w - l.margin)
			t.expect(b.y + b.h + l.margin).toBe(bar.y)
		end
	end)

	it(
		"the 120-pixel radar is inside the screen, in the right half, and clear of the bar, the lives and the level",
		function()
			for _, v in VIEWS do
				local w, h = v[1], v[2]
				local b = radarBox(w, h, SIZE)
				local r = hudRects(w, h)
				t.expect(b.x >= 0 and b.y >= 0 and b.x + b.w <= w and b.y + b.h <= h).toBe(true)
				t.expect(b.x >= w / 2).toBe(true)
				t.expect(overlaps(b, r.bar)).toBe(false)
				t.expect(overlaps(b, r.lives)).toBe(false)
				t.expect(overlaps(b, r.level)).toBe(false)
			end
		end
	)
end)
