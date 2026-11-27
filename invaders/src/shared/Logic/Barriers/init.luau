--!strict
-- Barriers: the bunkers between the cannon and the formation, engine-free (f0216). Each bunker is a grid of
-- blocks (cols x rows); a shot erodes the block it reaches and its pattern around it, from whichever side it
-- comes, and an alien marching through erases every block its box overlaps. Coordinates are the field's:
-- x across, d the depth from the base line. Rows count from the near side (row 1 is nearest the cannon).
export type Layout = {
	lefts: { number }, -- each bunker's left x
	near: number, -- the depth of every bunker's near edge
	cols: number,
	rows: number,
	block: number, -- a block's side, in field units
}
export type Barriers = {
	layout: Layout,
	blocks: { { boolean } }, -- blocks[bunker][(row - 1) * cols + col]
}

local Barriers = {}
Barriers.CLASSIC = table.freeze({
	lefts = table.freeze({ 28, 76, 124, 172 }),
	near = 24,
	cols = 8,
	rows = 6,
	block = 3,
} :: Layout)
-- A hit's pattern: { column offset, row offset along the shot's travel }. The hit block, its two neighbours
-- across, and the block beyond it.
Barriers.EROSION = table.freeze({
	table.freeze({ 0, 0 }),
	table.freeze({ -1, 0 }),
	table.freeze({ 1, 0 }),
	table.freeze({ 0, 1 }),
})

function Barriers.new(layout: Layout): Barriers
	local blocks = {}
	for i = 1, #layout.lefts do
		local grid = table.create(layout.cols * layout.rows, true)
		blocks[i] = grid
	end
	return { layout = layout, blocks = blocks }
end

function Barriers.present(b: Barriers, bunker: number, col: number, row: number): boolean
	local l = b.layout
	if col < 1 or col > l.cols or row < 1 or row > l.rows then
		return false
	end
	local grid = b.blocks[bunker]
	return grid ~= nil and grid[(row - 1) * l.cols + col] == true
end

-- The present block whose square holds the point (x, d): bunker, col, row. Nil when there is none.
function Barriers.blockAt(b: Barriers, x: number, d: number): (number?, number?, number?)
	local l = b.layout
	local row = math.floor((d - l.near) / l.block) + 1
	if row < 1 or row > l.rows then
		return nil, nil, nil
	end
	for i, left in l.lefts do
		local col = math.floor((x - left) / l.block) + 1
		if col >= 1 and col <= l.cols then
			if Barriers.present(b, i, col, row) then
				return i, col, row
			end
			return nil, nil, nil
		end
	end
	return nil, nil, nil
end

-- A shot reached (bunker, col, row) travelling `travel` (+1 away from the base line, -1 toward it): removes the
-- EROSION pattern's present blocks. Returns how many were removed.
function Barriers.erode(b: Barriers, bunker: number, col: number, row: number, travel: number): number
	local l = b.layout
	local grid = b.blocks[bunker]
	local removed = 0
	for _, o in Barriers.EROSION do
		local c, r = col + o[1], row + o[2] * travel
		if Barriers.present(b, bunker, c, r) then
			grid[(r - 1) * l.cols + c] = false
			removed += 1
		end
	end
	return removed
end

-- Removes every present block overlapping the half-open box [x0, x1) x [d0, d1). Returns how many.
function Barriers.eraseBox(b: Barriers, x0: number, d0: number, x1: number, d1: number): number
	local l = b.layout
	local removed = 0
	for i, left in l.lefts do
		local grid = b.blocks[i]
		for row = 1, l.rows do
			local bd = l.near + (row - 1) * l.block
			if bd < d1 and bd + l.block > d0 then
				for col = 1, l.cols do
					local bx = left + (col - 1) * l.block
					local k = (row - 1) * l.cols + col
					if bx < x1 and bx + l.block > x0 and grid[k] then
						grid[k] = false
						removed += 1
					end
				end
			end
		end
	end
	return removed
end

-- Present blocks, in one bunker or in all of them.
function Barriers.count(b: Barriers, bunker: number?): number
	local n = 0
	for i, grid in b.blocks do
		if bunker == nil or bunker == i then
			for _, v in grid do
				if v then
					n += 1
				end
			end
		end
	end
	return n
end

return Barriers
