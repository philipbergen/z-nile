--!strict
-- c0239 AC1 to AC3: the gate-by-step rule in the words of the skills, the prompt template, the raft template and
-- AGENTS.md. Each line appears verbatim. Read from the checkout's top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{root}/{rel}`)
end
local function says(rel: string, line: string)
	if string.find(read(rel), line, 1, true) == nil then
		error(`{rel} does not say: {line}`)
	end
end
local function unsays(rel: string, line: string)
	if string.find(read(rel), line, 1, true) ~= nil then
		error(`{rel} still says: {line}`)
	end
end

return t.spec("c0239 gate by step wording", function(it)
	it("AC1: zz-test holds the rule table and no stop hook line", function()
		local f = "z-nile/skills/zz-test/SKILL.md"
		says(
			f,
			"**Gate by step**: the full gate runs once, at the merge; every step before it runs `--affected`, `./zn done` included."
		)
		says(f, "`land`, `setup.sh` and the merge's clean clone run `--full` fresh.")
		unsays(f, "On stop:")
		unsays(f, '(`"$ZN_ROOT/z-nile/check.sh" --project <project> --full`)')
	end)

	it("AC1: the stale gate lines are gone and their new text is pinned", function()
		local rules = "z-nile/skills/zz-rules/SKILL.md"
		says(rules, "runs the affected gate (`z-nile/check.sh --affected`) on that tree")
		unsays(rules, "runs the full gate (`z-nile/check.sh --full`) on that tree")
		says("SETUP.md", "(`./zn land` and zz-rules Merging; `./zn done` runs the affected gate)")
		unsays("SETUP.md", "(`./zn land`, `./zn done`, and zz-rules Merging)")
		unsays(
			"z-nile/skills/zz-review/SKILL.md",
			"Run `z-nile/check.sh --full` and each `./zn check <id>` yourself."
		)
		unsays("z-nile/templates/prompt.md", "The full gate is `z-nile/check.sh --full`.")
		unsays("z-nile/templates/prompt.md", "which covers the full repo gate plus every issue's `check.sh`")
		says(
			"z-nile/templates/prompt.md",
			"which covers the project's affected gate plus every issue's `check.sh`"
		)
		-- the done row's failure and fixture sentences (design review 004 F6)
		local zzRules = "z-nile/skills/zz-rules/SKILL.md"
		says(zzRules, "A failing gate rolls the tree back by itself")
		says(zzRules, "it skips the gate, says so, and checks only the promoted specs")
		unsays(zzRules, "A failing full gate rolls the tree back by itself")
		says(
			"z-nile/skills/zz-test/SKILL.md",
			"a raft's `check.sh` runs its project's gate (`\"$ZN_ROOT/z-nile/check.sh\" --project <project> --affected`)"
		)
	end)

	it("AC1: the other files restate each step's gate", function()
		says(
			"z-nile/skills/zz-review/SKILL.md",
			"Run `z-nile/check.sh --affected` and each `./zn check <id>` yourself."
		)
		says(
			"z-nile/templates/prompt.md",
			"Iterate with `z-nile/check.sh --affected`. The full gate runs once, at the merge."
		)
		says("z-nile/skills/zz-rules/SKILL.md", "and `z-nile/check.sh --affected`.") -- Landing step 0, the pre-PR gate
	end)

	it(
		"AC2: the raft template's RC0 runs the affected gate and nothing tells the author to run --full early",
		function()
			local tpl = "z-nile/templates/raft/check.sh"
			says(
				tpl,
				'check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project {{PROJECT}} --affected'
			)
			unsays(tpl, "--project {{PROJECT}} --full")
			local ex = "z-nile/skills/zz-execute/SKILL.md"
			for _, early in
				{
					"Confirm `z-nile/check.sh --full` passes here.",
					"Double-check that `z-nile/check.sh --full` passes as well",
					"Run `z-nile/check.sh --full` and read the whole lint summary",
					"rerun `z-nile/check.sh --full`, commit with `./zn commit --phase deliver`",
					"from a `z-nile/check.sh --full` run in each issue's Verification log",
				}
			do
				unsays(ex, early)
			end
			unsays(
				"z-nile/skills/zz-rules/SKILL.md",
				"(it fails on a duplicate id and warns when one number is shared by two prefixes; renumber yours if you can) and `z-nile/check.sh --full`."
			)
		end
	)

	it(
		"AC3: Phase 0 runs no gate, Phases 3 to 5 use the affected gate, the merge keeps the one full gate",
		function()
			local ex = "z-nile/skills/zz-execute/SKILL.md"
			says(ex, "Phase 0 runs no gate and reads no CI result: a red `main` first shows at the merge.")
			unsays(ex, "**If main is red, stop.**")
			says(ex, "Double-check that `z-nile/check.sh --affected` passes as well")
			says(ex, "Run `z-nile/check.sh --affected` and read the whole lint summary")
			says(ex, "rerun `z-nile/check.sh --affected`, commit with `./zn commit --phase deliver`")
			says(
				ex,
				"Record the **gate wall time** and the `slowest:` specs of the merge's full gate in the final report and its PR comment"
			)
			says(ex, "the local full gate, `z-nile/check.sh --full`, in a clone of the exact head")
			-- a red merge gate (user decision, 2026-11-04): BLOCKED, the failing specs, a graph-miss chore for a spec the
			-- affected selection of the PR's changes does not list, and stop with the PR ready and unmerged
			says(
				ex,
				"If the merge's full gate fails, post a `BLOCKED:` comment naming the failing specs and stop with the PR ready and unmerged; in the raft worktree at the PR head, for each failing spec that `lune run z-nile/affected -- --base $(git merge-base origin/main HEAD)` does not list (every spec counts as listed when it prints `ALL`), file a graph-miss chore (zz-test, Graph miss) and say so in the comment, unless the spec also fails on `origin/main` (then it is a red `main`: say that instead)."
			)
			local rules = "z-nile/skills/zz-rules/SKILL.md"
			says(rules, "2. `z-nile/check.sh --full` passes on the final head, run by you, in a clone")
			says(rules, "rerun `z-nile/check.sh --full`") -- c0172/merge.spec keeps pinning this phrase; the two clone-clause pins above stop at the clause c0194 rewrites
			says(
				rules,
				"A red full gate here is BLOCKED: zz-execute Phase 6 step 1 says what to post and file."
			)
			unsays(rules, "--reuse")
			unsays(rules, "PICKMAN_REUSE_DB")
		end
	)

	-- design review 003 F6 (z-design/declare-what-full-runs-covered): the specs here read files they do not require, so
	-- c0165's selector can only pick them through declared inputs
	it("AC1: z-nile/tests/inputs.tsv declares what docs.spec, done.spec and land.spec read", function()
		local tsv = read("z-nile/tests/inputs.tsv")
		local function declared(spec: string, path: string)
			if string.find(tsv, `acceptance/c0239/{spec}\t{path}`, 1, true) == nil then
				error(`inputs.tsv does not declare {path} for c0239/{spec}`)
			end
		end
		for _, path in
			{
				"z-nile/skills/zz-test/SKILL.md",
				"z-nile/skills/zz-execute/SKILL.md",
				"z-nile/skills/zz-rules/SKILL.md",
				"z-nile/skills/zz-review/SKILL.md",
				"z-nile/templates/prompt.md",
				"z-nile/templates/raft/check.sh",
				"SETUP.md",
			}
		do
			declared("docs.spec.luau", path)
		end
		declared("done.spec.luau", "z-nile/engine/main.luau")
		declared("land.spec.luau", "z-nile/engine/main.luau")
	end)
end)
