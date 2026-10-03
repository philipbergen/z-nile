--!strict
-- c0790: scripts/tracker/stats.luau, the board's statistics: bucketing, counts, lines, minutes, ratios and time in
-- state. Pure; every expected number below is worked by hand from the data in this file.
local stats = require("@scripts/tracker/stats")
local t = require("@tests/lib/t")

local TODAY = "2026-10-03" -- a Saturday

local ITEMS: { stats.Item } = {
	{
		id = "f0010",
		type = "feature",
		opened = "2026-09-30",
		closed = "2026-10-02",
		spells = {
			{ state = "new", from = "2026-09-30T00:00:00Z", to = "2026-10-01T00:00:00Z" }, -- 1.0 day
			{ state = "preparing", from = "2026-10-01T00:00:00Z", to = "2026-10-01T12:00:00Z" }, -- 0.5
			{ state = "prepared", from = "2026-10-01T12:00:00Z", to = "2026-10-02T00:00:00Z" }, -- 0.5
			{ state = "active", from = "2026-10-02T00:00:00Z", to = "2026-10-02T12:00:00Z" }, -- 0.5
		},
	},
	{
		id = "d0020",
		type = "defect",
		opened = "2026-10-01",
		closed = "2026-10-03",
		spells = {
			{ state = "new", from = "2026-10-01T00:00:00Z", to = "2026-10-04T00:00:00Z" }, -- 3.0
			{ state = "active", from = "2026-10-03T00:00:00+02:00", to = "2026-10-03T22:00:00Z" }, -- 1.0 (offsets)
		},
	},
	{
		id = "c0030",
		type = "chore",
		opened = "2026-10-02",
		spells = { { state = "new", from = "2026-10-02T00:00:00Z" } }, -- still open: not counted
	},
	{
		id = "f0040",
		type = "feature",
		opened = "2026-09-10",
		spells = { { state = "new", from = "2026-09-10T00:00:00Z", to = "2026-09-12T00:00:00Z" } }, -- 2.0
	},
	{ id = "d0050", type = "defect", opened = "2026-09-27", closed = "2026-09-28", spells = {} },
}
local SPENDS: { stats.Spend } = {
	{ id = "f0010", type = "feature", day = "2026-10-02", added = 100, removed = 20, minutes = 30 },
	{ id = "d0020", type = "defect", day = "2026-10-03", added = 10, removed = 5, minutes = 10 },
	{ id = "c0030", type = "chore", day = "2026-10-02", added = 50, removed = 0, minutes = 20 },
	{ id = "d0050", type = "defect", day = "2026-09-27", added = 7, removed = 7, minutes = 5 },
}

local function counts(all: number, feature: number, defect: number, chore: number): stats.Counts
	return { all = all, feature = feature, defect = defect, chore = chore }
end

