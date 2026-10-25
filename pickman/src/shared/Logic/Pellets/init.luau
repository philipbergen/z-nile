--!strict
-- Pellets: the pellets still to eat in one maze instance. Pure state: which tiles hold a pellet,
-- eating one, putting them all back, and the points and eating pause each kind is worth.
local Maze = require("./Maze")

export type Kind = "pellet" | "power"
export type Slot = { x: number, y: number, kind: Kind }
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

-- Points for eating one.
function Pellets.points(kind: Kind): number
	return perKind(POINTS, kind)
end

-- Removes and returns what was on the tile; nil if nothing was.
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

-- The wire order of each maze's pellets, computed once per maze. Private: callers get copies.
local slotCache: { [Maze.Maze]: { Slot } } = setmetatable({}, { __mode = "k" }) :: any

local function slotsOf(m: Maze.Maze): { Slot }
	local cached = slotCache[m]
	if cached == nil then
		local list: { Slot } = {}
		for y = 0, m.height - 1 do
			for x = 0, m.width - 1 do
				local k = Maze.kind(m, { x = x, y = y })
				if k == "pellet" or k == "power" then
					table.insert(list, { x = x, y = y, kind = k :: Kind })
				end
			end
		end
		slotCache[m] = list
		return list
	end
	return cached
end

-- Every pellet and power tile of the layout, row-major: the order of the bits in a code. A deep copy.
function Pellets.slots(m: Maze.Maze): { Slot }
	local out: { Slot } = {}
	for i, slot in slotsOf(m) do
		out[i] = { x = slot.x, y = slot.y, kind = slot.kind }
	end
	return out
end

Pellets.ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local VALUE: { [string]: number } = {}
for i = 1, #Pellets.ALPHABET do
	VALUE[string.sub(Pellets.ALPHABET, i, i)] = i - 1
end

-- What is left, as text: one bit per slot (1 = still there), six to a base64url character. Slot i is
-- bit (i - 1) % 6 of character (i - 1) // 6 + 1; the unused bits of the last character are 0.
function Pellets.encode(p: Pellets): string
	local slots = slotsOf(p.maze)
	local width = p.maze.width
	local chars: { string } = {}
	local value = 0
	for i, slot in slots do
		if p.cells[slot.y * width + slot.x + 1] then
			value += bit32.lshift(1, (i - 1) % 6)
		end
		if i % 6 == 0 or i == #slots then
			table.insert(chars, string.sub(Pellets.ALPHABET, value + 1, value + 1))
			value = 0
		end
	end
	return table.concat(chars)
end

-- Per slot, whether the pellet is still there. Refuses a code that can't come from this maze: a wrong
-- length, a character outside the alphabet, or a set bit past the last slot.
function Pellets.decode(m: Maze.Maze, code: string): { boolean }
	local n = #slotsOf(m)
	local want = (n + 5) // 6
	if #code ~= want then
		error(`pellets: the code has {#code} characters, this maze needs {want}`, 0)
	end
	local present: { boolean } = {}
	for c = 1, want do
		local value = VALUE[string.sub(code, c, c)]
		if value == nil then
			error(`pellets: character {c} of the code is not base64url`, 0)
		end
		for b = 0, 5 do
			local i = (c - 1) * 6 + b + 1
			local set = bit32.btest(value, bit32.lshift(1, b))
			if i <= n then
				present[i] = set
			elseif set then
				error(`pellets: bit {b} of the last character is past the last slot`, 0)
			end
		end
	end
	return present
end

-- The distance eating stops the player for: `frames` of the arcade's 60 fps at the player's speed.
function Pellets.stallUnits(kind: Kind, speed: number, tickRate: number): number
	return math.floor(speed * perKind(STALL_FRAMES, kind) * tickRate / Pellets.ARCADE_FPS)
end

return Pellets
