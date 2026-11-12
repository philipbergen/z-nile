--!strict
-- c0117 AC14: the skills, the README, AGENTS.md, the usage and the prompt template say what the design's Docs part
-- says: the headless rules in every model step's skill, word for word; the review model of the CLI wherever a skill
-- says who reviews (no "Opus 5.5" rule is left); zz-rules' Dispatch section; z-run's end under the dispatcher; the
-- built dispatcher and .models.toml in the README; the model cell; and the template that names files.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- c0117 runs from its project's home, z-nile/ (c0120): every path of the real tree this spec reads is the
-- repository's, from its top
local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)
local function read(path: string): string
	return fs.readFile(if string.sub(path, 1, 1) == "/" then path else `{TOP}/{path}`)
end
local function at(text: string, needle: string, where: string)
	if not string.find(text, needle, 1, true) then
		error(`{where} does not say: {needle}`, 2)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) then
		error(`{where} still says: {needle}`, 2)
	end
end
local function skill(name: string): string
	return read(`z-nile/skills/{name}/SKILL.md`)
end
local function section(text: string, heading: string): string
	local a = string.find(text, "\n" .. heading .. "\n", 1, true)
	if not a then
		error(`no {heading}`, 2)
	end
	local b = string.find(text, "\n## ", (a :: number) + #heading + 2, true)
	return string.sub(text, a :: number, (b or 0) - 1)
end

return t.spec("c0117 docs", function(it)
	it("every model step's skill carries the same headless section, before its lessons", function()
		local first: string? = nil
		for _, name in { "z-ticket", "z-design", "z-raft", "z-run" } do
			local text = skill(name)
			local h = section(text, "## Headless (under `./zn dispatch`)")
			at(h, "write the questions to `$ZN_DISPATCH_DIR/questions.md`", name)
			at(h, "./zn dispatch retry <id>", name)
			at(h, "Never `git push` to `main` and never merge a pull request", name)
			at(h, "the dispatcher pushes that tracker state to `main` for you", name)
			at(h, "with the agent's own GitHub credential", name)
			at(h, "Do not pass `--time` or `--tokens`", name)
			at(h, "`./zn dispatch zz-review <id> --mode <design|raft|code|stream>`", name)
			at(h, "give that one command a two-hour timeout", name)
			if first then
				t.expect(h).toBe(first)
			end
			first = h
			t.expect(
				(string.find(text, "## Headless", 1, true) :: number)
					< string.find(text, "\n## Lessons\n", 1, true) :: number
			).toBe(true)
		end
	end)

	it("who reviews is the role .models.toml names, wherever a skill says so", function()
		-- z-run's reviews are its protocol's, zz-execute's, since c0115
		at(skill("z-design"), "design-challenge role", "z-design")
		at(skill("z-raft"), "raft role", "z-raft")
		at(skill("zz-execute"), "code-review role", "zz-execute")
		at(skill("zz-review"), "design-challenge", "zz-review")
		at(skill("zz-review"), "code-review", "zz-review")
		at(skill("zz-review"), "final-review", "zz-review")
		at(skill("z-design"), "`./zn dispatch zz-review <id> --mode design`", "z-design")
		at(skill("z-raft"), "`./zn dispatch zz-review <R-id> --mode raft`", "z-raft")
		-- the run's protocol is zz-execute's since c0115 (z-run hands off to it)
		at(skill("zz-execute"), "`./zn dispatch zz-review <R-id> --mode code`", "zz-execute")
		at(skill("zz-execute"), "--model <reviewer model>", "zz-execute")
		-- stream reviews under the dispatcher (G15, design review 007 F1): the review model of the CLI, and the reviewer
		-- writes its own file, since a dispatched run has no caller to return text to
		local zr = skill("zz-review")
		at(zr, "`./zn dispatch zz-review <id> --mode design|raft|code|stream`", "zz-review Who reviews")
		absent(zr, "stream reviews stay on Sonnet subagents", "zz-review Who reviews")
		-- design review 008 F1, F2: the dispatcher lands a dispatched review; round 2's inputs are the files in the raft
		at(zr, "Layers replaced stream branches", "zz-review Stream mode")
		at(zr, "reviewed in Code mode, one layer at a time", "zz-review Stream mode")
		-- a dispatched raft review records its own row (design review 007 F2): the author records only a subagent's
		at(skill("z-raft"), "As soon as a subagent reviewer returns", "z-raft")
		at(
			skill("z-raft"),
			"Mark your own answering span with `./zn spend <R-id> --phase design-review --begin`",
			"z-raft"
		) -- design review 008 F4
		local ze = skill("zz-execute")
		-- design review 009 F1, F2: the dispatcher places every dispatched review; a failed one's line is committed alone
		at(
			zr,
			"Under `./zn dispatch`, in every mode, write your review to `$ZN_DISPATCH_DIR/review.md` (your own state folder) and nothing else",
			"zz-review Output file"
		)
		at(ze, "Layers replace stream branches. There is no `ws-<issue>` branch", "zz-execute Phase 2B")
		at(
			ze,
			'A dispatched review that fails with "the reviewer wrote no review" still prints its `record:` line: commit that line alone (the commit is its spend row), then rerun the review, which is still the same round.',
			"zz-execute"
		)
		absent(ze, "the reviewer writes `stream-review-<issue>-NNN.md` itself", "zz-execute")
		absent(ze, "next., and", "zz-execute")
		-- design review 010: the Visible record's file is scoped too, and the failed-review rule sits in Phase 4 step 3
		at(zr, "The names above and in Visible record are the interactive path's", "zz-review Output file")
		at(
			zr,
			"Write `review-NNN.md` in full (under `./zn dispatch`, `$ZN_DISPATCH_DIR/review.md`, as Output file says)",
			"zz-review Visible record"
		)
		local step3 = string.match(
			ze,
			"\n3%. The reviewer writes `review%-NNN%.md` in the raft directory[^\n]*"
		) or ""
		at(
			step3,
			'A dispatched review that fails with "the reviewer wrote no review" still prints its `record:` line',
			"zz-execute Phase 4 step 3"
		)
		at(ze, "After a fix on a lower layer, `./zn finish`", "zz-execute Phase 2B")
		at(ze, "`./zn done` already landed the stack", "zz-execute Phase 6")
		for _, name in fs.readDir(`{TOP}/z-nile/skills`) do
			if fs.isFile(`{TOP}/z-nile/skills/{name}/SKILL.md`) then
				absent(skill(name), "on **Opus 5.5**", name)
				absent(skill(name), "on Opus 5.5", name)
			end
		end
	end)

	it("z-ticket lands without asking, and a layer is reviewed in code mode", function()
		at(skill("z-ticket"), "Under the dispatcher, land without asking (the user started it)", "z-ticket")
		at(skill("zz-execute"), "Review that layer in Code mode", "zz-execute")
	end)

	it("z-run ends at Ready to merge under the dispatcher", function()
		at(
			section(skill("zz-execute"), "## Phase 6: Merge and clean up"),
			"Under `./zn dispatch` (headless) the run ends at Phase 5's `Ready to merge` comment",
			"z-run Phase 6"
		)
	end)

	it("zz-rules has the Dispatch section and names the dispatcher in its lists", function()
		local rules = skill("zz-rules")
		local d = section(rules, "## Dispatch")
		for _, phrase in
			{
				"- **Steps.**",
				"`z-ready` (`./zn ready`), `z-stop` (`./zn stop`), `raft-plan --apply`, `recombine`, `fold`, `release`, `spend`",
				"- **`.models.toml`.**",
				"the supported CLIs are `claude`, `grok` and `agent` (Cursor)",
				"`claude-cli`, `grok-cli` and `cursor-cli`",
				"Nothing defaults",
				"an `agent` role or fallback also `max_calls` and `max_minutes`",
				'- **What the guards are** (the user\'s "Keep same user, accept detection", 2026-10-21).',
				"none is a security boundary against a determined agent",
				"**Known limits:**",
				"A `.models.toml` is never tracker state",
				"judged per item",
				"origin's URL as the run pinned it at its start",
				"A run accepts `main` as it is when the process starts",
				"No file under the home directory",
				"another run's advance is never a trip",
				"writes a heartbeat in its parent's state folder",
				"`BASH_MAX_TIMEOUT_MS`",
				'a beat means "alive and within my limits"',
				"fetched from `refs/pull/<n>/head`",
				"calls are not tokens, so the user tunes it",
				'- **The agent credential** (the user\'s "Bot token, no bypass").',
				"can't merge, bypass `main`'s protection or write protection or rulesets",
				"Not enforceable: the agent runs as the user",
				"- **Tracker state from inside a step.**",
				"- **Tracker state** has one definition",
				'- **The tripwire** (the user\'s "Keep same user, accept detection").',
				"before every step and after every step",
				"and never prevents one",
				"`./zn dispatch retry <id>`",
				"--match-head-commit <head>`",
				"never forced",
				"stops as `cap-unknown`",
				"an uncommitted `.models.toml` on the walk is an error",
				"(exit 5, outcome `tripwire`)",
				"an unset or unreadable `auto_merge` is none",
				"Only the dispatcher merges",
				"holds a lifeline from the dispatcher",
				"Quota is only the CLI's own signals",
				"never a group id of 1 or less",
				"- **Running a model step.**",
				"It moves to the next model when the call fails",
				"input + cache writes + output, cache reads left out",
				"- **Spend.**",
				"- **The chain.**",
				"always a human's",
				"`./zn lessons --uncovered <id>`",
				"- **Run state.**",
				"- **The wrapper.**",
				"- **Inside a check.**",
			}
		do
			at(d, phrase, "zz-rules Dispatch")
		end
		at(rules, "   - `./zn dispatch` (Dispatch, below)", "zz-rules main-checkout list")
		at(rules, "- `./zn dispatch <id>`, `./zn dispatch new", "zz-rules Other commands")
		at(rules, "and a tenth, model, once any row of the file records the model", "zz-rules Spend")
		at(rules, "| the dispatcher's own spend rows | `zn-dispatch` |", "zz-rules worktree table")
	end)

	it("zz-test lists a model CLI started by a check as caught only by review", function()
		at(skill("zz-test"), "  - **Starting a model CLI** (`claude`, `grok`, `agent`)", "zz-test")
	end)

	it("the README draws the dispatcher and .models.toml as built", function()
		local readme = read("z-nile/README.md")
		at(readme, 'dispatcher["dispatcher: ./zn dispatch"]', "the README picture")
		at(readme, 'models[".models.toml: the model and CLI per step"]', "the README picture")
		absent(readme, "(c0117, planned)", "the README")
		at(readme, "- **The dispatcher.** `./zn dispatch <id>`", "the README")
		at(readme, "none of them is a security boundary against a determined agent", "the README")
		at(readme, "A run accepts `main` as it is when it starts", "the README")
		at(readme, "- **`.models.toml`.**", "the README")
	end)

	it("AGENTS.md and the usage name the dispatcher", function()
		local agents = read("AGENTS.md")
		at(agents, "the dispatcher's run state in `.cache/dispatch/`", "AGENTS.md")
		at(agents, "`./zn dispatch <id>`", "AGENTS.md")
		local usage = process.exec(`{TOP}/zn`, {}, { cwd = TOP }).stdout
		for _, line in
			{
				"  dispatch <id> [--dry-run]",
				'  dispatch new "<description>" [--project <name>] [--dry-run]',
				"  dispatch <step> <id> [--mode design|code|raft] [--dry-run]",
				"  dispatch stop|retry|status <id>",
				"[--model <id>]",
			}
		do
			at(usage, line, "the usage")
		end
	end)

	-- the prompt names each file and pastes none of them (step 1.3)
	it("the raft's prompt template names skills and the architecture path and pastes neither", function()
		local p = read("z-nile/templates/prompt.md")
		at(p, "## Skills", "prompt.md")
		at(p, "{{SKILLS}}", "prompt.md")
		at(p, "{{ARCHITECTURE}}", "prompt.md")
		at(p, "None of their text is in this prompt.", "prompt.md")
		at(p, "1. **Follow `z-nile/skills/zz-execute/SKILL.md` step by step.**", "prompt.md")
		absent(p, "{{LESSONS}}", "prompt.md")
		absent(p, "{{LESSONS_COMMAND}}", "prompt.md")
		absent(p, "## Skills (verbatim", "prompt.md")
		absent(p, "## Work items (verbatim from {{ROOT}}/)", "prompt.md")
	end)
end)
