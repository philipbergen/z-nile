--!strict
-- c0115 AC8: the renamed skills say what they now hold: z-run launches (launch-raft) and hands off to zz-execute
-- (execute-raft); zz-test keeps the gate,
-- check.sh, sequestration and the guards, and pickman-test the game's tiers; zz-arch holds the tooling's rules and
-- pickman-arch the game's; z-design reads its three checklists; zz-rules states the skill folders, the links, the
-- naming rule and the `skills` command in every list a command joins; every skill's lessons paragraph names the real
-- folder; AGENTS.md and SETUP.md name the new skills and commands; `./zn`'s usage names `skills`. Reads the real tree.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function read(path: string): string
	return fs.readFile(path)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function at(text: string, needle: string, where: string)
	if not has(text, needle) then
		error(`{where} is missing: {needle}`, 2)
	end
end
local function section(text: string, heading: string): string
	local a = string.find(text, "\n" .. heading, 1, true)
	if not a then
		error(`no section {heading}`, 2)
	end
	local b = string.find(text, "\n## ", (a :: number) + 1, true)
	return string.sub(text, a :: number, (b or 0) - 1)
end
local Z = "z-nile/skills"
local ALL = {
	"z-ticket",
	"z-design",
	"z-ready",
	"z-run",
	"z-stop",
	"zz-execute",
	"zz-review",
	"zz-rules",
	"zz-arch",
	"zz-test",
	"zz-stats",
}

return t.spec("c0115 the renamed skills say what they hold", function(it)
	it("z-run launches and hands off; zz-execute is the protocol it hands off to", function()
		local run = read(`{Z}/z-run/SKILL.md`)
		at(run, "`./zn prompt <R> --path`", "z-run")
		at(run, "run `/z-ready <R>`", "z-run")
		at(run, 'cd "$(./zn worktree <R>)"', "z-run")
		at(
			run,
			"**Hand off.** Follow the prompt as your instructions, from its first line: it carries the zz-execute skill",
			"z-run"
		)
		local exec = read(`{Z}/zz-execute/SKILL.md`)
		at(exec, "\n## Phase 0: Claim", "zz-execute")
		at(exec, "\n## Stop conditions", "zz-execute")
		at(
			read("z-nile/templates/prompt.md"),
			"1. **Follow the `zz-execute` skill below, step by step.**",
			"the prompt template"
		)
	end)

	it(
		"zz-test keeps the gate, check.sh, sequestration and the guards; pickman-test the game's tiers",
		function()
			local zt = read(`{Z}/zz-test/SKILL.md`)
			for _, h in
				{
					"## Running tests",
					"## Affected selection",
					"## Acceptance checks (`check.sh`)",
					"## Speed",
					"## Specs never touch the real repository",
				}
			do
				at(zt, "\n" .. h, "zz-test")
			end
			t.expect(has(zt, "## Simulations")).toBe(false)
			t.expect(has(zt, "| `tests/scenario/`")).toBe(false)
			local pt = read("pickman/skills/pickman-test/SKILL.md")
			for _, needle in
				{
					"\n## Spec tiers",
					"| `tests/unit/<Feature>/` |",
					"| `tests/runtime/` |",
					"scripts/runtime-test",
					"Open Cloud",
					"\n## Simulations (`@tests/lib/sim`)",
					"`@tests/lib/fakeengine`",
					"in the zz-test skill",
				}
			do
				at(pt, needle, "pickman-test")
			end
		end
	)

	it("zz-arch holds the tooling's rules and checklist; pickman-arch the game's", function()
		local za = read(`{Z}/zz-arch/SKILL.md`)
		for _, needle in
			{
				"**One reader per format.**",
				"**Guards fail closed.**",
				"**Pure over texts, reads at the edge.**",
				"`@znile` names `z-nile/`",
				"## Design checklist (answer these in every tooling issue's Design section)",
			}
		do
			at(za, needle, "zz-arch")
		end
		local pa = read("pickman/skills/pickman-arch/SKILL.md")
		for _, needle in { "**Logic is pure.**", "## Design checklist", "`pickman/.tracker/architecture.md`" } do
			at(pa, needle, "pickman-arch")
		end
	end)

	it("z-design reads the checklist of the issue's type", function()
		at(
			read(`{Z}/z-design/SKILL.md`),
			"First read the checklist for the issue's type, `checklists/<feature|defect|chore>.md` beside this skill",
			"z-design"
		)
	end)

	it(
		"zz-rules states the folders, the links, the naming rule and the skills command in each list",
		function()
			local zr = read(`{Z}/zz-rules/SKILL.md`)
			at(
				zr,
				"- **Skills**: z-nile's skills live in `z-nile/skills/<name>/SKILL.md`, a project's own in `<project>/skills/<name>/SKILL.md`",
				"zz-rules"
			)
			at(zr, "which `./zn skills` writes and `./zn skills --check` (in the gate) checks", "zz-rules")
			at(zr, "a project's skill is named `<project>-…`", "zz-rules")
			at(zr, "| skills | `./zn skills [--check]` |", "zz-rules command table")
			at(zr, "`skills --check` and `capture <id>` (they only read)", "zz-rules main-checkout list")
			at(zr, "`compact`, `remap` and `skills` (without `--check`) refuse", "zz-rules refusal list")
			at(zr, "- `./zn skills [--check]`\n", "zz-rules Other commands")
			at(
				zr,
				"A branch from before c0115 that added a file inside an old skill folder (`.claude/skills/<old>/`) gets the same conflict",
				"zz-rules Conflicts"
			)
			local usage = process.exec("bash", { "zn" })
			at(usage.stdout, "skills [--check]", "./zn usage")
		end
	)

	it("every skill's lessons paragraph names the real folder", function()
		local dirs = {}
		for _, n in ALL do
			table.insert(dirs, `{Z}/{n}`)
		end
		table.insert(dirs, "pickman/skills/pickman-arch")
		table.insert(dirs, "pickman/skills/pickman-test")
		for _, d in dirs do
			local s = section(read(`{d}/SKILL.md`), "## Lessons")
			at(
				s,
				"writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder:",
				d
			)
			at(s, "never through a `.claude/skills/` link, which git can't add through", d)
			at(s, `./zn lessons --skill {string.match(d, "[^/]+$")} --full`, d)
		end
	end)

	it(
		"AGENTS.md lists every skill by its real path and starts execution with /z-run; SETUP.md too",
		function()
			local agents = read("AGENTS.md")
			for _, n in ALL do
				at(agents, `| \`{Z}/{n}/SKILL.md\` |`, "AGENTS.md")
			end
			at(agents, "| `pickman/skills/pickman-arch/SKILL.md` |", "AGENTS.md")
			at(agents, "| `pickman/skills/pickman-test/SKILL.md` |", "AGENTS.md")
			at(agents, "Start execution with `/z-run <R-id>`", "AGENTS.md")
			at(agents, "`z-nile/README.md` is the map", "AGENTS.md")
			local setup = read("SETUP.md")
			at(setup, "/z-run R0010", "SETUP.md")
			at(setup, "`/z-ready` writes it", "SETUP.md")
		end
	)
end)
