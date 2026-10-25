--!strict
-- Awareness: how the player senses ghosts they cannot see (R0100). Engine-free numbers in, numbers out: a
-- minimap (radar) around the player and edge indicators for ghosts outside the field of view, which grow
-- and brighten as the ghost gets closer along the maze. The client draws what this returns.
--
-- Coordinates are tile units. A yaw follows View: 0 looks north (-y), a positive yaw turns left. A bearing is
-- the angle from where the camera looks to the ghost, positive to the left, in (-pi, pi].
local Maze = require("./Maze")

export type Look = "normal" | "frightened" | "blinking" | "eyes"
-- name and flash are carried through to the indicators and glows untouched (f0102: a glow is coloured as its ghost)
export type Ghost = { x: number, y: number, look: Look, name: string?, flash: boolean? }
export type Pose = { x: number, y: number, yaw: number }
export type Options = {
	verticalFieldOfView: number?, -- the camera's (Roblox's) vertical field of view in radians
	aspect: number?, -- screen width over height: the horizontal field of view follows from it
	maxDistance: number?, -- tiles along the maze beyond which a ghost is not indicated
	minSize: number?,
	maxSize: number?,
	minBrightness: number?,
	inView: boolean?, -- also indicate ghosts inside the field of view (the glows, f0102); each says which it is
}
export type Indicator = {
	index: number, -- the ghost's place in the input list
	bearing: number,
	distance: number, -- tiles along the maze
	size: number, -- 0..1: the larger, the closer
	brightness: number, -- 0..1: the brighter, the closer
	look: Look,
	inView: boolean, -- inside the horizontal field of view (only with the inView option)
	name: string?, -- the ghost's, as given
	flash: boolean?, -- the ghost's, as given
}
-- One lit place on the screen edge (f0102). Sectors count from straight ahead (0, the top) to the left: 1 the
-- top-left corner, 2 left, 3 bottom-left, 4 behind (the bottom), 5 bottom-right, 6 right, 7 top-right.
export type Glow = {
	sector: number,
	bearing: number, -- the bearing Awareness.edgePoint takes to that sector's place (a corner for a diagonal)
	index: number, -- the nearest ghost's place in the indicators' input list: it gives the colour
	distance: number,
	size: number,
	brightness: number,
	look: Look,
	name: string?, -- the nearest ghost's
	flash: boolean?, -- the nearest ghost's
}
export type Box = { x: number, y: number, w: number, h: number } -- pixels, top-left corner
export type Blip = { x: number, y: number, look: Look } -- offsets from the player, x right and y down on the radar
export type Radar = { radius: number, walls: { { x: number, y: number } }, blips: { Blip } }

local DEFAULTS = {
	verticalFieldOfView = math.rad(80), -- as View.SCALE.fieldOfView; Roblox's FieldOfView is the vertical one
	aspect = 16 / 9,
	maxDistance = 12,
	minSize = 0.25,
	maxSize = 1,
	minBrightness = 0.3,
}

local Awareness = {}
Awareness.DEFAULTS = table.freeze(DEFAULTS)
Awareness.RADAR_RADIUS = 7
Awareness.SECTORS = 8
-- A glow's square side at full size, as a share of the screen's smaller side; at most this far in from an edge,
-- so the middle of the screen, the view ahead, stays clear.
Awareness.GLOW = table.freeze({ side = 0.12 })

