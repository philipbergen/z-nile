--!strict
-- Field: the flat, wrap-around field every rule plays on. Field units, x across and y up; leaving one edge
-- comes back on the opposite one. Headings are whole numbers 0..255, counter-clockwise from +x (64 is +y).
local Field = {}

export type Field = { width: number, height: number }

Field.CLASSIC = table.freeze({ width = 1024, height = 768 } :: Field)
Field.HEADINGS = 256

-- a point folded back onto the field: x in [0, width), y in [0, height)
function Field.wrap(f: Field, x: number, y: number): (number, number)
	return x % f.width, y % f.height
end

local function near(v: number, size: number): number
	local d = v % size
	if d >= size / 2 then
		d -= size
	end
	return d
end

-- the shortest vector from a to b across the wrap; each part in [-size/2, size/2)
function Field.delta(f: Field, ax: number, ay: number, bx: number, by: number): (number, number)
	return near(bx - ax, f.width), near(by - ay, f.height)
end

function Field.distance(f: Field, ax: number, ay: number, bx: number, by: number): number
	local dx, dy = Field.delta(f, ax, ay, bx, by)
	return math.sqrt(dx * dx + dy * dy)
end

-- the unit vector of a heading
function Field.unit(heading: number): (number, number)
	local a = heading * 2 * math.pi / Field.HEADINGS
	return math.cos(a), math.sin(a)
end

-- the heading (0..255) nearest the direction (dx, dy); 0 for no direction
function Field.heading(dx: number, dy: number): number
	if dx == 0 and dy == 0 then
		return 0
	end
	return math.floor(math.atan2(dy, dx) * Field.HEADINGS / (2 * math.pi) + 0.5) % Field.HEADINGS
end

-- How far along its move (0 to 1) a point moving from (x, y) by (vx, vy) first comes closer than r to
-- (cx, cy), across the wrap; nil when it never does.
function Field.sweep(
	f: Field,
	x: number,
	y: number,
	vx: number,
	vy: number,
	cx: number,
	cy: number,
	r: number
): number?
	local dx, dy = Field.delta(f, x, y, cx, cy)
	local c = dx * dx + dy * dy - r * r
	if c < 0 then
		return 0
	end
	local a = vx * vx + vy * vy
	if a == 0 then
		return nil
	end
	local b = dx * vx + dy * vy
	local along = math.clamp(b / a, 0, 1)
	local ex, ey = dx - along * vx, dy - along * vy
	if ex * ex + ey * ey >= r * r then
		return nil
	end
	return math.clamp((b - math.sqrt(math.max(b * b - a * c, 0))) / a, 0, 1)
end

return Field
