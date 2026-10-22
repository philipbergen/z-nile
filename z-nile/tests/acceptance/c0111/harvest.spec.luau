--!strict
-- c0111 AC2: harvest.md ledgers parse; findings, sources and uncovered findings are exact; and check names every
-- broken reference and sourceless lesson, but never coverage (c0112's gate owns that).
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")

local function review(...: string): string
	local out = "# Review 001: R0010 (design mode)\nInputs: abc\n\n"
	for _, f in { ... } do
		out ..= `### {f} [medium] a claim\nWhere: x\nEvidence: F9 is mentioned here, not a heading\n\n`
	end
	return out .. "Verdict: changes\n"
end

local LESSON = "---\ntitle: T\nwhen: build\ntags: [wiring]\ncheck: Is it pinned?\n---\nBody.\n"
local FROM =
	"---\ntitle: T\nwhen: both\ntags: [wiring]\ncheck: Is it?\nfrom: user 2026-10-20: told us\n---\nBody.\n"

local function has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) then
			return true
		end
	end
	return false
end

local function tree(items: { lessons.Item }, files: { [string]: string }?): lessons.Tree
	return {
		lessons = files or { ["testing/pin"] = LESSON },
		found = {},
		skills = { testing = true, review = true },
		items = items,
		problems = {},
	}
end

