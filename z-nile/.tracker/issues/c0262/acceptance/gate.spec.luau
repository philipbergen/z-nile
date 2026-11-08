--!strict
-- c0262 AC2: the rule `./zn done` applies to a raft's final reviews, the exemption of rafts that predate it, and the
-- rounds' cap. Pure: z-nile/engine/finalreview.luau.
local finalreview = require("@znile/engine/finalreview")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function review(verdict: string, findings: string?): string
	return `# Review 001: c0010 (final mode)\nInputs: view\n\n{findings or ""}\nVerdict: {verdict}\n`
end
local function problem(created: string, reviews: { [string]: string }, grouped: boolean?): string?
	return finalreview.problem({
		raft = "R0099",
		created = created,
		grouped = grouped ~= false,
		issues = { "c0010", "c0011" },
		reviews = reviews,
	})
end

return t.spec("c0262 AC2 the gate ./zn done applies to final reviews", function(it)
	it("AC2: done passes only when every member's latest final review is an approve", function()
		local ok = {
			["final-review-c0010-001.md"] = review("approve"),
			["final-review-c0011-001.md"] = review("approve"),
		}
		t.expect(problem("2026-11-08", ok)).toBe(nil)
	end)

	it("AC2: a member with no final review is named", function()
		local p = problem("2026-11-08", { ["final-review-c0010-001.md"] = review("approve") })
		t.expect(p ~= nil and has(p :: string, "c0011")).toBe(true)
	end)

	it("AC2: a review that sent the ticket back blocks done, whatever the author answered", function()
		local p = problem("2026-11-08", {
			["final-review-c0010-001.md"] = review("changes", "### F1 [medium] off course\nOff course: implementation\n"),
			["final-refute-c0010-001.md"] = "- F1: fixed abc123: done; consequences: none\n",
			["final-review-c0011-001.md"] = review("approve"),
		})
		t.expect(p ~= nil and has(p :: string, "c0010") and has(p :: string, "sent back")).toBe(true)
	end)

	it("AC2: only the newest round counts: a later approve clears an earlier sent-back", function()
		local ok = {
			["final-review-c0010-001.md"] = review("changes", "### F1 [medium] x\n"),
			["final-review-c0010-002.md"] = review("approve"),
			["final-review-c0011-001.md"] = review("approve"),
		}
		t.expect(problem("2026-11-08", ok)).toBe(nil)
		-- and a later sent-back is not cleared by an earlier approve
		local bad = {
			["final-review-c0010-001.md"] = review("approve"),
			["final-review-c0010-002.md"] = review("changes", "### F1 [medium] x\n"),
			["final-review-c0011-001.md"] = review("approve"),
		}
		t.expect(problem("2026-11-08", bad) ~= nil).toBe(true)
	end)

	it("AC2: an approve that still carries a high finding is refused", function()
		local p = problem("2026-11-08", {
			["final-review-c0010-001.md"] = review("approve", "### F1 [high] off course\n"),
			["final-review-c0011-001.md"] = review("approve"),
		})
		t.expect(p ~= nil and has(p :: string, "c0010")).toBe(true)
	end)

	it("AC2: a file that is not a numbered round of a member is ignored (a stream review, another raft's)", function()
		local p = problem("2026-11-08", {
			["final-review-c0010-001.md"] = review("approve"),
			["final-review-c0011-001.md"] = review("changes"),
			["final-review-c0011-002.md.bak"] = review("approve"),
			["stream-review-c0011-001.md"] = review("approve"),
			["review-001.md"] = review("approve"),
		})
		t.expect(p ~= nil and has(p :: string, "c0011")).toBe(true)
	end)

	it("AC2: a raft z-raft did not make (no grouped: record) is exempt, a grouped one is not", function()
		t.expect(problem("2026-11-08", {}, false)).toBe(nil)
		t.expect(problem("2026-11-08", {}, true) ~= nil).toBe(true)
		t.expect(finalreview.exempt("2026-11-08", false)).toBe(true)
		t.expect(finalreview.exempt("2026-11-08", true)).toBe(false)
	end)

	it("AC2: a raft created before the cutoff day is exempt, one created on it is not", function()
		t.expect(finalreview.exempt("2026-11-07", true)).toBe(true)
		t.expect(finalreview.exempt("2026-11-08", true)).toBe(false)
		t.expect(problem("2026-11-07", {})).toBe(nil)
		t.expect(problem("2026-11-08", {}) ~= nil).toBe(true)
		-- a missing or unreadable created day is never an exemption (fail closed)
		t.expect(finalreview.exempt("", true)).toBe(false)
		t.expect(finalreview.exempt("soon", true)).toBe(false)
	end)

	it("AC2: round 3 that still sends the ticket back says to escalate, round 2 says to fix and rerun", function()
		local two = problem("2026-11-08", {
			["final-review-c0010-001.md"] = review("changes"),
			["final-review-c0010-002.md"] = review("changes"),
			["final-review-c0011-001.md"] = review("approve"),
		})
		t.expect(two ~= nil and has(two :: string, "round 3")).toBe(true)
		t.expect(two ~= nil and has(two :: string, "BLOCKED")).toBe(false)
		local three = problem("2026-11-08", {
			["final-review-c0010-001.md"] = review("changes"),
			["final-review-c0010-002.md"] = review("changes"),
			["final-review-c0010-003.md"] = review("changes"),
			["final-review-c0011-001.md"] = review("approve"),
		})
		t.expect(three ~= nil and has(three :: string, "BLOCKED")).toBe(true)
		t.expect(finalreview.MAX_ROUNDS).toBe(3)
	end)
end)
