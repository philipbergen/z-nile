--!strict
-- c0261: every place that says who runs what says it per activity, in the words the Design fixes: zz-rules' Dispatch,
-- the review and authoring skills (the final round procedure), AGENTS.md, the README and the .models.toml header.
-- The exact model names live only in .models.toml (root-file.spec pins them at check time).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (
	string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)
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

return t.spec("c0261 docs", function(it)
	it("zz-rules Dispatch has the Models per activity bullet, with no new vocabulary (rule)", function()
		local b = bullet(skill("zz-rules"), "- **Models per activity.**")
		for _, w in {
			"`[<activity>.<cli>]`", "real model names", "never aliases", "`z-wait`", "`--final`", "`zz-review`",
			"`zz-review-design`", "`zz-review-design-final`", "`zz-review-code`", "`zz-review-stream`", "`z-design`", "`z-ticket`",
			"falls back to `zz-review`", "./zn metrics", "by model",
		} do
			at(b, w, "zz-rules Models per activity")
		end
		for _, w in { "tier", "cheap tier", "sharp tier" } do
			absent(b, w, "zz-rules Models per activity")
		end
	end)

	it("who reviews is said per activity: the final round is the expensive one, the rounds on the way are not (rule)", function()
		for _, name in { "z-design", "z-raft", "zz-execute", "zz-review" } do
			at(skill(name), "the final round", name)
			absent(skill(name), "Opus through `claude` or `agent`, any grok model at `xhigh` through `grok`", name)
		end
		at(skill("z-design"), "`./zn dispatch zz-review <id> --mode design --final`", "z-design")
		at(skill("zz-execute"), "`./zn dispatch zz-review <R-id> --mode code --final`", "zz-execute")
		at(skill("z-raft"), "`./zn dispatch zz-review <R-id> --mode raft`", "z-raft")
		at(skill("zz-review"), "`--final`", "zz-review")
		at(skill("zz-review"), "a stream review is never final", "zz-review")
	end)

	it("the round rule: the final round is always run with --final, and the old definition is gone (rule)", function()
		for _, name in { "z-design", "zz-execute" } do
			local s = skill(name)
			at(s, "It is always run with `--final` (the expensive model): a round on the way never ends the count", name)
			at(s, "round 5 is run with `--final`", name)
			at(s, "from the first round run with `--final` on, every round is run with `--final`", name)
			absent(s, "any round 1 to 4 where it says stop", name)
		end
		at(skill("z-design"), "A final round holds a high only in round 5", "z-design")
	end)

	it("the interactive spend lines record the reviewer's model, and zz-rules and zz-execute still never say to wait for green CI (rule)", function()
		at(skill("z-design"), "--model <reviewer model id> --note design-review-NNN", "z-design")
		at(skill("z-raft"), "--model <reviewer model id> --note design-review-NNN", "z-raft")
		for _, name in { "zz-rules", "zz-execute" } do
			absent(skill(name), "green CI", name) -- c0172's pin: a merge does not wait for an Actions result
		end
	end)

	it("the old statements are gone: nothing defaults without the fallback, Opus through claude and agent, the settings list (rule)", function()
		local rules = skill("zz-rules")
		absent(rules, "through `claude` and `agent`, any grok model", "zz-rules")
		absent(rules, "Nothing defaults: a skill no file names", "zz-rules")
		at(rules, "`wait_minutes`", "zz-rules")
		absent(read(".models.toml"), "nothing defaults: a skill no file names is an error", ".models.toml")
	end)

	it("stream reviews and Phase 2B no longer say the stream review runs on the review model of the CLI (rule)", function()
		absent(skill("zz-review"), "on the review model of the CLI", "zz-review")
		absent(skill("zz-execute"), "on the review model of the CLI", "zz-execute")
		at(skill("zz-review"), "a stream review runs on the model `zz-review-stream` names", "zz-review")
	end)

	it("AGENTS.md, the README and the .models.toml header say it per activity (rule)", function()
		at(read("AGENTS.md"), "final-round reviewers", "AGENTS.md")
		absent(read("AGENTS.md"), "which the skills pin to Opus 5.5", "AGENTS.md")
		local readme = read("z-nile/README.md")
		at(bullet(readme, "- **`.models.toml`.**"), "Models per activity", "README")
		absent(readme, "round one Opus through `claude` or `agent`", "README")
		local text = read(".models.toml")
		local head = string.sub(text, 1, string.find(text, "\n[dispatch]", 1, true) or 1)
		for _, w in { "per activity", "real model names", "final review", "z-wait" } do
			at(head, w, ".models.toml header")
		end
	end)
end)
