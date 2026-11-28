--!strict
-- Maps: Snake's arena sizing, progression formulas, spawn layout, and seeded non-connecting wall placement.
-- Pure Logic: no engine references; randomness enters via Draw.
export type Draw = (n: number) -> number
export type Heading = "N" | "E" | "S" | "W"
export type Dir = "H" | "V"
export type Tile = { x: number, y: number }
export type Wall = { x: number, y: number, dir: Dir, length: number }
export type Spawn = { x: number, y: number, heading: Heading }
export type Layout = { map: number, side: number, walls: { Wall }, spawns: { Spawn } }

local Maps = {}

Maps.TUNING = table.freeze({
	baseArea = 400,
	areaPerPlayer = 250,
	speedStart = 4,
	speedStep = 0.25,
	speedCap = 7,
	goalBase = 10,
	goalStep = 2,
	startLength = 4,
	clearAhead = 3,
	wallMin = 3,
	wallMaxFloor = 4,
	middleReach = 2,
	wallTries = 100,
	grow = 2,
})

local H_N: Heading, H_E: Heading, H_S: Heading, H_W: Heading = "N", "E", "S", "W"
Maps.HEADINGS = table.freeze({ H_N, H_E, H_S, H_W })

local STEPS: { [Heading]: Tile } = {
	N = { x = 0, y = -1 },
	E = { x = 1, y = 0 },
	S = { x = 0, y = 1 },
	W = { x = -1, y = 0 },
}

local LEFT: { [Heading]: Heading } = { N = H_W, W = H_S, S = H_E, E = H_N }
local RIGHT: { [Heading]: Heading } = { N = H_E, E = H_S, S = H_W, W = H_N }

local function checkPosInt(fn: string, name: string, v: any)
	if type(v) ~= "number" or v ~= v or math.abs(v) == math.huge or v < 1 or v ~= math.floor(v) then
		error(`{fn}: {name} must be a whole number of at least 1`)
	end
end

function Maps.step(h: Heading): Tile
	local s = STEPS[h]
	return { x = s.x, y = s.y }
end

function Maps.turn(h: Heading, side: "Left" | "Right"): Heading
	return if side == "Left" then LEFT[h] else RIGHT[h]
end

function Maps.side(players: number): number
	checkPosInt("Maps.side", "players", players)
	local t = Maps.TUNING
	return math.ceil(math.sqrt(t.baseArea + t.areaPerPlayer * (players - 1)))
end

function Maps.speed(map: number): number
	checkPosInt("Maps.speed", "map", map)
	local t = Maps.TUNING
	return math.min(t.speedCap, t.speedStart + t.speedStep * (map - 1))
end

function Maps.goal(map: number): number
	checkPosInt("Maps.goal", "map", map)
	local t = Maps.TUNING
	return t.goalBase + t.goalStep * map
end

function Maps.wallCount(map: number): number
	checkPosInt("Maps.wallCount", "map", map)
	return map - 1
end

function Maps.wallMax(side: number): number
	local t = Maps.TUNING
	return math.max(t.wallMaxFloor, math.floor(side / 3))
end

function Maps.wallTiles(w: Wall): { Tile }
	local out: { Tile } = table.create(w.length)
	local dx = if w.dir == "H" then 1 else 0
	local dy = if w.dir == "V" then 1 else 0
	for i = 0, w.length - 1 do
		out[i + 1] = { x = w.x + dx * i, y = w.y + dy * i }
	end
	return out
end

function Maps.spawnTiles(s: Spawn): { Tile }
	local t = Maps.TUNING
	local d = STEPS[s.heading]
	local out: { Tile } = table.create(t.startLength + t.clearAhead)
	for i = 0, t.startLength - 1 do
		table.insert(out, { x = s.x - d.x * i, y = s.y - d.y * i })
	end
	for i = 1, t.clearAhead do
		table.insert(out, { x = s.x + d.x * i, y = s.y + d.y * i })
	end
	return out
end

function Maps.spawns(side: number, players: number): { Spawn }
	checkPosInt("Maps.spawns", "side", side)
	checkPosInt("Maps.spawns", "players", players)
	local cols = math.ceil(math.sqrt(players))
	local rows = math.ceil(players / cols)
	local cw = math.floor(side / cols)
	local ch = math.floor(side / rows)
	local out: { Spawn } = table.create(players)
	for i = 0, players - 1 do
		local c = i % cols
		local r = math.floor(i / cols)
		local hx = c * cw + Maps.TUNING.startLength
		local hy = r * ch + math.max(1, math.floor((ch + 1) / 2))
		out[i + 1] = { x = hx, y = hy, heading = H_E }
	end
	return out
end

