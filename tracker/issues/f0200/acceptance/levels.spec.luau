--!strict
-- f0200: the ghost columns of the Levels table (Pittman's Table A.1 and A.2), the slower-ghosts tuning
-- factor, and the scatter/chase timetable in ticks.
local Levels = require("@logic/Levels")
local t = require("@tests/lib/t")

return t.spec("f0200 Levels ghost columns", function(it)
	it(
		"ghost speeds are the table's shares of the arcade maximum, relative to level 1's player (80%)",
		function()
			local l1, l2, l4, l5, l20, l21 =
				Levels.row(1).ghost,
				Levels.row(2).ghost,
				Levels.row(4).ghost,
				Levels.row(5).ghost,
				Levels.row(20).ghost,
				Levels.row(21).ghost
			t.expect(l1.speedFactor).toBeNear(0.75 / 0.8, 1e-12)
			t.expect(l1.tunnelFactor).toBeNear(0.4 / 0.8, 1e-12)
			t.expect(l1.frightFactor).toBeNear(0.5 / 0.8, 1e-12)
			for _, g in { l2, l4 } do
				t.expect(g.speedFactor).toBeNear(0.85 / 0.8, 1e-12)
				t.expect(g.tunnelFactor).toBeNear(0.45 / 0.8, 1e-12)
				t.expect(g.frightFactor).toBeNear(0.55 / 0.8, 1e-12)
			end
			for _, g in { l5, l20, l21 } do
				t.expect(g.speedFactor).toBeNear(0.95 / 0.8, 1e-12)
				t.expect(g.tunnelFactor).toBeNear(0.5 / 0.8, 1e-12)
				t.expect(g.frightFactor).toBeNear(0.6 / 0.8, 1e-12)
			end
			t.expect(Levels.row(50).ghost).toEqual(l21)
		end
	)

	it("ghostSpeed is whole units per tick from level 1's player speed", function()
		t.expect(Levels.ghostSpeed(30, 1, "normal", 1)).toBe(28) -- 28.125
		t.expect(Levels.ghostSpeed(30, 1, "tunnel", 1)).toBe(15)
		t.expect(Levels.ghostSpeed(30, 1, "frightened", 1)).toBe(19) -- 18.75
		t.expect(Levels.ghostSpeed(30, 5, "normal", 1)).toBe(36) -- 35.625
		t.expect(Levels.ghostSpeed(30, 2, "normal", 1)).toBe(32) -- 31.875
	end)

	it("eyes run at twice level 1's player speed, whatever the level or the tuning", function()
		t.expect(Levels.EYES_FACTOR).toBe(2)
		t.expect(Levels.ghostSpeed(30, 1, "eyes", 1)).toBe(60)
		t.expect(Levels.ghostSpeed(30, 9, "eyes", 0.5)).toBe(60)
	end)

	it(
		"the tuning factor scales hunting and frightened speeds, never goes below 1 unit, and defaults to the classic 1",
		function()
			t.expect(Levels.GHOST_TUNING).toBe(1)
			t.expect(Levels.ghostSpeed(30, 1, "normal")).toBe(28)
			t.expect(Levels.ghostSpeed(30, 1, "normal", 0.5)).toBe(14)
			t.expect(Levels.ghostSpeed(30, 1, "frightened", 0.5)).toBe(9)
			t.expect(Levels.ghostSpeed(30, 1, "tunnel", 0.5)).toBe(8) -- 7.5 rounds up
			t.expect(Levels.ghostSpeed(30, 1, "normal", 0.001)).toBe(1)
		end
	)

	it("no ghost can cover a whole tile in one tick on any level", function()
		for level = 1, Levels.COUNT do
			for _, kind in { "normal", "tunnel", "frightened", "eyes" } do
				t.expect(Levels.ghostSpeed(30, level, kind :: any, 1) < 120).toBe(true)
			end
		end
	end)

	it("the scatter/chase timetable is Table A.2 in ticks, ending in a chase that never stops", function()
		t.expect(Levels.schedule(1, 30)).toEqual({ 210, 600, 210, 600, 150, 600, 150 })
		t.expect(Levels.schedule(2, 30)).toEqual({ 210, 600, 210, 600, 150, 30990, 1 })
		t.expect(Levels.schedule(4, 30)).toEqual({ 210, 600, 210, 600, 150, 30990, 1 })
		t.expect(Levels.schedule(5, 30)).toEqual({ 150, 600, 150, 600, 150, 31110, 1 })
		t.expect(Levels.schedule(21, 30)).toEqual(Levels.schedule(5, 30))
		t.expect(Levels.schedule(1, 60)).toEqual({ 420, 1200, 420, 1200, 300, 1200, 300 })
	end)

	it("the existing player columns and frightened times are untouched", function()
		t.expect(Levels.row(1).speedFactor).toBe(1)
		t.expect(Levels.row(1).frightSpeedFactor).toBe(1.125)
		t.expect(Levels.row(1).frightenedSeconds).toBe(6)
		t.expect(Levels.row(21).frightenedSeconds).toBe(0)
		t.expect(Levels.playerSpeed(30, 5, true)).toBe(38)
	end)
end)
