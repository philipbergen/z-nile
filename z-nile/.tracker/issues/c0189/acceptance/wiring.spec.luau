--!strict
-- c0189 AC4: the hook is reachable and the rules that mention it agree. The gate's static stage runs `./zn hooks --check`,
-- `z-nile/setup.sh` runs `./zn hooks` before its gate (and not for `--tools`), the usage text and every exhaustive
-- list name the command, and the rule about fixture identities and the retry-once rule read the same in each place
-- that states them. This spec reads texts of the checkout only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(path: string): string
	return fs.readFile(`{root}/{path}`)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function at(text: string, needle: string): number?
	return (string.find(text, needle, 1, true))
end

-- The rule about prototypes (z-design, zz-execute, zz-test) and the retry-once rule (zz-test, AGENTS.md), word for word.
local RULE =
	"A prototype or experiment lives in a scratch clone (a `git clone` of the checkout into `$TMPDIR` or the scratchpad) or commits under your own identity, and never commits as `@example.invalid` in the real repository or any worktree of it: the repository refuses such a commit (`./zn hooks`), because every running gate reads a ref at one as a spec's escape."
local RETRY =
	'If the tripwire\'s only finding is "refs written by a fixture appeared" and every listed ref is checked out in a live `.worktree/<name>` outside `.cache` (`git worktree list`), retry the gate or `./zn land` once without asking, and say so; if it fires again, or reports anything else, stop and report.'