-- Tiles to walk from `from` to `to` through the maze, ghosts' routes (doors and the house included), or
-- nil when it is more than `limit`. Wrapping tunnels count.
-- Breadth-first search over the ghosts' routes. Returns the tiles to walk and the direction in which the
-- shortest path crosses a tunnel wrap (-1 west, 1 east, 0 when it does not cross one), or nil beyond `limit`.
local function search(m: Maze.Maze, from: Maze.Tile, to: Maze.Tile, limit: number): (number?, number)
	if from.x == to.x and from.y == to.y then
		return 0, 0
	end
	local seen: { [number]: boolean } = { [from.y * m.width + from.x + 1] = true }
	local frontier: { { tile: Maze.Tile, wrap: number } } = { { tile = from, wrap = 0 } }
	for distance = 1, limit do
		local nextFrontier: { { tile: Maze.Tile, wrap: number } } = {}
		for _, node in frontier do
			for _, h: Maze.Heading in Maze.HEADINGS do
				local n, wrapped = Maze.neighbor(m, node.tile, h)
				local key = n.y * m.width + n.x + 1
				if not seen[key] and Maze.passable(m, n, "ghost") then
					local wrap = node.wrap
					if wrapped and (h == "W" or h == "E") then
						wrap = if h == "W" then -1 else 1
					end
					if n.x == to.x and n.y == to.y then
						return distance, wrap
					end
					seen[key] = true
					table.insert(nextFrontier, { tile = n, wrap = wrap })
				end
			end
		end
		frontier = nextFrontier
		if #frontier == 0 then
			return nil, 0
		end
	end
	return nil, 0
end

-- Tiles to walk from `from` to `to` through the maze, ghosts' routes (doors and the house included), or
-- nil when it is more than `limit`. Wrapping tunnels count.
function Awareness.pathDistance(m: Maze.Maze, from: Maze.Tile, to: Maze.Tile, limit: number): number?
	local distance = search(m, from, to, limit)
	return distance
end

-- The bearing of a point seen from the pose.
function Awareness.bearing(pose: Pose, x: number, y: number): number
	local dx, dy = x - pose.x, y - pose.y
	local fx, fy = -math.sin(pose.yaw), -math.cos(pose.yaw)
	local lx, ly = -math.cos(pose.yaw), math.sin(pose.yaw)
	return math.atan2(dx * lx + dy * ly, dx * fx + dy * fy)
end

-- Where on the screen border (u right, v down, both in -1..1) an indicator at `bearing` sits.
function Awareness.edgePoint(bearing: number, aspect: number): (number, number)
	local du, dv = -math.sin(bearing), -math.cos(bearing)
	local t = math.huge
	if du ~= 0 then
		t = math.min(t, aspect / math.abs(du))
	end
	if dv ~= 0 then
		t = math.min(t, 1 / math.abs(dv))
	end
	return du * t / aspect, dv * t
end

local function occupied(g: Ghost, m: Maze.Maze): Maze.Tile
	return { x = math.floor(g.x + 0.5) % m.width, y = math.floor(g.y + 0.5) % m.height }
end

-- A row wraps when both of its edge tiles are open to ghosts: only then does the maze continue on the other
-- side. The classic maze wraps one row, sideways; nothing wraps vertically.
local function rowWraps(m: Maze.Maze, y: number): boolean
	return Maze.passable(m, { x = 0, y = y }, "ghost")
		and Maze.passable(m, { x = m.width - 1, y = y }, "ghost")
end

-- The part of a position left over once it is rounded to its tile: in -0.5 .. 0.5. Positions are not wrapped (a
-- ghost heading east runs on from 27.0 to 27.99 before it is back at tile 0), but tiles are.
local function frac(v: number): number
	return v - math.floor(v + 0.5)
end

-- Where a ghost is relative to the pose along the path the search found: the tile offset, across the wrap in
-- direction `wrap` (-1, 0 or 1), plus the two fractions, so the answer is continuous when either of them crosses
-- the edge of the map. `unseen` says the 3D positions, which do not wrap, are on opposite sides of the maze from
-- where the path puts the ghost: it cannot be seen, whatever its bearing.
local function offsetVia(
	m: Maze.Maze,
	pose: Pose,
	here: Maze.Tile,
	g: Ghost,
	tile: Maze.Tile,
	wrap: number
): (number, number, boolean)
	local dx = (tile.x - here.x) + wrap * m.width + frac(g.x) - frac(pose.x)
	local unseen = math.abs((g.x - pose.x) - dx) > m.width / 2
	return dx, g.y - pose.y, unseen
