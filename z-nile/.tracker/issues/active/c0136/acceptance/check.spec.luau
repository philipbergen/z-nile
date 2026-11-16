--!strict
-- c0136 AC2: `lessons.check` refuses a lesson filed under a step its harvest line does not name, a step that is no
-- skill, a line that differs from the reviewer's `Erred:` and `Upstream:` lines, a build-only lesson for a mistake
-- design made or should have caught, and a review that uses the lines half-way. Pure over texts: nothing is read
-- or written.
local lessons = require("@znile/engine/lessons")
local t = require("@tests/lib/t")

local function lesson(when: string?): string
	return `---\ntitle: T\nwhen: {when or "both"}\ntags: [wiring]\ncheck: Is it pinned?\nfrom: a user\n---\nBody.\n`
end

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

local function tree(items: { lessons.Item }): lessons.Tree
	return {
		lessons = {
			["z-design/a"] = lesson(),
			["z-ticket/b"] = lesson(),
			["zz-test/c"] = lesson(),
			["z-design/design-only"] = lesson("design"),
			["zz-execute/build-only"] = lesson("build"),
			["z-raft/build-only"] = lesson("build"),
			["zz-test/build-only"] = lesson("build"),
			["zz-review/build-only"] = lesson("build"),
		},
		found = {},
		skills = {
			["z-design"] = true,
			["z-ticket"] = true,
			["z-raft"] = true,
			["zz-test"] = true,
			["zz-execute"] = true,
			["zz-review"] = true,
		},
		items = items,
		problems = {},
	}
end

local FULL = review({
	{ id = "F1", lines = { "Erred: z-design", "Upstream: none" } },
	{ id = "F2", lines = { "Erred: z-design", "Upstream: z-ticket" } },
})

