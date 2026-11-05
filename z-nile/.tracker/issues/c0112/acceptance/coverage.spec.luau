--!strict
-- c0112 AC1: full coverage is a gate invariant. On the real tree, `lessons.check` finds no problem, every
-- finding of every review (design, code and stream) has a harvest entry, and every entry and note names its step; the
-- same three lists name what is missing on a hand-made tree, so a pass cannot come from lists that are always empty.
-- Reads the real files, writes nothing.
local lessons = require("@znile/engine/lessons")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- the repository's files, from its top (this spec runs from z-nile/, c0120)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function lesson(): string
	return "---\ntitle: T\nwhen: both\ntags: [wiring]\ncheck: Is it pinned?\nfrom: a user\n---\nBody.\n"
end

local REVIEW =
	"# Review 001: R0010 (design mode)\nInputs: abc\n\n### F1 [medium] a\nWhere: x\n\n### F2 [low] b\nWhere: y\n"

-- the real tree, read once for the cases below
local cached: lessons.Tree? = nil
local function loaded(): lessons.Tree
	if not cached then
		cached = lessons.load(TOP)
	end
	return cached :: lessons.Tree
end

local function joined(list: { string }): string
	return table.concat(list, "\n")
end

return t.spec("c0112 every review finding is harvested and attributed", function(it)
	it("the lists name an unharvested finding of each review kind and an entry with no step", function()
		local items: { lessons.Item } = {
			{
				id = "R0010",
				reviews = {
					["design-review-001"] = REVIEW,
					["review-001"] = "# Review 001: R0010 (code mode)\n\n### F1 [low] d\nWhere: z\n",
					["focused-review-001"] = "# Review 001: R0010 (focused mode, build)\n\n### F1 [low] e\nWhere: z\n",
					["stream-review-c0010-001"] = "# Review\n\n### F1 [low] c\nWhere: z\n",
				},
				harvest = "# Harvest: R0010\n\n- design-review-001 F1: z-design/a\n",
			},
		}
		local gaps = lessons.uncovered(items)
		t.expect(joined(gaps)).toBe(
			"R0010 design-review-001 F2\nR0010 focused-review-001 F1\nR0010 review-001 F1\nR0010 stream-review-c0010-001 F1"
		)
		-- F1 names a lesson but no step; the entry is listed, the finding is not
		t.expect(joined(lessons.unattributed(items))).toBe("R0010 design-review-001 F1")
		local grouped: { lessons.Item } = {
			{
				id = "R0010",
				reviews = { ["design-review-001"] = REVIEW },
				harvest = "# Harvest: R0010\n\n- design-review-001 F1 (erred z-design): z-design/a\n"
					.. "- design-review-001 F2 (erred none): one-off: a taste call\n"
					.. "- note a user correction (erred z-design): z-design/a\n",
			},
		}
		t.expect(#lessons.uncovered(grouped)).toBe(0)
		t.expect(#lessons.unattributed(grouped)).toBe(0)
		local tree: lessons.Tree = {
			lessons = { ["z-design/a"] = lesson() },
			found = {},
			skills = { ["z-design"] = true },
			items = grouped,
			problems = {},
		}
		t.expect(joined(lessons.check(tree))).toBe("")
	end)

	it("on this tree every check, coverage and attribution list is empty", function()
		local tree = loaded()
		t.expect(joined(lessons.check(tree))).toBe("")
		t.expect(joined(lessons.uncovered(tree.items))).toBe("")
		t.expect(joined(lessons.unattributed(tree.items))).toBe("")
	end)
end)
