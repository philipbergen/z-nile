--!strict
-- Formation: the rows x cols aliens and their march, engine-free (f0216). The formation steps sideways as one
-- block; when its living extent would cross a side margin it advances one row toward the base line instead and
-- reverses. The wait between steps is read from the live count every tick, so it shortens as the formation thins.
-- Row 1 is the front row (nearest the cannon), column 1 the leftmost.
export type Config = {
	rows: number,
	cols: number,
	colSpacing: number,
	rowSpacing: number,
	width: number, -- an alien's box across
	depth: number, -- an alien's box in depth
	stepX: number, -- one sideways step
	rowStep: number, -- one advance toward the base line
	margin: number, -- the living extent stays within [margin, fieldWidth - margin]
	fieldWidth: number,
	ticksPerAlien: number,
	minInterval: number,
	points: { number }, -- by row, front first
}
export type Formation = {
	config: Config,
	x: number, -- column 1's left edge
	d: number, -- row 1's near edge
	dir: number, -- +1 marching right, -1 left
	elapsed: number, -- ticks since the last step
	alive: { boolean }, -- alive[(row - 1) * cols + col]
	live: number,
}
export type Move = "step" | "advance"

local Formation = {}
Formation.CLASSIC = table.freeze({
	rows = 5,
	cols = 11,
	colSpacing = 16,
	rowSpacing = 16,
	width = 12,
	depth = 8,
	stepX = 2,
	rowStep = 8,
	margin = 8,
	fieldWidth = 224,
	ticksPerAlien = 1,
	minInterval = 1,
	points = table.freeze({ 10, 10, 20, 20, 30 }),
} :: Config)

-- A full formation, centred across, its front row's near edge at depth `d`, marching right.
function Formation.new(config: Config, d: number): Formation
	local span = (config.cols - 1) * config.colSpacing + config.width
	return {
		config = config,
		x = (config.fieldWidth - span) // 2,
		d = d,
		dir = 1,
		elapsed = 0,
		alive = table.create(config.rows * config.cols, true),
		live = config.rows * config.cols,
	}
end

function Formation.isAlive(f: Formation, row: number, col: number): boolean
	local c = f.config
	if row < 1 or row > c.rows or col < 1 or col > c.cols then
		return false
	end
	return f.alive[(row - 1) * c.cols + col] == true
end

-- The ticks between steps at the current live count.
function Formation.interval(f: Formation): number
	return math.max(f.config.minInterval, f.live * f.config.ticksPerAlien)
end

-- The half-open box [x0, x1) x [d0, d1) of the alien at (row, col).
function Formation.box(f: Formation, row: number, col: number): (number, number, number, number)
	local c = f.config
	local x0 = f.x + (col - 1) * c.colSpacing
	local d0 = f.d + (row - 1) * c.rowSpacing
	return x0, d0, x0 + c.width, d0 + c.depth
end

-- The living extent: left edge, right edge (exclusive) and the front's near edge. Nil when none is alive.
function Formation.extent(f: Formation): (number?, number?, number?)
	local c = f.config
	local minCol, maxCol, minRow = math.huge, -math.huge, math.huge
	for row = 1, c.rows do
		for col = 1, c.cols do
			if f.alive[(row - 1) * c.cols + col] then
				minCol = math.min(minCol, col)
				maxCol = math.max(maxCol, col)
				minRow = math.min(minRow, row)
			end
		end
	end
	if f.live == 0 then
		return nil, nil, nil
	end
	local left = f.x + (minCol - 1) * c.colSpacing
	local right = f.x + (maxCol - 1) * c.colSpacing + c.width
	return left, right, f.d + (minRow - 1) * c.rowSpacing
end

-- One tick of the march. Returns the move made when a step was due, else nil. An empty formation never moves.
function Formation.tick(f: Formation): Move?
	if f.live == 0 then
		return nil
	end
	f.elapsed += 1
	if f.elapsed < Formation.interval(f) then
		return nil
	end
	f.elapsed = 0
	local c = f.config
	local left, right = Formation.extent(f)
	assert(left and right, "a living formation has an extent")
	local nl, nr = left + f.dir * c.stepX, right + f.dir * c.stepX
	if nl < c.margin or nr > c.fieldWidth - c.margin then
		f.d -= c.rowStep
		f.dir = -f.dir
		return "advance"
	end
	f.x += f.dir * c.stepX
	return "step"
end

-- The living alien whose box holds the point (x, d), or nil.
function Formation.hitAt(f: Formation, x: number, d: number): (number?, number?)
	local c = f.config
	local col = math.floor((x - f.x) / c.colSpacing) + 1
	local row = math.floor((d - f.d) / c.rowSpacing) + 1
	if not Formation.isAlive(f, row, col) then
		return nil, nil
	end
	local x0, d0, x1, d1 = Formation.box(f, row, col)
	if x >= x0 and x < x1 and d >= d0 and d < d1 then
		return row, col
	end
	return nil, nil
end

-- Kills the alien at (row, col): its points, or 0 when it was not alive.
function Formation.kill(f: Formation, row: number, col: number): number
	if not Formation.isAlive(f, row, col) then
		return 0
	end
	f.alive[(row - 1) * f.config.cols + col] = false
	f.live -= 1
	return f.config.points[row]
end

-- The front-most living row of a column, or nil.
function Formation.front(f: Formation, col: number): number?
	for row = 1, f.config.rows do
		if Formation.isAlive(f, row, col) then
			return row
		end
	end
	return nil
end

-- The columns with a living alien, left to right.
function Formation.columns(f: Formation): { number }
	local out = {}
	for col = 1, f.config.cols do
		if Formation.front(f, col) then
			table.insert(out, col)
		end
	end
	return out
end

return Formation
