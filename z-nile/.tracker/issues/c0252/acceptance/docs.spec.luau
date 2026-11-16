--!strict
-- c0252 AC13: every text that restates the changed rule says the new one: the skills (zz-rules Dispatch, zz-execute
-- Phase 6, z-run Headless), the README markers, the root .models.toml and the step prompt. The sentences the old rule
-- pinned (c0117's docs.spec and models.spec) are this chore's Overrides.
local dispatch = require("@znile/engine/dispatch")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function says(text: string, phrase: string, where: string)
	if string.find(text, phrase, 1, true) == nil then
		error(`{where} does not say: {phrase}`, 2)
	end
end
local function lacks(text: string, phrase: string, where: string)
	if string.find(text, phrase, 1, true) ~= nil then
		error(`{where} still says: {phrase}`, 2)
	end
end

return t.spec("c0252 the texts say the dispatcher lands a green stack", function(it)
	it(
		"AC13: zz-rules Dispatch: the chain judges and lands a finished raft with the base's engine, gates a game stack in a clean clone, and names the run gate",
		function()
			local rules = read("z-nile/skills/zz-rules/SKILL.md")
			for _, phrase in
				{
					"with the base's engine (the main checkout's, run as `./zn -C <worktree> …`, never the stack's own `zn`)",
					"`./zn land-check <R-id>` reads the checks before a landing",
					"Every read that fails (git, the registry, gh, an answer it cannot read) is a wait, never a pass",
					"gated by `./zn land-gate` in a clean clone outside the checkout",
					"a tooling-only stack by `done`'s affected gate on the merged tree (Merging 2)",
					"lands it itself with `./zn done` in the raft's worktree with its own environment (the `run` gate)",
					"or a stack that changes the gate's own driver",
					"up to `merge_retries` reruns (default 2: three runs) of one repeated failure",
					"a failed read is never counted",
					"An unruled high finding or approval drift blocks at once",
					"which recommends `retry`, or `approve` when a person must rule",
					"`./zn block` writes `block-request` and a copy of the note in the state folder and stops",
					"lands the green layers below the Layer with `./zn done --through` (waiting at the gate while their CI runs)",
					"`./zn done` in a session that holds the agent's credential (`ZN_DISPATCH` or `ZN_HEADLESS`) runs every check, writes a land request",
					"the dispatcher's landing of that raft, or a person's `./zn lander`, lands it with their own credential",
					"A raft with no layer branches keeps its one pull request and a human's merge",
					"must keep an admin bypass for `./zn done`'s direct push of the bind",
				}
			do
				says(rules, phrase, "zz-rules Dispatch")
			end
			lacks(rules, "and that PR is the `run` gate, always a human's", "zz-rules Dispatch")
			lacks(rules, "merge_attempts", "zz-rules")
		end
	)

	it(
		"AC13: zz-execute Phase 6 and z-run Headless: a worker stops after its work, never runs done, and blocks by request",
		function()
			local exec = read("z-nile/skills/zz-execute/SKILL.md")
			says(
				exec,
				"the dispatcher lands the stack itself with `./zn done` once its checks pass (`./zn land-check`)",
				"zz-execute"
			)
			says(
				exec,
				"`./zn done` in a session that holds the agent's credential (`ZN_DISPATCH` or `ZN_HEADLESS`) runs every check and leaves a land request instead of pushing",
				"zz-execute"
			)
			says(
				exec,
				"under the dispatcher it only leaves a request, you stop, and the dispatcher lands the green layers below the Layer before it files the block",
				"zz-execute"
			)
			lacks(exec, "the merge of the run's PR is a human's gate", "zz-execute")
			local run = read("z-nile/skills/z-run/SKILL.md")
			says(
				run,
				"`./zn done` here runs every check and, instead of pushing, writes a land request",
				"z-run"
			)
			says(run, "`./zn block` here only leaves a request: stop after it", "z-run")
		end
	)

	it(
		"AC13: the README marks the dispatcher's landing as existing and keeps the person-approval clause the scope decision asks for",
		function()
			local readme = read("z-nile/README.md")
			says(readme, "| the dispatcher lands a green stack | c0252 | exists |", "README table")
			says(readme, "*exists* (c0252)", "README autonomous delivery")
			lacks(readme, "*captured* (c0252)", "README")
			-- c0264's words: a worker drafts and a person approves (the 2026-11-08 scope decision), and nobody rafts by hand
			says(readme, "once a person has approved its design", "README autonomous delivery")
			says(readme, "stops at a person's `./zn approve`", "README")
			lacks(readme, "a person rafts", "README")
		end
	)

	it(
		"AC13: the root .models.toml arms the run gate and names merge_retries, and the step prompt tells a worker what done does and a rerun why it runs",
		function()
			local toml = read(".models.toml")
			says(toml, 'auto_merge = ["prep", "raft", "run"]', ".models.toml")
			says(toml, "merge_retries = 2", ".models.toml")
			lacks(toml, "merge_attempts", ".models.toml")
			lacks(toml, "the run's PR is always a human's", ".models.toml")
			local function prompt(rerun: { string }?): string
				return dispatch.prompt({
					step = "z-run",
					id = "R0010",
					mode = nil,
					skillPath = "z-nile/skills/z-run/SKILL.md",
					worktree = "/w",
					stateDir = "/state",
					promptPath = "/p",
					streamWorktree = nil,
					description = nil,
					project = nil,
					exchange = nil,
					exchangeAsker = nil,
					exchangeNoReply = nil,
					exchangeUnknownReply = nil,
					exchangeLastStep = nil,
					parentExchange = nil,
					parentStateDir = nil,
					rerun = rerun,
				} :: any)
			end
			local first = prompt(nil)
			says(
				first,
				"`./zn done` here runs every check and leaves a land request instead of pushing: when your work is done, stop, and a lander lands the stack.",
				"the z-run prompt"
			)
			says(first, "Never merge a pull request and never push to main yourself", "the z-run prompt")
			says(prompt({ "ci-failed (redo): x" }), "ci-failed (redo): x", "the rerun prompt")
		end
	)
end)