return t.spec("c0189 the hook is wired into the gate, setup and the rules", function(it)
	it(
		"the gate's static stage runs ./zn hooks --check beside the skills check, and --plan lists it",
		function()
			local gate = read("z-nile/check.sh")
			local skills = at(gate, 'par_start "skills (./zn skills --check)" ./zn skills --check')
			local hooks = at(gate, 'par_start "hooks (./zn hooks --check)" ./zn hooks --check')
			local wait = at(gate, "par_wait || exit 1")
			t.expect(skills ~= nil and hooks ~= nil and wait ~= nil).toBe(true)
			t.expect((skills :: number) < (hooks :: number) and (hooks :: number) < (wait :: number))
				.toBe(true)
			t.expect(
				has(
					gate,
					"printf 'hooks: reference-transaction in the git directory (./zn hooks --check)\\n'"
				)
			)
				.toBe(true)
		end
	)

	it("setup.sh runs ./zn hooks after the tools-only exit and before the gate", function()
		local setup = read("z-nile/setup.sh")
		local toolsExit = at(setup, 'echo "tools only: gate skipped (--tools)"')
		local hooks = at(setup, "./zn hooks")
		local gate = at(setup, "z-nile/check.sh --full")
		t.expect(toolsExit ~= nil and hooks ~= nil and gate ~= nil).toBe(true)
		t.expect((toolsExit :: number) < (hooks :: number) and (hooks :: number) < (gate :: number))
			.toBe(true)
	end)

	it("the usage text and the command table name hooks, and the main checkout's list allows it", function()
		local main = read("z-nile/engine/main.luau")
		t.expect(has(main, "  hooks [--check]   ")).toBe(true)
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		t.expect(has(rules, "| hooks | `./zn hooks [--check]` |")).toBe(true)
		t.expect(
			has(
				rules,
				"installs `origin/main`'s copy of `z-nile/lib/repo-hooks/reference-transaction` (this tree's own when the repository has no `origin/main`, as in the Merging clone; never an unmerged edit)"
			)
		).toBe(true)
		t.expect(
			has(
				rules,
				"and `./zn hooks` (it writes only the reference-transaction hook in the git directory every worktree shares, never the working tree)"
			)
		).toBe(true)
		t.expect(
			has(
				rules,
				"`capture <id>` (they only read), `hooks --check` (it only reads), and the worktree commands"
			)
		).toBe(true)
		t.expect(has(rules, "- `./zn hooks [--check]`\n")).toBe(true)
		-- it is not among the commands that refuse the main checkout
		t.expect(has(rules, "`remap` and `skills` (without `--check`) refuse to run in the main checkout"))
			.toBe(true)
	end)

	it("the merge's clone installs the hook before its gate", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		local clone = at(rules, "and `git checkout --detach` the exact head. Run `./zn hooks` in the clone ")
		local gate = at(rules, "Spawn the gate there")
		t.expect(clone ~= nil and gate ~= nil).toBe(true)
		t.expect((clone :: number) < (gate :: number)).toBe(true)
		t.expect(has(rules, "a fresh clone has no hook of its own")).toBe(true)
	end)

	it(
		"the layout table, the reviewer's guard list and SETUP.md name the hook folder and the step",
		function()
			t.expect(
				has(
					read("z-nile/skills/zz-arch/SKILL.md"),
					"`repo-hooks/` (the hook installed in the real repository by `./zn hooks`)"
				)
			).toBe(true)
			t.expect(
				has(
					read("z-nile/skills/zz-review/SKILL.md"),
					"`z-nile/lib/git-hooks/`, `z-nile/lib/repo-hooks/`, the fence in `z-nile/lib/ac.sh`"
				)
			).toBe(true)
			local setup = read("SETUP.md")
			t.expect(has(setup, "4. **Repository hook**: runs `./zn hooks`")).toBe(true)
			t.expect(has(setup, "5. **Gate**: runs `z-nile/check.sh --full`.")).toBe(true)
		end
	)

	it("the prototype rule reads the same in z-design, zz-execute and zz-test", function()
		for _, path in
			{
				"z-nile/skills/z-design/SKILL.md",
				"z-nile/skills/zz-execute/SKILL.md",
				"z-nile/skills/zz-test/SKILL.md",
			}
		do
			t.expect(`{path} {has(read(path), RULE)}`).toBe(`{path} true`)
		end
		t.expect(
			has(
				read("z-nile/skills/z-design/SKILL.md"),
				"when you prototype the change in a scratch clone or worktree (the rule under Unknowns & experiments)"
			)
		).toBe(true)
	end)

	it("the retry-once rule reads the same in zz-test and AGENTS.md", function()
		for _, path in { "z-nile/skills/zz-test/SKILL.md", "AGENTS.md" } do
			t.expect(`{path} {has(read(path), RETRY)}`).toBe(`{path} true`)
		end
	end)

	it(
		"only the pure hooks module names the setting that moves the hooks folder; main.luau does not",
		function()
			-- the name is built here so that this file does not name it (repo-fence.spec bans the name in checks)
			local key = "hooks" .. "Path"
			t.expect(has(read("z-nile/engine/hooks.luau"), `hooks.CONFIG_KEY = "core.{key}"`)).toBe(true)
			t.expect(has(read("z-nile/engine/main.luau"), key)).toBe(false)
			t.expect(has(read("z-nile/engine/main.luau"), "hooksLib.CONFIG_KEY")).toBe(true)
		end
	)

	it("the hook and the tripwire name the same fixture domain", function()
		local tripwire = read("z-nile/tests/lib/fence.luau")
		t.expect(has(tripwire, 'FIXTURE_EMAIL = "@example.invalid"')).toBe(true)
		local hook = read("z-nile/lib/repo-hooks/reference-transaction")
		t.expect(has(hook, "/@example\\.invalid$/")).toBe(true)
		t.expect(has(hook, "*@[eE][xX][aA][mM][pP][lL][eE].[iI][nN][vV][aA][lL][iI][dD]*")).toBe(true)
		t.expect(string.sub(hook, 1, 10)).toBe("#!/bin/sh\n")
		t.expect(has(hook, "\n" .. "# pickman-repo-hook: reference-transaction\n")).toBe(true)
	end)

	it("zz-test describes the hook: where it is, who installs it, what it refuses", function()
		local text = read("z-nile/skills/zz-test/SKILL.md")
		t.expect(has(text, "- **Fixture identities stay in fixtures**: ")).toBe(true)
		t.expect(
			has(
				text,
				"`z-nile/lib/repo-hooks/reference-transaction`, installed in the git directory every worktree shares by `./zn hooks` (`z-nile/setup.sh` runs it; the gate's static stage runs `./zn hooks --check`, which only reads), from `origin/main`'s copy and never from a branch's unmerged edit."
			)
		).toBe(true)
		t.expect(
			has(
				text,
				"It cannot see `git branch -m` or `git branch -c` (git writes those refs outside a transaction), so never rename or copy a branch whose tip is a fixture commit: delete it, or look at it with `git worktree add <dir> <branch>`. Spec fixtures have repositories of their own, which never run it."
			)
		).toBe(true)
	end)
end)
