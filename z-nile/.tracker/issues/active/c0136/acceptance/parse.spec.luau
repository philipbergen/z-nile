--!strict
-- c0136 AC1: the step group `(erred <skill>[, upstream <skill>])` on a harvest entry or a note, the `Erred:` and
-- `Upstream:` lines of a review finding, the refusal of a malformed one, entries written without a group read as
-- before, and the ledger rename reader that must see an id list behind a group. Pure over texts: no fixture, no file
-- read, nothing written.
local lessons = require("@znile/engine/lessons")
local t = require("@tests/lib/t")

-- a review: each finding is `### F<n> [low] claim`, then the given extra lines
local function review(findings: { { id: string, lines: { string }? } }): string
	local out = "# Review 001: R0010 (design mode)\nInputs: abc\n\n"
	for _, f in findings do
		out ..= `### {f.id} [medium] a claim\nWhere: x\nEvidence: Erred: is quoted here, not a field\n`
		local extra: { string } = f.lines or {}
		for _, line in extra do
			out ..= line .. "\n"
		end
		out ..= "\n"
	end
	return out .. "Verdict: changes\n"
end

local function has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) then
			return true
		end
	end
	return false
end

local FULL = review({
	{ id = "F1", lines = { "Erred: z-design", "Upstream: none" } },
	{ id = "F2", lines = { "Erred: z-design", "Upstream: z-ticket" } },
})