function Maps.nearMiddle(w: Wall, side: number): boolean
	local c = (side + 1) / 2
	local mx = if w.dir == "H" then w.x + (w.length - 1) / 2 else w.x
	local my = if w.dir == "V" then w.y + (w.length - 1) / 2 else w.y
	local reach = Maps.TUNING.middleReach
	return math.abs(mx - c) <= reach and math.abs(my - c) <= reach
end

local function keyOf(x: number, y: number, side: number): number
	return y * (side + 2) + x
end

local function markBlocked(blocked: { [number]: boolean }, x: number, y: number, side: number)
	for dy = -1, 1 do
		for dx = -1, 1 do
			local nx, ny = x + dx, y + dy
			if nx >= 1 and nx <= side and ny >= 1 and ny <= side then
				blocked[keyOf(nx, ny, side)] = true
			end
		end
	end
end

local function wallFits(w: Wall, side: number, blocked: { [number]: boolean }, middleOnly: boolean): boolean
	if middleOnly and not Maps.nearMiddle(w, side) then
		return false
	end
	local dx = if w.dir == "H" then 1 else 0
	local dy = if w.dir == "V" then 1 else 0
	for i = 0, w.length - 1 do
		local tx, ty = w.x + dx * i, w.y + dy * i
		if tx < 2 or tx > side - 1 or ty < 2 or ty > side - 1 then
			return false
		end
		if blocked[keyOf(tx, ty, side)] then
			return false
		end
	end
	return true
end

local function placeWall(w: Wall, side: number, blocked: { [number]: boolean })
	local dx = if w.dir == "H" then 1 else 0
	local dy = if w.dir == "V" then 1 else 0
	for i = 0, w.length - 1 do
		markBlocked(blocked, w.x + dx * i, w.y + dy * i, side)
	end
end

local function scanWall(side: number, blocked: { [number]: boolean }, middleOnly: boolean): Wall?
	local len = Maps.TUNING.wallMin
	local dirs: { Dir } = { "H" :: Dir, "V" :: Dir }
	for _, dir: Dir in dirs do
		local maxX = if dir == "H" then side - len else side - 1
		local maxY = if dir == "V" then side - len else side - 1
		for y = 2, maxY do
			for x = 2, maxX do
				local w: Wall = { x = x, y = y, dir = dir, length = len }
				if wallFits(w, side, blocked, middleOnly) then
					return w
				end
			end
		end
	end
	return nil
end

function Maps.roll(map: number, players: number, draw: Draw): Layout
	checkPosInt("Maps.roll", "map", map)
	checkPosInt("Maps.roll", "players", players)
	local t = Maps.TUNING
	local count = Maps.wallCount(map)
	local side = Maps.side(players)
	local middleOnly = map == 2

	while true do
		local spawns = Maps.spawns(side, players)
		local blocked: { [number]: boolean } = {}
		for _, sp in spawns do
			for _, tile in Maps.spawnTiles(sp) do
				markBlocked(blocked, tile.x, tile.y, side)
			end
		end

		local walls: { Wall } = {}
		local wMax = Maps.wallMax(side)
		local lenSpan = math.max(1, wMax - t.wallMin + 1)
		local okAll = true

		for _ = 1, count do
			local placed: Wall? = nil
			for _ = 1, t.wallTries do
				local dir: Dir = if draw(2) == 1 then "H" :: Dir else "V" :: Dir
				local len = t.wallMin - 1 + draw(lenSpan)
				local minX, maxX = 2, if dir == "H" then side - len else side - 1
				local minY, maxY = 2, if dir == "V" then side - len else side - 1
				if middleOnly then
					local c = (side + 1) / 2
					local r = t.middleReach
					if dir == "H" then
						minX = math.max(minX, math.ceil(c - r - (len - 1) / 2))
						maxX = math.min(maxX, math.floor(c + r - (len - 1) / 2))
						minY = math.max(minY, math.ceil(c - r))
						maxY = math.min(maxY, math.floor(c + r))
					else
						minX = math.max(minX, math.ceil(c - r))
						maxX = math.min(maxX, math.floor(c + r))
						minY = math.max(minY, math.ceil(c - r - (len - 1) / 2))
						maxY = math.min(maxY, math.floor(c + r - (len - 1) / 2))
					end
				end
				if minX <= maxX and minY <= maxY then
					local x = minX - 1 + draw(maxX - minX + 1)
					local y = minY - 1 + draw(maxY - minY + 1)
					local cand: Wall = { x = x, y = y, dir = dir, length = len }
					if wallFits(cand, side, blocked, middleOnly) then
						placed = cand
						break
					end
				end
			end
			if placed == nil then
				placed = scanWall(side, blocked, middleOnly)
			end
			if placed == nil then
				okAll = false
				break
			end
			placeWall(placed, side, blocked)
			table.insert(walls, placed)
		end

		if okAll then
			return { map = map, side = side, walls = walls, spawns = spawns }
		end
		side += t.grow
	end
end

return Maps
