--!strict
-- The portal's games (f0205), one entry each, in the carousel's order. `name` is the game's paid-play title (the
-- arcade's Catalog), `place` its place in the arcade's Places (whose id says whether it is published), and `preview`
-- the parts of its live 3-D preview, in studs within Card.FRAME of the centre. A new game is one entry here.
local Card = require("./Logic/Card")

local function part(shape: Card.Shape, size: { number }, at: { number }, color: { number }): Card.Part
	return table.freeze({
		shape = shape,
		size = table.freeze(size),
		at = table.freeze(at),
		color = table.freeze(table.clone(color)),
	})
end

local YELLOW, WHITE, RED, PINK = { 255, 221, 0 }, { 245, 245, 245 }, { 230, 40, 40 }, { 255, 150, 200 }
local GREEN, DARK, APPLE = { 60, 200, 80 }, { 30, 140, 50 }, { 220, 30, 30 }
local ALIEN, CANNON, BUNKER = { 120, 255, 120 }, { 80, 160, 255 }, { 60, 200, 60 }
local ROCK, SHIP = { 140, 140, 150 }, { 235, 235, 255 }

local LIST: { Card.Entry } = {
	{
		name = "pickman",
		place = "Pickman",
		title = "PICKMAN",
		tagline = "Clear the maze from the inside. Mind the ghosts.",
		preview = {
			part("Ball", { 3, 3, 3 }, { -2, 0, 0 }, YELLOW),
			part("Ball", { 0.6, 0.6, 0.6 }, { 0.5, 0, 0 }, WHITE),
			part("Ball", { 0.6, 0.6, 0.6 }, { 1.7, 0, 0 }, WHITE),
			part("Ball", { 1.2, 1.2, 1.2 }, { 3, 0, 0 }, WHITE),
			part("Block", { 2, 1.6, 2 }, { 0, 0, -2.6 }, RED),
			part("Ball", { 2, 2, 2 }, { 0, 0.8, -2.6 }, RED),
			part("Block", { 2, 1.6, 2 }, { 2.4, 0, 2.6 }, PINK),
			part("Ball", { 2, 2, 2 }, { 2.4, 0.8, 2.6 }, PINK),
		},
	},
	{
		name = "snake",
		place = "Snake",
		title = "SNAKE",
		tagline = "Eat, grow and outlast the walls.",
		preview = {
			part("Block", { 1, 1, 1 }, { -3, -1, 2 }, GREEN),
			part("Block", { 1, 1, 1 }, { -2, -1, 2 }, GREEN),
			part("Block", { 1, 1, 1 }, { -1, -1, 2 }, GREEN),
			part("Block", { 1, 1, 1 }, { 0, -1, 2 }, GREEN),
			part("Block", { 1, 1, 1 }, { 0, -1, 1 }, GREEN),
			part("Block", { 1, 1, 1 }, { 0, -1, 0 }, GREEN),
			part("Block", { 1, 1, 1 }, { 1, -1, 0 }, DARK),
			part("Ball", { 1, 1, 1 }, { 3, -1, 0 }, APPLE),
			part("Block", { 7, 1, 1 }, { 0, -1, -3 }, DARK),
		},
	},
	{
		name = "invaders",
		place = "Invaders",
		title = "INVADERS",
		tagline = "Hold the line against the falling waves.",
		preview = {
			part("Block", { 3, 1, 1 }, { 0, 2, 0 }, ALIEN),
			part("Block", { 5, 1, 1 }, { 0, 1, 0 }, ALIEN),
			part("Block", { 1, 1, 1 }, { -2, 0, 0 }, ALIEN),
			part("Block", { 1, 1, 1 }, { 2, 0, 0 }, ALIEN),
			part("Block", { 3, 1, 2 }, { -2.5, -2, 2 }, BUNKER),
			part("Block", { 3, 1, 2 }, { 2.5, -2, 2 }, BUNKER),
			part("Block", { 1.6, 0.8, 1 }, { 0, -3, 3 }, CANNON),
			part("Cylinder", { 1, 0.4, 0.4 }, { 0, -2.3, 3 }, CANNON),
		},
	},
	{
		name = "asteroids",
		place = "Asteroids",
		title = "ASTEROIDS",
		tagline = "Split the rocks. Dodge the saucers. Stay alive.",
		preview = {
			part("Ball", { 3, 3, 3 }, { -2, 1, -1 }, ROCK),
			part("Ball", { 2, 2, 2 }, { 2, 2, 1 }, ROCK),
			part("Ball", { 1, 1, 1 }, { 2.5, -1.5, -2 }, ROCK),
			part("Ball", { 1, 1, 1 }, { -2.5, -2, 2 }, ROCK),
			part("Block", { 0.8, 0.4, 2 }, { 0, -1, 2 }, SHIP),
			part("Cylinder", { 0.3, 0.3, 0.3 }, { 0, -1, 3.2 }, SHIP),
		},
	},
}

for _, e in LIST do
	table.freeze(e.preview)
	table.freeze(e)
end

return table.freeze({ LIST = table.freeze(LIST) })
