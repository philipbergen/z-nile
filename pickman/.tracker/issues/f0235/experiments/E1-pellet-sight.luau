--!strict
-- f0235 E1: from a jump's top (eyeHeight + Hop.RISE), how often does a power pellet itself show over the walls, against
-- how often its beacon does? Pairs: every walkable tile of the classic maze and each of its four power pellets. A
-- pellet shows when a ray from the eye to its top or its centre clears the walls (f0101's grid walk, copied); the beacon
-- when a ray to any point of it from the wall top to BEACON.top does.
local Hop = require("@logic/Hop")
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local View = require("@logic/View")

local TILE = View.SCALE.tileStuds
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

local eye = View.SCALE.eyeHeight + Hop.RISE
local B = (View :: any).BEACON
local pairs_, pellet, beacon, standingPellet = 0, 0, 0, 0
for _, slot in Pellets.slots(m) do
	if slot.kind == "power" then
		local bx, bz = slot.x * TILE, slot.y * TILE
		for y = 0, m.height - 1 do
			for x = 0, m.width - 1 do
				if Maze.passable(m, { x = x, y = y }, "player") and (x ~= slot.x or y ~= slot.y) then
					pairs_ += 1
					local px, pz = x * TILE, y * TILE
					local top = View.PELLET.height + View.PELLET.power / 2
					if
						clear(px, pz, eye, bx, bz, top, View.SCALE.wallHeight)
						or clear(px, pz, eye, bx, bz, View.PELLET.height, View.SCALE.wallHeight)
					then
						pellet += 1
					end
					if clear(px, pz, View.SCALE.eyeHeight, bx, bz, top, View.SCALE.wallHeight) then
						standingPellet += 1
					end
					for h = View.SCALE.wallHeight + 0.5, B.top, 0.5 do
						if clear(px, pz, eye, bx, bz, h, View.SCALE.wallHeight) then
							beacon += 1
							break
						end
					end
				end
			end
		end
	end
end
print(
	`pairs {pairs_}; pellet seen from a jump's top {pellet} ({math.floor(pellet / pairs_ * 1000) / 10}%); standing {standingPellet} ({math.floor(
		standingPellet / pairs_ * 1000
	) / 10}%); beacon from a jump's top {beacon} ({math.floor(beacon / pairs_ * 1000) / 10}%)`
)
