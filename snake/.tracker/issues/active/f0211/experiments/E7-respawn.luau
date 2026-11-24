--!strict
-- E7 (f0211 prep, design review 001 F5): what does one respawn (World.safest) and one apple placement cost at the
-- largest arena and late maps? Pass: one World.safest on map 20 with 24 snakes under 5 ms, one apple placement under
-- 1 ms, in Lune.
local Maps = require("@logic/Maps")
local World = require("@logic/World")

local function drawOf(seed: number): (n: number) -> number
	local s = seed % 2147483646 + 1
	return function(n: number): number
		s = (s * 48271) % 2147483647
		return s % n + 1
	end
end

for _, case in { { 24, 1 }, { 24, 10 }, { 24, 20 }, { 24, 30 }, { 8, 20 }, { 1, 20 } } do
	local players, map = case[1], case[2]
	local d = drawOf(players * 100 + map)
	local w = World.new(players, d)
	World.start(w, Maps.roll(map, players, d), d)
	w.snakes[1].state = "dying"
	local n = 20
	local t0 = os.clock()
	for _ = 1, n do
		World.safest(w, 1)
	end
	local safest = (os.clock() - t0) / n * 1000
	-- the placement alone: top up from empty, players + 1 apples, per apple
	local t2 = os.clock()
	for _ = 1, n do
		World.start(w, w.layout, d)
	end
	local start = (os.clock() - t2) / n * 1000
	print(
		`{players} players, map {map}, side {w.layout.side}: safest {string.format("%.2f", safest)} ms; a map start with {players + 1} apples {string.format(
			"%.2f",
			start
		)} ms ({string.format("%.3f", start / (players + 1))} ms an apple)`
	)
end
