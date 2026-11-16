--!strict
-- c0293 AC5: a rule the root AGENTS.md drops stays stated where the step that needs it reads it: the lesson
-- rules in every skill, the harvest in z-design and zz-execute, the skill links in zz-rules, and the prefixes, the
-- project's home and the zz- skills' table in z-nile/README.md.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{root}/{rel}`)
end

local function says(rel: string, needle: string)
	if string.find(read(rel), needle, 1, true) == nil then
		error(`{rel} does not say: {needle}`)
	end
end

-- every skill folder of every registered project, z-nile's included, from the folders themselves (a skill or a
-- project added later is covered: c0184's rule, a promoted check over projects runs over the registry)
local function skills(): { string }
	local out: { string } = {}
	for _, p in projects.load(root).projects do
		local home = p.home
		local dir = `{root}/{home}/skills`
		for _, name in fs.readDir(dir) do
			if fs.isFile(`{dir}/{name}/SKILL.md`) then
				table.insert(out, `{home}/skills/{name}/SKILL.md`)
			end
		end
	end
	table.sort(out)
	return out
end

return t.spec("c0293 dropped rules stay stated", function(it)
	it("AC5: every skill says how lessons are searched and where a new one goes", function()
		local all = skills()
		if #all < 24 then
			error(`found {#all} skills, fewer than the 24 of c0293's day`)
		end
		for _, rel in all do
			says(
				rel,
				"Search with `./zn lessons <terms>` when you are about to do something a lesson might cover."
			)
			says(rel, "**Any other lead** (in the main checkout, a capture, or a metrics report) captures it")
		end
	end)

	it("AC5: every skill carries c0136's lead-in, and zz-review the question it adds", function()
		-- c0136's exact sentences run at its `done` and never again (its check.sh); the root's copy of the rule is
		-- dropped here, so they are pinned for good
		local all = skills()
		if #all < 24 then
			error(`found {#all} skills, fewer than the 24 of c0293's day`)
		end
		for _, rel in all do
			says(
				rel,
				"A lesson goes to the step that erred: the skill whose instructions the author was following when the mistake was made"
			)
		end
		says(
			"z-nile/skills/zz-review/SKILL.md",
			"Ask: which step made this mistake, and which earlier step should have caught it?"
		)
	end)

	it("AC5: z-design and zz-execute harvest every review finding", function()
		says("z-nile/skills/z-design/SKILL.md", "**Harvest the round**")
		says("z-nile/skills/zz-execute/SKILL.md", "**Harvest the round**")
	end)

	it("AC5: zz-rules says where the skills live and how they are linked", function()
		says("z-nile/skills/zz-rules/SKILL.md", "`.claude/skills/<name>`")
		says("z-nile/skills/zz-rules/SKILL.md", "`./zn skills`")
	end)

	it("AC5: the README keeps the prefixes, the project's home and every zz- skill's row", function()
		local readme = "z-nile/README.md"
		says(readme, "Both prefixes are z-nile's: a project's skills are named `<project>-…`.")
		says(readme, "## A project's home")
		for _, s in { "zz-execute", "zz-review", "zz-rules", "zz-arch", "zz-test", "zz-stats" } do
			says(readme, `| \`{s}\` |`)
		end
	end)
end)
