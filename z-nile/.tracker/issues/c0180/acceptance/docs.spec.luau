--!strict
-- c0180: the skills that restate the selection rule and the engine's layout say what c0180 built (the Wording of the
-- issue), and the sentences they replace are gone. Runs from z-nile's home.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function has(path: string, text: string): boolean
	return (string.find(fs.readFile(path), text, 1, true)) ~= nil
end

local TEST = "skills/zz-test/SKILL.md"
local ARCH = "skills/zz-arch/SKILL.md"
local RULES = "skills/zz-rules/SKILL.md"

return t.spec("c0180 the skills state selection by command", function(it)
	it("zz-test: engine files no longer force z-nile's run; they select through the command trace", function()
		t.expect(
			has(
				TEST,
				"and any other change under `z-nile/` (the gate, the templates, the skills) z-nile's; a change to the engine's Luau files (`z-nile/engine/**/*.luau`) selects instead, see **Command trace**"
			)
		).toBe(true)
		t.expect(has(TEST, "and any other change under `z-nile/` (the engine, the gate) z-nile's"))
			.toBe(false)
	end)

	it(
		"zz-test: the Command trace bullet states the record, the variable, the rule and the backstop",
		function()
			for _, text in
				{
					"**Command trace** (c0180): each multi-file spec run records which `./zn` commands every passing spec ran (`usage` for the usage path), in `<home>/.cache/spec-commands.tsv`, keyed by a hash of the spec's test-side require closure and of the tooling that launches `./zn`",
					"the runner passes the engine `ZN_SPEC_TRACE`, a `:`-separated list of `.cache/spec-trace/<name>` directories",
					"With `--recorded` (the gate's selection passes it), a change to an engine Luau file that no program requires selects the z-nile specs that require it, declare it, are `*`, ran a command whose module (`z-nile/engine/cmd/<name>.luau`) or the dispatch core (`main.luau`, `cli.luau`, `z-nile/lib/sh.luau`) reaches it, or have no record for their current key",
					"an engine file a program requires (a Luau file at the top of `z-nile/` or under `scripts/` or a home's `scripts/`, the forwarders in `scripts/tracker/` aside) still forces z-nile's run",
					"Records come from this worktree and every other worktree of the checkout.",
					"A spec that runs engine code another way than through `./zn`, `engine/main` or those programs declares the engine files it runs.",
					"A spec that sets `ZN_SPEC_TRACE` for a command it starts appends the value it inherited (`<its dir>:<inherited>`)",
					"The merge's full gate is the backstop.",
				}
			do
				t.expect(has(TEST, text)).toBe(true)
			end
		end
	)

	it("zz-arch: the engine row describes the dispatcher and the command modules", function()
		t.expect(
			has(
				ARCH,
				"`main.luau` parses arguments, guards and dispatches; each command is `cmd/<name>.luau`, and the helpers several commands share are modules beside it"
			)
		).toBe(true)
		t.expect(
			has(ARCH, "`main.luau` is the CLI: it parses arguments and does the git, file and process work")
		)
			.toBe(false)
	end)

	it("zz-arch: rule 4 names the command modules as the CLI that reads and writes", function()
		t.expect(
			has(
				ARCH,
				"one `load` function, or the engine's CLI (`main.luau` and the command modules in `engine/cmd/` with the shared helpers beside them), does the reading and writing"
			)
		).toBe(true)
		t.expect(has(ARCH, "one `load` function, or `main.luau`, does the reading and writing")).toBe(false)
	end)

	it("zz-rules: the busy row names FREEZES where it now lives and c0180's readiness condition", function()
		t.expect(has(RULES, "(`FREEZES` in `z-nile/engine/cmd/busy.luau`)")).toBe(true)
		t.expect(has(RULES, "(`FREEZES` in `z-nile/engine/main.luau`)")).toBe(false)
		t.expect(
			has(
				RULES,
				"c0180's split of `z-nile/engine/main.luau` is readied only when `./zn busy z-nile/engine/main.luau` lists no active raft (the user's decision)."
			)
		).toBe(true)
	end)
end)
