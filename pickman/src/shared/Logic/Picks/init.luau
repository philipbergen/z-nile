--!strict
-- Picks: risky wall picks (f0126), engine-free. A few interior walls are marked (gold); the player stands at one
-- and picks it for as long as a ghost takes to walk PACES tiles, and a finished pick opens that wall and rolls one
-- of the boons, each as likely as the next. Session owns when a pick starts, what wastes it and what a boon does;
-- this holds the marks, the rolls and the arithmetic.
local Maze = require("./Maze")
local Movement = require("./Movement")

export type Boon = "jumps" | "fastpick" | "pill" | "longpill" | "shot" | "pellets"
export type Picks = {
	marked: { Maze.Tile }, -- the walls that can be picked now, in the order they were marked
	fast: number, -- faster picks banked (the "fastpick" boon): the next pick that finishes spends one
	rng: number, -- the generator state (Park-Miller), in 1..MODULUS-1
}

local MODULUS = 2147483647
local BOONS: { Boon } = { "jumps", "fastpick", "pill", "longpill", "shot", "pellets" }

local Picks = {}
Picks.INTENT = "Pick" -- the wire string on the Intent remote
Picks.MARKED = 3 -- marked walls at a time: a finished pick marks the next at once (user, 2026-10-25)
Picks.PACES = 10 -- a pick lasts as long as a hunting ghost takes to walk this many tiles (user, 2026-10-25)
Picks.BOONS = table.freeze(BOONS)
Picks.LONG_PILL_FACTOR = 2 -- the long ghost pill: a power pellet of this many times the level's time

function Picks.isIntent(raw: any): boolean
	return raw == Picks.INTENT
end

-- Its own stream from the session seed: not the ghosts' and not the blaster's.
function Picks.new(seed: number): Picks
	local s = math.floor(seed)
	if s ~= s or math.abs(s) == math.huge then
		s = 0
	end
	return { marked = {}, fast = 0, rng = (s * 69621 + 7) % (MODULUS - 1) + 1 }
end

local function roll(p: Picks, n: number): number
	p.rng = (p.rng * 48271) % MODULUS
	return p.rng % n + 1
end

-- May this tile be marked? An interior wall (not on the outer edge), with no door or house tile among its eight
-- neighbours (the ghost house stays shut), next to a tile the player can walk (so it can be stood at).
function Picks.pickable(m: Maze.Maze, tile: Maze.Tile): boolean
	local x, y = tile.x, tile.y
	if x < 1 or y < 1 or x > m.width - 2 or y > m.height - 2 or Maze.kind(m, tile) ~= "wall" then
		return false
	end
	for dy = -1, 1 do
		for dx = -1, 1 do
			local k = Maze.kind(m, { x = x + dx, y = y + dy })
			if k == "door" or k == "house" then
				return false
			end
		end
	end
	for _, h: Maze.Heading in Maze.HEADINGS do
		if Maze.passable(m, (Maze.neighbor(m, tile, h)), "player") then
			return true
		end
	end
	return false
end

function Picks.isMarked(p: Picks, tile: Maze.Tile): boolean
	for _, t in p.marked do
		if t.x == tile.x and t.y == tile.y then
			return true
		end
	end
	return false
end

-- Every pickable tile not already marked, row-major.
function Picks.candidates(p: Picks, m: Maze.Maze): { Maze.Tile }
	local out: { Maze.Tile } = {}
	for y = 1, m.height - 2 do
		for x = 1, m.width - 2 do
			local tile = { x = x, y = y }
			if Picks.pickable(m, tile) and not Picks.isMarked(p, tile) then
				table.insert(out, tile)
			end
		end
	end
	return out
end

-- Marks walls until MARKED are marked (or no candidate is left), each a seeded roll among the candidates. Returns
-- the tiles it marked.
function Picks.mark(p: Picks, m: Maze.Maze): { Maze.Tile }
	local added: { Maze.Tile } = {}
	while #p.marked < Picks.MARKED do
		local options = Picks.candidates(p, m)
		if #options == 0 then
			break
		end
		local tile = options[roll(p, #options)]
		table.insert(p.marked, tile)
		table.insert(added, tile)
	end
	return added
end

-- A fresh maze (a new level or a new run): the old marks go and new ones are rolled. The generator runs on.
function Picks.reset(p: Picks, m: Maze.Maze)
	p.marked = {}
	Picks.mark(p, m)
end

-- A finished pick: the wall is no longer marked.
function Picks.unmark(p: Picks, tile: Maze.Tile)
	for i, t in p.marked do
		if t.x == tile.x and t.y == tile.y then
			table.remove(p.marked, i)
			return
		end
	end
end

-- The marked wall next to `tile` that a player standing there facing `heading` would pick: ahead first, then left,
-- right and behind. Nil when none is next to it.
function Picks.wallBeside(p: Picks, m: Maze.Maze, tile: Maze.Tile, heading: Maze.Heading): Maze.Tile?
	for _, h: Maze.Heading in { heading, Maze.left(heading), Maze.right(heading), Maze.opposite(heading) } do
		local n = (Maze.neighbor(m, tile, h))
		if Picks.isMarked(p, n) then
			return n
		end
	end
	return nil
end

-- Steps a pick takes: PACES tiles at `ghostSpeed` units a tick, rounded up; a fast pick takes half of that, rounded
-- up. At least 1.
function Picks.ticks(ghostSpeed: number, fast: boolean): number
	local whole = math.ceil(Picks.PACES * Movement.UNITS / math.max(1, ghostSpeed))
	return math.max(1, if fast then math.ceil(whole / 2) else whole)
end

-- The boon a finished pick grants: one of BOONS, each with the same chance.
function Picks.roll(p: Picks): Boon
	return BOONS[roll(p, #BOONS)]
end

return Picks
