--!strict
-- f0217 prep E4: how many ticks each wave's fly-in takes, paired and lone, waves 1 to 9. Run from invaders/ with
-- f0216's and this item's prototypes applied:
--   ../zn run --time 60 -- lune run .tracker/issues/f0217/experiments/flyin-ticks.luau
local Formation = require("../../../../src/shared/Logic/Formation")
local TwoPlayer = require("../../../../src/shared/Logic/TwoPlayer")

local function clearAll(g: TwoPlayer.Match)
	for _, side in g.sides do
		local f = side.run.formation
		for row = 1, f.config.rows do
			for col = 1, f.config.cols do
				Formation.kill(f, row, col)
			end
		end
	end
	g.flyers = {}
end

for _, lone in { false, true } do
	local g = TwoPlayer.new(1)
	if lone then
		TwoPlayer.retire(g, 2)
	end
	for _ = 1, 9 do
		local n = 0
		while g.phase ~= "playing" do
			TwoPlayer.step(g, nil)
			n += 1
		end
		print(if lone then "lone" else "pair", "wave", g.wave, "formed after", n, "ticks")
		clearAll(g)
		while g.phase ~= "flyin" do
			TwoPlayer.step(g, nil)
		end
	end
end
