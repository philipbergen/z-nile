--!strict
-- c0316 AC2, AC3, AC4, AC7: harvest.md takes an escape entry, a finding names the stage that made it, the escapes the
-- tracker sees (a finding made at an earlier stage than its review, a second approval, a stop, a rework) are listed
-- when no entry covers them, a finding with no Stage line is named, `check` refuses an entry with nothing behind it,
-- and the report's counts go under the stage that made and the stage that found each escape.
-- Pure: hand-built items and trees, no file system, no git, no CLI.
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")

-- a review whose findings are given as { heading, extra lines }: "F1" with no extra line has no Stage line
local function review(blocks: { { string } }): string
	local out = "# Review 001: R0010\nInputs: abc\n\n"
	for _, b in blocks do
		out ..= `### {b[1]} [medium] a claim\nWhere: x\n`
		for i = 2, #b do
			out ..= `{b[i]}\n`
		end
		out ..= "Evidence: text\n\n"
	end
	return out .. "Verdict: changes\n"
end

local FROM =
	"---\ntitle: T\nwhen: build\ntags: [wiring]\ncheck: Is it pinned?\nfrom: user 2026-11-13: told us\n---\nBody.\n"

local function has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) then
			return true
		end
	end
	return false
end

local function tree(items: { lessons.Item }, found: { [string]: boolean }?): lessons.Tree
	return {
		lessons = { ["testing/pin"] = FROM },
		found = found or {},
		skills = { testing = true },
		items = items,
		problems = {},
	}
end