return t.spec("tracker stats", function(it)
	it("floor rounds a day down to its week, month, quarter and year", function()
		t.expect(stats.floor("2026-10-03", "week")).toBe("2026-09-28") -- Saturday
		t.expect(stats.floor("2026-10-04", "week")).toBe("2026-09-28") -- Sunday
		t.expect(stats.floor("2026-09-28", "week")).toBe("2026-09-28") -- Monday
		t.expect(stats.floor("2026-01-01", "week")).toBe("2025-12-29") -- across a year
		t.expect(stats.floor("2026-10-03", "month")).toBe("2026-10-01")
		t.expect(stats.floor("2026-10-03", "quarter")).toBe("2026-10-01")
		t.expect(stats.floor("2026-08-15", "quarter")).toBe("2026-07-01")
		t.expect(stats.floor("2026-06-30", "quarter")).toBe("2026-04-01")
		t.expect(stats.floor("2026-03-31", "quarter")).toBe("2026-01-01")
		t.expect(stats.floor("2026-10-03", "year")).toBe("2026-01-01")
	end)

	it("the month, quarter and year views have the right buckets, clamped month ends included", function()
		local month = stats.buckets("month", TODAY)
		t.expect(#month).toBe(31)
		t.expect(month[1].start).toBe("2026-09-03")
		t.expect(month[1].stop).toBe("2026-09-04")
		t.expect(month[31].start).toBe("2026-10-03")
		t.expect(month[31].stop).toBe("2026-10-04")
		local clamped = stats.buckets("month", "2026-03-31")
		t.expect(#clamped).toBe(32)
		t.expect(clamped[1].start).toBe("2026-02-28")
		local quarter = stats.buckets("quarter", TODAY)
		t.expect(#quarter).toBe(14)
		t.expect(quarter[1].start).toBe("2026-06-29")
		t.expect(quarter[1].stop).toBe("2026-07-06")
		t.expect(quarter[14].start).toBe("2026-09-28")
		t.expect(quarter[14].stop).toBe("2026-10-05")
		local year = stats.buckets("year", TODAY)
		t.expect(#year).toBe(13)
		t.expect(year[1].start).toBe("2025-10-01")
		t.expect(year[1].stop).toBe("2025-11-01")
		t.expect(year[13].start).toBe("2026-10-01")
		t.expect(year[13].stop).toBe("2026-11-01")
		for _, b in month do
			t.expect(b.label ~= "").toBe(true)
		end
	end)

	it("the periods are calendar-aligned to date", function()
		local p = stats.periods(TODAY)
		t.expect({ p.week.start, p.week.stop }).toEqual({ "2026-09-28", "2026-10-04" })
		t.expect({ p.month.start, p.month.stop }).toEqual({ "2026-10-01", "2026-10-04" })
		t.expect({ p.quarter.start, p.quarter.stop }).toEqual({ "2026-10-01", "2026-10-04" })
		t.expect({ p.year.start, p.year.stop }).toEqual({ "2026-01-01", "2026-10-04" })
	end)

	it("a row counts opened, closed, net, minutes and lines per type", function()
		local week = stats.row(ITEMS, SPENDS, stats.periods(TODAY).week)
		t.expect(week.opened).toEqual(counts(3, 1, 1, 1)) -- d0050 opened the Sunday before
		t.expect(week.closed).toEqual(counts(3, 1, 2, 0)) -- d0050 closed on the Monday: inside
		t.expect(week.net).toEqual(counts(0, 0, -1, 1))
		t.expect(week.minutes).toEqual(counts(60, 30, 10, 20))
		t.expect(week.added).toEqual(counts(160, 100, 10, 50))
		t.expect(week.removed).toEqual(counts(25, 20, 5, 0))
		t.expect(week.netLines).toEqual(counts(135, 80, 5, 50))
		-- half-open day buckets: the Sunday holds d0050's opening and spend, the Monday its closing
		local sunday = stats.row(ITEMS, SPENDS, { start = "2026-09-27", stop = "2026-09-28", label = "x" })
		t.expect(sunday.opened).toEqual(counts(1, 0, 1, 0))
		t.expect(sunday.closed).toEqual(counts(0, 0, 0, 0))
		t.expect(sunday.minutes).toEqual(counts(5, 0, 5, 0))
		t.expect(sunday.netLines).toEqual(counts(0, 0, 0, 0))
		local monday = stats.row(ITEMS, SPENDS, { start = "2026-09-28", stop = "2026-09-29", label = "x" })
		t.expect(monday.closed).toEqual(counts(1, 0, 1, 0))
		t.expect(monday.opened).toEqual(counts(0, 0, 0, 0))
	end)

	it("ratios are percentages of the right denominators, nil when empty", function()
		local week = stats.row(ITEMS, SPENDS, stats.periods(TODAY).week)
		t.expect(week.ratios.defectCount).toBe(66.7) -- 2 defects / (2 defects + 1 feature) closed
		t.expect(week.ratios.defectTime).toBe(25.0) -- 10 / (10 + 30) minutes
		t.expect(week.ratios.choreCount).toBe(0.0) -- 0 chores / 3 closed
		t.expect(week.ratios.choreTime).toBe(33.3) -- 20 / 60 minutes
		local empty = stats.row(ITEMS, SPENDS, { start = "2026-09-15", stop = "2026-09-16", label = "x" })
		t.expect(empty.ratios.defectCount).toBe(nil)
		t.expect(empty.ratios.defectTime).toBe(nil)
		t.expect(empty.ratios.choreCount).toBe(nil)
		t.expect(empty.ratios.choreTime).toBe(nil)
	end)

	it("durations count only closed spells, per state and type, with mean and median", function()
		local d = stats.durations(ITEMS)
		t.expect(d.new.all).toEqual({ n = 3, mean = 2.0, median = 2.0 }) -- 1.0, 3.0, 2.0; c0030's is open
		t.expect(d.new.feature).toEqual({ n = 2, mean = 1.5, median = 1.5 })
		t.expect(d.new.defect).toEqual({ n = 1, mean = 3.0, median = 3.0 })
		t.expect(d.new.chore).toEqual({ n = 0 })
		t.expect(d.preparing.all).toEqual({ n = 1, mean = 0.5, median = 0.5 })
		t.expect(d.active.all).toEqual({ n = 2, mean = 0.75, median = 0.75 }) -- 0.5 and 1.0 (offset-aware)
		t.expect(d.active.defect).toEqual({ n = 1, mean = 1.0, median = 1.0 })
	end)

	it("compute assembles views, periods and durations for a today", function()
		local s = stats.compute(ITEMS, SPENDS, TODAY, true)
		t.expect(s.today).toBe(TODAY)
		t.expect(s.history).toBe(true)
		t.expect(#s.views.month).toBe(31)
		t.expect(#s.views.quarter).toBe(14)
		t.expect(#s.views.year).toBe(13)
		t.expect(s.periods.week.bucket.start).toBe("2026-09-28")
		t.expect(s.periods.week.opened).toEqual(counts(3, 1, 1, 1))
		t.expect(s.views.year[13].opened).toEqual(counts(2, 0, 1, 1)) -- October 2026: d0020, c0030
		t.expect(s.views.year[12].opened).toEqual(counts(3, 2, 1, 0)) -- September: f0010, f0040, d0050
		t.expect(s.durations.new.all.n).toBe(3)
		t.expect(stats.compute(ITEMS, SPENDS, TODAY, false).history).toBe(false)
	end)
end)
