--!strict
-- Every title's paid play (f0201): its name, the title its screens print, its two DataStores (live and test) and the
-- ServerScriptService attributes that hold its two Developer Product ids. Every place installs Receipts with this whole
-- list, so a receipt for any title is granted wherever it is processed. A new title is one entry here and two products.
-- Pickman keeps f0145's names (its store, its test store and its two attributes).
return table.freeze({
	table.freeze({
		name = "pickman",
		title = "PICKMAN",
		store = "PaidPlay",
		testStore = "PaidPlayTest",
		play = "PlayProductId",
		revive = "ContinueProductId",
	}),
	table.freeze({
		name = "snake",
		title = "SNAKE",
		store = "SnakePaidPlay",
		testStore = "SnakePaidPlayTest",
		play = "SnakePlayProductId",
		revive = "SnakeReviveProductId",
	}),
	table.freeze({
		name = "invaders",
		title = "INVADERS",
		store = "InvadersPaidPlay",
		testStore = "InvadersPaidPlayTest",
		play = "InvadersPlayProductId",
		revive = "InvadersReviveProductId",
	}),
	table.freeze({
		name = "asteroids",
		title = "ASTEROIDS",
		store = "AsteroidsPaidPlay",
		testStore = "AsteroidsPaidPlayTest",
		play = "AsteroidsPlayProductId",
		revive = "AsteroidsReviveProductId",
	}),
})
