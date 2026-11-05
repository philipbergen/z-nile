--!strict
-- Blaster: the ghost blaster's shots, engine-free (R0035, f0100). Eating a ghost may drop a shot (a seeded roll),
-- the player holds at most MAX_SHOTS, and a shot goes along the maze grid from the player's tile in one of the
-- four headings: the first active ghost on that line is hit. Walls, doors and the house stop it; a wrapping row
-- carries it round once. Session owns the rules of when a shot is taken and what a hit does.
local Maze = require("./Maze")

export type Blaster = {
	shots: number, -- 0..MAX_SHOTS
	rng: number, -- the drop roll's generator state (Park-Miller), in 1..MODULUS-1
}
-- One ghost as the shot sees it: the tile it occupies, and whether it can be hit (only an active ghost can).
export type Target = { tile: Maze.Tile, active: boolean }

local MODULUS = 2147483647
local INTENTS: { [Maze.Heading]: string } = { N = "FireN", E = "FireE", S = "FireS", W = "FireW" }

local Blaster = {}
Blaster.MAX_SHOTS = 3
Blaster.DROP_PERCENT = 50 -- the chance that eating a ghost drops a shot (a tuning constant; user, 2026-10-17)
Blaster.INTENTS = table.freeze(INTENTS)

-- A seed's own stream: not the ghosts' (Ghosts seeds its generator with the same session seed), so the drops and
-- the frightened ghosts' wandering do not move together.
function Blaster.new(seed: number): Blaster
	local s = math.floor(seed)
	if s ~= s or math.abs(s) == math.huge then
		s = 0
	end
	return { shots = 0, rng = (s * 48271 + 11) % (MODULUS - 1) + 1 }
end

-- A ghost was eaten: roll for a drop. True when a shot was gained; a drop while full is lost. The roll is made
-- either way, so the drops depend only on how many ghosts were eaten, not on what was held.
function Blaster.drop(b: Blaster): boolean
	b.rng = (b.rng * 16807) % MODULUS
	local dropped = b.rng % 100 < Blaster.DROP_PERCENT
	if dropped and b.shots < Blaster.MAX_SHOTS then
		b.shots += 1
		return true
	end
	return false
end

-- A shot granted outright (f0126's blaster boon): true when it was gained, false (wasted) while full. No roll.
function Blaster.gain(b: Blaster): boolean
	if b.shots >= Blaster.MAX_SHOTS then
		return false
	end
	b.shots += 1
	return true
end

-- Spends one shot. False (and nothing spent) when there is none.
function Blaster.spend(b: Blaster): boolean
	if b.shots <= 0 then
		return false
	end
	b.shots -= 1
	return true
end

-- A new run: no shots. The generator runs on.
function Blaster.reset(b: Blaster)
	b.shots = 0
end

-- The wire form of a shot along `h`, sent on the Intent remote beside the movement intents.
function Blaster.intent(h: Maze.Heading): string
	return INTENTS[h]
end

-- The heading of a fire intent, or nil for anything that is not exactly one.
function Blaster.heading(raw: any): Maze.Heading?
	if type(raw) ~= "string" then
		return nil
	end
	for _, h: Maze.Heading in Maze.HEADINGS do
		if raw == INTENTS[h] then
			return h
		end
	end
	return nil
end

-- The tiles a shot from `from` along `h` passes: `from` itself first, then each tile ahead while it is passable
-- for the player (a wall, a door or the house stops it, and is not included). Across a wrapping row it goes on
-- from the other side, and stops before it would come back to `from`.
function Blaster.ray(m: Maze.Maze, from: Maze.Tile, h: Maze.Heading): { Maze.Tile }
	local out: { Maze.Tile } = { { x = from.x, y = from.y } }
	local cursor = from
	for _ = 1, m.width + m.height do
		local nextTile = (Maze.neighbor(m, cursor, h))
		if nextTile.x == from.x and nextTile.y == from.y then
			break
		end
		if not Maze.passable(m, nextTile, "player") then
			break
		end
		table.insert(out, nextTile)
		cursor = nextTile
	end
	return out
end

-- Which target a shot from `from` along `h` hits: the index of the first active one on the ray, nearest first;
-- on one tile, the lowest index. Nil for a miss. Inactive targets (in the house, leaving it, eyes) don't stop it.
function Blaster.target(m: Maze.Maze, from: Maze.Tile, h: Maze.Heading, targets: { Target }): number?
	for _, tile in Blaster.ray(m, from, h) do
		for i, target in targets do
			if target.active and target.tile.x == tile.x and target.tile.y == tile.y then
				return i
			end
		end
	end
	return nil
end

return Blaster
