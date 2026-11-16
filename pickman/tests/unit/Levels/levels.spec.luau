--!strict
-- Levels: a few row lookups beyond the acceptance table.
local Levels = require("@logic/Levels")
local t = require("@tests/lib/t")

return t.spec("Levels extras", function(it)
	it("level 1 is the base speed and 6 s of frightened time", function()
		t.expect(Levels.row(1).speedFactor).toBe(1)
		t.expect(Levels.row(1).frightenedSeconds).toBe(6)
		t.expect(Levels.playerSpeed(30, 1)).toBe(30)
	end)

	it("levels past the table use the last row", function()
		t.expect(Levels.row(40)).toEqual(Levels.row(Levels.COUNT))
	end)

	it("the timetable is worked out once per level and tick rate, and is frozen", function()
		local a = Levels.schedule(1, 30)
		t.expect(Levels.schedule(1, 30)).toBe(a)
		t.expect(table.isfrozen(a)).toBe(true)
		t.expect(Levels.schedule(1, 60) ~= a).toBe(true)
	end)

	it("the ramp factor is first x step^(min(level, top) - 1)", function()
		local r = Levels.RAMP
		t.expect(r.picks).toBe(10)
		t.expect(Levels.rampFactor(r, 1)).toBe(0.7)
		t.expect(math.abs(Levels.rampFactor(r, 3) - 0.7 * 1.05 ^ 2) < 1e-9).toBe(true)
		t.expect(Levels.rampFactor(r, 40)).toBe(Levels.rampFactor(r, r.top))
	end)

	it("a ramp is refused unless picks, top, first and step are usable", function()
		local function bad(change: { [string]: number })
			local r = { picks = 10, first = 0.7, step = 1.05, top = 34 }
			for k, v in change do
				(r :: any)[k] = v
			end
			t.expect(pcall(Levels.validateRamp, r)).toBe(false)
		end
		bad({ picks = 0 })
		bad({ picks = 1.5 })
		bad({ top = 0 })
		bad({ top = Levels.MAX_TOP + 1 })
		bad({ first = 0 })
		bad({ first = math.huge })
		bad({ step = 0.9 })
		bad({ step = 0 / 0 })
		t.expect(pcall(Levels.validateRamp, Levels.RAMP)).toBe(true)
	end)

	it("a ramped row is level 1's with the speeds ramped, made once and frozen", function()
		local a = Levels.row(5, Levels.RAMP)
		t.expect(Levels.row(5, Levels.RAMP)).toBe(a)
		t.expect(table.isfrozen(a)).toBe(true)
		t.expect(a.frightenedSeconds).toBe(Levels.row(1).frightenedSeconds)
		t.expect(Levels.row(5)).toBe(Levels.row(5))
		t.expect(Levels.playerSpeed(30, 1, false, Levels.RAMP)).toBe(21)
		t.expect(Levels.playerSpeed(30, 2, false, Levels.RAMP)).toBe(22)
	end)

	it("without a ramp the ghost rate is the whole-unit speed, with one the exact rate", function()
		t.expect(Levels.ghostRate(12, 1, "frightened", nil, nil))
			.toBe(Levels.ghostSpeed(12, 1, "frightened", nil, nil))
		local flat = { picks = 10, first = 1, step = 1, top = 34 }
		local slow = Levels.ghostRate(100, 1, "frightened", 1, Levels.RAMP)
		local full = Levels.ghostRate(100, 1, "frightened", 1, flat)
		t.expect(math.abs(slow / full - 0.7) < 1e-9).toBe(true)
	end)
end)
