--!strict
-- f0170 AC1: Levels is the classic per-level table (Pittman, The Pac-Man Dossier, Table A.1): player
-- speed as a factor of level 1, the frightened time in seconds, and the number of flashes.
local Levels = require("@logic/Levels")
local t = require("@tests/lib/t")

-- { level, speed factor, frightened speed factor, frightened seconds, flashes } for levels 1 to 21. The
-- frightened speed is the arcade's "Pac-Man fright speed": 90%, 95% and 100% of full speed against
-- the normal 80%, 90% and 100%, relative to level 1's 80%.
local TABLE: { { number } } = {
	{ 1, 1, 1.125, 6, 5 },
	{ 2, 1.125, 1.1875, 5, 5 },
	{ 3, 1.125, 1.1875, 4, 5 },
	{ 4, 1.125, 1.1875, 3, 5 },
	{ 5, 1.25, 1.25, 2, 5 },
	{ 6, 1.25, 1.25, 5, 5 },
	{ 7, 1.25, 1.25, 2, 5 },
	{ 8, 1.25, 1.25, 2, 5 },
	{ 9, 1.25, 1.25, 1, 3 },
	{ 10, 1.25, 1.25, 5, 5 },
	{ 11, 1.25, 1.25, 2, 5 },
	{ 12, 1.25, 1.25, 1, 3 },
	{ 13, 1.25, 1.25, 1, 3 },
	{ 14, 1.25, 1.25, 3, 5 },
	{ 15, 1.25, 1.25, 1, 3 },
	{ 16, 1.25, 1.25, 1, 3 },
	{ 17, 1.25, 1.25, 0, 0 },
	{ 18, 1.25, 1.25, 1, 3 },
	{ 19, 1.25, 1.25, 0, 0 },
	{ 20, 1.25, 1.25, 0, 0 },
	{ 21, 1.125, 1.125, 0, 0 },
}

return t.spec("f0170 Levels", function(it)
	it("has a row for each of the 21 levels, exactly as the classic table says", function()
		t.expect(Levels.COUNT).toBe(21)
		t.expect(#Levels.ROWS).toBe(21)
		for _, want in TABLE do
			local row = Levels.row(want[1])
			if
				row.speedFactor ~= want[2]
				or row.frightSpeedFactor ~= want[3]
				or row.frightenedSeconds ~= want[4]
				or row.flashes ~= want[5]
			then
				error(
					`level {want[1]}: got {row.speedFactor}/{row.frightSpeedFactor}/{row.frightenedSeconds}/{row.flashes}, want {want[2]}/{want[3]}/{want[4]}/{want[5]}`
				)
			end
		end
	end)

	it("every level after the last uses the last row", function()
		for _, level in { 22, 23, 50, 1000 } do
			t.expect(Levels.row(level)).toEqual(Levels.row(21))
		end
	end)

	it("rejects a level that is not a whole number of at least 1", function()
		for _, bad in { 0, -1, 1.5, 0 / 0 } do
			t.expect(function()
				Levels.row(bad)
			end).toThrow("level")
		end
		t.expect(function()
			Levels.row("2" :: any)
		end).toThrow("level")
	end)

	it("the table is read-only", function()
		t.expect(function()
			(Levels.row(1) :: any).speedFactor = 9
		end).toThrow()
		t.expect(function()
			(Levels.ROWS :: any)[1] = Levels.ROWS[2]
		end).toThrow()
	end)

	it("playerSpeed scales the base speed by the level's factor, rounding half up", function()
		-- base speed 30 is level 1 (80% of full speed): 30, 34 (90%), 38 (100%), 34 again from level 21
		t.expect(Levels.playerSpeed(30, 1)).toBe(30)
		t.expect(Levels.playerSpeed(30, 2)).toBe(34) -- 33.75
		t.expect(Levels.playerSpeed(30, 4)).toBe(34)
		t.expect(Levels.playerSpeed(30, 5)).toBe(38) -- 37.5 rounds up
		t.expect(Levels.playerSpeed(30, 20)).toBe(38)
		t.expect(Levels.playerSpeed(30, 21)).toBe(34)
		t.expect(Levels.playerSpeed(30, 60)).toBe(34)
		t.expect(Levels.playerSpeed(10, 2)).toBe(11) -- 11.25 rounds down
		t.expect(Levels.playerSpeed(6, 2)).toBe(7) -- 6.75 rounds up
		t.expect(Levels.playerSpeed(4, 5)).toBe(5) -- 5.0
	end)

	it("playerSpeed while frightened uses the frightened factor: 34, 36, 38 and 34 at 30 units", function()
		t.expect(Levels.playerSpeed(30, 1, true)).toBe(34) -- 33.75
		t.expect(Levels.playerSpeed(30, 2, true)).toBe(36) -- 35.625
		t.expect(Levels.playerSpeed(30, 4, true)).toBe(36)
		t.expect(Levels.playerSpeed(30, 5, true)).toBe(38) -- 37.5
		t.expect(Levels.playerSpeed(30, 20, true)).toBe(38)
		t.expect(Levels.playerSpeed(30, 21, true)).toBe(34)
		t.expect(Levels.playerSpeed(30, 1, false)).toBe(30)
		t.expect(Levels.playerSpeed(30, 1)).toBe(30) -- not frightened by default
	end)

	it("frightenedTicks converts seconds to ticks at the given rate", function()
		t.expect(Levels.frightenedTicks(1, 30)).toBe(180)
		t.expect(Levels.frightenedTicks(2, 30)).toBe(150)
		t.expect(Levels.frightenedTicks(9, 30)).toBe(30)
		t.expect(Levels.frightenedTicks(17, 30)).toBe(0)
		t.expect(Levels.frightenedTicks(99, 30)).toBe(0)
		t.expect(Levels.frightenedTicks(1, 60)).toBe(360)
	end)
end)
