--!strict
-- c0112 AC6: the skills and AGENTS.md say that full coverage is a gate invariant, where it runs, and what a branch does
-- on a harvest.md conflict. Each sentence is pinned where it lives, exactly once. Reads the real files,
-- writes nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- the repository's files, from its top (this spec runs from z-nile/, c0120)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end
local function count(text: string, needle: string): number
	local n, from = 0, 1
	while true do
		local a, b = string.find(text, needle, from, true)
		if not a then
			return n
		end
		n += 1
		from = (b :: number) + 1
	end
end
-- exactly once, so a copy pasted into a second place, or a rewording that leaves the old text behind, is red
local function once(rel: string, needle: string)
	t.expect(count(read(rel), needle)).toBe(1)
end

local ZZ_TEST = "z-nile/skills/zz-test/SKILL.md"
local ZZ_RULES = "z-nile/skills/zz-rules/SKILL.md"
local ZZ_EXECUTE = "z-nile/skills/zz-execute/SKILL.md"

return t.spec("c0112 the docs name the coverage invariant", function(it)
	it(
		"zz-test says the full gate runs the three lists over the whole tree, and where the early warnings are",
		function()
			once(
				ZZ_TEST,
				"**Lessons coverage is a gate invariant (c0112).** `tests/acceptance/c0112/coverage.spec.luau` runs in every full gate: `lessons --check`, `--uncovered` and `--unattributed` over the whole tree must print nothing, so a branch with an unharvested review finding, or a harvest entry or note that names no step, cannot merge."
			)
			once(
				ZZ_TEST,
				"A tracker-only change selects no spec, so `--affected` does not run it: `./zn lessons --uncovered <id>` and `--unattributed <id>` at the confirm steps (z-design step 5.5, zz-execute Phase 5) are the early warning, and the full gate at merge is the wall."
			)
		end
	)

	it(
		"zz-rules says what the lessons command's lists gate, and what to do on a harvest.md conflict",
		function()
			once(
				ZZ_RULES,
				"The full gate fails when `--check`, `--uncovered` or `--unattributed` reports anything for the whole tree (zz-test skill, Running tests)."
			)
			once(
				ZZ_RULES,
				"On a conflict in a `harvest.md`, keep one line per finding, with `main`'s step: its lesson ids are `main`'s plus every lesson of the other side that a skill the line names files, and each remaining lesson goes into a note `- note <stem> F<n> <why> (erred <the lesson's skill>): <ids>`; a lesson beats a one-off, the notes of both sides are kept (a reworded note in its newer text), and no line is dropped. Then `lune run z-nile/tests/acceptance/c0112/sources-kept.luau -- --merges <git archive of each merge parent> .` must pass for both parents."
			)
		end
	)

	it("zz-execute and AGENTS.md say a finding missed at the confirm step stops the merge", function()
		once(
			ZZ_EXECUTE,
			"The full gate runs the same three commands over the whole tree, so a finding this step missed stops the merge."
		)
		once(
			"AGENTS.md",
			"The full gate refuses a tree with an unharvested finding or an entry that names no step (zz-test skill, Running tests)."
		)
	end)
end)
