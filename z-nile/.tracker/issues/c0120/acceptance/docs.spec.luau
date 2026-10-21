--!strict
-- c0120 AC13: the skills, AGENTS.md, SETUP.md, the templates and the command's usage say where pickman lives and what
-- a home is: pickman's root and home, the retired tracker/, checks and specs run from their home, each project's gate,
-- promotion into the home, the new command (`busy`) in every list of commands, and no old path to
-- pickman's architecture map or game design.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local SKILLS = ".claude/skills"
local function read(path: string): string
	return fs.readFile(path)
end
local function at(text: string, needle: string, where: string)
	if not string.find(text, needle, 1, true) then
		error(`{where} is missing: {needle}`)
	end
end
local function docs(): { [string]: string }
	local out: { [string]: string } = { ["AGENTS.md"] = read("AGENTS.md"), ["SETUP.md"] = read("SETUP.md") }
	for _, name in fs.readDir(SKILLS) do
		local dir = `{SKILLS}/{name}`
		if fs.isFile(`{dir}/SKILL.md`) then
			out[`{dir}/SKILL.md`] = read(`{dir}/SKILL.md`)
		end
		if fs.isDir(`{dir}/lessons`) then
			for _, l in fs.readDir(`{dir}/lessons`) do
				out[`{dir}/lessons/{l}`] = read(`{dir}/lessons/{l}`)
			end
		end
	end
	for _, rel in { "prompt.md", "issue/doc.md", "issue/check.sh", "raft/doc.md", "raft/check.sh" } do
		out[`z-nile/templates/{rel}`] = read(`z-nile/templates/{rel}`)
	end
	return out
end

return t.spec("c0120 the documents say where pickman lives", function(it)
	it("the tracker skill states the roots, the homes, the retired root and the new commands", function()
		local s = read(`{SKILLS}/tracker/SKILL.md`)
		local w = "tracker skill"
		at(s, "pickman's is `pickman/.tracker/` and z-nile's, the tooling's, is `z-nile/.tracker/`", w)
		at(
			s,
			"Each project also has a home, the folder its `check.sh` files and specs run in: `pickman/` for pickman",
			w
		)
		at(s, "`./zn check` runs a pickman item's `check.sh` from `pickman/`", w)
		at(s, "`./zn find` and `members` print paths from the folder you run them in", w)
		at(s, "`tracker/` is a retired root (c0120)", w)
		at(s, "`./zn audit` and the gate fail if anything else appears there", w)
		at(
			s,
			"`check.yml` ignores `pickman/.tracker/**`, `z-nile/.tracker/**` and `z-nile/next` on `push`",
			w
		)
		at(s, "a branch from before c0120 that added a file in a pickman item's folder", w)
		at(s, "`./zn busy` lists what holds them", w)
		at(s, "| busy | `./zn busy [<path>...]` |", w)
		at(s, "`list`, `audit`, `find`, `members`, `busy`,", w)
		at(s, "writes the ignored `<root>/rafts/active/<R-id>/prompt.md`", w)
	end)

	it(
		"the testing skill states where specs live and run, each project's gate, and promotion into the home",
		function()
			local s = read(`{SKILLS}/testing/SKILL.md`)
			local w = "testing skill"
			at(
				s,
				"| `pickman/check.sh [--full]` / `z-nile/check.sh --project <name>` | one project's gate",
				w
			)
			at(s, "| `z-nile/check.sh --plan` |", w)
			at(s, "Each project's specs live under its home and run from it (c0120)", w)
			at(s, "`pickman/tests/run.luau` runs it from `pickman/`", w)
			at(s, "**Runs from its project's home** (c0120)", w)
			at(s, "A `check.sh` under a `.tracker/` folder that no project's root holds refuses to run.", w)
			at(s, "`$ZN_ROOT` is the repository root", w)
			at(s, "in the item's project's home (`pickman/tests/acceptance/<id>/` for pickman's)", w)
			at(s, "one run at a time per checkout and home (`<home>/.cache/tests-run.lock`)", w)
			at(s, "`lune run z-nile/affected -- --project <name>`", w)
		end
	)

	it("the architecture and ticket-prep skills, AGENTS.md and SETUP.md name pickman's home", function()
		at(
			read(`{SKILLS}/architecture/SKILL.md`),
			"every path in this skill is relative to `pickman/`",
			"architecture skill"
		)
		at(read(`{SKILLS}/architecture/SKILL.md`), "`pickman/.tracker/architecture.md`", "architecture skill")
		at(read(`{SKILLS}/ticket-prep/SKILL.md`), "`pickman/.tracker/game-design.md`", "ticket-prep skill")
		at(read("AGENTS.md"), "The game is the `pickman` project, in `pickman/`", "AGENTS.md")
		at(read("AGENTS.md"), "designing or writing anything in `pickman/src/`", "AGENTS.md")
		at(read("AGENTS.md"), "runs one suite per checkout and project home at a time", "AGENTS.md")
		at(
			read("SETUP.md"),
			"In `pickman/` (the game's home: its Rojo projects are there), `rojo serve`",
			"SETUP.md"
		)
		at(read("SETUP.md"), "run `lune run scripts/deploy-beta` in `pickman/`", "SETUP.md")
	end)

	it("the templates run from any home and name the project's architecture map", function()
		local raft = read("z-nile/templates/raft/check.sh")
		at(raft, 'check "RC0: repo gate passes (full)" "$ZN_ROOT/z-nile/check.sh" --full', "raft check.sh")
		at(raft, 'for dir in $("$ZN_ROOT/zn" members {{ID}}); do', "raft check.sh")
		at(raft, '"$ZN_ROOT/zn" promote-check {{ID}}', "raft check.sh")
		at(read("z-nile/templates/issue/check.sh"), "# cds to the item's project home", "issue check.sh")
		local prompt = read("z-nile/templates/prompt.md")
		at(prompt, "## Architecture map ({{ARCHITECTURE_PATH}})", "prompt.md")
		at(prompt, "## Work items (verbatim from {{ROOT}}/)", "prompt.md")
	end)

	it("the command's usage names busy", function()
		local main = read("z-nile/engine/main.luau")
		at(main, "  busy [<path>...]", "usage")
	end)

	it("no document names pickman's old map or design paths", function()
		local bad: { string } = {}
		for path, text in docs() do
			for _, old in
				{ "`tracker/architecture.md`", "`tracker/game-design.md`", " tracker/architecture.md" }
			do
				if string.find(text, old, 1, true) then
					table.insert(bad, `{path}: {old}`)
				end
			end
		end
		table.sort(bad)
		t.expect(table.concat(bad, "\n")).toBe("")
	end)
end)
