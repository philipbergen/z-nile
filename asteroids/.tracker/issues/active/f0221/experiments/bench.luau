--!strict
-- f0221 prep E3: what a two-player tick costs. 20 matches x 6,000 ticks, both players busy (turning, thrusting,
-- firing and jumping now and then), each revived once at the end of their run, restarted at the match's end.
-- Run from asteroids/ with both prototypes applied: ../zn run --time 120 -- lune run .tracker/issues/f0221/experiments/bench.luau
local TwoPlayer = require("@logic/TwoPlayer")

local function input(tick: number, slot: number)
	local k = tick + slot * 37
	return {
		turn = if k % 90 < 30 then 1 elseif k % 90 < 45 then -1 else 0,
		thrust = k % 50 < 10,
		fire = k % (5 + slot) == 0,
		hyperspace = k % 1500 == 0,
	}
end

local steps, most = 0, 0
local start = os.clock()
for seed = 1, 20 do
	local m = TwoPlayer.new(seed)
	local revived = { false, false }
	for tick = 1, 6000 do
		TwoPlayer.step(m, { input(tick, 1), input(tick, 2) })
		steps += 1
		most = math.max(most, #m.rocks)
		for slot = 1, 2 do
			if m.pilots[slot].phase == "gameover" and not revived[slot] then
				revived[slot] = TwoPlayer.revive(m, slot)
			end
		end
		if m.phase == "gameover" then
			m = TwoPlayer.new(seed + 100 * tick)
			revived = { false, false }
		end
	end
end
local took = os.clock() - start
print(
	string.format(
		"%d steps in %.2f s, %.1f us a step, %.3f%% of a core per match at 60 Hz; at most %d rocks",
		steps,
		took,
		took / steps * 1e6,
		took / steps * 60 * 100,
		most
	)
)
