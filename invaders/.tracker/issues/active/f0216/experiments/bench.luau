--!strict
-- f0216 prep E3: the per-tick cost of one solo run, on the prototype (apply prototype.patch first). Steps 50 runs
-- for 6,000 ticks each (100 s of play), a busy player firing whenever it can, reviving at game over.
local Classic = require("@logic/Classic")

local RUNS, TICKS = 50, 6000
local games = {}
for i = 1, RUNS do
	games[i] = Classic.new(i)
end
local t0 = os.clock()
for tick = 1, TICKS do
	local input = { move = if (tick // 150) % 2 == 0 then 1 else -1, fire = true }
	for _, g in games do
		Classic.step(g, input)
		if g.phase == "gameover" then
			Classic.revive(g)
		end
	end
end
local elapsed = os.clock() - t0
local steps = RUNS * TICKS
print(
	string.format(
		"%d steps in %.3f s: %.2f us a step; one run at 60 Hz costs %.4f%% of a core",
		steps,
		elapsed,
		elapsed / steps * 1e6,
		elapsed / steps * 60 * 100
	)
)