return t.spec("c0136 the step group and the finding lines are read", function(it)
	it("an entry names its step before the colon, and an entry without one is still read", function()
		local entries, problems = lessons.parseHarvest(
			"R0010",
			"# Harvest\n"
				.. "- design-review-001 F1 (erred z-design): z-design/a\n"
				.. "- design-review-001 F2 (erred z-design, upstream z-ticket): z-ticket/b, z-design/a\n"
				.. "- design-review-001 F3: z-design/a\n"
				.. "- review-001 F4 (erred none): one-off: the reviewer misread the spec\n"
				.. "- review-001 F5 (erred zz-execute): one-off: a typo in this item\n"
		)
		t.expect(problems).toEqual({})
		t.expect(#entries).toBe(5)
		t.expect(entries[1].erred).toBe("z-design")
		t.expect(entries[1].upstream).toBe(nil)
		t.expect(entries[1].lessons).toEqual({ "z-design/a" })
		t.expect(entries[2].erred).toBe("z-design")
		t.expect(entries[2].upstream).toBe("z-ticket")
		t.expect(entries[2].lessons).toEqual({ "z-ticket/b", "z-design/a" })
		t.expect(entries[3].erred).toBe(nil) -- written before the group existed
		t.expect(entries[3].lessons).toEqual({ "z-design/a" })
		t.expect(entries[4].erred).toBe("none")
		t.expect(entries[4].oneOff).toBe("the reviewer misread the spec")
		t.expect(entries[5].erred).toBe("zz-execute")
		t.expect(entries[5].oneOff).toBe("a typo in this item")
	end)

	it("a note's group is the end of its text; parentheses anywhere else stay text", function()
		local entries, problems = lessons.parseHarvest(
			"c0010",
			"- note c0010 prep round 2, one state was seeded (erred z-design): zz-test/c\n"
				.. "- note user 2026-11-02 (the capture was vague) said so (erred z-ticket, upstream none): z-ticket/b\n"
				.. "- note a legacy note (see the review): zz-test/c\n"
				.. "- note (erred z-design) is only the start of this text: zz-test/c\n"
		)
		-- the second line writes upstream none, which is left out instead: refused, named
		t.expect(#problems).toBe(1)
		t.expect(has(problems, "c0010/harvest.md")).toBe(true)
		t.expect(#entries).toBe(3)
		t.expect(entries[1].note).toBe("c0010 prep round 2, one state was seeded")
		t.expect(entries[1].erred).toBe("z-design")
		t.expect(entries[2].note).toBe("a legacy note (see the review)")
		t.expect(entries[2].erred).toBe(nil)
		t.expect(entries[3].note).toBe("(erred z-design) is only the start of this text")
		t.expect(entries[3].erred).toBe(nil)
	end)

	it(
		"a malformed group, a repeated or empty step and erred none with a lesson are named, never guessed",
		function()
			local entries, problems = lessons.parseHarvest(
				"R0010",
				"- design-review-001 F1 (erred): z-design/a\n" -- no skill
					.. "- design-review-001 F2 (erred Z Design): z-design/a\n" -- not kebab
					.. "- design-review-001 F3 (erred z-design, upstream z-design): z-design/a\n" -- same step
					.. "- design-review-001 F4 (erred z-design, upstream none): z-design/a\n" -- none is left out
					.. "- design-review-001 F5 (erred z-design, extra z-ticket): z-design/a\n" -- unknown key
					.. "- design-review-001 F6 (upstream z-ticket): z-ticket/b\n" -- upstream alone
					.. "- design-review-001 F7 (erred none): z-design/a\n" -- none names no lesson
					.. "- design-review-001 F8 (erred z-design) (erred z-ticket): z-design/a\n" -- two groups
					.. "- note a note (erred none): z-design/a\n"
					.. "- design-review-001 F9 (erred none, upstream z-ticket): one-off: x\n" -- no mistake, yet an earlier step
			)
			t.expect(#entries).toBe(0)
			t.expect(#problems).toBe(10)
			for _, key in { "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "a note" } do
				if not has(problems, key) then
					error(`no problem names {key}`)
				end
			end
		end
	)

	it("a note keeps its text for a reader that matches it (c0166's five-round note)", function()
		local entries, problems = lessons.parseHarvest(
			"R0010",
			"- note 5 design rounds, design prompt unclear (erred z-design): z-design/a\n"
				.. "- note 5 design rounds, design prompt unclear: z-design/a\n"
		)
		t.expect(problems).toEqual({})
		t.expect(entries[1].note).toBe("5 design rounds, design prompt unclear")
		t.expect(entries[1].erred).toBe("z-design")
		t.expect(entries[2].note).toBe("5 design rounds, design prompt unclear")
		t.expect(entries[2].erred).toBe(nil)
	end)

	it(
		"a finding's lines go through the rules a harvest group does, and a quoted template is not a field",
		function()
			local function steps(lines: { string }, skills: { [string]: boolean }?)
				return lessons.findingSteps(review({ { id = "F1", lines = lines } }), skills)
			end
			-- the same skill on both lines, none with an upstream, an unknown skill: refused, and the finding binds nothing
			local same, sameProblems = steps({ "Erred: z-design", "Upstream: z-design" })
			t.expect(same["F1"]).toBe(nil)
			t.expect(has(sameProblems, "F1:")).toBe(true)
			local none, noneProblems = steps({ "Erred: none", "Upstream: z-ticket" })
			t.expect(none["F1"]).toBe(nil)
			t.expect(has(noneProblems, "F1:")).toBe(true)
			local typo, typoProblems = steps({ "Erred: z-desgin", "Upstream: none" }, { ["z-design"] = true })
			t.expect(typo["F1"]).toBe(nil)
			t.expect(has(typoProblems, "F1: Erred: no skill z-desgin")).toBe(true)
			-- without a skill list the same lines read (the pure parse does not know the skills)
			t.expect(steps({ "Erred: z-desgin", "Upstream: none" })["F1"]).toEqual({ erred = "z-desgin" })
			-- a template quoted in a code fence, and a line after a section heading, are nobody's field
			local quoted = "# Review 001\n\n### F1 [low] c\nEvidence: x\n```markdown\nErred: <skill, or none>\n```\n"
				.. "Erred: z-design\nUpstream: none\n\n## Judged criteria\nErred: z-ticket\n\nVerdict: changes\n"
			local got, gotProblems = lessons.findingSteps(quoted)
			t.expect(gotProblems).toEqual({})
			t.expect(got["F1"]).toEqual({ erred = "z-design" })
		end
	)

	it("a finding's Erred and Upstream lines are read per finding; none leaves upstream out", function()
		local steps, problems = lessons.findingSteps(FULL)
		t.expect(problems).toEqual({})
		t.expect(steps["F1"]).toEqual({ erred = "z-design" })
		t.expect(steps["F2"]).toEqual({ erred = "z-design", upstream = "z-ticket" })
		-- a review written before the lines existed has none, and no problem
		local old, oldProblems = lessons.findingSteps(review({ { id = "F1" }, { id = "F2" } }))
		t.expect(old).toEqual({})
		t.expect(oldProblems).toEqual({})
	end)

	it(
		"once any finding has a step line every finding needs both, and a line is not repeated or empty",
		function()
			local _, half = lessons.findingSteps(review({
				{ id = "F1", lines = { "Erred: z-design", "Upstream: none" } },
				{ id = "F2" },
				{ id = "F3", lines = { "Erred: z-design" } },
			}))
			t.expect(#half).toBe(2)
			t.expect(has(half, "F2")).toBe(true)
			t.expect(has(half, "F3")).toBe(true)
			local _, twice = lessons.findingSteps(
				review({ { id = "F1", lines = { "Erred: z-design", "Erred: z-ticket", "Upstream: none" } } })
			)
			t.expect(has(twice, "F1: Erred: is repeated")).toBe(true)
			local _, bad = lessons.findingSteps(
				review({ { id = "F1", lines = { "Erred: Z Design", "Upstream: none" } } })
			)
			t.expect(has(bad, "F1: Erred: needs a skill name or none")).toBe(true)
		end
	)

	it("the old-id rules reach an id list behind a step group", function()
		local existing = { ["zz-test/pin"] = true }
		local ledger = "- design-review-001 F1 (erred zz-test): testing/pin, testing/gone\n"
			.. "- note one (erred z-design): testing/pin\n"
		local found, unknown = lessons.ledgerOldIds(ledger, existing)
		t.expect(found).toEqual({ "testing/pin", "testing/gone", "testing/pin" })
		t.expect(unknown).toEqual({ "testing/gone" })
		local renamed, n = lessons.renameLedger(ledger, existing)
		t.expect(n).toBe(2)
		t.expect(renamed).toBe(
			"- design-review-001 F1 (erred zz-test): zz-test/pin, testing/gone\n"
				.. "- note one (erred z-design): zz-test/pin\n"
		)
	end)
	it("a note about a finding has a head the engine reads; any other note has none", function()
		local stem, finding, rest = lessons.noteHead("design-review-001 F3 the author disagrees")
		t.expect(stem).toBe("design-review-001")
		t.expect(finding).toBe("F3")
		t.expect(rest).toBe("the author disagrees")
		local s2, f2, r2 = lessons.noteHead("stream-review-c0010-001 F1 step lines invalid")
		t.expect(s2).toBe("stream-review-c0010-001")
		t.expect(f2).toBe("F1")
		t.expect(r2).toBe("step lines invalid")
		-- not a review stem, not a finding id, nothing after: no head, the text unchanged
		for _, text in { "notes-001 F1 x", "design-review-001 x", "the user said so", "design-review-001 F" } do
			local a, b, c = lessons.noteHead(text)
			t.expect(a).toBe(nil)
			t.expect(b).toBe(nil)
			t.expect(c).toBe(text)
		end
	end)

	it("the ledger rename also renames the skill names of a step group", function()
		local existing = { ["zz-test/pin"] = true }
		local ledger = "- design-review-001 F1 (erred testing, upstream ticket-prep): testing/pin\n"
			.. "- review-001 F2 (erred review): one-off: x\n"
			.. "- note one (erred testing): testing/pin\n"
		local found = lessons.ledgerOldIds(ledger, existing)
		t.expect(has(found, "testing/(step)")).toBe(true)
		t.expect(has(found, "ticket-prep/(step)")).toBe(true)
		t.expect(has(found, "review/(step)")).toBe(true)
		local renamed = lessons.renameLedger(ledger, existing)
		t.expect(renamed).toBe(
			"- design-review-001 F1 (erred zz-test, upstream z-design): zz-test/pin\n"
				.. "- review-001 F2 (erred zz-review): one-off: x\n"
				.. "- note one (erred zz-test): zz-test/pin\n"
		)
	end)
	it(
		"one fence rule: the indented close, a longer fence, a tilde fence and a fence never closed",
		function()
			local function body(fence: string, close: string): string
				return "# Review 001\n\n### F1 [low] c\nEvidence: x\n"
					.. fence
					.. "\nErred: <skill, or none>\n"
					.. close
					.. "\nErred: z-design\nUpstream: none\n\n### F2 [low] c\nErred: z-desgin\nUpstream: none\n\nVerdict: changes\n"
			end
			local skills = { ["z-design"] = true }
			-- each closes properly: F1 binds, F2 (a typo) is a problem
			for _, shape in
				{
					{ "```", "```" },
					{ "````", "````" },
					{ "~~~markdown", "~~~" },
					{ "```", "  ```" }, -- up to three spaces
				}
			do
				local got, problems = lessons.findingSteps(body(shape[1], shape[2]), skills)
				t.expect(got["F1"]).toEqual({ erred = "z-design" })
				t.expect(has(problems, "F2: Erred: no skill z-desgin")).toBe(true)
			end
			-- a closer four spaces in is not a closer: the fence never ends, so the file is read with no fences and the
			-- quoted template shows as the problem it would be, not as a review with no lines
			local _, problems = lessons.findingSteps(body("```", "    ```"), skills)
			t.expect(has(problems, "F1: Erred: needs a skill name or none")).toBe(true)
			t.expect(has(problems, "F2: Erred: no skill z-desgin")).toBe(true)
		end
	)

	it("a fence closes only with its own character and at least its own length", function()
		local skills = { ["z-design"] = true }
		local function steps(fenced: string)
			local text = "# Review 001\n\n### F1 [low] c\nEvidence: x\n"
				.. fenced
				.. "\nErred: z-design\nUpstream: none\n\nVerdict: changes\n"
			return lessons.findingSteps(text, skills)
		end
		-- a three-backtick line inside a four-backtick fence, and a tilde line inside a backtick fence, close nothing
		for _, fenced in
			{
				"````markdown\n```\nErred: <skill, or none>\n```\n````",
				"```\n~~~\nErred: <skill, or none>\n~~~\n```",
			}
		do
			local got, problems = steps(fenced)
			t.expect(problems).toEqual({})
			t.expect(got["F1"]).toEqual({ erred = "z-design" })
		end
	end)

	it(
		"checkNewReview: a new review gives every finding its lines; an approving round with no finding passes",
		function()
			local skills = { ["z-design"] = true }
			local none = "# Review 001\n\n### F1 [low] c\nEvidence: x\n\nVerdict: changes\n"
			t.expect(has(lessons.checkNewReview("design-review-003", none, skills), "no step lines"))
				.toBe(true)
			local bold =
				"# Review 001\n\n### F1 [low] c\n**Erred:** z-design\n- Upstream: none\n\nVerdict: changes\n"
			t.expect(has(lessons.checkNewReview("design-review-003", bold, skills), "no step lines"))
				.toBe(true)
			t.expect(
				lessons.checkNewReview("design-review-003", "# Review 003\n\nVerdict: approve\n", skills)
			)
				.toEqual({})
			local good =
				"# Review 001\n\n### F1 [low] c\nErred: z-design\nUpstream: none\n\nVerdict: changes\n"
			t.expect(lessons.checkNewReview("design-review-003", good, skills)).toEqual({})
			-- a focused text is judged by its heading wherever it is saved (a dispatcher calls every file review.md)
			local focused =
				"# Review 001: c0010 (focused mode)\n\n### F1 [low] c\nErred: z-design\nUpstream: none\n"
			t.expect(
				has(
					lessons.checkNewReview("review", focused, skills),
					"the heading must say (focused mode, design)"
				)
			).toBe(true)
			t.expect(
				lessons.checkNewReview("review", (string.gsub(focused, "mode%)", "mode, build)", 1)), skills)
			)
				.toEqual({})
			t.expect(has(lessons.checkNewReview("focused-review-001", good, skills), "the heading must say"))
				.toBe(true)
		end
	)
end)
