--!strict
-- E1 (f0211 prep): do the walls of map k fit, how far does the arena grow, and how long does a roll take?
local Maps = require("@logic/Maps")
local World = require("@logic/World")

local function drawOf(seed: number): (n: number) -> number
	local s = seed % 2147483646 + 1
	return function(n: number): number
		s = (s * 48271) % 2147483647
		return s % n + 1
	end
end

for _, players in { 1, 2, 4, 8, 16, 24 } do
	local line = {}
	local worst = 0
	for _, map in { 2, 5, 10, 15, 20, 30, 40 } do
		local maxSide, t0 = 0, os.clock()
		for seed = 1, 20 do
			local l = Maps.roll(map, players, drawOf(seed))
			maxSide = math.max(maxSide, l.side)
		end
		local ms = (os.clock() - t0) / 20 * 1000
		worst = math.max(worst, ms)
		table.insert(line, `m{map}:{maxSide}`)
	end
	print(
		`players {players} base {Maps.side(players)}: {table.concat(line, " ")}  worst roll {string.format(
			"%.2f",
			worst
		)} ms`
	)
end

-- step cost: 24 snakes alive on map 1, steps over 60 s of play with random turns
for _, players in { 1, 24 } do
	local draw = drawOf(7)
	local w = World.new(players, draw)
	local t0 = os.clock()
	local steps = 0
	for _ = 1, 60 * 30 do
		for id = 1, players do
			if draw(8) == 1 then
				World.turn(w, id, if draw(2) == 1 then "Left" else "Right")
			end
		end
		World.advance(w, 1 / 30, draw)
		steps += 1
	end
	print(
		`players {players}: {steps} ticks of 1/30 s, {string.format("%.3f", (os.clock() - t0) / steps * 1000)} ms a tick, map {w.map}`
	)
end
