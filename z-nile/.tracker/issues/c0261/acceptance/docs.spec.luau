--!strict
-- c0261 AC12: every place that says who runs what says it in tiers, in the words the Design fixes: zz-rules' Dispatch,
-- zz-review, z-design, zz-execute, AGENTS.md, the README and the .models.toml header.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
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
	it("zz-rules Dispatch has the Model tiers bullet with every CLI's three models (AC12)", function()
		local b = bullet(skill("zz-rules"), "- **Model tiers.**")
		for _, w in {
			"`[tiers.<cli>.<tier>]`", "`tier = \"cheap\"`", "cheap", "sharp", "wait", "`--final`", "never aliases",
			"`claude-sonnet-5`", "`claude-opus-5-5`", "`claude-haiku-5-5`",
			"`grok-4.6` at high", "`grok-4.7` at xhigh", "`grok-4.5` at low",
			"`cursor-grok-4.6-high`", "`grok-4.7-xhigh`", "`composer-2.5`",
			"`z-wait`", "nothing expensive orchestrates or waits", "records the tier",
		} do
			at(b, w, "zz-rules Model tiers")
		end
	end)

	it("who reviews is said in tiers, and the old Opus-only rule is gone from the skills (AC12)", function()
		for _, name in { "z-design", "z-raft", "zz-execute", "zz-review" } do
			at(skill(name), "the sharp tier", name)
			absent(skill(name), "Opus through `claude` or `agent`, any grok model at `xhigh` through `grok`", name)
		end
		at(skill("z-design"), "`./zn dispatch zz-review <id> --mode design --final`", "z-design")
		at(skill("zz-execute"), "`./zn dispatch zz-review <R-id> --mode code --final`", "zz-execute")
		at(skill("z-raft"), "`./zn dispatch zz-review <R-id> --mode raft --final`", "z-raft")
		at(skill("zz-review"), "`--final`", "zz-review")
		at(skill("zz-review"), "a stream review is never final", "zz-review")
	end)

	it("the round rule names the final round: cheap while the rule says go on, one sharp round to stop (AC12)", function()
		local d = skill("z-design")
		at(d, "the round after which this rule runs no further round", "z-design")
		at(d, "run it sharp: `--final`", "z-design")
		at(skill("zz-execute"), "run it sharp: `--final`", "zz-execute")
	end)

	it("AGENTS.md, the README and the .models.toml header say tiers (AC12)", function()
		at(read("AGENTS.md"), "final-round reviewers", "AGENTS.md")
		absent(read("AGENTS.md"), "which the skills pin to Opus 5.5", "AGENTS.md")
		local readme = read("z-nile/README.md")
		at(bullet(readme, "- **`.models.toml`.**"), "tiers", "README")
		local text = read(".models.toml")
		local head = string.sub(text, 1, string.find(text, "\n[dispatch]", 1, true) or 1)
		for _, w in { "cheap", "sharp", "wait", "real model names" } do
			at(head, w, ".models.toml header")
		end
	end)
end)
