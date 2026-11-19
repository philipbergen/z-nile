--!strict
-- d0415 AC1, AC2, AC3 and AC5: where a dispatched review is filed or why not, decided from the folder's state alone, as
-- pure functions over texts (dispatch.filing, raftplan.coveringReview). No fixture, no process.
local dispatch = require("@znile/engine/dispatch")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")

local OLD = "[c0030@111111111111]"
local NOW = "[c0030@111111111111, c0040@222222222222]"
local DIR = "pickman/.tracker/rafts/R0095"

local function review(quoted: string): string
	return `# Review\n\nInputs:\nGrouped: {quoted}\n\nVerdict: approve\n`
end

local function raft(reviews: { [string]: string }, grouped: string?): dispatch.Filing
	return dispatch.filing({
		mode = "raft",
		dir = DIR,
		prefix = "design-review-",
		raftId = "R0095",
		reviews = reviews,
		grouped = grouped,
	})
end

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text :: string, needle, 1, true) ~= nil
end

return t.spec("d0415 a raft review is filed per grouped record", function(it)
	it("AC1: a raft with no review files round 1", function()
		t.expect(raft({}, NOW).number).toBe(1)
		t.expect(raft({}, NOW).refusal).toBe(nil)
	end)

	it("AC1: a refolded raft, whose only review quotes the older record, files the next number", function()
		local f = raft({ ["design-review-001.md"] = review(OLD) }, NOW)
		t.expect(f.refusal).toBe(nil)
		t.expect(f.number).toBe(2)
	end)

	it("AC1: the next number is one past the highest, not the count of files", function()
		local f = raft({
			["design-review-001.md"] = review(OLD),
			["design-review-004.md"] = review("[c0030@000000000000]"),
		}, NOW)
		t.expect(f.number).toBe(5)
	end)

	it(
		"AC2: a review that quotes the current record is refused, naming the file, the record and the rule",
		function()
			local f = raft({ ["design-review-001.md"] = review(NOW) }, NOW)
			t.expect(f.number).toBe(nil)
			t.expect(has(f.refusal, "design-review-001.md")).toBe(true)
			t.expect(has(f.refusal, "R0095")).toBe(true)
			t.expect(has(f.refusal, "there is no second round")).toBe(true)
		end
	)

	it("AC2: any one of several reviews quoting the current record refuses", function()
		local f = raft({
			["design-review-001.md"] = review(OLD),
			["design-review-002.md"] = review(NOW),
		}, NOW)
		t.expect(has(f.refusal, "design-review-002.md")).toBe(true)
	end)

	it("AC2: a review that quotes a record with one other hash does not cover it", function()
		local f = raft({ ["design-review-001.md"] = review("[c0030@111111111111, c0040@999999999999]") }, NOW)
		t.expect(f.refusal).toBe(nil)
		t.expect(f.number).toBe(2)
	end)

	it(
		"AC2: a review of a larger record covers a smaller one (an unfold alone needs no new review)",
		function()
			local f = raft({ ["design-review-001.md"] = review(NOW) }, OLD)
			t.expect(has(f.refusal, "design-review-001.md")).toBe(true)
		end
	)

	it("AC2: a review that quotes no record covers none", function()
		local f = raft({ ["design-review-001.md"] = "# Review\n\nVerdict: approve\n" }, NOW)
		t.expect(f.refusal).toBe(nil)
		t.expect(f.number).toBe(2)
	end)

	it(
		"AC2: an older review that covers the record still refuses when a newer one quotes another record",
		function()
			local f = raft({
				["design-review-001.md"] = review(NOW),
				["design-review-002.md"] = review("[c0030@111111111111, c0040@999999999999]"),
			}, NOW)
			t.expect(has(f.refusal, "design-review-001.md")).toBe(true)
		end
	)

	it("AC2: a raft with no grouped record keeps one round, as every other mode does", function()
		local f = raft({ ["design-review-001.md"] = review(NOW) }, nil)
		t.expect(has(f.refusal, "one round")).toBe(true)
		t.expect(raft({}, "").number).toBe(1)
	end)

	it("AC3: a malformed grouped record is refused, naming the raft and the problem", function()
		local f = raft({}, "c0030@1")
		t.expect(has(f.refusal, "R0095")).toBe(true)
		t.expect(has(f.refusal, "grouped: is not a list")).toBe(true)
	end)

	it(
		"AC3: the one-round rule of every other mode is decided from the folder, and keeps its words",
		function()
			for _, c in
				{
					{ "design", "design-review-" },
					{ "code", "review-" },
					{ "final", "final-review-" },
					{ "stream", "stream-review-c0010-" },
				}
			do
				local f = dispatch.filing({
					mode = c[1],
					dir = "d",
					prefix = c[2],
					raftId = "c0010",
					reviews = { [`{c[2]}002.md`] = "x", [`{c[2]}001.md`] = "x" },
					grouped = nil,
				})
				t.expect(has(f.refusal, `d already has {c[2]}002.md: one round, then the author answers it`))
					.toBe(true)
				local none = dispatch.filing({
					mode = c[1],
					dir = "d",
					prefix = c[2],
					raftId = "c0010",
					reviews = {},
					grouped = nil,
				})
				t.expect(none.number).toBe(1)
			end
		end
	)

	it("AC3: another prefix's or another issue's files never count", function()
		local f = dispatch.filing({
			mode = "stream",
			dir = "d",
			prefix = "stream-review-c0010-",
			raftId = "c0010",
			reviews = { ["stream-review-c0011-001.md"] = "x", ["stream-review-c0010-001-notes.md"] = "x" },
			grouped = nil,
		})
		t.expect(f.number).toBe(1)
	end)

	it("AC5: a pending row says when it is written, from where its item stands on origin/main", function()
		t.expect(dispatch.pendingFate("c0030", "design-review", "backlog", false))
			.toBe("written by the next run of c0030")
		t.expect(dispatch.pendingFate("R0095", "design-review", "backlog", true))
			.toBe("written by the next run of R0095")
		t.expect(dispatch.pendingFate("R0095", "deliver", "done", true))
			.toBe("written by the next run of R0095")
		t.expect(
			has(
				dispatch.pendingFate("R0099", "design-review", "active", true),
				"never written: R0099 is active"
			)
		).toBe(true)
		t.expect(has(dispatch.pendingFate("R0099", "deliver", "active", true), "waits for done")).toBe(true)
		t.expect(has(dispatch.pendingFate("R0070", "design-review", nil, true), "does not list R0070"))
			.toBe(true)
		t.expect(dispatch.rowWritable("c0030", "design-review", "done", false)).toBe(false)
		t.expect(dispatch.rowWritable("c0030", "deliver", "backlog", false)).toBe(false)
	end)

	it(
		"AC5: a raft row that names no members (recorded before d0415) is never written, and says so",
		function()
			t.expect(dispatch.rowWritable("R0070", "design-review", "backlog", false)).toBe(false)
			t.expect(
				has(dispatch.pendingFate("R0070", "design-review", "backlog", false), "names no members")
			)
				.toBe(true)
			t.expect(dispatch.rowWritable("R0070", "design-review", "backlog", true)).toBe(true)
		end
	)

	it("AC1: coveringReview names the first covering review in name order and ignores other files", function()
		local reviews = {
			["design-review-002.md"] = review(NOW),
			["design-review-001.md"] = review(NOW),
			["notes.md"] = review(NOW),
		}
		local map = raftplan.parseGrouped(NOW)
		t.expect(raftplan.coveringReview(reviews, map)).toBe("design-review-001.md")
		t.expect(raftplan.coveringReview({ ["notes.md"] = review(NOW) }, map)).toBe(nil)
		t.expect(raftplan.coveringReview(reviews, {})).toBe(nil)
		t.expect(raftplan.reviewCovers(reviews, {})).toBe(true)
	end)
end)