return t.spec("c0136 a lesson is filed under the step that erred", function(it)
	it("a lesson must be filed under a step its line names; the steps must be skills", function()
		local ok = {
			{
				id = "R0010",
				reviews = { ["design-review-001"] = review({ { id = "F1" }, { id = "F2" }, { id = "F3" } }) },
				harvest = "- design-review-001 F1 (erred z-design): z-design/a\n"
					.. "- design-review-001 F2 (erred z-design, upstream z-ticket): z-ticket/b, z-design/a\n"
					.. "- design-review-001 F3 (erred zz-test): zz-test/c\n",
			},
		}
		t.expect(lessons.check(tree(ok))).toEqual({})
		local wrong = {
			{
				id = "R0010",
				reviews = { ["design-review-001"] = review({ { id = "F1" }, { id = "F2" } }) },
				harvest = "- design-review-001 F1 (erred z-design): zz-test/c\n"
					.. "- design-review-001 F2 (erred z-gone): z-gone/x\n",
			},
		}
		local problems = lessons.check(tree(wrong))
		t.expect(
			has(problems, "R0010/harvest.md: design-review-001 F1: lesson zz-test/c is filed under zz-test")
		)
			.toBe(true)
		t.expect(has(problems, "which the line does not name (erred z-design)")).toBe(true)
		t.expect(has(problems, "design-review-001 F2: no skill z-gone")).toBe(true)
		-- a note is held to the same rule
		local note = {
			{
				id = "c0010",
				reviews = {},
				harvest = "- note the capture was vague (erred z-ticket): z-design/a\n",
			},
		}
		t.expect(
			has(
				lessons.check(tree(note)),
				"note the capture was vague: lesson z-design/a is filed under z-design"
			)
		).toBe(true)
		-- a lesson a legacy line names is not judged: the line names no step
		local legacy = {
			{
				id = "R0010",
				reviews = { ["design-review-001"] = review({ { id = "F1" } }) },
				harvest = "- design-review-001 F1: zz-test/c\n",
			},
		}
		t.expect(lessons.check(tree(legacy))).toEqual({})
	end)

	it(
		"a mistake design made or should have caught reaches design: a build-only lesson is refused",
		function()
			local function run(line: string, stem: string?): { string }
				local name = stem or "design-review-001"
				return lessons.check(tree({
					{
						id = "R0010",
						reviews = { [name] = review({ { id = "F1" } }) },
						harvest = line:gsub("STEM", name),
					},
				}))
			end
			-- erred names a design step, upstream names none
			local erred = run("- STEM F1 (erred z-raft): z-raft/build-only\n", "review-001")
			t.expect(
				has(
					erred,
					"lesson z-raft/build-only is when: build, but the line names a design step (erred z-raft)"
				)
			).toBe(true)
			-- the design step is only upstream: a build-step mistake design should have caught, found by a code review
			local up =
				run("- STEM F1 (erred zz-execute, upstream z-design): zz-execute/build-only\n", "review-001")
			t.expect(has(up, "zz-execute/build-only is when: build, but the line names a design step"))
				.toBe(true)
			-- every finding of a design review is a design-phase mistake, whichever skill the line names
			for _, line in
				{
					"- STEM F1 (erred zz-test): zz-test/build-only\n",
					"- STEM F1 (erred zz-execute): zz-execute/build-only\n",
				}
			do
				t.expect(has(run(line), "is when: build, but it answers a design review finding (erred "))
					.toBe(true)
			end
			-- ... except the reviewer's own mistake, which is a reviewer lesson
			t.expect(run("- STEM F1 (erred zz-review): zz-review/build-only\n")).toEqual({})
			-- the same line from a code review or a stream review names no design step: judged by the reviewer, not here
			t.expect(run("- STEM F1 (erred zz-test): zz-test/build-only\n", "review-001")).toEqual({})
			t.expect(run("- STEM F1 (erred zz-execute): zz-execute/build-only\n", "review-001")).toEqual({})
			-- design-only and both are fine
			t.expect(run("- STEM F1 (erred z-design): z-design/design-only\n")).toEqual({})
			t.expect(run("- STEM F1 (erred zz-test, upstream z-design): zz-test/c\n")).toEqual({})
			-- a legacy line names no step, so it is not judged
			t.expect(run("- STEM F1: zz-execute/build-only\n")).toEqual({})
			for _, step in { "z-ticket", "z-design", "z-raft" } do
				t.expect(table.find(lessons.DESIGN_STEPS, step) ~= nil).toBe(true) -- a later design step may join them
			end
		end
	)

	it("the reviewer's lines are the entry's: a different step or a different upstream is named", function()
		local function run(harvestLine: string): { string }
			return lessons.check(tree({
				{ id = "R0010", reviews = { ["design-review-001"] = FULL }, harvest = harvestLine },
			}))
		end
		t.expect(run("- design-review-001 F1 (erred z-design): z-design/a\n")).toEqual({})
		t.expect(run("- design-review-001 F2 (erred z-design, upstream z-ticket): z-ticket/b\n")).toEqual({})
		local erred = run("- design-review-001 F1 (erred zz-test): zz-test/c\n")
		t.expect(
			has(
				erred,
				"the line says (erred zz-test) but design-review-001.md F1 says Erred: z-design, Upstream: none"
			)
		).toBe(true)
		-- upstream alone differs: left out by the entry, named by the reviewer
		local up = run("- design-review-001 F2 (erred z-design): z-design/a\n")
		t.expect(has(up, "design-review-001.md F2 says Erred: z-design, Upstream: z-ticket")).toBe(true)
		-- an entry with no group, answering a finding whose review gives the lines, is refused: it copies them
		t.expect(
			has(
				run("- design-review-001 F1: z-design/a\n"),
				"gives Erred: z-design, Upstream: none: the entry copies them"
			)
		).toBe(true)
	end)

	it("a review that uses the step lines half-way fails --check by file and finding", function()
		local half = review({ { id = "F1", lines = { "Erred: z-design", "Upstream: none" } }, { id = "F2" } })
		local problems = lessons.check(
			tree({ { id = "R0010", reviews = { ["design-review-001"] = half }, harvest = nil } })
		)
		t.expect(has(problems, "R0010/design-review-001.md F2")).toBe(true)
	end)
	it(
		"lines that cannot be read bind nothing and are reported; a waiver note clears them, the review untouched",
		function()
			local bad = review({
				{ id = "F1", lines = { "Erred: z-desgin", "Upstream: none" } }, -- a typo
				{ id = "F2", lines = { "Erred: z-design", "Upstream: z-design" } }, -- the same step twice
				{ id = "F3", lines = { "Erred: z-design", "Upstream: none" } },
			})
			local function run(harvest: string): { string }
				return lessons.check(
					tree({ { id = "R0010", reviews = { ["design-review-001"] = bad }, harvest = harvest } })
				)
			end
			local entries = "- design-review-001 F1 (erred z-design): z-design/a\n"
				.. "- design-review-001 F2 (erred z-design): z-design/a\n"
				.. "- design-review-001 F3 (erred z-design): z-design/a\n"
			local problems = run(entries)
			t.expect(has(problems, "R0010/design-review-001.md F1: Erred: no skill z-desgin")).toBe(true)
			t.expect(has(problems, "R0010/design-review-001.md F2:")).toBe(true)
			t.expect(#problems).toBe(2) -- F3 is fine, and the entries (the author's own lines) are not contradicted
			local waived = run(
				entries
					.. "- note design-review-001 F1 step lines invalid (erred zz-review): zz-review/build-only\n"
					.. "- note design-review-001 F2 step lines invalid (erred zz-review): zz-review/build-only\n"
			)
			t.expect(waived).toEqual({})
			-- a waiver is for its finding only
			local partial = run(
				entries
					.. "- note design-review-001 F1 step lines invalid (erred zz-review): zz-review/build-only\n"
			)
			t.expect(#partial).toBe(1)
			t.expect(has(partial, "F2:")).toBe(true)
		end
	)
	it("the phase is the review's, wherever the answer is written: a note, a focused review", function()
		local function run(reviews: { [string]: string }, harvest: string): { string }
			return lessons.check(tree({ { id = "R0010", reviews = reviews, harvest = harvest } }))
		end
		local design = review({ { id = "F1", lines = { "Erred: z-design", "Upstream: none" } } })
		local entry = "- design-review-001 F1 (erred z-design): z-design/design-only\n"
		-- an author's disagreement, written as a note about the finding, is judged like the finding's own entry
		local note = run(
			{ ["design-review-001"] = design },
			entry .. "- note design-review-001 F1 the author disagrees (erred zz-test): zz-test/build-only\n"
		)
		t.expect(
			has(
				note,
				"note design-review-001 F1 the author disagrees: lesson zz-test/build-only is when: build"
			)
		).toBe(true)
		t.expect(has(note, "it answers a design review finding")).toBe(true)
		-- a design lesson in a third skill (an entry names at most two) goes in such a note, and is accepted
		t.expect(
			run(
				{ ["design-review-001"] = design },
				entry .. "- note design-review-001 F1 and a spec rule (erred zz-test): zz-test/c\n"
			)
		).toEqual({})
		-- a note without that head is a source that is not about a finding: not judged by the phase of any review
		t.expect(
			run(
				{ ["design-review-001"] = design },
				entry .. "- note the user said so (erred zz-test): zz-test/build-only\n"
			)
		).toEqual({})
		-- a focused review says which phase it looked at
		local function focused(phase: string): string
			return `# Review 001: R0010 (focused mode, {phase})\nInputs: abc\n\n### F1 [low] a claim\nWhere: x\nErred: zz-test\nUpstream: none\n\nVerdict: changes\n`
		end
		local line = "- focused-review-001 F1 (erred zz-test): zz-test/build-only\n"
		t.expect(
			has(
				run({ ["focused-review-001"] = focused("design") }, line),
				"it answers a design review finding"
			)
		)
			.toBe(true)
		t.expect(run({ ["focused-review-001"] = focused("build") }, line)).toEqual({})
		t.expect(
			has(
				run({ ["focused-review-001"] = focused("") }, line),
				"the heading must say (focused mode, design)"
			)
		).toBe(true)
		t.expect(lessons.reviewPhase("review-001", "# Review 001\n")).toBe("build")
		t.expect(lessons.reviewPhase("stream-review-c0010-001", "# Review 001\n")).toBe("build")
		t.expect(lessons.reviewPhase("design-review-002", "# x\n")).toBe("design")
	end)

	it("a waiver note is the reviewer-slip note, for a finding that has a problem", function()
		local bad = review({
			{ id = "F1", lines = { "Erred: z-desgin", "Upstream: none" } },
			{ id = "F2", lines = { "Erred: z-design", "Upstream: none" } },
		})
		local entries =
			"- design-review-001 F1 (erred z-design): z-design/a\n- design-review-001 F2 (erred z-design): z-design/a\n"
		local function run(waiver: string): { string }
			return lessons.check(tree({
				{ id = "R0010", reviews = { ["design-review-001"] = bad }, harvest = entries .. waiver },
			}))
		end
		t.expect(
			run("- note design-review-001 F1 step lines invalid (erred zz-review): zz-review/build-only\n")
		)
			.toEqual({})
		-- no group, another step, a finding without a problem, a review that is not there: each named
		t.expect(
			has(
				run("- note design-review-001 F1 step lines invalid: z-design/a\n"),
				"a waiver note is (erred zz-review)"
			)
		).toBe(true)
		t.expect(
			has(
				run("- note design-review-001 F1 step lines invalid (erred z-design): z-design/a\n"),
				"a waiver note is (erred zz-review)"
			)
		).toBe(true)
		t.expect(
			has(
				run(
					"- note design-review-001 F2 step lines invalid (erred zz-review): zz-review/build-only\n"
				),
				"has no step-line problem to waive"
			)
		).toBe(true)
		t.expect(
			has(
				run("- note review-004 F1 step lines invalid (erred zz-review): zz-review/build-only\n"),
				"no review-004.md in R0010"
			)
		).toBe(true)
	end)

	it("a skill renamed later (skills.RENAMED) keeps the records that name its old name valid", function()
		-- testing was renamed zz-test (c0115): a review line and a group written with the old name bind as zz-test
		local rev = review({ { id = "F1", lines = { "Erred: testing", "Upstream: none" } } })
		local steps = lessons.findingSteps(rev, { ["zz-test"] = true })
		t.expect(steps["F1"]).toEqual({ erred = "zz-test" })
		local ok = lessons.check(tree({
			{
				id = "R0010",
				reviews = { ["review-001"] = rev },
				harvest = "- review-001 F1 (erred testing): zz-test/c\n",
			},
		}))
		t.expect(ok).toEqual({})
		-- a name in neither the tree nor the table is still a problem
		local unknown = lessons.findingSteps(
			review({ { id = "F1", lines = { "Erred: made-up", "Upstream: none" } } }),
			{ ["zz-test"] = true }
		)
		t.expect(unknown["F1"]).toBe(nil)
	end)
	it("an unreadable phase fails closed: it is a problem and counts as design", function()
		local function focused(heading: string): string
			return `# Review 001: R0010 ({heading})\nInputs: abc\n\n### F1 [low] a claim\nWhere: x\nErred: zz-test\nUpstream: none\n\nVerdict: changes\n`
		end
		local line = "- focused-review-001 F1 (erred zz-test): zz-test/build-only\n"
		local function run(heading: string, extra: string?): { string }
			return lessons.check(tree({
				{
					id = "R0010",
					reviews = { ["focused-review-001"] = focused(heading) },
					harvest = line .. (extra or ""),
				},
			}))
		end
		for _, heading in
			{
				"focused mode, Design",
				"focused mode, both",
				"focused mode, prep",
				"focused mode",
				"focused mode, ",
			}
		do
			local problems = run(heading)
			t.expect(has(problems, "the heading must say (focused mode, design) or (focused mode, build)"))
				.toBe(true)
			t.expect(has(problems, "is when: build, but it answers a design review finding")).toBe(true) -- counted as design
		end
		-- a committed heading is never edited: a phase note supplies the phase and clears the problem
		local phase = "- note focused-review-001 phase build (erred zz-review): zz-review/build-only\n"
		t.expect(run("focused mode", phase)).toEqual({})
		local design = run(
			"focused mode",
			"- note focused-review-001 phase design (erred zz-review): zz-review/build-only\n"
		)
		t.expect(has(design, "is when: build, but it answers a design review finding")).toBe(true)
		t.expect(#design).toBe(1)
		-- the note's form: a focused review, erred zz-review, design or build, a review that is there, a heading that has the problem
		t.expect(
			has(
				run("focused mode", "- note focused-review-001 phase build: zz-review/build-only\n"),
				"a phase note is (erred zz-review)"
			)
		).toBe(true)
		t.expect(
			has(
				run(
					"focused mode",
					"- note focused-review-001 phase both (erred zz-review): zz-review/build-only\n"
				),
				"the phase is design or build"
			)
		).toBe(true)
		t.expect(
			has(
				run(
					"focused mode",
					"- note focused-review-002 phase build (erred zz-review): zz-review/build-only\n"
				),
				"no focused-review-002.md in R0010"
			)
		).toBe(true)
		t.expect(has(run("focused mode, build", phase), "already names its phase")).toBe(true)
		t.expect(
			has(
				run(
					"focused mode",
					"- note design-review-001 phase build (erred zz-review): zz-review/build-only\n"
				),
				"a phase note names a focused review"
			)
		).toBe(true)
	end)

	it("a note headed for a finding must name a review of the item and a finding it has", function()
		local design = review({ { id = "F1", lines = { "Erred: z-design", "Upstream: none" } } })
		local function run(note: string): { string }
			return lessons.check(tree({
				{
					id = "R0010",
					reviews = { ["design-review-001"] = design },
					harvest = "- design-review-001 F1 (erred z-design): z-design/design-only\n" .. note,
				},
			}))
		end
		t.expect(run("- note design-review-001 F1 more (erred zz-test): zz-test/c\n")).toEqual({})
		t.expect(
			has(
				run("- note design-review-002 F1 more (erred zz-test): zz-test/build-only\n"),
				"no design-review-002.md in R0010"
			)
		).toBe(true)
		t.expect(
			has(
				run("- note design-review-001 F9 more (erred zz-test): zz-test/c\n"),
				"design-review-001.md has no F9"
			)
		).toBe(true)
	end)

	it("a skill that exists under an old name is not mapped away by the rename table", function()
		-- a tree from before c0115 still has `testing`: its own name stands, and no zz-test is invented
		local rev = review({ { id = "F1", lines = { "Erred: testing", "Upstream: none" } } })
		t.expect(lessons.findingSteps(rev, { testing = true })["F1"]).toEqual({ erred = "testing" })
		local problems = lessons.check({
			lessons = { ["testing/x"] = lesson() },
			found = {},
			skills = { testing = true },
			items = {
				{
					id = "R0010",
					reviews = { ["review-001"] = rev },
					harvest = "- review-001 F1 (erred testing): testing/x\n",
				},
			},
			problems = {},
		})
		t.expect(problems).toEqual({})
	end)
	it(
		"the reviewer's-own-mistake exemption is for lessons filed under zz-review, not under the upstream skill",
		function()
			local rev = review({ { id = "F1", lines = { "Erred: zz-review", "Upstream: zz-test" } } })
			local function run(harvest: string): { string }
				return lessons.check(
					tree({ { id = "R0010", reviews = { ["design-review-001"] = rev }, harvest = harvest } })
				)
			end
			-- filed under zz-review: a reviewer reads those whatever their when:, so build is fine
			t.expect(
				run("- design-review-001 F1 (erred zz-review, upstream zz-test): zz-review/build-only\n")
			)
				.toEqual({})
			-- filed under the upstream skill: the next design never reads a build lesson there
			local up = run("- design-review-001 F1 (erred zz-review, upstream zz-test): zz-test/build-only\n")
			t.expect(has(up, "zz-test/build-only is when: build, but it answers a design review finding"))
				.toBe(true)
			-- the waiver and the note about a finding go through the same loop
			local waived = lessons.check(tree({
				{
					id = "R0010",
					reviews = {
						["design-review-001"] = review({
							{ id = "F1", lines = { "Erred: z-desgin", "Upstream: none" } },
						}),
					},
					harvest = "- design-review-001 F1 (erred z-design): z-design/design-only\n"
						.. "- note design-review-001 F1 step lines invalid (erred zz-review, upstream zz-test): zz-test/build-only\n",
				},
			}))
			t.expect(has(waived, "zz-test/build-only is when: build")).toBe(true)
		end
	)

	it("a note that tries to be a head and is not one is refused, a legacy note is not judged", function()
		local design = review({ { id = "F1", lines = { "Erred: z-design", "Upstream: none" } } })
		local function run(note: string): { string }
			return lessons.check(tree({
				{
					id = "R0010",
					reviews = { ["design-review-001"] = design },
					harvest = "- design-review-001 F1 (erred z-design): z-design/design-only\n" .. note,
				},
			}))
		end
		for _, text in
			{
				"design-review-01 F1 more",
				"design-review-001 f1 more",
				"design-review-001, F1 more",
				"design-review-001 F 1 more",
				"review 002 F1 more",
				"design review 001 F1 more",
			}
		do
			local problems = run(`- note {text} (erred zz-test): zz-test/build-only\n`)
			if not has(problems, "a note about a finding starts <stem> F<n>") then
				error(`not refused: {text}`)
			end
		end
		-- the same words with no group are legacy notes (as on main): not judged
		t.expect(run("- note design-review-004, the reviewer's note: zz-test/build-only\n")).toEqual({})
		-- a grouped note that merely mentions a review is not a head
		t.expect(
			run("- note the reviewer's note on design-review-004 (erred zz-review): zz-review/build-only\n")
		)
			.toEqual({})
	end)
	it(
		"a finding that is design's is judged once: its entry and every note about it get the same answer",
		function()
			-- a code review's finding the reviewer attributes to design (Upstream: z-design)
			local rev = review({ { id = "F1", lines = { "Erred: zz-execute", "Upstream: z-design" } } })
			local entry = "- review-001 F1 (erred zz-execute, upstream z-design): z-design/a\n"
			local function run(reviewText: string, harvest: string): { string }
				return lessons.check(
					tree({ { id = "R0010", reviews = { ["review-001"] = reviewText }, harvest = harvest } })
				)
			end
			-- the note's own group names no design step, the finding does: a build lesson is refused, a both lesson is not
			local refused = run(
				rev,
				entry .. "- note review-001 F1 a spec rule too (erred zz-test): zz-test/build-only\n"
			)
			t.expect(
				has(refused, "note review-001 F1 a spec rule too: lesson zz-test/build-only is when: build")
			)
				.toBe(true)
			t.expect(has(refused, "it answers a finding whose lines or entry name a design step")).toBe(true)
			t.expect(run(rev, entry .. "- note review-001 F1 a spec rule too (erred zz-test): zz-test/c\n"))
				.toEqual({})
			-- the lines alone make it design's, even when the entry's own group (a copy that differs) does not
			local alone = run(
				rev,
				"- review-001 F1 (erred zz-execute): zz-execute/build-only\n"
					.. "- note review-001 F1 a spec rule too (erred zz-test): zz-test/build-only\n"
			)
			t.expect(
				has(alone, "note review-001 F1 a spec rule too: lesson zz-test/build-only is when: build")
			)
				.toBe(true)
			-- no lines at all (a review from before c0136, or a backfill): the entry's group alone makes it design's
			local plain = review({ { id = "F1" } })
			t.expect(
				has(
					run(
						plain,
						entry .. "- note review-001 F1 a spec rule too (erred zz-test): zz-test/build-only\n"
					),
					"is when: build"
				)
			).toBe(true)
			-- a code finding with no design step anywhere stays a build matter
			t.expect(
				run(
					review({ { id = "F1", lines = { "Erred: zz-execute", "Upstream: none" } } }),
					"- review-001 F1 (erred zz-execute): zz-execute/build-only\n"
						.. "- note review-001 F1 and a test rule (erred zz-test): zz-test/build-only\n"
				)
			).toEqual({})
		end
	)
end)
