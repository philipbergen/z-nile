--!strict
-- f0217 prep E3: what a two-player tick costs. 20 matches x 6,000 ticks, both players busy, reviving at game over.
-- Run from invaders/ with f0216's and this item's prototypes applied:
--   ../zn run --time 120 -- lune run .tracker/issues/f0217/experiments/bench.luau
local TwoPlayer = require("../../../../src/shared/Logic/TwoPlayer")

local MATCHES, TICKS = 20, 6000
local start = os.clock()
local steps = 0
for seed = 1, MATCHES do
	local g = TwoPlayer.new(seed)
	for tick = 1, TICKS do
		local a = { move = if (tick // 150) % 2 == 0 then 1 else -1, fire = tick % 5 == 0 }
		local b = { move = if (tick // 110) % 2 == 0 then -1 else 1, fire = tick % 6 == 0 }
		TwoPlayer.step(g, { a, b })
		steps += 1
		for p = 1, 2 do
			if TwoPlayer.phaseOf(g, p) == "gameover" then
				TwoPlayer.revive(g, p)
			end
		end
	end
end
local secs = os.clock() - start
print(
	string.format(
		"%d steps in %.2f s: %.1f us a step, %.4f %% of a core per match at 60 Hz",
		steps,
		secs,
		secs / steps * 1e6,
		secs / steps * 60 * 100
	)
)
