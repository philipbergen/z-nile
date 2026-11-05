--!strict
-- c0123 AC2: the places that restate the fence's hook rule say the new one. The zz-test skill's Ref guard bullet states
-- that the guard's hooks are pinned by content, how an inherited fence hook variable is used and what the repository's
-- own hook is, phase by phase; its "Caught only by review" bullet no longer lists a permissive hook folder as switching
-- the guard off and names what the pin does not cover; fence.sh's header says the hooks are pinned. Each sentence is
-- pinned whole, so a reworded or dropped one fails; the stale clause is pinned absent. The cases name the sentences
-- c0123 adds, never the fetch sentences c0122 rewrites in the same bullet. This file builds the fence variables' names
-- from parts (`@F@` below), as c0122's wording.spec does, so the guard scan needs no allowance for it.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local PREFIX = "PICKMAN" .. "_FENCE_"
-- `@F@` in a needle stands for the fence variables' common prefix
local function named(s: string): string
	return (string.gsub(s, "@F@", PREFIX))
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

-- The line of `text` that starts with `prefix`, or "" (a missing bullet fails its own case, never passes by absence).
local function lineStarting(text: string, prefix: string): string
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, #prefix) == prefix then
			return line
		end
	end
	return ""
end

-- Raises naming the phrases `line` lacks, so the failure says which sentence is missing.
local function expectAll(line: string, phrases: { string })
	local lacking = {}
	for _, p in phrases do
		if not has(line, named(p)) then
			table.insert(lacking, named(p))
		end
	end
	if #lacking > 0 then
		error("missing: " .. table.concat(lacking, " | "))
	end
end

local skill = fs.readFile(`{root}/z-nile/skills/zz-test/SKILL.md`)

return t.spec("c0123 the documents state the pinned hook rule", function(it)
	it(
		"the Ref guard bullet states the pin, the inherited value's rule and the repository's own hook",
		function()
			local line = lineStarting(skill, "  - **Ref guard**:")
			t.expect(line ~= "").toBe(true)
			expectAll(line, {
				"The hooks must be the guard's own: `fence.sh` pins the SHA-256 of every file's name and bytes in `z-nile/lib/git-hooks/` (`_@F@HOOKS_SHA256`, with the names in `_@F@HOOKS_NAMES` so a refusal can say which entry differs; a spec checks both against the folder, so editing a hook means updating the pins), and uses a folder only when its files match it and `reference-transaction` and `pre-push` are executable. A stray file in the folder (an editor backup, `.DS_Store`) counts: remove it, and never change the pin to make a fence pass.",
				"An inherited `@F@HOOKS` is used only when it matches, which is how a nested copy of the fence that lacks the folder keeps the first guard's; any other value is ignored with a message on stderr, and when no matching folder is left the fence refuses (c0123). Under the jail the fence neither reads nor changes it.",
				"A hook in the repository's own `.git/hooks` (such as c0189's) is not the guard's: in the `prepared` phase the guard runs it only after it allows the update, and it passes every other phase straight to it (so it also sees a refused update as `preparing` then `aborted`); it can only refuse more.",
			})
		end
	)

	it("the review bullet no longer lists a permissive hook folder, and names what the pin leaves", function()
		local line = lineStarting(skill, "  - **The guards trust their own environment**:")
		t.expect(line ~= "").toBe(true)
		expectAll(line, {
			"An inherited `@F@HOOKS` is not among them since c0123: only a folder with the guard's own files is used.",
			"A bash the caller starts itself runs its own `$BASH_ENV` and imports its functions before the first line of ours, and the first lines of a `check.sh` started by hand find `git` by the caller's `PATH`: start checks through `./zn check`, which starts `bash -p` in the allow-listed environment.",
			"A variable whose value the list admits (`HOME`, `TMPDIR`, `SSH_AUTH_SOCK`, the proxies, the tokens) is still the caller's; none of them can set the fence's own `core.hooksPath`, which the fence passes in its environment config.",
			"Nothing in the fence tells a real jail from forged markers (c0120 code review 004 F5): review a check or spec that sets any `PICKMAN_TEST_*` or `@F@*` variable.",
		})
		t.expect(has(line, "switches the ref guard off (captured as")).toBe(false)
		t.expect(has(line, "(captured as c0123)")).toBe(false)
	end)

	it("the Ref guard bullet says how the hooks start", function()
		local line = lineStarting(skill, "  - **Ref guard**:")
		expectAll(line, {
			"The hooks start as `#!/bin/sh -p` (privileged mode: no `$BASH_ENV`, no imported function) and resolve paths with `CDPATH= cd -P --`, so nothing of the caller's shell reaches them.",
		})
	end)

	it("the skill states the allow-listed environment", function()
		local line = lineStarting(skill, "  - **Allow-listed environment** (c0123):")
		t.expect(line ~= "").toBe(true)
		expectAll(line, {
			"every launcher starts what it runs in exactly the environment `z-nile/lib/cleanenv.list` names, and nothing else of the caller's:",
			"`PATH` is the fixed directories (`~/.rokit/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`), after the run's own `pickman-run.*/bin`, `pickman-guard.*` and `pickman-stub.*` folders, each kept only inside a folder the runner registered for this run while that run is alive, judged by its canonical path (a leftover or a lookalike anywhere else, in any spelling, is dropped).",
			"A script a caller starts begins with `#!/bin/bash -p`",
			'`pickman_clean_env "$0" "$@"` (`z-nile/lib/cleanenv.sh`), which starts it again under `env -i` with the allowed names when the environment is not the list; `ac.sh` does the same for a `check.sh`.',
			"The engine and the runner start shells only as `/bin/bash -p` and `/bin/sh -p`, and `tests/run` restarts itself under `env -i` through `z-nile/lib/cleanenv.luau` when its environment is not the list (a scan spec holds every entry script and spawn to this).",
			"Tools must therefore live in the fixed directories (SETUP.md); a spec's stub folder on `PATH` is made with `fixture.stubDir(\"<name>\")`, a `pickman-stub.<name>` folder in the run's temp folder, a name a spec hands a launcher gets the `PICKMAN_` prefix, and anything else the list lacks is added to it in a reviewed change.",
		})
	end)

	it("the architecture skill and SETUP.md state the rule", function()
		local arch = fs.readFile(`{root}/z-nile/skills/zz-arch/SKILL.md`)
		expectAll(lineStarting(arch, "9. **Launchers start children in the allow-listed environment**"), {
			"A new entry script or spawn does the same (`entries.spec` scans for it).",
			'a script begins `#!/bin/bash -p` and calls `pickman_clean_env "$0" "$@"`, the runner restarts itself through `cleanenv.luau`, and a Lune launcher starts shells only as `/bin/bash -p` or `/bin/sh -p`.',
		})
		local setup = fs.readFile(`{root}/SETUP.md`)
		t.expect(has(setup, "## The environment checks run in")).toBe(true)
		t.expect(
			has(
				setup,
				"`PATH` becomes `~/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`, so `git`, `gh`, `node` and `perl` must be installed in one of those directories"
			)
		).toBe(true)
	end)

	it("fence.sh's header says the guard's hooks are pinned by content", function()
		local text = fs.readFile(`{root}/z-nile/lib/fence.sh`)
		t.expect(has(text, "pinned by content (c0123)")).toBe(true)
		t.expect(has(text, "the first guard's hook stays in force: a nested copy may lack")).toBe(false)
	end)
end)
