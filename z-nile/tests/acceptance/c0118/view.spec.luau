--!strict
-- c0118 AC1: the board's pure rules (boardview): every effective status maps to one column (ready against run by the
-- raft's branch), raft bands, the done age, UTC ISO weeks, a raft's review rounds counted once, and the two charts'
-- weekly series (the range, zero weeks, the review phases, the model order and cap, the unrecorded series).
local boardview = require("@znile/engine/boardview")
local stats = require("@znile/engine/stats")
local t = require("@tests/lib/t")

local function at(ts: string): number
	return stats.seconds(ts)
end
local DAY = 86400

local function seriesOf(w: boardview.Weekly, key: string): { number? }?
	for _, s in w.series do
		if s.key == key then
			return s.values
		end
	end
	return nil
end
local function labelsOf(w: boardview.Weekly): { string }
	local out = {}
	for _, s in w.series do
		table.insert(out, s.label)
	end
	return out
end

return t.spec("c0118 board rules", function(it)
	it("maps each effective status to its column, and active by the raft's branch to ready or run", function()
		t.expect(boardview.column("new", false)).toBe("ticket")
		t.expect(boardview.column("new", true)).toBe("ticket")
		t.expect(boardview.column("preparing", false)).toBe("design")
		t.expect(boardview.column("prepared", false)).toBe("raft")
		t.expect(boardview.column("prepared", true)).toBe("raft")
		t.expect(boardview.column("active", false)).toBe("ready")
		t.expect(boardview.column("active", true)).toBe("run")
		t.expect(boardview.column("done", false)).toBe("done")
		t.expect(boardview.column("done", true)).toBe("done")
	end)

	it("has six columns in pipeline order", function()
		t.expect(boardview.COLUMNS).toEqual({ "ticket", "design", "raft", "ready", "run", "done" })
	end)

	it("refuses a status that is not an effective status, naming it", function()
		t.expect(function()
			boardview.column("blocked", false)
		end).toThrow("blocked")
		t.expect(function()
			boardview.column("", true)
		end).toThrow("effective status")
	end)

	it("bands a column by raft in id order, the raftless cards last, ids sorted", function()
		local bands = boardview.bands({
			{ id = "f0031", raft = "R0030" },
			{ id = "c0090", raft = nil },
			{ id = "f0030", raft = "R0030" },
			{ id = "d0012", raft = "R0010" },
			{ id = "c0080", raft = nil },
		})
		local want: { boardview.Band } = {
			{ raft = "R0010", ids = { "d0012" } },
			{ raft = "R0030", ids = { "f0030", "f0031" } },
			{ raft = nil, ids = { "c0080", "c0090" } },
		}
		t.expect(bands).toEqual(want)
		t.expect(boardview.bands({})).toEqual({})
	end)

	it(
		"ages a done card from the page's as-of time, never below zero, and unknown when either time is",
		function()
			t.expect(boardview.age(1000, 4600)).toBe(3600)
			t.expect(boardview.age(5000, 4600)).toBe(0)
			t.expect(boardview.age(nil, 4600)).toBe(nil)
			t.expect(boardview.age(1000, nil)).toBe(nil)
		end
	)

	it("the done window is 24 hours by default and runs from 1 hour to 30 days", function()
		t.expect(boardview.WINDOW).toBe(DAY)
		t.expect(boardview.WINDOWS[1]).toBe(3600)
		t.expect(boardview.WINDOWS[#boardview.WINDOWS]).toBe(30 * DAY)
		t.expect(table.find(boardview.WINDOWS, DAY) ~= nil).toBe(true)
		for i = 2, #boardview.WINDOWS do
			t.expect(boardview.WINDOWS[i] > boardview.WINDOWS[i - 1]).toBe(true)
		end
	end)

	it("the charts' range is 90 days by default and opens to all history", function()
		t.expect(boardview.RANGE).toBe("90d")
		local keys, all = {}, nil
		for _, r in boardview.RANGES do
			table.insert(keys, r.key)
			if r.key == "all" then
				all = r
			end
		end
		t.expect(table.find(keys, "90d") ~= nil).toBe(true)
		t.expect(all ~= nil and (all :: any).days == nil).toBe(true)
	end)

	it("weeks are ISO weeks in UTC: a Sunday-evening landing in -07:00 is the next week", function()
		-- Sunday 2026-10-18 23:30 -07:00 is Monday 2026-10-19 06:30 UTC
		t.expect(boardview.weekOf(at("2026-10-18T23:30:00-07:00"))).toBe("2026-10-19")
		t.expect(boardview.weekOf(at("2026-10-18T22:59:59-01:00"))).toBe("2026-10-12") -- 23:59:59 UTC Sunday
		t.expect(boardview.weekOf(at("2026-10-19T00:00:00Z"))).toBe("2026-10-19")
		t.expect(boardview.weekOf(at("2026-01-01T12:00:00Z"))).toBe("2025-12-29") -- ISO week 1 of 2026
	end)

	it(
		"counts a raft's rounds from its files: design reviews and code reviews, each path once, nothing else",
		function()
			local design, code = boardview.rounds({
				"z/rafts/done/R0010/design-review-001.md",
				"z/rafts/done/R0010/design-review-001.md", -- the same file offered twice
				"z/issues/done/c0011/design-review-001.md", -- a member's: another file of the same name
				"z/rafts/done/R0010/review-001.md",
				"z/rafts/done/R0010/review-002.md",
				"z/rafts/done/R0010/design-refute-001.md",
				"z/rafts/done/R0010/refute-001.md",
				"z/rafts/done/R0010/stream-review-c0011-001.md",
				"z/rafts/done/R0010/design-review-notes.md",
				"z/rafts/done/R0010/harvest.md",
			})
			t.expect(design).toBe(2)
			t.expect(code).toBe(2)
		end
	)

	it(
		"review rounds by week cover every week of the range, landed rafts in their UTC week, none outside",
		function()
			local asOf = at("2026-10-21T12:00:00Z") -- a Wednesday
			local landed = {
				{ id = "R0010", at = at("2026-10-18T23:30:00-07:00"), design = 3, code = 1 }, -- week of Oct 19
				{ id = "R0011", at = at("2026-10-20T08:00:00Z"), design = 1, code = 2 }, -- week of Oct 19
				{ id = "R0012", at = at("2026-10-07T08:00:00Z"), design = 2, code = 0 }, -- week of Oct 5
				{ id = "R0013", at = asOf - 31 * DAY, design = 9, code = 9 }, -- outside 30 days
				{ id = "R0014", at = asOf + 3600, design = 7, code = 7 }, -- after the page's as-of time
			}
			local w = boardview.roundsByWeek(landed, asOf, 30)
			t.expect(w.weeks)
				.toEqual({ "2026-09-21", "2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19" })
			t.expect(w.labels).toEqual({ "Sep 21", "Sep 28", "Oct 5", "Oct 12", "Oct 19" })
			t.expect(seriesOf(w, "design")).toEqual({ 0, 0, 2, 0, 4 })
			t.expect(seriesOf(w, "code")).toEqual({ 0, 0, 0, 0, 3 })
			t.expect(labelsOf(w)).toEqual({ "Design reviews", "Code reviews" })
		end
	)

	it("a raft that landed exactly at the range's start counts, one second earlier does not", function()
		local asOf = at("2026-10-21T12:00:00Z")
		local start = asOf - 30 * DAY
		local w = boardview.roundsByWeek({ { id = "R1", at = start, design = 1, code = 0 } }, asOf, 30)
		t.expect((seriesOf(w, "design") :: { number? })[1]).toBe(1)
		local w2 = boardview.roundsByWeek({ { id = "R1", at = start - 1, design = 1, code = 0 } }, asOf, 30)
		local sum = 0
		for _, v in seriesOf(w2, "design") :: { number } do
			sum += v
		end
		t.expect(sum).toBe(0)
	end)

	it("all history starts at the earliest landing, and nothing landed gives no weeks", function()
		local asOf = at("2026-10-21T12:00:00Z")
		local w = boardview.roundsByWeek({
			{ id = "R1", at = at("2026-09-30T10:00:00Z"), design = 5, code = 1 },
			{ id = "R2", at = at("2026-10-13T10:00:00Z"), design = 1, code = 1 },
		}, asOf, nil)
		t.expect(w.weeks).toEqual({ "2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19" })
		t.expect(seriesOf(w, "design")).toEqual({ 5, 0, 1, 0 })
		local empty = boardview.roundsByWeek({}, asOf, nil)
		t.expect(empty.weeks).toEqual({})
		t.expect(empty.series).toEqual({})
	end)

	it(
		"tokens by model read only design-review and code-review rows with tokens, dated in the range",
		function()
			local asOf = at("2026-10-21T12:00:00Z")
			local w = boardview.tokensByWeek({
				{
					at = at("2026-10-20T10:00:00Z"),
					phase = "design-review",
					tokens = 500,
					model = "claude-opus-5-5-high",
				},
				{
					at = at("2026-10-14T13:00:00Z"),
					phase = "code-review",
					tokens = 300,
					model = "claude-opus-5-5-high",
				},
				{
					at = at("2026-10-20T11:00:00Z"),
					phase = "code-review",
					tokens = 900,
					model = "grok-4.7-xhigh",
				},
				{
					at = at("2026-10-20T12:00:00Z"),
					phase = "build",
					tokens = 99999,
					model = "build-only-model",
				},
				{ at = at("2026-10-20T12:00:00Z"), phase = "prep", tokens = 77777, model = nil },
				{
					at = at("2026-10-20T13:00:00Z"),
					phase = "design-review",
					tokens = 0,
					model = "zero-model",
				},
				{ at = at("2026-10-15T13:00:00Z"), phase = "design-review", tokens = 40, model = nil },
				{ at = asOf - 8 * DAY, phase = "design-review", tokens = 5000, model = "old-model" }, -- outside 7 days
				{ at = asOf + 60, phase = "design-review", tokens = 6000, model = "future-model" }, -- after as-of
			}, asOf, 7)
			t.expect(w.weeks).toEqual({ "2026-10-12", "2026-10-19" })
			-- largest total first: grok 900, opus 800; the unrecorded series last
			t.expect(labelsOf(w)).toEqual({ "grok-4.7-xhigh", "claude-opus-5-5-high", "unrecorded model" })
			t.expect(seriesOf(w, "m1")).toEqual({ 0, 900 })
			t.expect(seriesOf(w, "m2")).toEqual({ 300, 500 })
			t.expect(seriesOf(w, "unrecorded")).toEqual({ 40, 0 })
		end
	)

	it("ties between models go by id, and models past the cap are summed as other models", function()
		local asOf = at("2026-10-21T12:00:00Z")
		local rows = {}
		for i = 1, boardview.MAX_MODELS + 2 do
			table.insert(rows, {
				at = at("2026-10-20T10:00:00Z"),
				phase = "code-review",
				tokens = if i <= 2 then 100 else 1000 - i,
				model = string.format("model-%02d", i),
			})
		end
		local w = boardview.tokensByWeek(rows, asOf, 7)
		local labels = labelsOf(w)
		t.expect(#labels).toBe(boardview.MAX_MODELS + 1)
		t.expect(labels[1]).toBe("model-03")
		t.expect(labels[#labels]).toBe("other models")
		-- model-01 and model-02 tie at 100 and are the two smallest: both fall into other models
		t.expect(table.find(labels, "model-01")).toBe(nil)
		t.expect(seriesOf(w, "other")).toEqual({ 0, 200 }) -- weeks of Oct 12 and Oct 19
	end)

	it("models with equal totals are ordered by id", function()
		local asOf = at("2026-10-21T12:00:00Z")
		local w = boardview.tokensByWeek({
			{ at = at("2026-10-20T10:00:00Z"), phase = "code-review", tokens = 100, model = "zeta" },
			{ at = at("2026-10-20T10:00:00Z"), phase = "code-review", tokens = 100, model = "alpha" },
			{ at = at("2026-10-20T10:00:00Z"), phase = "design-review", tokens = 100, model = "mid" },
		}, asOf, 7)
		t.expect(labelsOf(w)).toEqual({ "alpha", "mid", "zeta" })
	end)

	it("scales a tall token axis to k or M tokens, and leaves a short one alone", function()
		local function weekly(v: number): boardview.Weekly
			return {
				labels = { "Oct 19" },
				weeks = { "2026-10-19" },
				series = { { key = "m1", label = "a", values = { v } } },
			}
		end
		local w1, u1 = boardview.scaled(weekly(9000), "tokens")
		t.expect(u1).toBe("tokens")
		t.expect(w1.series[1].values[1]).toBe(9000)
		local w2, u2 = boardview.scaled(weekly(123456), "tokens")
		t.expect(u2).toBe("k tokens")
		t.expect(w2.series[1].values[1]).toBe(123.5)
		local w3, u3 = boardview.scaled(weekly(25000000), "tokens")
		t.expect(u3).toBe("M tokens")
		t.expect(w3.series[1].values[1]).toBe(25)
	end)

	it("reads a spend row's UTC minute, or a bare day, and nothing else", function()
		t.expect(boardview.rowInstant("2026-10-21 10:00")).toBe(at("2026-10-21T10:00:00Z"))
		t.expect(boardview.rowInstant("2026-10-21")).toBe(at("2026-10-21T00:00:00Z"))
		t.expect(boardview.rowInstant("yesterday")).toBe(nil)
	end)
end)
