--!strict
-- f0190: where each ghost is heading: the classic maze's ghost data (the no-up junctions, the scatter corners) and the
-- four personalities' chase targets.
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
-- an open 5x5 plaza: every tile is a junction, so ties are easy to build
local PLAZA = Maze.parse({ ".....", ".....", "..P..", ".....", "....." }, "plaza")

return t.spec("f0190 ghost targets", function(it)
	it("names the four ghosts in a fixed order", function()
		t.expect(Ghosts.NAMES).toEqual({ "blinky", "pinky", "inky", "clyde" })
	end)
	it(
		"the classic maze has four no-up junctions, all of them open to the north; other mazes have none",
		function()
			local tiles = Ghosts.noUpTiles(classic)
			t.expect(tiles)
				.toEqual({ { x = 12, y = 11 }, { x = 15, y = 11 }, { x = 12, y = 23 }, { x = 15, y = 23 } })
			for _, tile in tiles do
				t.expect(table.find(Maze.exits(classic, tile, "ghost"), "N") ~= nil).toBe(true)
			end
			t.expect(Ghosts.noUpTiles(PLAZA)).toEqual({})
		end
	)
	it(
		"each ghost scatters to its own corner outside the maze; a maze without ghost data is refused",
		function()
			t.expect(Ghosts.scatterTile(classic, "blinky")).toEqual({ x = 25, y = -3 })
			t.expect(Ghosts.scatterTile(classic, "pinky")).toEqual({ x = 2, y = -3 })
			t.expect(Ghosts.scatterTile(classic, "inky")).toEqual({ x = 27, y = 31 })
			t.expect(Ghosts.scatterTile(classic, "clyde")).toEqual({ x = 0, y = 31 })
			t.expect(function()
				Ghosts.scatterTile(PLAZA, "blinky")
			end).toThrow("no ghost data")
			t.expect(Ghosts.available(classic)).toBe(true)
			t.expect(Ghosts.available(PLAZA)).toBe(false)
		end
	)
	it("Blinky targets the player's tile", function()
		local c = {
			player = { x = 9, y = 4 },
			heading = "E" :: Maze.Heading,
			blinky = { x = 1, y = 1 },
			self = { x = 1, y = 1 },
		}
		t.expect(Ghosts.chaseTarget(classic, "blinky", c)).toEqual({ x = 9, y = 4 })
	end)
	it("Pinky targets 4 tiles ahead of the player, whichever way the player faces", function()
		local base = { player = { x = 10, y = 5 }, blinky = { x = 0, y = 0 }, self = { x = 0, y = 0 } }
		local function target(h: Maze.Heading): Maze.Tile
			return Ghosts.chaseTarget(
				classic,
				"pinky",
				{ player = base.player, heading = h, blinky = base.blinky, self = base.self }
			)
		end
		t.expect(target("E")).toEqual({ x = 14, y = 5 })
		t.expect(target("W")).toEqual({ x = 6, y = 5 })
		t.expect(target("S")).toEqual({ x = 10, y = 9 })
		t.expect(target("N")).toEqual({ x = 10, y = 1 }) -- exactly ahead: the arcade's extra shift to the left is not copied
	end)
	it("Inky doubles the vector from Blinky to the tile 2 ahead of the player", function()
		local c = {
			player = { x = 10, y = 5 },
			heading = "E" :: Maze.Heading,
			blinky = { x = 6, y = 5 },
			self = { x = 0, y = 0 },
		}
		t.expect(Ghosts.chaseTarget(classic, "inky", c)).toEqual({ x = 18, y = 5 })
		local c2 = {
			player = { x = 10, y = 5 },
			heading = "N" :: Maze.Heading,
			blinky = { x = 12, y = 9 },
			self = { x = 0, y = 0 },
		}
		-- pivot (10,3); 2 * pivot - blinky = (8, -3)
		t.expect(Ghosts.chaseTarget(classic, "inky", c2)).toEqual({ x = 8, y = -3 })
	end)
	it("Clyde targets the player when more than 8 tiles away, and his corner at 8 or closer", function()
		local function target(clydeX: number): Maze.Tile
			return Ghosts.chaseTarget(classic, "clyde", {
				player = { x = 10, y = 5 },
				heading = "E",
				blinky = { x = 0, y = 0 },
				self = { x = clydeX, y = 5 },
			})
		end
		t.expect(target(18)).toEqual({ x = 0, y = 31 }) -- exactly 8 away: close
		t.expect(target(19)).toEqual({ x = 10, y = 5 }) -- 9 away
		t.expect(target(10)).toEqual({ x = 0, y = 31 })
	end)
end)
