--!strict
-- E1 (f0100): a cardinal line through player-passable tiles on Maze.parse fixtures: the rules of Blaster.ray.
-- A mutant that keeps the blocking tile fails the wall case.
local Maze = require("@logic/Maze")

type Tile = Maze.Tile
type Heading = Maze.Heading

local function same(a: Tile, b: Tile): boolean
	return a.x == b.x and a.y == b.y
end

local function ray(m: Maze.Maze, from: Tile, heading: Heading, includeBlocked: boolean): { Tile }
	local out: { Tile } = {}
	local cursor = from
	for _ = 1, m.width do
		local nextTile = Maze.neighbor(m, cursor, heading)
		if same(nextTile, from) then
			break
		end
		if not Maze.passable(m, nextTile, "player") then
			if includeBlocked then
				table.insert(out, nextTile)
			end
			break
		end
		table.insert(out, nextTile)
		cursor = nextTile
	end
	return out
end

local function clear(m: Maze.Maze, from: Tile, to: Tile, includeBlocked: boolean): boolean
	if same(from, to) then
		return true
	end
	if from.x ~= to.x and from.y ~= to.y then
		return false
	end
	local headings: { Heading } = if from.y == to.y then { "E", "W" } else { "N", "S" }
	for _, h in headings do
		for _, tile in ray(m, from, h, includeBlocked) do
			if same(tile, to) then
				return true
			end
		end
	end
	return false
end

local function expect(name: string, ok: boolean)
	if not ok then
		error("FAIL " .. name, 0)
	end
	print("PASS " .. name)
end

local corridor = Maze.parse({ "#####", "# P #", "#####" }, "corridor")
local east = ray(corridor, { x = 2, y = 1 }, "E", false)
expect("open tile then a wall stops before the wall", #east == 1 and east[1].x == 3 and east[1].y == 1)
expect("west from spawn hits the empty tile and stops", #ray(corridor, { x = 2, y = 1 }, "W", false) == 1)

local blocked = ray(corridor, { x = 2, y = 1 }, "E", true)
local mutantKeepsWall = #blocked == 2 and blocked[2].x == 4
expect("mutant that includes the wall is a different result", mutantKeepsWall)
local mutantWouldFail = #blocked == 1
expect("wall case fails if the blocking tile is kept", not mutantWouldFail)

local door = Maze.parse({ "#####", "#P  #", "#-  #", "#H  #", "#####" }, "door")
expect("a door stops the ray before the door tile", #ray(door, { x = 1, y = 1 }, "S", false) == 0)
expect("the house beyond a door is not in sight", not clear(door, { x = 1, y = 1 }, { x = 1, y = 3 }, false))
expect("the door tile itself is not in sight", not clear(door, { x = 1, y = 1 }, { x = 1, y = 2 }, false))

local wrap = Maze.parse({ "#####", "#P  #", "     ", "#####" }, "wrap")
local around = ray(wrap, { x = 2, y = 2 }, "E", false)
expect("an open row wraps and does not repeat the start", #around == 4)
expect("the tile across the wrap is in sight", clear(wrap, { x = 2, y = 2 }, { x = 0, y = 2 }, false))
expect("a diagonal is never in sight", not clear(wrap, { x = 1, y = 1 }, { x = 2, y = 2 }, false))
expect("the origin tile is in sight of itself", clear(wrap, { x = 2, y = 2 }, { x = 2, y = 2 }, false))

print("E1 ok")