end

-- The radar has no path search: it takes the short way round when the player's row or the point's row wraps.
local function offsetShort(m: Maze.Maze, pose: Pose, x: number, y: number): (number, number)
	local dx, dy = x - pose.x, y - pose.y
	local prow, row = math.floor(pose.y + 0.5), math.floor(y + 0.5)
	local wraps = (prow >= 0 and prow < m.height and rowWraps(m, prow))
		or (row >= 0 and row < m.height and rowWraps(m, row))
	if wraps then
		if dx > m.width / 2 then
			dx -= m.width
		elseif dx < -m.width / 2 then
			dx += m.width
		end
	end
	return dx, dy
end

-- One indicator per ghost that is close along the maze and outside the field of view, nearest first.
-- Eyes (a ghost going home) are never indicated.
function Awareness.indicators(m: Maze.Maze, pose: Pose, ghosts: { Ghost }, options: Options?): { Indicator }
	local o: Options = options or {}
	-- a ghost inside the horizontal field is on screen: it gets no arrow, however the screen is shaped
	local fov = 2
		* math.atan(
			math.tan((o.verticalFieldOfView or DEFAULTS.verticalFieldOfView) / 2)
				* (o.aspect or DEFAULTS.aspect)
		)
	local maxDistance = o.maxDistance or DEFAULTS.maxDistance
	local minSize = o.minSize or DEFAULTS.minSize
	local maxSize = o.maxSize or DEFAULTS.maxSize
	local minBrightness = o.minBrightness or DEFAULTS.minBrightness
	local here: Maze.Tile =
		{ x = math.floor(pose.x + 0.5) % m.width, y = math.floor(pose.y + 0.5) % m.height }
	local out: { Indicator } = {}
	for i, g in ghosts do
		if g.look ~= "eyes" then
			local tile = occupied(g, m)
			local d, wrap = search(m, here, tile, maxDistance)
			if d ~= nil then
				local dx, dy, unseen = offsetVia(m, pose, here, g, tile, wrap)
				local bearing = Awareness.bearing(pose, pose.x + dx, pose.y + dy)
				local inView = not unseen and math.abs(bearing) <= fov / 2
				if o.inView or not inView then
					local closeness = 1 - math.clamp(d / maxDistance, 0, 1)
					table.insert(out, {
						index = i,
						bearing = bearing,
						distance = d,
						size = minSize + (maxSize - minSize) * closeness,
						brightness = minBrightness + (1 - minBrightness) * closeness,
						look = g.look,
						inView = inView,
						name = g.name,
						flash = g.flash,
					})
				end
			end
		end
	end
	table.sort(out, function(a: Indicator, b: Indicator): boolean
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.index < b.index
	end)
	return out
end

-- The sector (0..7, see Glow) a bearing falls in: the nearest eighth of a turn, positive left. A bearing exactly
-- between two sectors goes to the one ahead, behind or to a side, not to a corner.
function Awareness.sector(bearing: number): number
	if bearing ~= bearing or math.abs(bearing) == math.huge then
		return 0
	end
	local q = bearing / (math.pi / 4)
	local n = math.floor(q + 0.5)
	if q + 0.5 == n and n % 2 ~= 0 then
		n -= 1
	end
	return n % 8
end

-- The bearing that Awareness.edgePoint maps to a sector's place on a screen of this aspect: the middle of an edge
-- for 0, 2, 4 and 6, the corner for the diagonals. An aspect that is not a positive finite number counts as 1.
function Awareness.sectorBearing(sector: number, aspect: number): number
	local a = if aspect > 0 and aspect < math.huge then aspect else 1
	local corner = math.atan(a)
	local bearings =
		{ 0, corner, math.pi / 2, math.pi - corner, math.pi, -(math.pi - corner), -math.pi / 2, -corner }
	return bearings[(sector % 8) + 1]
