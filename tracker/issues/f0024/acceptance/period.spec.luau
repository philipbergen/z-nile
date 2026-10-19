--!strict
-- f0024 AC1: period keys are UTC calendar dates. The week starts on Monday. A local-time key fails
-- these instants on a machine whose zone is not UTC, and the module must not call os.date at all
-- (that half is adapter.spec, so a UTC CI host cannot hide a local os.date).
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

local SUN = 1792281600 -- 2026-10-18 00:00 UTC, Sunday
local MON = 1791763200 -- 2026-10-12 00:00 UTC, Monday
local FRI = 1792108800 -- 2026-10-16 00:00 UTC, Friday. PDT of this instant is still 2026-10-15.
local NEXT_MON = 1792368000 -- 2026-10-19 00:00 UTC, Monday
local MARCH = 1772323200 -- 2026-03-01 00:00 UTC, Sunday
local JAN = 1767225600 -- 2026-01-01 00:00 UTC, Thursday
local LEAP = 1709164800 -- 2024-02-29 00:00 UTC, Thursday

return t.spec("f0024 period keys", function(it)
	it("the epoch day is 1970-01-01 and the second before it is 1969-12-31", function()
		t.expect(Hiscores.dayKey(0)).toBe("1970-01-01")
		t.expect(Hiscores.dayKey(-1)).toBe("1969-12-31")
	end)

	it("a UTC midnight stays on that UTC date, including late the same day", function()
		t.expect(Hiscores.dayKey(FRI)).toBe("2026-10-16")
		t.expect(Hiscores.dayKey(FRI + 23 * 3600 + 30 * 60)).toBe("2026-10-16")
		t.expect(Hiscores.dayKey(FRI + 86400)).toBe("2026-10-17")
	end)

	it("the week key is the Monday of that UTC week, not the Sunday", function()
		t.expect(Hiscores.weekKey(0)).toBe("1969-12-29")
		t.expect(Hiscores.weekKey(-1)).toBe("1969-12-29")
		t.expect(Hiscores.weekKey(SUN)).toBe("2026-10-12")
		t.expect(Hiscores.weekKey(MON)).toBe("2026-10-12")
		t.expect(Hiscores.weekKey(NEXT_MON)).toBe("2026-10-19")
		t.expect(Hiscores.weekKey(FRI)).toBe("2026-10-12")
	end)

	it("a week can start in the previous month, and a leap day keeps its date", function()
		t.expect(Hiscores.weekKey(MARCH)).toBe("2026-02-23")
		t.expect(Hiscores.weekKey(JAN)).toBe("2025-12-29")
		t.expect(Hiscores.dayKey(LEAP)).toBe("2024-02-29")
		t.expect(Hiscores.weekKey(LEAP)).toBe("2024-02-26")
	end)

	it("dates are zero-padded, and a non-finite instant is refused", function()
		t.expect(Hiscores.dayKey(0)).toBe("1970-01-01")
		t.expect(function()
			Hiscores.dayKey(math.huge)
		end).toThrow()
		t.expect(function()
			Hiscores.dayKey(0 / 0)
		end).toThrow()
		t.expect(function()
			Hiscores.weekKey(-math.huge)
		end).toThrow()
	end)

	it("all-time has no period, and day and week scopes do not collide", function()
		local all = Hiscores.board("all", FRI)
		t.expect(all.id).toBe("all")
		t.expect(all.period).toBe(nil)
		t.expect(Hiscores.scope(all)).toBe("all")
		t.expect(Hiscores.entryKey("7", all)).toBe("7")
		t.expect(Hiscores.entryKey("-2", all)).toBe("-2")
		local day = Hiscores.board("day", FRI)
		t.expect(day.period).toBe("2026-10-16")
		t.expect(Hiscores.scope(day)).toBe("day:2026-10-16")
		t.expect(Hiscores.entryKey("7", day)).toBe("7:2026-10-16")
		t.expect(Hiscores.entryKey("-2", day)).toBe("-2:2026-10-16")
		local week = Hiscores.board("week", SUN)
		t.expect(Hiscores.scope(week)).toBe("week:2026-10-12")
		t.expect(Hiscores.cacheKey("day", FRI)).toBe("day:2026-10-16")
		t.expect(Hiscores.cacheKey("day", FRI + 7 * 86400)).toBe("day:2026-10-23")
		t.expect(Hiscores.cacheKey("all", FRI)).toBe("all")
		t.expect(Hiscores.cacheKey("all", FRI + 86400)).toBe("all")
		t.expect(Hiscores.userIdFromKey("7:2026-10-16", day)).toBe("7")
		t.expect(Hiscores.userIdFromKey("-2:2026-10-16", day)).toBe("-2")
		t.expect(Hiscores.userIdFromKey("7:2026-10-16", all)).toBe(nil)
		t.expect(Hiscores.userIdFromKey("-", all)).toBe(nil)
		t.expect(Hiscores.userIdFromKey("", all)).toBe(nil)
	end)
end)
