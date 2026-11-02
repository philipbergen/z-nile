--!strict
-- c0112 AC5: a grouped note may name an issue id (`f0110`, `c0155`): 5 notes on main do, and only a word shaped like
-- a finding (`f1`, `F12`, `f123`) is taken for a mistyped head; and the zz-rules sentence for a harvest.md conflict, applied
-- to a worked example, gives a ledger `lessons.check` accepts. Pure over texts: nothing is read or written.
local lessons = require("@znile/engine/lessons")
local t = require("@tests/lib/t")

local REVIEW = "# Review 001: R0010 (design mode)\nInputs: abc\n\n### F1 [medium] a\nWhere: x\n"

local LESSON = "---\ntitle: T\nwhen: both\ntags: [wiring]\ncheck: Is it pinned?\nfrom: a user\n---\nBody.\n"

local function treeOf(ledger: string): lessons.Tree
	local items: { lessons.Item } = {
		{
			id = "R0010",
			reviews = { ["design-review-001"] = REVIEW },
			harvest = `# Harvest: R0010\n\n{ledger}`,
		},
	}
	return {
		lessons = { ["z-design/a"] = LESSON, ["z-design/c"] = LESSON, ["zz-test/b"] = LESSON },
		found = {},
		skills = { ["z-design"] = true, ["zz-test"] = true },
		items = items,
		problems = {},
	}
end

local function ledgerProblems(ledger: string): string
	return table.concat(lessons.check(treeOf(ledger)), "\n")
end

-- how many sources a lesson has once the ledger is read: the property a conflict resolution must keep
local function sourceCount(ledger: string, id: string): number
	local list: { string } = lessons.sources(treeOf(ledger).items)[id] or {}
	return #list
end

local function problems(note: string): string
	return ledgerProblems(
		`- design-review-001 F1 (erred z-design): z-design/a\n- note {note} (erred z-design): z-design/a\n`
	)
end

return t.spec("c0112 a note may name an issue id", function(it)
	it("issue ids of four digits are ordinary words in a note", function()
		t.expect(problems("c0155's capture landed late")).toBe("")
		t.expect(problems("the f0126 and f0146 preps found f0110's specs closed")).toBe("")
		t.expect(problems('prep E2: renamed.id("f0110") read the wrong folder')).toBe("")
		t.expect(problems("a user correction, d0149 and R0012 again")).toBe("")
	end)

	it("a word shaped like a finding still marks a mistyped head", function()
		for _, note in
			{
				"the finding f1 again",
				"see f12 and more",
				"a lowercase F123",
				"typo'd head: design-review-01 F1",
			}
		do
			local out = problems(note)
			t.expect(string.find(out, "a note about a finding starts <stem> F<n>", 1, true) ~= nil).toBe(true)
		end
	end)

	it(
		"the zz-rules conflict sentence, applied to worked examples, keeps every lesson of both sides",
		function()
			-- cross-skill: main (erred z-design): a; the branch (erred zz-test): b. The union under main's step is refused ...
			local union = ledgerProblems("- design-review-001 F1 (erred z-design): z-design/a, zz-test/b\n")
			t.expect(
				string.find(union, "zz-test/b is filed under zz-test, which the line does not name", 1, true)
					~= nil
			).toBe(true)
			-- ... the resolution (main's line whole, the other side's lesson in a note headed for the finding) is not
			local cross = "- design-review-001 F1 (erred z-design): z-design/a\n"
				.. "- note design-review-001 F1 a further lesson (erred zz-test): zz-test/b\n"
			t.expect(ledgerProblems(cross)).toBe("")
			t.expect(sourceCount(cross, "z-design/a")).toBe(1)
			t.expect(sourceCount(cross, "zz-test/b")).toBe(1)
			-- same skill: main (erred z-design): a; the branch (erred z-design): a, c. Main's line whole drops c and --check
			-- stays empty (the lost source only a source count sees), which is why the sentence adds the lessons a skill the
			-- line names files
			local dropped = "- design-review-001 F1 (erred z-design): z-design/a\n"
			t.expect(ledgerProblems(dropped)).toBe("")
			t.expect(sourceCount(dropped, "z-design/c")).toBe(0)
			local same = "- design-review-001 F1 (erred z-design): z-design/a, z-design/c\n"
			t.expect(ledgerProblems(same)).toBe("")
			t.expect(sourceCount(same, "z-design/c")).toBe(1)
			-- two skills on the kept line: main (erred z-design, upstream zz-test): a; the branch (erred z-design): a, b
			local two = "- design-review-001 F1 (erred z-design, upstream zz-test): z-design/a, zz-test/b\n"
			t.expect(ledgerProblems(two)).toBe("")
			t.expect(sourceCount(two, "zz-test/b")).toBe(1)
		end
	)
end)
