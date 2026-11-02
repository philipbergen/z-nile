--!strict
-- c0194: every place that tells an agent where a scratch or merge clone goes says `.cache/.tmp/` in the same words, and
-- none still sends it to $TMPDIR or the system temp folder. Merging's clone keeps its other rules (origin removed, the
-- real repository fenced, the exact head), and is made by `./zn tmp new gate` and proved by `./zn tmp verify`.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{root}/{rel}`)
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

local function lacks(text: string, part: string)
	t.expect(has(text, part)).toBe(false)
end

local EXCEPTION =
	"The one exception is Merging's final check and `lune run scripts/cicd` in that clone, a clone under the checkout's `.cache/.tmp/` that is not a worktree."
local SCRATCH =
	"`./zn tmp new <kind>` (under `.cache/.tmp/`, never the system temp folder) and removes it when it ends."

local function merging(): string
	local rules = read("z-nile/skills/zz-rules/SKILL.md")
	local at = string.find(rules, "## Merging\n", 1, true) :: number
	return string.sub(rules, at)
end

return t.spec("c0194 the places that name the temporary folder", function(it)
	it("AGENTS.md states the rule once, with the command and the hook", function()
		local text = read("AGENTS.md")
		t.expect(has(text, "**Temporary trees live in `.cache/.tmp/`, never in the system temp folder.**"))
			.toBe(true)
		t.expect(has(text, "`./zn tmp new <kind>`")).toBe(true)
		t.expect(has(text, "the SessionStart hook")).toBe(true)
		t.expect(
			has(
				text,
				"`./zn tmp` and the SessionStart hook write only inside `.cache/.tmp/` there, agents' scratch trees included"
			)
		).toBe(true)
	end)

	it(
		"Merging's clone is made by ./zn tmp new gate, proved by ./zn tmp verify, and keeps its other rules",
		function()
			local text = merging()
			t.expect(has(text, "`dir=$(./zn tmp new gate)`")).toBe(true)
			t.expect(has(text, '`./zn tmp verify "$dir"` must print `isolated`')).toBe(true)
			t.expect(has(text, "git clone --no-hardlinks --no-checkout")).toBe(true)
			t.expect(has(text, "git remote remove origin")).toBe(true)
			t.expect(has(text, "git checkout --detach")).toBe(true)
			t.expect(has(text, "PICKMAN_FENCE_REAL_GIT")).toBe(true)
			lacks(text, "`dir=$(mktemp -d)`")
			lacks(text, "if `$TMPDIR` is inside this checkout, stop")
			lacks(text, "parent directories are not a checkout of this repo")
		end
	)

	it(
		"the worktree rule, SETUP and the final-check sentences name .cache/.tmp/ as the clone's place",
		function()
			t.expect(has(read("z-nile/skills/zz-rules/SKILL.md"), EXCEPTION)).toBe(true)
			t.expect(has(read("SETUP.md"), EXCEPTION)).toBe(true)
			t.expect(
				has(
					read("z-nile/skills/zz-rules/SKILL.md"),
					"The final check is `z-nile/check.sh --full` in a clone of the exact head under the checkout's `.cache/.tmp/` that `./zn tmp verify` calls isolated."
				)
			).toBe(true)
			t.expect(
				has(
					read("z-nile/skills/zz-execute/SKILL.md"),
					"the local full gate, `z-nile/check.sh --full`, in a clone of the exact head under the checkout's `.cache/.tmp/` that `./zn tmp verify` calls isolated"
				)
			).toBe(true)
			lacks(read("z-nile/skills/zz-rules/SKILL.md"), "a clone outside the repo that is not a worktree")
			lacks(read("SETUP.md"), "a clone outside the repo that is not a worktree")
		end
	)

	it("experiments and prototypes in z-design and zz-execute use ./zn tmp new", function()
		t.expect(has(read("z-nile/skills/z-design/SKILL.md"), SCRATCH)).toBe(true)
		t.expect(has(read("z-nile/skills/zz-execute/SKILL.md"), SCRATCH)).toBe(true)
		t.expect(
			has(read("z-nile/skills/z-design/SKILL.md"), "run them only in a clone under `.cache/.tmp/`")
		)
			.toBe(true)
		t.expect(has(read("z-nile/skills/z-design/SKILL.md"), "jailed: every command through `./zn tmp jail"))
			.toBe(true)
		t.expect(
			has(
				read("z-nile/skills/z-design/SKILL.md"),
				"a mutant of guard code is unguarded code: it runs only in that jailed clone, never in a worktree"
			)
		).toBe(true)
		t.expect(has(read("z-nile/skills/zz-test/SKILL.md"), "this includes every mutant of guard code"))
			.toBe(true)
		t.expect(
			has(read("z-nile/skills/zz-rules/SKILL.md"), "Scratch trees (an experiment's clone) are not jobs")
		)
			.toBe(true)
	end)

	it(
		"zz-test describes the run's folder, the closed rest of .cache/.tmp, and the unguarded clone",
		function()
			local text = read("z-nile/skills/zz-test/SKILL.md")
			t.expect(has(text, "a fresh `pickman-run.*` under this home's `.cache/.tmp/`")).toBe(true)
			t.expect(has(text, "and the rest of `.cache/.tmp/` itself")).toBe(true)
			t.expect(has(text, "tree=$(./zn tmp new unguarded)")).toBe(true)
			t.expect(has(text, '`./zn tmp jail "$tree" -- <command>...`')).toBe(true)
			t.expect(has(text, "is the spec jail's rule set applied to the clone")).toBe(true)
			t.expect(has(text, "every fixture path stays absolute")).toBe(true)
			t.expect(has(text, "which runs it with the tree as its working directory")).toBe(true)
			t.expect(has(text, "copy the prototype's uncommitted files in and commit them there")).toBe(true)
			t.expect(has(text, "nested runs, `fence-leftovers` and the lock specs pass there")).toBe(true)
			t.expect(has(text, "**Unjailed runs and `.cache/.tmp/`**")).toBe(true)
			lacks(text, "a fresh `pickman-run.*` under the shell's temp folder")
			lacks(text, "in a clone under `$TMPDIR`, outside every repository")
		end
	)

	it(
		"a scratch clone is never a git worktree add, and a prototype worktree stays under .worktree/, in the same words",
		function()
			for _, rel in
				{
					"AGENTS.md",
					"z-nile/skills/zz-rules/SKILL.md",
					"z-nile/skills/z-design/SKILL.md",
					"z-nile/skills/zz-execute/SKILL.md",
				}
			do
				t.expect(has(read(rel), "scratch clone (never a `git worktree add`)")).toBe(true)
				t.expect(has(read(rel), "a prototype worktree goes under `.worktree/`")).toBe(true)
			end
		end
	)

	it(
		"the main checkout's complete command list names ./zn tmp and the hook, bounded to .cache/.tmp/",
		function()
			local rules = read("z-nile/skills/zz-rules/SKILL.md")
			local at = string.find(rules, "**The main checkout is read-only.**", 1, true) :: number
			local list = string.sub(rules, at, at + 4000)
			t.expect(has(list, "`./zn tmp new|root|verify|sweep|jail|rm|leftovers`")).toBe(true)
			t.expect(has(list, "`scripts/hooks/session-tmp.sh`")).toBe(true)
			t.expect(has(list, "only stale direct children there")).toBe(true)
			t.expect(has(list, "`./zn remap` write their trees into the session's folder too")).toBe(true)
		end
	)

	it("Landing removes the merge clone with ./zn tmp rm, and the table lists jail and rm", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		t.expect(has(rules, '`./zn tmp rm "$dir"`')).toBe(true)
		t.expect(has(rules, "`jail <tree> -- <command>…` \\| `rm <tree>`")).toBe(true)
		t.expect(has(rules, "from the tree as its working directory")).toBe(true)
		t.expect(has(read("AGENTS.md"), "(`./zn tmp rm <tree>`)")).toBe(true)
	end)

	it("the zz-rules command table lists ./zn tmp", function()
		local text = read("z-nile/skills/zz-rules/SKILL.md")
		t.expect(has(text, "| tmp | `./zn tmp new <kind>`")).toBe(true)
	end)

	it("no skill sends an agent's clone to $TMPDIR any more", function()
		for _, rel in
			{
				"z-nile/skills/z-design/SKILL.md",
				"z-nile/skills/zz-execute/SKILL.md",
				"z-nile/skills/zz-review/SKILL.md",
				"z-nile/skills/zz-rules/SKILL.md",
				"z-nile/skills/zz-test/SKILL.md",
				"AGENTS.md",
				"SETUP.md",
			}
		do
			lacks(read(rel), "clone under `$TMPDIR`")
			lacks(read(rel), '"$(mktemp -d)/repo"')
		end
	end)
end)
