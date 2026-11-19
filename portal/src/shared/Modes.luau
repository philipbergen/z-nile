--!strict
-- The play buttons of each title's card (f0208), by its paid-play name (src/shared/Games.luau), in the order they
-- show: PLAY on every card, ARENA on Snake, 2 PLAYERS on Invaders and Asteroids. A new title is one entry here.
local Play = require("./Logic/Play")

local function modes(list: { Play.Mode }): { Play.Mode }
	return table.freeze(list)
end

return table.freeze({
	pickman = modes({ "solo" }),
	snake = modes({ "solo", "arena" }),
	invaders = modes({ "solo", "pair" }),
	asteroids = modes({ "solo", "pair" }),
} :: Play.Modes)
