--!strict
-- Maze: the tile grid, its text format, and the coordinate and heading conventions every other
-- feature shares. Pure and read-only.
--
-- Tile coordinates { x, y } are 0-based: x is the column, y the row, origin at the top-left
-- character. Headings: N is up the text (-y), E is right (+x), S is down (+y), W is left (-x).
-- Every edge wraps: stepping off one edge lands on the opposite tile of the same row or column.
--
-- Text format: '#' wall, ' ' empty, '.' pellet, 'o' power pellet, 'P' spawn (exactly one),
-- '-' ghost door, 'H' ghost house. Doors and the house are passable only for ghosts.
local Layouts = require("@self/Layouts")

export type Heading = "N" | "E" | "S" | "W"
export type Tile = { x: number, y: number }
export type Kind = "wall" | "empty" | "pellet" | "power" | "spawn" | "door" | "house"
export type Agent = "player" | "ghost"
export type Maze = {
	id: string,
	width: number,
	height: number,
	spawn: Tile,
}

local HEADINGS: { Heading } = { "N", "E", "S", "W" }
local LEFT: { [Heading]: Heading } = { N = "W", W = "S", S = "E", E = "N" }
local RIGHT: { [Heading]: Heading } = { N = "E", E = "S", S = "W", W = "N" }
local OPPOSITE: { [Heading]: Heading } = { N = "S", S = "N", E = "W", W = "E" }
local DX: { [Heading]: number } = { N = 0, E = 1, S = 0, W = -1 }
local DY: { [Heading]: number } = { N = -1, E = 0, S = 1, W = 0 }

local KINDS: { [string]: Kind } = {
	["#"] = "wall",
	[" "] = "empty",
	["."] = "pellet",
	["o"] = "power",
	["P"] = "spawn",
	["-"] = "door",
	["H"] = "house",
}

-- The grids are private: row-major, index y * width + x + 1. Keyed by the frozen maze.
local grids: { [Maze]: { Kind } } = setmetatable({}, { __mode = "k" }) :: any
local cache: { [string]: Maze } = {}

local Maze = {}
Maze.HEADINGS = table.freeze(HEADINGS)
Maze.DEFAULT = "classic"

local function fail(problem: string): never
	error(`maze: {problem}`, 0)
end

local function gridOf(m: Maze): { Kind }
	local grid = grids[m]
	if grid == nil then
		error("maze: not a maze made by Maze.parse or Maze.layout", 0)
	end
	return grid
end

function Maze.kind(m: Maze, tile: Tile): Kind
	local x, y = tile.x, tile.y
	if x < 0 or y < 0 or x >= m.width or y >= m.height or x ~= math.floor(x) or y ~= math.floor(y) then
		fail(`out of bounds at ({x}, {y})`)
	end
	return gridOf(m)[y * m.width + x + 1]
end

function Maze.passable(m: Maze, tile: Tile, agent: Agent): boolean
	local kind = Maze.kind(m, tile)
	if kind == "wall" then
		return false
	end
	if kind == "door" or kind == "house" then
		return agent == "ghost"
	end
	return true
end

function Maze.delta(h: Heading): (number, number)
	return DX[h], DY[h]
end

function Maze.left(h: Heading): Heading
	return LEFT[h]
end

function Maze.right(h: Heading): Heading
	return RIGHT[h]
end

function Maze.opposite(h: Heading): Heading
	return OPPOSITE[h]
end

function Maze.neighbor(m: Maze, tile: Tile, h: Heading): (Tile, boolean)
	local nx, ny = tile.x + DX[h], tile.y + DY[h]
	local wrapped = nx < 0 or nx >= m.width or ny < 0 or ny >= m.height
	return { x = nx % m.width, y = ny % m.height }, wrapped
end

function Maze.exits(m: Maze, tile: Tile, agent: Agent): { Heading }
	local out: { Heading } = {}
	for _, h: Heading in HEADINGS do
		if Maze.passable(m, (Maze.neighbor(m, tile, h)), agent) then
			table.insert(out, h)
		end
	end
	return out
end

function Maze.isJunction(m: Maze, tile: Tile, agent: Agent): boolean
	return #Maze.exits(m, tile, agent) > 2