end

-- One glow per sector that has a ghost, in sector order. The nearest ghost in a sector lights it: its look, size,
-- brightness and index (a tie in distance: the earlier in the list, which Awareness.indicators sorts so).
function Awareness.glows(list: { Indicator }, aspect: number): { Glow }
	local best: { [number]: Indicator } = {}
	for _, ind in list do
		local k = Awareness.sector(ind.bearing)
		local held = best[k]
		if
			held == nil
			or ind.distance < held.distance
			or (ind.distance == held.distance and ind.index < held.index)
		then
			best[k] = ind
		end
	end
	local out: { Glow } = {}
	for k = 0, Awareness.SECTORS - 1 do
		local ind = best[k]
		if ind then
			table.insert(out, {
				sector = k,
				bearing = Awareness.sectorBearing(k, aspect),
				index = ind.index,
				distance = ind.distance,
				size = ind.size,
				brightness = ind.brightness,
				look = ind.look,
				name = ind.name,
				flash = ind.flash,
			})
		end
	end
	return out
end

-- Where a glow of `size` (0..1) is drawn on a width x height screen: a square of Awareness.GLOW.side times the
-- smaller side times `size`, centred on the edge point (u, v) from Awareness.edgePoint and moved in until it is
-- whole on the screen. A side that is not a positive finite number counts as 0.
function Awareness.glowBox(u: number, v: number, size: number, width: number, height: number): Box
	local function side(n: number): number
		return if n > 0 and n < math.huge then n else 0
	end
	local w, h = side(width), side(height)
	local s = Awareness.GLOW.side * math.min(w, h) * math.clamp(if size == size then size else 0, 0, 1)
	local cu = if u == u then math.clamp(u, -1, 1) else 0
	local cv = if v == v then math.clamp(v, -1, 1) else 0
	local x = math.clamp((cu * 0.5 + 0.5) * w - s / 2, 0, w - s)
	local y = math.clamp((cv * 0.5 + 0.5) * h - s / 2, 0, h - s)
	return { x = x, y = y, w = s, h = s }
end

-- The radar's content around the player, turned so that "up" is where the camera looks.
function Awareness.radar(m: Maze.Maze, pose: Pose, ghosts: { Ghost }, radius: number?): Radar
	local r = radius or Awareness.RADAR_RADIUS
	local cx, cy = math.floor(pose.x + 0.5), math.floor(pose.y + 0.5)
	local sin, cos = math.sin(pose.yaw), math.cos(pose.yaw)
	local function turn(dx: number, dy: number): (number, number)
		-- x grows to the right, y downward (backwards)
		local right = dx * cos - dy * sin
		local back = dx * sin + dy * cos
		return right, back
	end
	local walls: { { x: number, y: number } } = {}
	for dy = -r, r do
		local y = cy + dy
		if y >= 0 and y < m.height then -- nothing is drawn above the top or below the bottom of the maze
			for dx = -r, r do
				local x = cx + dx
				if x < 0 or x >= m.width then
					x = if rowWraps(m, y) then x % m.width else -1 -- off the sides: only a tunnel row continues
				end
				if x >= 0 and dx * dx + dy * dy <= r * r and Maze.kind(m, { x = x, y = y }) == "wall" then
					-- the wall is on its tile, the player is not at the centre of theirs: the radar moves with the player
					local rx, ry = turn(dx - frac(pose.x), dy - frac(pose.y))
					table.insert(walls, { x = rx, y = ry })
				end
			end
		end
	end
	local blips: { Blip } = {}
	for _, g in ghosts do
		local dx, dy = offsetShort(m, pose, g.x, g.y)
		if dx * dx + dy * dy <= (r + 0.5) * (r + 0.5) then
			local x, y = turn(dx, dy)
			table.insert(blips, { x = x, y = y, look = g.look })
		end
	end
	return { radius = r, walls = walls, blips = blips }
end

return Awareness
