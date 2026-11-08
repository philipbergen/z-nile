--!strict
-- c0262 AC2: the rule `./zn done` applies to a raft's final reviews, and the exemption of rafts that predate it. Pure: z-nile/engine/finalreview.luau.
-- The reviews of a ticket are the final-review-NNN.md files of its own folder: `reviews` maps member -> file name -> text.
local finalreview = require("@znile/engine/finalreview")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function review(verdict: string, findings: string?): string
	return `# Review 001: c0010 (final mode)\nInputs: view\n\n{findings or ""}\nVerdict: {verdict}\n`
end
local GAP = "### F1 [high] the design misses the idea\nGap: design\n"
local IMPL = "### F1 [high] the implementation misses the design\nGap: implementation\n"
local function problem(created: string, reviews: { [string]: { [string]: string } }, grouped: boolean?): string?
	return finalreview.problem({
		raft = "R0099",
		created = created,
		grouped = grouped ~= false,
		issues = { "c0010", "c0011" },
		reviews = reviews,
	})
end
local OK = { ["final-review-001.md"] = review("on-course") }

return t.spec("c0262 AC2 the gate ./zn done applies to final reviews", function(it)
	it("AC2: done passes only when every member's newest final review is on-course", function()
		t.expect(problem("2026-11-08", { c0010 = OK, c0011 = OK })).toBe(nil)
	end)

	it("AC2: a member with no final review is named, with the command that makes it", function()
		local p = problem("2026-11-08", { c0010 = OK })
		t.expect(p ~= nil and has(p :: string, "c0011") and has(p :: string, "--mode final")).toBe(true)
	end)

	it("AC2: a first off-course verdict is a redo, routed by its gap: design goes back to z-design, implementation rebuilds the layer", function()
		local d = problem("2026-11-08", { c0010 = { ["final-review-001.md"] = review("off-course", GAP) }, c0011 = OK })
		t.expect(d ~= nil and has(d :: string, "c0010") and has(d :: string, "REDO") and has(d :: string, "z-design")).toBe(true)
		t.expect(has(d :: string, "BLOCKED")).toBe(false)
		local i = problem("2026-11-08", { c0010 = { ["final-review-001.md"] = review("off-course", IMPL) }, c0011 = OK })
		t.expect(i ~= nil and has(i :: string, "REDO") and has(i :: string, "rebuild")).toBe(true)
		t.expect(has(i :: string, "z-design")).toBe(false)
	end)

	it("AC2: a second off-course verdict blocks the ticket for the human, whatever the gaps", function()
		local p = problem("2026-11-08", {
			c0010 = {
				["final-review-001.md"] = review("off-course", GAP),
				["final-review-002.md"] = review("off-course", IMPL),
			},
			c0011 = OK,
		})
		t.expect(p ~= nil and has(p :: string, "BLOCKED") and has(p :: string, "c0010") and has(p :: string, "human")).toBe(true)
		t.expect(has(p :: string, "REDO")).toBe(false)
	end)

	it("AC2: only a newer on-course round clears it (rounds read by number); an author's answer file clears nothing", function()
		local cleared = problem("2026-11-08", {
			c0010 = {
				["final-review-001.md"] = review("off-course", GAP),
				["final-review-002.md"] = review("on-course"),
			},
			c0011 = OK,
		})
		t.expect(cleared).toBe(nil)
		local answered = problem("2026-11-08", {
			c0010 = {
				["final-review-001.md"] = review("off-course", IMPL),
				["final-refute-001.md"] = "- F1: fixed abc123: done; consequences: none\n",
			},
			c0011 = OK,
		})
		t.expect(answered ~= nil).toBe(true)
		local later = problem("2026-11-08", {
			c0010 = { ["final-review-001.md"] = review("on-course"), ["final-review-002.md"] = review("off-course", GAP) },
			c0011 = OK,
		})
		t.expect(later ~= nil and has(later :: string, "REDO")).toBe(true)
		local ten = problem("2026-11-08", {
			c0010 = {
				["final-review-001.md"] = review("off-course", GAP),
				["final-review-009.md"] = review("off-course", GAP),
				["final-review-010.md"] = review("on-course"),
			},
			c0011 = OK,
		})
		t.expect(ten).toBe(nil)
	end)

	it("AC2: a newest round with no Verdict line is refused; the verdict is read at a line start, once", function()
		local none = problem("2026-11-08", { c0010 = { ["final-review-001.md"] = "# Review\nnothing\n" }, c0011 = OK })
		t.expect(none ~= nil and has(none :: string, "c0010")).toBe(true)
		t.expect(finalreview.verdict("Verdict: On-Course\n")).toBe("on-course")
		t.expect(finalreview.verdict("Verdict: off-course\n")).toBe("off-course")
		t.expect(finalreview.verdict("Verdict: approve\n")).toBe(nil)
		t.expect(finalreview.verdict("quoted: Verdict: on-course in prose\nVerdict: off-course\n")).toBe("off-course")
		t.expect(finalreview.verdict("Verdict: on-course\nVerdict: on-course\n")).toBe(nil)
		t.expect(finalreview.verdict("see Verdict: on-course\n")).toBe(nil)
	end)

	it("AC2: an on-course verdict that still names a high or medium gap is refused, a low one passes, prose is not a gap", function()
		for _, sev in { "high", "medium" } do
			local p = problem("2026-11-08", {
				c0010 = { ["final-review-001.md"] = review("on-course", `### F1 [low] a\n\n### F2 [{sev}] gap\n`) },
				c0011 = OK,
			})
			t.expect(p ~= nil and has(p :: string, "c0010")).toBe(true)
		end
		t.expect(problem("2026-11-08", {
			c0010 = { ["final-review-001.md"] = review("on-course", "### F1 [low] a\n") },
			c0011 = OK,
		})).toBe(nil)
		t.expect(problem("2026-11-08", {
			c0010 = { ["final-review-001.md"] = review("on-course", "No [high] gap was found.\n") },
			c0011 = OK,
		})).toBe(nil)
		local f = finalreview.findings("### F1 [low] a\n### F2 [High] b\n### F3 c\n")
		t.expect(#f).toBe(3)
		t.expect(f[2].severity).toBe("high")
		t.expect(f[3].severity).toBe(nil)
	end)

	it("AC2: a file that is not a numbered final review of the ticket is ignored", function()
		local p = problem("2026-11-08", {
			c0010 = OK,
			c0011 = {
				["final-review-001.md"] = review("off-course", GAP),
				["final-review-002.md.bak"] = review("on-course"),
				["design-review-001.md"] = review("on-course"),
				["review-001.md"] = review("on-course"),
			},
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
		t.expect(finalreview.exempt("", true)).toBe(false)
		t.expect(finalreview.exempt("soon", true)).toBe(false)
	end)
end)