end

function Maze.tiles(m: Maze, kind: Kind): { Tile }
	local grid = gridOf(m)
	local out: { Tile } = {}
	for y = 0, m.height - 1 do
		for x = 0, m.width - 1 do
			if grid[y * m.width + x + 1] == kind then
				table.insert(out, { x = x, y = y })
			end
		end
	end
	return out
end

-- Every tile the agent can pass that a walk from the spawn cannot reach; the first one, row-major.
local function firstUnreachable(m: Maze, agent: Agent): Tile?
	local seen: { [number]: boolean } = { [m.spawn.y * m.width + m.spawn.x + 1] = true }
	local queue: { Tile } = { m.spawn }
	local head = 1
	while head <= #queue do
		local tile = queue[head]
		head += 1
		for _, h: Heading in HEADINGS do
			local n = Maze.neighbor(m, tile, h)
			local key = n.y * m.width + n.x + 1
			if not seen[key] and Maze.passable(m, n, agent) then
				seen[key] = true
				table.insert(queue, n)
			end
		end
	end
	for y = 0, m.height - 1 do
		for x = 0, m.width - 1 do
			local tile = { x = x, y = y }
			if Maze.passable(m, tile, agent) and not seen[y * m.width + x + 1] then
				return tile
			end
		end
	end
	return nil
end

function Maze.parse(rows: { string }, id: string?): Maze
	-- 1. size
	local first = rows[1]
	if first == nil or first == "" then
		fail("empty")
	end
	local width, height = #first, #rows

	-- 2. equal widths, 3. known characters, 4. exactly one spawn
	local grid: { Kind } = {}
	local spawns: { Tile } = {}
	for y = 0, height - 1 do
		local row = rows[y + 1]
		if type(row) ~= "string" then
			fail(`row {y} is not a string`)
		end
		if #row ~= width then
			fail(`row {y} has width {#row}, expected {width}`)
		end
		for x = 0, width - 1 do
			local c = string.sub(row, x + 1, x + 1)
			local found: Kind? = KINDS[c]
			if found == nil then
				fail(`unknown character '{c}' at ({x}, {y})`)
			end
			local kind: Kind = found :: Kind
			grid[y * width + x + 1] = kind
			if kind == "spawn" then
				table.insert(spawns, { x = x, y = y })
			end
		end
	end
	if #spawns ~= 1 then
		fail(`expected exactly one spawn 'P', found {#spawns}`)
	end

	local m: Maze = table.freeze({
		id = id or "custom",
		width = width,
		height = height,
		spawn = table.freeze(spawns[1]),
	})
	grids[m] = grid

	-- 5. open edges: walking off a walkable edge tile must not wrap into a wall
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local onXEdge, onYEdge = x == 0 or x == width - 1, y == 0 or y == height - 1
			if (onXEdge or onYEdge) and grid[y * width + x + 1] ~= "wall" then
				local wrapsToWall = (onXEdge and grid[y * width + (width - 1 - x) + 1] == "wall")
					or (onYEdge and grid[(height - 1 - y) * width + x + 1] == "wall")
				if wrapsToWall then
					fail(`open edge at ({x}, {y})`)
				end
			end
		end
	end

	-- 6. the spawn leads somewhere
	if #Maze.exits(m, m.spawn, "player") == 0 then
		fail(`spawn at ({m.spawn.x}, {m.spawn.y}) has no exit`)
	end

	-- 7. reachability: the player first, then ghosts
	for _, agent: Agent in { "player", "ghost" } :: { Agent } do
		local lost = firstUnreachable(m, agent)
		if lost then
			fail(`tile ({lost.x}, {lost.y}) is unreachable for the {agent} from the spawn`)
		end
	end
	return m
end

function Maze.layout(layoutId: string): Maze
	local cached = cache[layoutId]
	if cached then
		return cached
	end
	local rows = Layouts[layoutId]
	if rows == nil then
		fail(`unknown layout '{layoutId}'`)
	end
	local m = Maze.parse(rows, layoutId)
	cache[layoutId] = m
	return m
end

return Maze
