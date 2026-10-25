--!strict
-- E3 (f0101): wall height against eye, ghost and jump heights on the classic maze, in studs.
-- For every pair of a player tile centre (eye on the centreline) and a ghost tile within RANGE tiles (Chebyshev),
-- it casts rays from the eye to sample points on the ghost's body (a 6 x GHOST x 6 box on the tile centre) and
-- walks the grid exactly (Amanatides-Woo). A ray is blocked by a wall or door tile if its height anywhere inside
-- that tile is at or below the wall top (the height is linear, so the lower of the entry and exit heights decides).
-- "Hidden" means hidden by walls of infinite height; "shows" means visible over walls of height H.
-- Run: lune run tracker/rafts/R0035/experiments/E3-spyhop.luau   (about 30 s)
local Maze = require("@logic/Maze")

local TILE = 8
local RANGE = 10
local EYE = 4
local GHOST = 10
local m = Maze.layout("classic")

local function solid(x: number, y: number): boolean
	if y < 0 or y >= m.height then
		return true
	end
	local k = Maze.kind(m, { x = x % m.width, y = y })
	return k == "wall" or k == "door"
end

local function cell(v: number): number
	return math.floor((v + TILE / 2) / TILE) -- tile i covers [i*TILE - TILE/2, i*TILE + TILE/2)
end

-- Is the segment from (ax, az, ah) to (bx, bz, bh) clear of walls of height `wall`? The endpoints' own tiles are
-- open (the eye's and the ghost's).
local function clear(
	ax: number,
	az: number,
	ah: number,
	bx: number,
	bz: number,
	bh: number,
	wall: number
): boolean
	local cx, cz = cell(ax), cell(az)
	local ex, ez = cell(bx), cell(bz)
	local dx, dz = bx - ax, bz - az
	local stepX = if dx > 0 then 1 elseif dx < 0 then -1 else 0
	local stepZ = if dz > 0 then 1 elseif dz < 0 then -1 else 0
	local function boundary(c: number, step: number): number
		return (c + (if step > 0 then 0.5 else -0.5)) * TILE
	end
	local tMaxX = if stepX ~= 0 then (boundary(cx, stepX) - ax) / dx else math.huge
	local tMaxZ = if stepZ ~= 0 then (boundary(cz, stepZ) - az) / dz else math.huge
	local tDeltaX = if stepX ~= 0 then TILE / math.abs(dx) else math.huge
	local tDeltaZ = if stepZ ~= 0 then TILE / math.abs(dz) else math.huge
	for _ = 1, 200 do
		if cx == ex and cz == ez then
			return true
		end
		local tIn
		if tMaxX < tMaxZ then
			tIn = tMaxX
			cx += stepX
			tMaxX += tDeltaX
		else
			tIn = tMaxZ
			cz += stepZ
			tMaxZ += tDeltaZ
		end
		if cx == ex and cz == ez then
			return true
		end
		if solid(cx, cz) then
			local tOut = math.min(tMaxX, tMaxZ, 1)
			local hIn = ah + (bh - ah) * tIn
			local hOut = ah + (bh - ah) * tOut
			if math.min(hIn, hOut) <= wall then
				return false
			end
		end
	end
	return true
end

local OFFSETS = {
	{ -2.9, -2.9 },
	{ 2.9, -2.9 },
	{ -2.9, 2.9 },
	{ 2.9, 2.9 },
	{ 0, 0 },
	{ -2.9, 0 },
	{ 2.9, 0 },
	{ 0, -2.9 },
	{ 0, 2.9 },
}

-- Does any of the body show at the heights listed (edges, centre line and face middles at each height)?
local function shows(p: Maze.Tile, g: Maze.Tile, eye: number, wall: number, heights: { number }): boolean
	local x, z = g.x * TILE, g.y * TILE
	for _, h in heights do
		for _, o in OFFSETS do
			if clear(p.x * TILE, p.y * TILE, eye, x + o[1], z + o[2], h, wall) then
				return true
			end
		end
	end
	return false
end

local WHOLE: { number } = {}
for h = GHOST, 0, -1 do
	table.insert(WHOLE, h)
end

local floors: { Maze.Tile } = {}
local ghostTiles: { Maze.Tile } = {}
for y = 0, m.height - 1 do
	for x = 0, m.width - 1 do
		if Maze.passable(m, { x = x, y = y }, "player") then
			table.insert(floors, { x = x, y = y })
		end
		if Maze.passable(m, { x = x, y = y }, "ghost") then
			table.insert(ghostTiles, { x = x, y = y })
		end
	end
end

-- the pairs within RANGE whose ghost the tall walls hide entirely
local hidden: { { Maze.Tile } } = {}
local pairs = 0
for _, p in floors do
	for _, g in ghostTiles do
		local d = math.max(math.abs(p.x - g.x), math.abs(p.y - g.y))
		if d >= 1 and d <= RANGE then
			pairs += 1
			if not shows(p, g, EYE, math.huge, WHOLE) then
				table.insert(hidden, { p, g })
			end
		end
	end
end

local function share(eye: number, wall: number, heights: { number }): (number, number)
	local n = 0
	for _, pg in hidden do
		if shows(pg[1], pg[2], eye, wall, heights) then
			n += 1
		end
	end
	return n, 100 * n / #hidden
end

print(`classic: {#floors} floor tiles, {#ghostTiles} ghost tiles, range {RANGE}, eye {EYE}, ghost {GHOST}`)
print(`{pairs} pairs, {#hidden} with the ghost hidden by tall walls`)
print("standing: hidden ghosts any part of which (a sliver of the top included) shows over walls of height H")
for _, wall in { 8, 8.5, 9, 9.5 } do
	local n, pct = share(EYE, wall, WHOLE)
	print(string.format("  wall %4.1f: %d (%.3f%%)", wall, n, pct))
end
-- From above the wall top, every point above it shows however far away it is, so the jump is judged by how far
-- down the body shows: a point at height GHOST - k visible means k studs of the body show.
print("jump apex: share of the hidden ghosts showing their top k studs over walls of height H")
for _, wall in { 8, 9 } do
	for _, k in { 2, 3, 5 } do
		for _, apex in { 12, 14, 16, 18, 20 } do
			local _, pct = share(apex, wall, { GHOST - k })
			print(string.format("  wall %d k %d apex %2d: %.1f%%", wall, k, apex, pct))
		end
	end
end
