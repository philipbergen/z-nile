--!strict
-- f0101 AC4: the spy hop works on the classic maze, measured with View's own numbers (prep experiment E3).
-- For every pair of a player tile centre and a ghost tile up to 10 tiles away (in x and in y), rays from the eye to
-- points on the ghost's body (a GHOST.width box GHOST.height tall on the tile centre: its edges, centre line and face
-- middles) walk the grid exactly; a wall or door tile blocks a ray that is at or below the wall top anywhere inside
-- it. A ghost is "hidden" when walls of unlimited height hide all of it.
-- Standing (the eye at eyeHeight), at most 0.1% of the hidden ghosts show any of themselves over the lowered walls.
-- At the top of a jump (eyeHeight + Hop.RISE), at least 80% of them show their top 2 studs over the walls.
local Hop = require("@logic/Hop")
local Maze = require("@logic/Maze")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local TILE = View.SCALE.tileStuds
local RANGE = 10
local m = Maze.layout("classic")

local function solid(x: number, y: number): boolean
	if y < 0 or y >= m.height then
		return true
	end
	local k = Maze.kind(m, { x = x % m.width, y = y })
	return k == "wall" or k == "door"
end

local function cell(v: number): number
	return math.floor((v + TILE / 2) / TILE)
end

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
			if math.min(ah + (bh - ah) * tIn, ah + (bh - ah) * tOut) <= wall then
				return false
			end
		end
	end
	return true
end

local half = View.GHOST.width / 2 - 0.1
local OFFSETS = {
	{ -half, -half },
	{ half, -half },
	{ -half, half },
	{ half, half },
	{ 0, 0 },
	{ -half, 0 },
	{ half, 0 },
	{ 0, -half },
	{ 0, half },
}

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
for h = View.GHOST.height, 0, -1 do
	table.insert(WHOLE, h)
end

local hidden: { { Maze.Tile } } = {}
for y = 0, m.height - 1 do
	for x = 0, m.width - 1 do
		local p = { x = x, y = y }
		if Maze.passable(m, p, "player") then
			for gy = math.max(0, y - RANGE), math.min(m.height - 1, y + RANGE) do
				for gx = math.max(0, x - RANGE), math.min(m.width - 1, x + RANGE) do
					local g = { x = gx, y = gy }
					if (gx ~= x or gy ~= y) and Maze.passable(m, g, "ghost") then
						if not shows(p, g, View.SCALE.eyeHeight, math.huge, WHOLE) then
							table.insert(hidden, { p, g })
						end
					end
				end
			end
		end
	end
end

local function share(eye: number, heights: { number }): number
	local n = 0
	for _, pg in hidden do
		if shows(pg[1], pg[2], eye, View.SCALE.wallHeight, heights) then
			n += 1
		end
	end
	return n / #hidden
end

return t.spec("f0101 seeing over the walls", function(it)
	it("most ghosts within ten tiles are hidden behind walls from the standing eye", function()
		t.expect(#hidden > 25000).toBe(true)
	end)

	it(
		"standing, almost no hidden ghost shows any of itself over the lowered walls (at most 0.1%)",
		function()
			t.expect(share(View.SCALE.eyeHeight, WHOLE) <= 0.001).toBe(true)
		end
	)

	it("at the top of a jump, at least 80% of them show their top two studs over the walls", function()
		local apex = View.SCALE.eyeHeight + Hop.RISE
		t.expect(share(apex, { View.GHOST.height - 2 }) >= 0.8).toBe(true)
	end)
end)
