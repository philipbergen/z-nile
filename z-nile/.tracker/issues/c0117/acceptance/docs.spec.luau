--!strict
-- c0117 AC14: the skills, the README, AGENTS.md, the usage and the prompt template say what the design's Docs part
-- says: the headless rules in every model step's skill, word for word; the review model of the CLI wherever a skill
-- says who reviews (no "Opus 5.5" rule is left); zz-rules' Dispatch section; z-run's end under the dispatcher; the
-- built dispatcher and .models.toml in the README; the model cell; and the template that names files.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function read(path: string): string
	return fs.readFile(path)
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
			at(h, "Never merge a pull request and never push to `main`", name)
			at(h, "without `--tokens` for your own session", name)
			at(h, "`./zn dispatch zz-review <id> --mode <design|raft|code>`", name)
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
		at(skill("z-run"), "`./zn dispatch zz-review <R-id> --mode code`", "z-run")
		at(skill("z-run"), "--model <reviewer model>", "z-run")
		for _, name in fs.readDir("z-nile/skills") do
			if fs.isFile(`z-nile/skills/{name}/SKILL.md`) then
				absent(skill(name), "on **Opus 5.5**", name)
				absent(skill(name), "on Opus 5.5", name)
			end
		end
	end)

	it("z-run ends at Ready to merge under the dispatcher", function()
		at(
			section(skill("z-run"), "## Phase 6: Merge and clean up"),
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
				"- **Running a model step.**",
				"It moves down `order` only when a CLI fails on quota",
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
		at(readme, "- **`.models.toml`.**", "the README")
	end)

	it("AGENTS.md and the usage name the dispatcher", function()
		local agents = read("AGENTS.md")
		at(agents, "the dispatcher's run state in `.cache/dispatch/`", "AGENTS.md")
		at(agents, "`./zn dispatch <id>`", "AGENTS.md")
		local usage = process.exec("./zn", {}).stdout
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
