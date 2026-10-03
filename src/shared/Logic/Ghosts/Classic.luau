--!strict
-- The classic layout's ghost data: where each ghost starts, the corner it scatters to and the junctions
-- where it may not turn up. Keyed by layout id; a maze without an entry has no ghosts.
local Maze = require("../Maze")

export type Name = "blinky" | "pinky" | "inky" | "clyde"
export type Start = { tile: Maze.Tile, heading: Maze.Heading, inHouse: boolean }
export type Data = {
	starts: { [Name]: Start },
	corners: { [Name]: Maze.Tile }, -- scatter targets; they lie outside the maze
	noUp: { Maze.Tile },
	exitX: number, -- the column the ghosts use to pass the door
	doorY: number, -- the door row; the tile above it is where eyes aim
}

local DATA: { [string]: Data } = {
	classic = {
		starts = {
			blinky = { tile = { x = 14, y = 11 }, heading = "W", inHouse = false },
			pinky = { tile = { x = 13, y = 14 }, heading = "S", inHouse = true },
			inky = { tile = { x = 12, y = 14 }, heading = "N", inHouse = true },
			clyde = { tile = { x = 15, y = 14 }, heading = "N", inHouse = true },
		},
		corners = {
			blinky = { x = 25, y = -3 },
			pinky = { x = 2, y = -3 },
			inky = { x = 27, y = 31 },
			clyde = { x = 0, y = 31 },
		},
		noUp = { { x = 12, y = 11 }, { x = 15, y = 11 }, { x = 12, y = 23 }, { x = 15, y = 23 } },
		exitX = 13,
		doorY = 12,
	},
}

local Classic = {}

function Classic.of(m: Maze.Maze): Data?
	return DATA[m.id]
end

return Classic
