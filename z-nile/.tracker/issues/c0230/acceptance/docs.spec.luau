--!strict
-- c0230 AC3: the fast-tests rule in the zz-test skill's Speed section (verbatim), and the lesson the runner's report names
-- exists. The lesson's own wording is pinned only before `./zn done`, by lesson-words.luau in check.sh: lesson text is
-- meant to change (harvest notes, c0181's caps and merges), so the permanent suite pins the rule, not the sentences.
local budget = require("@tests/lib/budget")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local SKILL = "z-nile/skills/zz-test/SKILL.md"

return t.spec("c0230 fast tests wording", function(it)
	it("AC3: the zz-test skill's Speed section states the rule and the report", function()
		local text = fs.readFile(`{root}/{SKILL}`)
		local speed = string.match(text, "\n## Speed\n(.-)\n## ")
		if speed == nil then
			error("zz-test has no Speed section")
		end
		local line =
			"- **Real work is a one-time proof** (lesson zz-test/specs-never-burn-real-resources): a spec burns no CPU, sleeps no seconds and writes no thousands of files; a proof that needs them is a check.sh-only script run once and never promoted. Every concurrent run with a file over budget prints `over budget: <n> spec files over 60 s wall or 5 s cpu` and one line per file (at most ten) before its summary, from each worker's own seconds and the CPU of the worker and every process it waited for (a detached process is not counted). It reports only: the outcome stands. An in-process run (one file, `--jobs 1`) prints none. `lune run tests/run -- --budget <wall>:<cpu>` sets the limits for that run (a flag, so no nested run inherits them); anything else is refused before a spec runs."
		if string.find(speed :: string, line, 1, true) == nil then
			error(`the Speed section does not say: {line}`)
		end
	end)

	it("AC3: the lesson the report names is a zz-test lesson file", function()
		local skill, slug = string.match(budget.LESSON, "^([%w%-]+)/([%w%-]+)$")
		t.expect(skill).toBe("zz-test")
		t.expect(fs.isFile(`{root}/z-nile/skills/{skill}/lessons/{slug}.md`)).toBe(true)
	end)
end)
