--!strict
-- E2: Ghosts.eat pays the chain and sets eyes. A homeward shot must not call it when the ghost is not frightened.
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")

local set = Ghosts.new(Maze.layout("classic"), 1, { start = "active" })
local before = set.chain
local points = Ghosts.eat(set, "blinky")
local g = Ghosts.ghost(set, "blinky")
assert(points == 200, "points")
assert(set.chain == before + 1, "chain")
assert(g.status == "eyes", "eyes")
assert(g.frightened == false, "not frightened")
print("E2 ok: eat pays 200, chain + 1, status eyes")
