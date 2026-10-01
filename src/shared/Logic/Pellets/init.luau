--!strict
-- Pellets: the pellets still to eat in one maze instance. Pure state: which tiles hold a pellet,
-- eating one, putting them all back, and the points and eating pause each kind is worth.
local Maze = require("./Maze")

export type Kind = "pellet" | "power"
export type Pellets = {
	maze: Maze.Maze,
	cells: { [number]: Kind }, -- tile index -> what is still there
	remaining: number,
	total: number,
}

-- one number per kind
export type PerKind = { pellet: number, power: number }
local POINTS: PerKind = { pellet = 10, power = 50 }
local STALL_FRAMES: PerKind = { pellet = 1, power = 3 } -- frames of the arcade's 60 fps

local function perKind(table_: PerKind, kind: Kind): number
	return if kind == "pellet" then table_.pellet else table_.power
end

local Pellets = {}
Pellets.POINTS = table.freeze(POINTS)
Pellets.STALL_FRAMES = table.freeze(STALL_FRAMES)
Pellets.ARCADE_FPS = 60

local function index(p: Pellets, tile: Maze.Tile): number
	local m = p.maze
	if tile.x < 0 or tile.x >= m.width or tile.y < 0 or tile.y >= m.height then
		error(`pellets: tile ({tile.x}, {tile.y}) is out of bounds`, 0)
	end
	return tile.y * m.width + tile.x + 1
end

local function place(p: Pellets, kind: Kind)
	for _, tile in Maze.tiles(p.maze, kind) do
		p.cells[index(p, tile)] = kind
	end
end

local function fill(p: Pellets)
	p.cells = {}
	place(p, "pellet")
	place(p, "power")
end

-- a pellet on every "pellet" and "power" tile of the maze
function Pellets.new(m: Maze.Maze): Pellets
	local p: Pellets = { maze = m, cells = {}, remaining = 0, total = 0 }
	fill(p)
	local n = 0
	for _ in p.cells do
		n += 1
	end
	p.remaining, p.total = n, n
	return p
end

function Pellets.at(p: Pellets, tile: Maze.Tile): Kind?
	return p.cells[index(p, tile)]
end

-- Removes and returns what was on the tile; nil if nothing was.
-- Points for eating one.
function Pellets.points(kind: Kind): number
	return perKind(POINTS, kind)
end

function Pellets.eat(p: Pellets, tile: Maze.Tile): Kind?
	local i = index(p, tile)
	local kind: Kind? = p.cells[i]
	if kind then
		p.cells[i] = nil
		p.remaining -= 1
	end
	return kind
end

function Pellets.remaining(p: Pellets): number
	return p.remaining
end

function Pellets.total(p: Pellets): number
	return p.total
end

function Pellets.reset(p: Pellets)
	fill(p)
	p.remaining = p.total
end

-- What is left, row-major, optionally of one kind.
function Pellets.tiles(p: Pellets, kind: Kind?): { Maze.Tile }
	local out: { Maze.Tile } = {}
	local m = p.maze
	for y = 0, m.height - 1 do
		for x = 0, m.width - 1 do
			local k = p.cells[y * m.width + x + 1]
			if k and (kind == nil or k == kind) then
				table.insert(out, { x = x, y = y })
			end
		end
	end
	return out
end

-- The distance eating stops the player for: `frames` of the arcade's 60 fps at the player's speed.
function Pellets.stallUnits(kind: Kind, speed: number, tickRate: number): number
	return math.floor(speed * perKind(STALL_FRAMES, kind) * tickRate / Pellets.ARCADE_FPS)
end

return Pellets
