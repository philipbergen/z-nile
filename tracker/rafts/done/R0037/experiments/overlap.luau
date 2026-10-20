--!strict
-- E1: the bottom-right radar box, computed from the real Hud.layout, clears the power bar,
-- the lives row and the level label. Prints the golden boxes the acceptance spec pins.
local Hud = require("@logic/Hud")

local function side(v: number): number
	return if v > 0 and v < math.huge then v else 0
end

local function radarBox(width: number, height: number, size: number)
	local l = Hud.layout(width, height)
	local s = side(size)
	local right = side(width) - l.margin
	local bottom = side(height) - (l.barHeight + 2 * l.margin)
	return { x = right - s, y = bottom - s, w = s, h = s }
end

local function overlaps(a, b): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local SIZE = 120
local views = {
	{ 480, 320 },
	{ 667, 375 },
	{ 800, 600 },
	{ 1280, 720 },
	{ 1920, 1080 },
	{ 1080, 1920 },
	{ 3840, 2160 },
}

for _, v in views do
	local w, h = v[1], v[2]
	local l = Hud.layout(w, h)
	local b = radarBox(w, h, SIZE)
	local bar = {
		x = w - (l.barWidth + l.margin),
		y = h - (l.barHeight + l.margin),
		w = l.barWidth,
		h = l.barHeight,
	}
	local lives = { x = l.margin, y = h - (l.iconSize + l.margin), w = w / 2, h = l.iconSize }
	local level = { x = w / 2 + l.margin, y = l.margin, w = w / 2 - 2 * l.margin, h = l.textSize }
	local gap = bar.y - (b.y + b.h)
	local inside = b.x >= 0 and b.y >= 0 and b.x + b.w <= w and b.y + b.h <= h
	local right = b.x + b.w == w - l.margin
	local half = b.x >= w / 2
	assert(gap == l.margin, `{w}x{h} gap {gap} ~= margin {l.margin}`)
	assert(inside, `{w}x{h} outside`)
	assert(right, `{w}x{h} right edge`)
	assert(half, `{w}x{h} not in the right half`)
	assert(not overlaps(b, bar), `{w}x{h} hits the bar`)
	assert(not overlaps(b, lives), `{w}x{h} hits lives`)
	assert(not overlaps(b, level), `{w}x{h} hits level`)
	print(`{w}x{h} -> x={b.x} y={b.y} gap={gap} margin={l.margin}`)
end

local z = radarBox(1280, 720, 0)
assert(z.x == 1264 and z.y == 675 and z.w == 0 and z.h == 0, "zero size")
local n = radarBox(1280, 720, -3)
assert(n.x == z.x and n.y == z.y and n.w == 0, "negative size")
local nan = radarBox(1280, 720, 0 / 0)
assert(nan.w == 0 and nan.h == 0, "nan size")
print("E1 pass")