return t.spec("c0111 harvest ledgers", function(it)
	it("findings are the ### F<n> headings tracker.sh done reads, in order", function()
		t.expect(lessons.findings(review("F1", "F2", "F10"))).toEqual({ "F1", "F2", "F10" })
		t.expect(
			lessons.findings("### F1\n#### F2 deeper\ntext ### F3\n### F4: a colon\n### F5[low] tight\n")
		)
			.toEqual({ "F1", "F4", "F5" })
		t.expect(lessons.findings("# Review\n\nVerdict: approve\n")).toEqual({})
	end)

	it("an entry with several lessons, and a one-off", function()
		local entries, problems = lessons.parseHarvest(
			"R0010",
			"# Harvest: R0010\n\nSome prose.\n- design-review-001 F1: testing/pin, review/text\n"
				.. "- review-002 F3: one-off: a typo in the plan\n"
		)
		t.expect(problems).toEqual({})
		t.expect(#entries).toBe(2)
		t.expect(entries[1].item).toBe("R0010")
		t.expect(entries[1].review).toBe("design-review-001")
		t.expect(entries[1].finding).toBe("F1")
		t.expect(entries[1].lessons).toEqual({ "testing/pin", "review/text" })
		t.expect(entries[1].oneOff).toBe(nil)
		t.expect(entries[2].review).toBe("review-002")
		t.expect(entries[2].lessons).toEqual({})
		t.expect(entries[2].oneOff).toBe("a typo in the plan")
	end)

	it("bad lines, an empty one-off reason and a duplicate finding are named", function()
		local _, problems = lessons.parseHarvest(
			"R0010",
			"- design-review-001 F1: testing/pin\n"
				.. "- design-review-001 F1: review/text\n" -- duplicate
				.. "- review-001 F2: one-off:\n" -- no reason
				.. "- review-001 F3: Not An Id\n" -- neither
				.. "- stream-review-c0010-001 F1: testing/pin\n" -- not a review stem
				.. "- design-review-001: testing/pin\n" -- no finding
		)
		t.expect(#problems).toBe(5)
		t.expect(has(problems, "R0010")).toBe(true)
		t.expect(has(problems, "design-review-001 F1")).toBe(true)
		t.expect(has(problems, "review-001 F2")).toBe(true)
		t.expect(has(problems, "review-001 F3")).toBe(true)
		t.expect(has(problems, "stream-review-c0010-001")).toBe(true)
	end)

	it("uncovered findings are listed in item, review and number order", function()
		local items: { lessons.Item } = {
			{
				id = "R0010",
				reviews = { ["design-review-001"] = review("F1", "F2", "F10"), ["review-001"] = review("F1") },
				harvest = "- design-review-001 F2: testing/pin\n",
			},
			{ id = "c0020", reviews = { ["review-001"] = review("F1") }, harvest = nil },
			{
				id = "R0030",
				reviews = { ["design-review-001"] = "# Review\n\nVerdict: approve\n" },
				harvest = nil,
			},
		}
		t.expect(lessons.uncovered(items)).toEqual({
			"R0010 design-review-001 F1",
			"R0010 design-review-001 F10",
			"R0010 review-001 F1",
			"c0020 review-001 F1",
		})
		-- F2 before F10, not after it
		local two =
			{ { id = "R0010", reviews = { ["design-review-001"] = review("F10", "F2") }, harvest = nil } }
		t.expect(lessons.uncovered(two))
			.toEqual({ "R0010 design-review-001 F2", "R0010 design-review-001 F10" })
	end)

	it("sources come from entries only, and one-offs name no lesson", function()
		local items: { lessons.Item } = {
			{
				id = "R0010",
				reviews = { ["design-review-001"] = review("F1", "F2", "F3") },
				harvest = "- design-review-001 F1: testing/pin\n- design-review-001 F2: testing/pin, review/text\n- design-review-001 F3: one-off: once\n",
			},
			{
				id = "R0020",
				reviews = { ["review-001"] = review("F4") },
				harvest = "- review-001 F4: testing/pin\n",
			},
		}
		local s = lessons.sources(items)
		t.expect(s["testing/pin"])
			.toEqual({ "R0010 design-review-001 F1", "R0010 design-review-001 F2", "R0020 review-001 F4" })
		t.expect(s["review/text"]).toEqual({ "R0010 design-review-001 F2" })
		local n = 0
		for _ in s do
			n += 1
		end
		t.expect(n).toBe(2)
	end)

	it("a note entry is a source, never a finding, and needs text and lesson ids", function()
		local entries, problems = lessons.parseHarvest(
			"R0010",
			"- note ws-c0010 stream: testing/pin\n- note user 2026-11-01: said so: testing/pin, review/text\n"
				.. "- note : testing/pin\n- note no ids: \n- note bad ids: Not An Id\n"
		)
		t.expect(#entries).toBe(2)
		t.expect(entries[1].note).toBe("ws-c0010 stream")
		t.expect(entries[1].lessons).toEqual({ "testing/pin" })
		t.expect(entries[2].note).toBe("user 2026-11-01: said so") -- the text may hold a colon
		t.expect(entries[2].lessons).toEqual({ "testing/pin", "review/text" })
		t.expect(#problems).toBe(3)
		t.expect(has(problems, "R0010/harvest.md: note")).toBe(true)
		local items: { lessons.Item } = {
			{
				id = "R0010",
				reviews = { ["review-001"] = review("F1", "F2") },
				harvest = "- note ws-c0010 stream: testing/pin\n- review-001 F2: testing/pin\n- note later: testing/pin\n",
			},
		}
		-- review sources first, then notes in file order
		t.expect(lessons.sources(items)["testing/pin"])
			.toEqual({ "R0010 review-001 F2", "R0010 note ws-c0010 stream", "R0010 note later" })
		t.expect(lessons.uncovered(items)).toEqual({ "R0010 review-001 F1" }) -- a note covers nothing
		t.expect(lessons.check(tree(items))).toEqual({})
		items[1].harvest = "- note ws: testing/gone\n"
		t.expect(lessons.check(tree(items, { ["testing/pin"] = FROM })))
			.toEqual({ "R0010/harvest.md: note ws: no lesson testing/gone" })
	end)

	it("an entry that names one lesson twice is a problem, so it can't count twice", function()
		local entries, problems = lessons.parseHarvest(
			"R0010",
			"- review-001 F1: testing/pin, testing/pin\n- note ws-c0010: review/text, review/text\n"
		)
		t.expect(#entries).toBe(0)
		t.expect(#problems).toBe(2)
		t.expect(has(problems, "R0010/harvest.md: review-001 F1: lesson testing/pin is named twice"))
			.toBe(true)
		t.expect(has(problems, "R0010/harvest.md: note ws-c0010: lesson review/text is named twice"))
			.toBe(true)
	end)

	it("check names broken references and sourceless lessons, accepts from, and ignores coverage", function()
		local covered: { lessons.Item } = {
			{
				id = "R0010",
				reviews = { ["design-review-001"] = review("F1", "F2") },
				harvest = "- design-review-001 F1: testing/pin\n",
			},
		}
		t.expect(lessons.check(tree(covered))).toEqual({}) -- F2 is uncovered: not a check problem
		t.expect(lessons.check(tree(covered, { ["testing/pin"] = LESSON, ["review/said"] = FROM })))
			.toEqual({})

		local broken: { lessons.Item } = {
			{
				id = "R0010",
				reviews = { ["design-review-001"] = review("F1") },
				harvest = "- design-review-001 F1: testing/pin\n- design-review-002 F1: testing/pin\n"
					.. "- design-review-001 F7: testing/pin\n- design-review-001 F1: testing/gone\n",
			},
		}
		local p = lessons.check(tree(broken, {
			["testing/pin"] = LESSON,
			["testing/lonely"] = LESSON,
			["nowhere/x"] = FROM, -- sourced, so only its missing skill is wrong
			["testing/bad"] = "---\ntitle: T\nwhen: never\ntags: [a]\ncheck: Q?\n---\nB\n",
		}))
		t.expect(has(p, "design-review-002")).toBe(true) -- no such review file
		t.expect(has(p, "F7")).toBe(true) -- no such finding
		t.expect(has(p, "design-review-001 F1")).toBe(true) -- a second entry for F1
		t.expect(has(p, "testing/lonely")).toBe(true) -- no source
		t.expect(has(p, "nowhere/x")).toBe(true) -- no such skill
		t.expect(has(p, "testing/bad")).toBe(true) -- fails parse
		for _, line in p do
			-- testing/pin is sound: no problem is about it, whatever entries quote it
			t.expect(string.sub(line, 1, 12) == "testing/pin:").toBe(false)
		end
		-- each problem starts with its subject
		local lonely, ledger = false, false
		for _, line in p do
			lonely = lonely or string.sub(line, 1, 16) == "testing/lonely: "
			ledger = ledger or string.sub(line, 1, 40) == "R0010/harvest.md: design-review-001 F7: "
		end
		t.expect(lonely).toBe(true)
		t.expect(ledger).toBe(true)
		local sorted = table.clone(p)
		table.sort(sorted)
		t.expect(p).toEqual(sorted)

		local unknown: { lessons.Item } = {
			{
				id = "R0010",
				reviews = { ["design-review-001"] = review("F1") },
				harvest = "- design-review-001 F1: testing/gone\n",
			},
		}
		t.expect(has(lessons.check(tree(unknown)), "testing/gone")).toBe(true)

		local loaded = tree(covered)
		loaded.problems = { ".claude/skills/testing/lessons/notes.txt: not a lesson file" }
		t.expect(lessons.check(loaded))
			.toEqual({ ".claude/skills/testing/lessons/notes.txt: not a lesson file" })
	end)
end)
