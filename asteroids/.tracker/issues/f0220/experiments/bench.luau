--!strict
-- f0220 prep, E3: what a tick costs. 50 runs of 6,000 ticks each (100 s of play), a busy player (turning,
-- thrusting, firing every few ticks, a hyperspace jump now and then), each started again at its end.
-- Run from asteroids/, with the prototype applied: ./zn run --time 120 -- lune run .tracker/issues/f0220/experiments/bench.luau
local Classic = require("@logic/Classic")

local RUNS, TICKS = 50, 6000
local steps, events, overs, maxRocks, waves = 0, 0, 0, 0, 0
local t0 = os.clock()
for seed = 1, RUNS do
	local g = Classic.new(seed)
	for tick = 1, TICKS do
		local input = {
			turn = if tick % 90 < 30 then 1 elseif tick % 90 < 45 then -1 else 0,
			thrust = tick % 50 < 10,
			fire = tick % 6 == 0,
			hyperspace = tick % 1500 == 0,
		}
		local e = Classic.step(g, input)
		steps += 1
		events += #e
		if #g.rocks > maxRocks then
			maxRocks = #g.rocks
		end
		if g.phase == "gameover" then
			overs += 1
			waves = math.max(waves, g.wave)
			g = Classic.new(seed * 1000 + tick)
		end
	end
	waves = math.max(waves, g.wave)
end
local dt = os.clock() - t0
print(
	string.format(
		"%d steps in %.3f s: %.2f us a step, %.4f %% of a core per run at 60 Hz",
		steps,
		dt,
		dt / steps * 1e6,
		dt / steps * 60 * 100
	)
)
print(
	string.format(
		"events %d, runs ended %d, most rocks at once %d, highest wave %d",
		events,
		overs,
		maxRocks,
		waves
	)
)
