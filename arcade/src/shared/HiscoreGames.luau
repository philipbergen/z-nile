--!strict
-- Each game's boards: the prefix its stores are named from (Hiscores.names; Pickman's "" keeps today's stores and
-- their rows) and what its progress figure, the rows' `level`, counts. A new game adds an entry here and opens its
-- boards with Boards.open(HiscoreGames.<game>.prefix); nothing else changes.
export type Game = { prefix: string, progress: string }

return table.freeze({
	pickman = table.freeze({ prefix = "", progress = "Level" }) :: Game,
	snake = table.freeze({ prefix = "Snake", progress = "Map" }) :: Game,
	invaders = table.freeze({ prefix = "Invaders", progress = "Wave" }) :: Game,
	asteroids = table.freeze({ prefix = "Asteroids", progress = "Wave" }) :: Game,
})