return t.spec("c0316 escapes", function(it)
	it(
		"AC2: an escape entry parses with its kind, number and stage; an unknown kind, a bad number, an unknown stage and a second entry for the same escape are problems",
		function()
			local entries, problems = lessons.parseHarvest(
				"R0010",
				"- design-review-001 F1: testing/pin\n"
					.. "- escape redesign 2 (design): testing/pin\n"
					.. "- escape stop 1 (implementation): one-off: main moved\n"
					.. "- escape rework 1 (idea): testing/pin, review/text\n"
			)
			t.expect(problems).toEqual({})
			t.expect(#entries).toBe(4)
			t.expect(entries[1].escape).toBe(nil)
			t.expect(entries[2].escape).toEqual({ kind = "redesign", n = 2, stage = "design" })
			t.expect(entries[2].lessons).toEqual({ "testing/pin" })
			t.expect(entries[3].escape).toEqual({ kind = "stop", n = 1, stage = "implementation" })
			t.expect(entries[3].oneOff).toBe("main moved")
			t.expect(entries[4].escape).toEqual({ kind = "rework", n = 1, stage = "idea" })
			t.expect(entries[4].lessons).toEqual({ "testing/pin", "review/text" })
			t.expect(lessons.STAGES).toEqual({ "idea", "design", "implementation" })

			-- each bad line alone: one problem that names the line, and no entry
			local bad = {
				{ "- escape bogus 1 (design): testing/pin", "bogus" }, -- M1: any word is a kind
				{ "- escape finding 1 (design): testing/pin", "finding" }, -- a finding is not a harvest escape kind
				{ "- escape stop 1 (nowhere): testing/pin", "nowhere" }, -- M2: any word is a stage
				{ "- escape stop 1 (): testing/pin", "escape stop 1" },
				{ "- escape stop 0 (design): testing/pin", "escape stop 0" },
				{ "- escape stop -1 (design): testing/pin", "escape stop -1" },
				{ "- escape stop 1.5 (design): testing/pin", "escape stop 1.5" },
				{ "- escape stop two (design): testing/pin", "escape stop two" },
				{ "- escape stop 02 (design): testing/pin", "escape stop 02" },
				{ "- escape stop 1 (design): Not An Id", "escape stop 1" },
				{ "- escape stop 1 (design): one-off:", "escape stop 1" },
			}
			for _, case in bad do
				local e, p = lessons.parseHarvest("R0010", case[1] .. "\n")
				t.expect(#e).toBe(0)
				t.expect(#p).toBe(1)
				t.expect(has(p, "R0010")).toBe(true)
				t.expect(has(p, case[2])).toBe(true)
			end

			-- M3: a second entry for the same kind and number is refused, the first kept
			local dupE, dupP = lessons.parseHarvest(
				"R0010",
				"- escape stop 1 (design): testing/pin\n- escape stop 1 (idea): review/text\n"
			)
			t.expect(#dupE).toBe(1)
			t.expect(dupE[1].escape).toEqual({ kind = "stop", n = 1, stage = "design" })
			t.expect(#dupP).toBe(1)
			t.expect(has(dupP, "escape stop 1")).toBe(true)
			-- a different number or kind is a different escape
			local ok, okP = lessons.parseHarvest(
				"R0010",
				"- escape stop 1 (design): testing/pin\n- escape stop 2 (design): testing/pin\n"
					.. "- escape redesign 2 (design): testing/pin\n- escape redesign 3 (design): testing/pin\n"
			)
			t.expect(okP).toEqual({})
			t.expect(#ok).toBe(4)
		end
	)

	it(
		"AC2: a finding's stage is read from its own block, not the next finding's; a finding with no line has none",
		function()
			local text = review({
				{ "F1" }, -- no line, and F2 has one right after
				{ "F2", "Stage: idea" },
				{ "F3", "Stage: design" },
			}) .. "## Verdict section\nStage: implementation\n"
			t.expect(lessons.stageOf(text, "F1")).toBe(nil) -- M4: the first Stage line after the heading, wherever
			t.expect(lessons.stageOf(text, "F2")).toBe("idea")
			t.expect(lessons.stageOf(text, "F3")).toBe("design") -- not the line of the later `##` heading
			t.expect(lessons.stageOf(text, "F9")).toBe(nil) -- no such finding

			-- F1 is a prefix of F10, and a Stage line before the first heading is nobody's
			local tens = "Stage: idea\n### F10 [low] x\nStage: design\n### F1 [low] y\nWhere: z\n"
			t.expect(lessons.stageOf(tens, "F1")).toBe(nil)
			t.expect(lessons.stageOf(tens, "F10")).toBe("design")
			-- a deeper heading stays inside the block; a `##` heading ends it
			local deeper =
				"### F1 [low] x\n#### detail\nStage: implementation\n## Next\n### F2 [low] y\nStage: idea\n"
			t.expect(lessons.stageOf(deeper, "F1")).toBe("implementation")
			t.expect(lessons.stageOf(deeper, "F2")).toBe("idea")
			-- an unknown stage is no stage
			t.expect(lessons.stageOf("### F1 [low] x\nStage: nowhere\n", "F1")).toBe(nil)
			t.expect(lessons.stageOf("### F1 [low] x\nStage:\n", "F1")).toBe(nil)
		end
	)

	it(
		"AC2: a design-review finding marked idea is an escape, one marked design is not; a review finding marked design or idea is, one marked implementation is not",
		function()
			t.expect(lessons.reviewStage("design-review-001")).toBe("design")
			t.expect(lessons.reviewStage("review-002")).toBe("implementation") -- M6: design for every stem
			t.expect(lessons.reviewStage("final-review-003")).toBe("implementation")
			local item: lessons.Item = {
				id = "R0010",
				reviews = {
					["design-review-001"] = review({
						{ "F1", "Stage: idea" },
						{ "F2", "Stage: design" },
						{ "F3", "Stage: implementation" },
						{ "F4" },
					}),
					["review-001"] = review({
						{ "F1", "Stage: design" },
						{ "F2", "Stage: idea" },
						{ "F3", "Stage: implementation" },
						{ "F4" },
					}),
				},
				harvest = nil,
			}
			-- M5: every marked finding is an escape (F2 of the design review, F3 of both, would be listed)
			t.expect(lessons.escapes(item)).toEqual({
				{
					item = "R0010",
					kind = "finding",
					ref = "design-review-001 F1",
					made = "idea",
					found = "design",
				},
				{
					item = "R0010",
					kind = "finding",
					ref = "review-001 F1",
					made = "design",
					found = "implementation",
				},
				{
					item = "R0010",
					kind = "finding",
					ref = "review-001 F2",
					made = "idea",
					found = "implementation",
				},
			})
			-- a final review is an implementation review as well
			local final: lessons.Item = {
				id = "R0011",
				reviews = {
					["final-review-001"] = review({
						{ "F1", "Stage: design" },
						{ "F2", "Stage: implementation" },
					}),
				},
				harvest = nil,
			}
			local list = lessons.escapes(final)
			t.expect(#list).toBe(1)
			t.expect(list[1].ref).toBe("final-review-001 F1")
			t.expect(list[1].found).toBe("implementation")
		end
	)

	it(
		"AC3: uncovered lists a second approval, each stop and a rework with no entry, after the item's findings, and none of them once its entry exists",
		function()
			local function item(harvest: string?): lessons.Item
				return {
					id = "R0010",
					reviews = { ["review-001"] = review({ { "F1" } }) },
					harvest = harvest,
					approvals = 3,
					stops = 2,
					reworks = "c0100",
				}
			end
			local finding = "R0010 review-001 F1"
			-- nothing covers anything: the findings first (M10), then redesign, stop and rework in order;
			-- the first approval is no escape (M7) and every stop is asked for (M9)
			t.expect(lessons.uncovered({ item(nil) })).toEqual({
				finding,
				"R0010 escape redesign 2",
				"R0010 escape redesign 3",
				"R0010 escape stop 1",
				"R0010 escape stop 2",
				"R0010 escape rework 1",
			})
			-- M8: an entry for redesign 2 does not cover redesign 3; one for stop 2 does not cover stop 1
			t.expect(lessons.uncovered({
				item("- escape redesign 2 (design): testing/pin\n- escape stop 2 (design): testing/pin\n"),
			})).toEqual({
				finding,
				"R0010 escape redesign 3",
				"R0010 escape stop 1",
				"R0010 escape rework 1",
			})
			-- an entry covers its own kind only
			t.expect(lessons.uncovered({ item("- escape stop 2 (design): testing/pin\n") })).toEqual({
				finding,
				"R0010 escape redesign 2",
				"R0010 escape redesign 3",
				"R0010 escape stop 1",
				"R0010 escape rework 1",
			})
			-- every entry present: only what is still uncovered by the finding's own entry remains
			local all = "- escape redesign 2 (design): testing/pin\n- escape redesign 3 (idea): testing/pin\n"
				.. "- escape stop 1 (implementation): one-off: moved\n- escape stop 2 (design): testing/pin\n"
				.. "- escape rework 1 (implementation): testing/pin\n"
			t.expect(lessons.uncovered({ item(all) })).toEqual({ finding })
			t.expect(lessons.uncovered({ item(all .. "- review-001 F1: testing/pin\n") })).toEqual({})
			-- another item sorts by id, and its escapes follow its own findings
			local other: lessons.Item = {
				id = "R0005",
				reviews = {},
				harvest = nil,
				stops = 1,
			}
			t.expect(lessons.uncovered({ item(nil), other })[1]).toBe("R0005 escape stop 1")
		end
	)

	it(
		"AC3: uncovered prints exactly what it printed before for a tree with no approvals, stops or reworks",
		function()
			local function rv(...: string): string
				local blocks = {}
				for _, f in { ... } do
					table.insert(blocks, { f })
				end
				return review(blocks)
			end
			local expected = {
				"R0010 design-review-001 F1",
				"R0010 design-review-001 F10",
				"R0010 review-001 F1",
				"c0020 review-001 F1",
			}
			local function items(
				extra: { approvals: number?, stops: number?, reworks: string? }
			): { lessons.Item }
				return {
					{
						id = "R0010",
						reviews = { ["design-review-001"] = rv("F1", "F2", "F10"), ["review-001"] = rv("F1") },
						harvest = "- design-review-001 F2: testing/pin\n",
						approvals = extra.approvals,
						stops = extra.stops,
						reworks = extra.reworks,
					},
					{
						id = "c0020",
						reviews = { ["review-001"] = rv("F1") },
						harvest = nil,
						approvals = extra.approvals,
						stops = extra.stops,
						reworks = extra.reworks,
					},
					{
						id = "R0030",
						reviews = { ["design-review-001"] = "# Review\n\nVerdict: approve\n" },
						harvest = nil,
					},
				}
			end
			t.expect(lessons.uncovered(items({}))).toEqual(expected) -- the fields absent, as every caller builds an item today
			t.expect(lessons.uncovered(items({ approvals = 0, stops = 0, reworks = nil }))).toEqual(expected)
			t.expect(lessons.uncovered(items({ approvals = 1, stops = 0, reworks = "" }))).toEqual(expected)
			-- F2 before F10 still
			t.expect(lessons.uncovered({
				{ id = "R0010", reviews = { ["design-review-001"] = rv("F10", "F2") }, harvest = nil },
			})).toEqual({ "R0010 design-review-001 F2", "R0010 design-review-001 F10" })
		end
	)

	it(
		"AC3: a first approval is no escape; a raft with stops 0 has none; an empty reworks has none",
		function()
			local function with(f: { approvals: number?, stops: number?, reworks: string? }): lessons.Item
				return {
					id = "R0010",
					reviews = {},
					harvest = nil,
					approvals = f.approvals,
					stops = f.stops,
					reworks = f.reworks,
				}
			end
			t.expect(lessons.escapes(with({ approvals = 1, stops = 0, reworks = "" }))).toEqual({}) -- M7: the first counts
			t.expect(lessons.escapes(with({ approvals = 0 }))).toEqual({})
			t.expect(lessons.escapes(with({}))).toEqual({})
			t.expect(lessons.uncovered({ with({ approvals = 1, stops = 0, reworks = "" }) })).toEqual({})
			t.expect(lessons.escapes(with({ approvals = 2 }))).toEqual({
				{
					item = "R0010",
					kind = "redesign",
					ref = "redesign 2",
					made = nil,
					found = "implementation",
				},
			})
			t.expect(lessons.escapes(with({ stops = 2 }))).toEqual({
				{ item = "R0010", kind = "stop", ref = "stop 1", made = nil, found = "implementation" },
				{ item = "R0010", kind = "stop", ref = "stop 2", made = nil, found = "implementation" },
			})
			t.expect(lessons.escapes(with({ reworks = "c0100" }))).toEqual({
				{ item = "R0010", kind = "rework", ref = "rework 1", made = nil, found = "merged" },
			})
			-- made comes from the harvest entry once it exists
			local covered = with({ approvals = 2, stops = 1, reworks = "c0100" })
			covered.harvest = "- escape redesign 2 (design): testing/pin\n- escape stop 1 (idea): testing/pin\n"
				.. "- escape rework 1 (implementation): testing/pin\n"
			local list = lessons.escapes(covered)
			t.expect(#list).toBe(3)
			t.expect(list[1].made).toBe("design")
			t.expect(list[2].made).toBe("idea")
			t.expect(list[3].made).toBe("implementation")
		end
	)

	it(
		"AC4: unstaged names every finding with no Stage line, skips an exempt review, and refuses a Stage line with an unknown stage",
		function()
			local item: lessons.Item = {
				id = "R0010",
				reviews = {
					["design-review-001"] = review({
						{ "F1" },
						{ "F2", "Stage: design" },
						{ "F10", "Stage: nowhere" }, -- M12: any text after Stage: counts
						{ "F3", "Stage:" },
					}),
					["review-001"] = review({ { "F1" } }),
					["review-002"] = review({ { "F1", "Stage: implementation" } }),
				},
				harvest = nil,
			}
			t.expect(lessons.unstaged(item, {})).toEqual({
				"R0010 design-review-001 F1: no Stage line",
				"R0010 design-review-001 F3: no Stage line",
				"R0010 design-review-001 F10: no Stage line",
				"R0010 review-001 F1: no Stage line",
			})
			-- M11: one exempt review exempts the whole item; only the exempt review is skipped
			t.expect(lessons.unstaged(item, { ["review-001"] = true })).toEqual({
				"R0010 design-review-001 F1: no Stage line",
				"R0010 design-review-001 F3: no Stage line",
				"R0010 design-review-001 F10: no Stage line",
			})
			t.expect(lessons.unstaged(item, { ["design-review-001"] = true })).toEqual({
				"R0010 review-001 F1: no Stage line",
			})
			t.expect(lessons.unstaged(item, { ["design-review-001"] = true, ["review-001"] = true }))
				.toEqual({})
			t.expect(lessons.unstaged({ id = "c0020", reviews = {}, harvest = nil }, {})).toEqual({})
		end
	)

	it(
		"AC2: check refuses an escape entry for an approval or a stop that does not exist, a rework entry on an item with no reworks, and a reworks that names no item",
		function()
			-- every entry has its escape: nothing to refuse
			local good: lessons.Item = {
				id = "R0010",
				reviews = {},
				harvest = "- escape redesign 2 (design): testing/pin\n- escape stop 1 (design): testing/pin\n"
					.. "- escape rework 1 (implementation): testing/pin\n",
				approvals = 2,
				stops = 1,
				reworks = "c0100",
			}
			t.expect(lessons.check(tree({ good }, { R0010 = true, c0100 = true }))).toEqual({})

			-- no second approval, no stop, no reworks: three entries with nothing behind them
			local bad: lessons.Item = {
				id = "R0020",
				reviews = {},
				harvest = "- escape redesign 2 (design): testing/pin\n- escape stop 1 (design): testing/pin\n"
					.. "- escape rework 1 (implementation): testing/pin\n",
				approvals = 1,
				stops = 0,
				reworks = nil,
			}
			local problems = lessons.check(tree({ bad }, { R0020 = true }))
			t.expect(#problems).toBe(3)
			t.expect(has(problems, "escape redesign 2")).toBe(true)
			t.expect(has(problems, "escape stop 1")).toBe(true) -- M13: an entry for a stop that never happened
			t.expect(has(problems, "escape rework 1")).toBe(true)
			-- the entries of an item with none of the fields at all (an item built as every caller does today)
			t.expect(
				#lessons.check(
					tree({ { id = "R0030", reviews = {}, harvest = bad.harvest } }, { R0030 = true })
				)
			).toBe(3)

			-- each alone: the next number past what exists
			local function one(
				harvest: string,
				approvals: number,
				stops: number,
				reworks: string?
			): { string }
				local item: lessons.Item = {
					id = "R0040",
					reviews = {},
					harvest = harvest,
					approvals = approvals,
					stops = stops,
					reworks = reworks,
				}
				return lessons.check(tree({ item }, { R0040 = true, c0100 = true }))
			end
			t.expect(one("- escape redesign 3 (design): testing/pin\n", 2, 0, nil))
				.toEqual(one("- escape redesign 3 (design): testing/pin\n", 2, 0, nil))
			t.expect(#one("- escape redesign 3 (design): testing/pin\n", 2, 0, nil)).toBe(1)
			t.expect(#one("- escape redesign 2 (design): testing/pin\n", 2, 0, nil)).toBe(0)
			t.expect(#one("- escape redesign 1 (design): testing/pin\n", 2, 0, nil)).toBe(1) -- the first approval is no escape
			t.expect(#one("- escape stop 2 (design): testing/pin\n", 0, 1, nil)).toBe(1)
			t.expect(#one("- escape stop 1 (design): testing/pin\n", 0, 1, nil)).toBe(0)
			t.expect(#one("- escape rework 1 (design): testing/pin\n", 0, 0, "")).toBe(1)
			t.expect(#one("- escape rework 1 (design): testing/pin\n", 0, 0, "c0100")).toBe(0)

			-- a reworks that names no item the tree holds
			local lost: lessons.Item = { id = "c0200", reviews = {}, harvest = nil, reworks = "c9999" }
			local lostProblems = lessons.check(tree({ lost }, { c0200 = true, c0100 = true }))
			t.expect(#lostProblems).toBe(1)
			t.expect(has(lostProblems, "c9999")).toBe(true)
			t.expect(lessons.check(tree({ lost }, { c0200 = true, c9999 = true }))).toEqual({})
		end
	)

	it(
		"AC7: escapeCounts puts each escape under the stage that made it and the stage that found it, and an uncovered one under not harvested",
		function()
			local first: lessons.Item = {
				id = "R0010",
				reviews = {
					["design-review-001"] = review({ { "F1", "Stage: idea" }, { "F2", "Stage: design" } }),
					["review-001"] = review({ { "F1", "Stage: design" }, { "F2", "Stage: implementation" } }),
				},
				harvest = "- escape redesign 2 (design): testing/pin\n- escape rework 1 (implementation): testing/pin\n",
				approvals = 2,
				stops = 1, -- no entry: not harvested
				reworks = "c0100",
			}
			local second: lessons.Item = {
				id = "R0020",
				reviews = {},
				harvest = "- escape redesign 2 (design): testing/pin\n",
				approvals = 2,
			}
			t.expect(lessons.escapeCounts({ first, second })).toEqual({
				{ made = "idea", found = "design", n = 1 },
				{ made = "design", found = "implementation", n = 3 }, -- a review finding and two redesigns
				{ made = "implementation", found = "merged", n = 1 }, -- M14: a rework found at implementation
				{ made = "not harvested", found = "implementation", n = 1 },
			})
			t.expect(lessons.escapeCounts({})).toEqual({})
			t.expect(lessons.escapeCounts({ { id = "c0001", reviews = {}, harvest = nil } })).toEqual({})
		end
	)
end)
