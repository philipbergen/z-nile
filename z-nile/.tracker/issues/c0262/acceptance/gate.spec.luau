--!strict
-- c0262 AC2: the rule `./zn done` applies to a raft's final reviews, and the exemption of rafts that predate it. Pure: z-nile/engine/finalreview.luau.
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
	it("AC2: done passes only when every member's newest final review is an approve", function()
		local ok = {
			["final-review-c0010-001.md"] = review("approve"),
			["final-review-c0011-001.md"] = review("approve"),
		}
		t.expect(problem("2026-11-08", ok)).toBe(nil)
	end)

	it("AC2: a member with no final review is named, with the command that makes it", function()
		local p = problem("2026-11-08", { ["final-review-c0010-001.md"] = review("approve") })
		t.expect(p ~= nil and has(p :: string, "c0011") and has(p :: string, "--mode final")).toBe(true)
	end)

	it("AC2: a review that did not approve is BLOCKED for the user, with its file named", function()
		local p = problem("2026-11-08", {
			["final-review-c0010-001.md"] = review("changes", "### F1 [medium] off course\nOff course: implementation\n"),
			["final-review-c0011-001.md"] = review("approve"),
		})
		t.expect(p ~= nil and has(p :: string, "final-review-c0010-001.md") and has(p :: string, "BLOCKED")).toBe(true)
	end)

	it("AC2: an author's answer file never clears it: only a newer approving round does", function()
		local blocked = problem("2026-11-08", {
			["final-review-c0010-001.md"] = review("changes", "### F1 [medium] x\n"),
			["final-refute-c0010-001.md"] = "- F1: fixed abc123: done; consequences: none\n",
			["final-review-c0011-001.md"] = review("approve"),
		})
		t.expect(blocked ~= nil).toBe(true)
		local ok = {
			["final-review-c0010-001.md"] = review("changes", "### F1 [medium] x\n"),
			["final-review-c0010-002.md"] = review("approve"),
			["final-review-c0011-001.md"] = review("approve"),
		}
		t.expect(problem("2026-11-08", ok)).toBe(nil)
		-- a later changes is not cleared by an earlier approve, and rounds are read by number, not by name order
		local bad = {
			["final-review-c0010-001.md"] = review("approve"),
			["final-review-c0010-002.md"] = review("changes", "### F1 [medium] x\n"),
			["final-review-c0011-001.md"] = review("approve"),
		}
		t.expect(problem("2026-11-08", bad) ~= nil).toBe(true)
		local ten = {
			["final-review-c0010-009.md"] = review("changes", "### F1 [medium] x\n"),
			["final-review-c0010-010.md"] = review("approve"),
			["final-review-c0011-001.md"] = review("approve"),
		}
		t.expect(problem("2026-11-08", ten)).toBe(nil)
	end)

	it("AC2: a newest round with no Verdict line is refused, and Verdict: Approve reads like approve", function()
		local none = problem("2026-11-08", {
			["final-review-c0010-001.md"] = "# Review\nno verdict here\n",
			["final-review-c0011-001.md"] = review("approve"),
		})
		t.expect(none ~= nil and has(none :: string, "c0010")).toBe(true)
		t.expect(finalreview.verdict("Verdict: Approve\n")).toBe("approve")
		t.expect(finalreview.verdict("Verdict: changes requested\n")).toBe("changes")
		t.expect(finalreview.verdict("no verdict")).toBe(nil)
	end)

	it("AC2: an approve that still carries a high finding is refused, and prose about [high] is not a finding", function()
		local p = problem("2026-11-08", {
			["final-review-c0010-001.md"] = review("approve", "### F1 [low] a\n\n### F2 [high] off course\n"),
			["final-review-c0011-001.md"] = review("approve"),
		})
		t.expect(p ~= nil and has(p :: string, "c0010")).toBe(true)
		local fine = problem("2026-11-08", {
			["final-review-c0010-001.md"] = review("approve", "No [high] finding was found.\n"),
			["final-review-c0011-001.md"] = review("approve"),
		})
		t.expect(fine).toBe(nil)
		local f = finalreview.findings("### F1 [low] a\n### F2 [High] b\n### F3 c\n")
		t.expect(#f).toBe(3)
		t.expect(f[2].severity).toBe("high")
		t.expect(f[3].severity).toBe(nil)
	end)

	it("AC2: a file that is not a numbered final round of a member is ignored", function()
		local p = problem("2026-11-08", {
			["final-review-c0010-001.md"] = review("approve"),
			["final-review-c0011-001.md"] = review("changes"),
			["final-review-c0011-002.md.bak"] = review("approve"),
			["stream-review-c0011-001.md"] = review("approve"),
			["review-001.md"] = review("approve"),
		})
		t.expect(p ~= nil and has(p :: string, "c0011")).toBe(true)
	end)

	it("AC2: a raft z-raft did not make (no grouped record) is exempt, a grouped one is not", function()
		t.expect(problem("2026-11-08", {}, false)).toBe(nil)
		t.expect(problem("2026-11-08", {}, true) ~= nil).toBe(true)
		t.expect(finalreview.exempt("2026-11-08", false)).toBe(true)
		t.expect(finalreview.exempt("2026-11-08", true)).toBe(false)
	end)

	it("AC2: a raft created before the cutoff day is exempt, one created on it is not, an unreadable day is not", function()
		t.expect(finalreview.exempt("2026-11-07", true)).toBe(true)
		t.expect(finalreview.exempt("2026-11-08", true)).toBe(false)
		t.expect(problem("2026-11-07", {})).toBe(nil)
		t.expect(problem("2026-11-08", {}) ~= nil).toBe(true)
		t.expect(finalreview.exempt("", true)).toBe(false)
		t.expect(finalreview.exempt("soon", true)).toBe(false)
	end)

	it("AC2: nothing reads a round count: the fifth non-approving round is BLOCKED like the first", function()
		local p = problem("2026-11-08", {
			["final-review-c0010-005.md"] = review("changes"),
			["final-review-c0011-001.md"] = review("approve"),
		})
		t.expect(p ~= nil and has(p :: string, "BLOCKED")).toBe(true)
		t.expect((finalreview :: any).MAX_ROUNDS).toBe(nil)
	end)
end)
