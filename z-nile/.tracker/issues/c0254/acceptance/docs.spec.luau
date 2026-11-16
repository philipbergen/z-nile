--!strict
-- c0254 AC6: the README's claim paragraph (the user's 2026-11-08 scope decision: it follows the raft claim, and the `preparing`
-- claim is a worker drafting a design for a person to approve), and the two skills that restate the rules it changes, say what a
-- worker on several hosts does and no longer say what it overtook (restated rules move together). The phrases and label the done
-- c0264's check pins are kept. Reads the real tree, plain finds only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function at(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) == nil then
		error(`{where} is missing: {needle}`, 2)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) ~= nil then
		error(`{where} still says: {needle}`, 2)
	end
end

return t.spec("c0254 the docs say what a worker on several hosts does", function(it)
	it("AC6: the claim paragraph follows the raft claim and says what a preparing claim is", function()
		local s = read("z-nile/README.md")
		absent(s, "a lost race means taking the next item", "README")
		at(s, "The push is the lock: a lost race means taking the next raft.", "README")
		at(s, "A `preparing` claim means a worker drafting the design for a person to approve.", "README")
		at(s, "exit 6 (`taken`)", "README")
		at(s, "a rafting claim is the raft's claim, so two hosts never raft one issue", "README")
	end)

	it(
		"AC6: the paragraph names the pushes, the exits, the trailer, the spend cells, the leftover and where who-holds-what shows",
		function()
			local s = read("z-nile/README.md")
			at(s, "pushes its layer branch after every commit, and a prep branch too", "README")
			at(s, "exits 7 when the push is refused under a claim and 8 when it fails", "README")
			at(s, "builds its own worktree from the pushed branch", "README")
			at(s, "never pushes, finishes or restacks that branch again", "README")
			at(s, "marked discarded by `./zn sync`", "README")
			at(s, "`./zn reap` lists what is left", "README")
			at(
				s,
				"`Worker:` trailer with the worker's host, CLI and model for every item it stamps",
				"README"
			)
			at(s, "spend rows record the host, the CLI and the model of the step that spent them", "README")
			at(s, '("held by") and `./zn work status`', "README")
		end
	)

	it("AC6: the done c0264's pins hold: its phrase, its label place, and the capability row", function()
		local s = read("z-nile/README.md")
		at(s, "pushes its layer branch after every commit", "README")
		at(s, "*exists* (c0254) (the claim itself *exists*)", "README")
		at(s, "| workers on several hosts, worker identity in spend | c0254 | exists |", "README")
	end)

	it(
		"AC6: zz-rules says a prep commit is pushed, names the claim step, and states the several-hosts rules",
		function()
			local rules = read("z-nile/skills/zz-rules/SKILL.md")
			at(rules, "and in an issue's prep worktree (`prep-<slug>`", "zz-rules")
			at(rules, "Both push the branch after every commit", "zz-rules")
			at(
				rules,
				"`claim` (`./zn status <id> preparing`, in the issue's prep worktree; worker mode only, c0254)",
				"zz-rules"
			)
			at(rules, "**Several hosts (c0254).**", "zz-rules")
			at(rules, "exit 6, `taken`", "zz-rules")
			at(rules, "never by the run state's history", "zz-rules")
			at(rules, "exit 7 when refused under a claim, 8 when it failed", "zz-rules")
		end
	)

	it(
		"AC6: z-design commits as it goes at named checkpoints, and skips the claim a worker's dispatcher made",
		function()
			local design = read("z-nile/skills/z-design/SKILL.md")
			at(design, '**Commit as you go** with `./zn commit -m "tracker: prep c0010 <what>"`', "z-design")
			at(
				design,
				"the Design draft, `check.sh` and the specs, the experiments and the prototype patch, the review file, and the answers to it",
				"z-design"
			)
			at(
				design,
				"If a commit exits 7, the push was refused because your claim was taken over: stop",
				"z-design"
			)
			at(design, "under `./zn dispatch --worker` the dispatcher has already claimed it", "z-design")
			absent(design, "as one commit with `./zn commit", "z-design")
		end
	)
end)
