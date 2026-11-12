--!strict
-- c0261: every place that says who runs what says it per activity, in the words the Design fixes: zz-rules' Dispatch,
-- the review and authoring skills (one round per review: the design review, the raft review and the final review of the
-- stack are the final reviews, a layer's code review is the work on the way), AGENTS.md, the README and the .models.toml
-- header. The exact model names live only in .models.toml (root-file.spec pins them at check time).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- the cells of today's text are pinned only where ZN_C0261_EXACT is set (this issue's check line), never in the gate
local EXACT = process.env.ZN_C0261_EXACT ~= nil

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
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
local function bullet(text: string, head: string): string
	local a = string.find(text, head, 1, true)
	if not a then
		error(`no bullet {head}`, 2)
	end
	local b = string.find(text, "\n- ", (a :: number) + 3, true)
	return string.sub(text, a :: number, (b or 0) - 1)
end

local RULE = "Opus through `claude` or `agent`, any grok model at `xhigh` through `grok`"
local FALLBACK = "agent falls back to a kimi model, then grok at xhigh, when Opus is not listed"
local FINAL_GATE =
	"refuse unless the design review round, or the final review, was recorded on a final-review model"

return t.spec("c0261 docs", function(it)
	it(
		"zz-rules Dispatch has the Models per activity bullet, with no new vocabulary and no round counting (rule)",
		function()
			local b = bullet(skill("zz-rules"), "- **Models per activity.**")
			for _, w in
				{
					"`[<activity>.<cli>]`",
					"real model names",
					"never aliases",
					"`z-wait`",
					"`zz-review`",
					"`zz-review-design`",
					"`zz-review-raft`",
					"`zz-review-final`",
					"`zz-review-code`",
					"`zz-review-stream`",
					"`z-design`",
					"`z-ticket`",
					"falls back to `zz-review`",
					"./zn metrics",
					"by model",
				}
			do
				at(b, w, "zz-rules Models per activity")
			end
			for _, w in { "tier", "cheap tier", "sharp tier", "--final", "round 5" } do
				absent(b, w, "zz-rules Models per activity")
			end
		end
	)

	it(
		"who reviews is said per activity: every review but a stream review is the expensive one (rule)",
		function()
			for _, name in { "z-design", "z-raft", "zz-execute", "zz-review" } do
				-- c0117's sentence stays true and is extended: Opus first on claude and agent, and the fallbacks
				at(skill(name), RULE, name)
				at(skill(name), FALLBACK, name)
			end
			at(skill("z-design"), "`./zn dispatch zz-review <id> --mode design`", "z-design")
			at(skill("z-design"), "The design review is a final review, its one round", "z-design")
			at(skill("z-raft"), "`./zn dispatch zz-review <R-id> --mode raft`", "z-raft")
			at(skill("z-raft"), "the raft review is a final review", "z-raft")
			at(skill("zz-execute"), "`./zn dispatch zz-review <R-id> --mode final`", "zz-execute")
			at(
				skill("zz-execute"),
				"It is a final review, so it runs the **review model of the CLI**",
				"zz-execute"
			)
			local review = skill("zz-review")
			at(review, "**final reviews** (nothing is judged after them)", "zz-review")
			at(review, "Every review runs the expensive review model of the CLI", "zz-review")
			at(review, "a layer's code review (Code mode)", "zz-review")
			at(review, "Only a stream review", "zz-review")
			absent(review, 'model: "sonnet"', "zz-review")
		end
	)

	it("a layer's code review runs the expensive model: the user ruled it on 2026-11-12 (rule)", function()
		local e = skill("zz-execute")
		at(e, "a reviewer on the author's model shares its blind spots", "zz-execute")
		at(e, "the user ruled (2026-11-12) that every layer's code review runs it", "zz-execute")
		at(e, '`model: "opus"` to the Agent tool', "zz-execute")
		absent(e, "A layer's code review is the work on the way", "zz-execute")
		absent(e, "names for `zz-review-code`", "zz-execute")
	end)

	it(
		"no skill, AGENTS.md or the README still counts review rounds or runs a round with --final (rule)",
		function()
			for _, name in { "z-design", "z-raft", "zz-execute", "zz-review", "zz-rules" } do
				absent(skill(name), "--final", name)
				absent(skill(name), "round 5", name)
			end
			absent(read("AGENTS.md"), "--final", "AGENTS.md")
			absent(read("z-nile/README.md"), "--final", "README")
			absent(read("z-nile/engine/dispatch.luau"), "--final", "dispatch.luau")
		end
	)

	it(
		"the interactive spend lines record the reviewer's model, and zz-rules and zz-execute still never say to wait for green CI (rule)",
		function()
			at(skill("z-design"), "with `--model <reviewer model id>`", "z-design")
			at(skill("z-design"), "with `--model <your model id>`", "z-design")
			at(skill("z-raft"), "with `--model <reviewer model id>`", "z-raft")
			at(
				skill("zz-execute"),
				'`./zn commit -m "<R-id>: final-review-001" --phase code-review --model <reviewer model id>`',
				"zz-execute"
			)
			for _, name in { "zz-rules", "zz-execute" } do
				absent(skill(name), "green CI", name) -- c0172's pin: a merge does not wait for an Actions result
			end
		end
	)

	it(
		"the old statements are gone: nothing defaults without the fallback, Opus through claude and agent, the settings list (rule)",
		function()
			local rules = skill("zz-rules")
			absent(rules, "through `claude` and `agent`, any grok model", "zz-rules")
			absent(rules, "Nothing defaults: a skill no file names", "zz-rules")
			at(rules, "`wait_minutes`", "zz-rules")
			absent(
				read(".models.toml"),
				"nothing defaults: a skill no file names is an error",
				".models.toml"
			)
		end
	)

	it("AGENTS.md, the README and the .models.toml header say it per activity (rule)", function()
		local agents = read("AGENTS.md")
		at(
			agents,
			"The exceptions are the reviewers (the design, layer code, raft and final reviews)",
			"AGENTS.md"
		)
		at(agents, "the work on the way and a stream review run cheap", "AGENTS.md")
		at(
			agents,
			"A lead you start by hand runs on the model `.models.toml` names for its activity",
			"AGENTS.md"
		)
		at(agents, "hands every final review to the reviewer the skills name.", "AGENTS.md")
		absent(agents, "(`/z-run`, `/z-design`) runs on the cheap model", "AGENTS.md")
		absent(agents, "which the skills pin to Opus 5.5", "AGENTS.md")
		at(skill("zz-rules"), "blocks on its nested review (accepted by the user)", "zz-rules")
		at(
			skill("zz-rules"),
			"Nothing expensive orchestrates or waits, with one accepted exception:",
			"zz-rules"
		)
		local readme = read("z-nile/README.md")
		at(bullet(readme, "- **`.models.toml`.**"), "Models per activity", "README")
		local text = read(".models.toml")
		local head = string.sub(text, 1, string.find(text, "\n[dispatch]", 1, true) or 1)
		for _, w in { "per activity", "real model names", "final review", "z-wait" } do
			at(head, w, ".models.toml header")
		end
		at(text, "(through agent only, where the ids carry their effort)", ".models.toml")
	end)

	it(
		"the lists of model steps and the dispatcher's description name z-wait and the wait at a gate (rule)",
		function()
			at(skill("zz-rules"), "`z-run`, `z-wait` and `zz-review`", "zz-rules Steps")
			at(skill("zz-rules"), "modes `design`, `raft`, `code`, `final`, `stream`", "zz-rules Steps")
			at(read("z-nile/README.md"), "it waits on the cheap `z-wait` step and then merges", "README")
			absent(read("z-nile/README.md"), "It stops at a merge gate, at a step's", "README")
			absent(read("z-nile/engine/dispatch.luau"), "4 waiting at a merge gate", "dispatch.luau")
		end
	)

	it("the commands that refuse are documented where an author reads them (rule)", function()
		local rules = skill("zz-rules")
		at(rules, "`./zn status <id> prepared` and `./zn done` " .. FINAL_GATE, "zz-rules")
		at(rules, "to have been recorded on a final-review model and to be resolved", "zz-rules done row")
		at(
			rules,
			"the final review was recorded on a final-review model and is answered, and the raft's `check.sh` passed",
			"zz-rules Merging"
		)
		at(
			skill("z-design"),
			"unless the design review round was recorded on a final-review model",
			"z-design"
		)
		at(
			skill("zz-execute"),
			"`done` refuses unless the last final review was recorded on a final-review model",
			"zz-execute"
		)
		at(skill("zz-review"), "`./zn status <id> prepared` and `./zn done` refuse unless", "zz-review")
	end)

	it(
		"the final-review kinds and the rows that record a round are defined once: the docs name them (rule)",
		function()
			local rules = skill("zz-rules")
			at(rules, "any Opus, kimi k3.1-pro or k3-256k at high or max", "zz-rules")
			at(rules, "an issue with no design review round at all is refused too", "zz-rules")
			at(rules, "`<R-id>: design-review-NNN`", "zz-rules")
			at(rules, "`<R-id>: final-review-NNN`", "zz-rules")
			at(rules, "a layer's `review-NNN.md` is not checked", "zz-rules")
			at(rules, "which wins over the model the runner measures from the session", "zz-rules")
			at(
				rules,
				"the rule guards against forgetting, not against a wrong id typed by the lead",
				"zz-rules"
			)
			at(skill("z-raft"), "under the subject `<R-id>: design-review-NNN`", "z-raft")
		end
	)

	it("the cells named in AGENTS.md and zz-rules are today's (check time only)", function()
		if not EXACT then
			return
		end
		at(read("AGENTS.md"), "(`/z-run` the cheap one, `/z-design` Opus at medium on claude)", "AGENTS.md")
		at(
			read("AGENTS.md"),
			"Opus 5.5 first on claude and agent (agent falls back to a kimi model, then grok-4.7-xhigh)",
			"AGENTS.md"
		)
		at(
			skill("zz-rules"),
			"a z-design session on Opus at medium blocks on its nested review (accepted by the user)",
			"zz-rules"
		)
	end)
end)
