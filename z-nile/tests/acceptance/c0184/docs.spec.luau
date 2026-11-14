--!strict
-- c0184 AC7: the sentences that restate the home scaffold, the generalised hook and the new skills move together
-- (z-design lesson restated-rules-move-together). Promoted, so every check over projects runs over the registry (never
-- today's five); the exact rows, and the text of the skills of today's five, are check.sh's. Read-only: the real tree.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end
local function at(text: string, needle: string, where: string)
	if not string.find(text, needle, 1, true) then
		error(`{where} is missing: {needle}`)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) then
		error(`{where} still has: {needle}`)
	end
end
-- a line of `text` that holds every needle
local function line(text: string, needles: { string }): boolean
	for l in string.gmatch(text, "[^\n]+") do
		local all = true
		for _, n in needles do
			if not string.find(l, n, 1, true) then
				all = false
			end
		end
		if all then
			return true
		end
	end
	return false
end
local function others(): { projects.Project }
	local out: { projects.Project } = {}
	for _, p in projects.load(TOP).projects do
		if p.name ~= "z-nile" and p.name ~= "pickman" then
			table.insert(out, p)
		end
	end
	return out
end

return t.spec("c0184 the restated rules and the new skills", function(it)
	it(
		"AC7: AGENTS.md and the README say every project with code has pickman's home, and name each project's skills",
		function()
			local agents, readme = read("AGENTS.md"), read("z-nile/README.md")
			at(agents, "Every project with code has the same home as `pickman/` (c0184)", "AGENTS.md")
			at(
				agents,
				"which the gate checks for each registered project (z-nile/README.md, A project's home).",
				"AGENTS.md"
			)
			at(readme, "## A project's home", "README")
			at(
				readme,
				"the gate checks it for every project of `z-nile/projects.toml` except z-nile",
				"README"
			)
			at(
				readme,
				"A new project with code needs its registry entry, its root and `deploy.yml` entry",
				"README"
			)
			for _, item in
				{
					"`check.sh`: the project's gate",
					"`default.project.json`, and any other `*.project.json`",
					"`tests/run.luau` (the shared runner, run from the home)",
					"`skills/<name>-arch/SKILL.md` and `skills/<name>-test/SKILL.md`",
					"In its root, `architecture.md`, with one `deps` block.",
				}
			do
				at(readme, item, "README")
			end
			-- every registered project but z-nile is named in a skills row of each
			for _, p in others() do
				t.expect(line(agents, { "-arch/SKILL.md", `\`{p.name}\`` })).toBe(true)
				t.expect(line(readme, { `{p.name}-arch`, `{p.name}-test` })).toBe(true)
			end
			t.expect(line(agents, { "pickman-arch/SKILL.md" })).toBe(true)
		end
	)

	it("AC7: zz-rules and zz-test restate the home and the fence scan for every registered home", function()
		local rules, test = read("z-nile/skills/zz-rules/SKILL.md"), read("z-nile/skills/zz-test/SKILL.md")
		at(
			rules,
			"A project with code also needs its home (z-nile/README.md, A project's home), which the gate checks for every project.",
			"zz-rules"
		)
		at(
			test,
			"(the root's `scripts/`, every registered project's home, `z-nile/`'s included, `./zn` and every `check.sh`;",
			"zz-test"
		)
		absent(test, "(`tests/`, `scripts/`, `z-nile/`, `./zn` and every `check.sh`;", "zz-test")
		at(
			test,
			"Every project with a home except z-nile has the same `tests/run.luau`, `tests/lib/t.luau` and `renamed.luau`, `tests/meta/architecture.spec.luau`, `fence.spec.luau` and `home.spec.luau`",
			"zz-test"
		)
		at(read("z-nile/skills/zz-rules/SKILL.md"), "`extends:`", "zz-rules")
	end)
end)
