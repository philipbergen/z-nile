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
			at(h, "without `--tokens` for your own session", name)
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

	it("who reviews is the review model of the CLI, wherever a skill says so", function()
		local rule = "Opus through `claude` or `agent`, `grok-4.7-xhigh` through `grok`"
		for _, name in { "z-design", "z-raft", "z-run", "zz-review" } do
			at(skill(name), rule, name)
		end
		at(skill("z-design"), "`./zn dispatch zz-review <id> --mode design`", "z-design")
		at(skill("z-raft"), "`./zn dispatch zz-review <R-id> --mode raft`", "z-raft")
		-- the run's protocol is zz-execute's since c0115 (z-run hands off to it)
		at(skill("zz-execute"), "`./zn dispatch zz-review <R-id> --mode code`", "zz-execute")
		at(skill("zz-execute"), "--model <reviewer model>", "zz-execute")
		for _, name in fs.readDir(`{TOP}/z-nile/skills`) do
			if fs.isFile(`{TOP}/z-nile/skills/{name}/SKILL.md`) then
				absent(skill(name), "on **Opus 5.5**", name)
				absent(skill(name), "on Opus 5.5", name)
			end
		end
	end)

	it(
		"z-ticket lands without asking, and z-run's stream reviews run on any CLI, under the dispatcher",
		function()
			at(
				skill("z-ticket"),
				"Under the dispatcher, land without asking (the user started it)",
				"z-ticket"
			)
			at(
				skill("zz-execute"),
				"a stream review is `./zn dispatch zz-review <issue> --mode stream` instead",
				"zz-execute"
			)
		end
	)

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
				"`claude-cli` and `claude-cloud` (`claude --cloud`), `grok-cli` and `grok-bot` (`grok agent headless`), `cursor-cli` and `cursor-app` (`agent worker`)",
				"Nothing defaults",
				"an `agent` table also `max_calls` and `max_minutes`",
				'- **What the guards are** (the user\'s "Keep same user, accept detection", 2026-10-21).',
				"none is a security boundary against a determined agent",
				"**Known limits:**",
				"A `.models.toml` is never tracker state",
				"judged per item",
				"origin's URL as the run pinned it at its start",
				"A missing watermark at a run's start is never trusted",
				"The file is shared by every dispatcher of the repository",
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
				'- **The watermark and the tripwire** (the user\'s "Persisted watermark", framed by "Keep same user, accept detection").',
				"where a well-behaved step never writes, and detects if it changes",
				"and never prevents one",
				"`./zn dispatch vet`",
				"--match-head-commit <head>`",
				"never forced",
				"stops as `cap-unknown`",
				"an uncommitted `.models.toml` on the walk is an error",
				"(exit 5, outcome `tripwire`)",
				"an unset or unreadable `auto_merge` is none",
				"Only the dispatcher merges",
				"holds a lifeline from the dispatcher",
				"only the CLI's own signals report",
				"never a group id of 1 or less",
				"- **Running a model step.**",
				"It moves down `order` only on quota",
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
		at(readme, "The watermark file is shared by every dispatcher of the repository", "the README")
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

	it("the prompt template names the files it used to paste", function()
		local p = read("z-nile/templates/prompt.md")
		at(
			p,
			"it names every file that holds a rule you need: the skills, the architecture map and the lessons command",
			"prompt.md"
		)
		at(p, "Run `{{LESSONS_COMMAND}}`", "prompt.md")
		at(p, "{{LESSONS}}", "prompt.md") -- the index stays (c0111); the text is named
		absent(p, "verbatim from z-nile/skills/", "prompt.md")
		at(p, "## Work items (verbatim from {{ROOT}}/)", "prompt.md")
	end)
end)
