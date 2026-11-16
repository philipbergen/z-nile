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
		"AC13: zz-rules Dispatch: the chain lands a finished raft through land-check and done, and names the run gate",
		function()
			local rules = read("z-nile/skills/zz-rules/SKILL.md")
			for _, phrase in
				{
					"runs `./zn land-check <R-id>`",
					"lands the stack itself with `./zn done` in the raft's worktree, with its own environment (the `run` gate)",
					"up to `merge_attempts` tries (default 2), then blocks under the problem's reason",
					"a failed check or an unruled high finding blocks at once",
					"`./zn block` writes `block-request` in the state folder and stops",
					"lands the green layers below the Layer with `./zn done --through`, then files the block",
					"`./zn done` is refused while `ZN_DISPATCH` is set",
					"a raft with no layer branches keeps its one pull request and a human's merge",
				}
			do
				says(rules, phrase, "zz-rules Dispatch")
			end
			lacks(rules, "and that PR is the `run` gate, always a human's", "zz-rules Dispatch")
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
			says(exec, "and `./zn done` is refused while `ZN_DISPATCH` is set", "zz-execute")
			says(
				exec,
				"under the dispatcher it only leaves a request, you stop, and the dispatcher lands the green layers below the Layer before it files the block",
				"zz-execute"
			)
			lacks(exec, "the merge of the run's PR is a human's gate", "zz-execute")
			local run = read("z-nile/skills/z-run/SKILL.md")
			says(run, "Never run `./zn done`: it is refused here", "z-run")
			says(run, "`./zn block` here only leaves a request: stop after it", "z-run")
		end
	)

	it(
		"AC13: the README marks the dispatcher's landing as existing, and keeps the person-approval clause",
		function()
			local readme = read("z-nile/README.md")
			says(readme, "| the dispatcher lands a green stack | c0252 | exists |", "README table")
			says(readme, "*exists* (c0252)", "README autonomous delivery")
			lacks(readme, "*captured* (c0252)", "README")
			lacks(readme, "a person rafts", "README")
		end
	)

	it(
		"AC13: the root .models.toml arms the run gate and names merge_attempts, and the step prompt tells a worker done is refused",
		function()
			local toml = read(".models.toml")
			says(toml, 'auto_merge = ["prep", "raft", "run"]', ".models.toml")
			says(toml, "merge_attempts = 2", ".models.toml")
			lacks(toml, "the run's PR is always a human's", ".models.toml")
			local prompt = dispatch.prompt({
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
			})
			says(
				prompt,
				"`./zn done` is refused here too: when your work is done, stop, and the dispatcher lands the stack.",
				"the z-run prompt"
			)
			says(prompt, "Never merge a pull request and never push to main yourself", "the z-run prompt")
		end
	)
end)
