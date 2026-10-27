--!strict
-- c0165 AC10: the restated rules. Every step before the merge runs the affected gate, the merge's full gate runs for
-- real in `./zn done` (and land, CI, setup.sh), the merge condition reuses done's run on the same content
-- (`--full --reuse`), graph misses are learned, and the db is a named, ignored writer of the main checkout.
-- The sentences are the Design's "Wording" list. Read from the checkout's top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{root}/{rel}`)
end
local function says(rel: string, line: string)
	if string.find(read(rel), line, 1, true) == nil then
		error(`{rel} does not say: {line}`)
	end
end
local function never(rel: string, line: string)
	if string.find(read(rel), line, 1, true) ~= nil then
		error(`{rel} still says: {line}`)
	end
end

return t.spec("c0165 restated gate rules", function(it)
	it(
		"AC10: zz-execute runs the affected gate before the merge and reuses done's full gate at it",
		function()
			local f = "z-nile/skills/zz-execute/SKILL.md"
			says(f, "Confirm `z-nile/check.sh --affected` passes here.")
			never(f, "Confirm `z-nile/check.sh --full` passes here.")
			says(f, "Double-check that `z-nile/check.sh --affected` passes as well")
			says(f, "from `./zn done`'s full gate")
			says(f, "Run `z-nile/check.sh --affected` and read the whole lint summary")
			never(f, "Run `z-nile/check.sh --full` and read the whole lint summary")
			says(f, "rerun `z-nile/check.sh --affected`")
			never(f, "rerun `z-nile/check.sh --full`")
			says(f, "(`z-nile/check.sh --full --reuse` on the final head")
		end
	)

	it("AC10: zz-rules and zz-review say the same", function()
		says("z-nile/skills/zz-rules/SKILL.md", "and `z-nile/check.sh --affected`.")
		says(
			"z-nile/skills/zz-rules/SKILL.md",
			"2. `z-nile/check.sh --full --reuse` passes on the final head, run by you."
		)
		says("z-nile/skills/zz-rules/SKILL.md", "runs `z-nile/check.sh --full` locally")
		never("z-nile/skills/zz-rules/SKILL.md", "2. `z-nile/check.sh --full` passes on the final head")
		says(
			"z-nile/skills/zz-review/SKILL.md",
			"Run `z-nile/check.sh --affected` and each `./zn check <id>` yourself."
		)
		never("z-nile/skills/zz-review/SKILL.md", "Run `z-nile/check.sh --full` and each")
	end)

	it("AC10: zz-test describes the modes, reuse, graph misses and the db writer", function()
		local f = "z-nile/skills/zz-test/SKILL.md"
		says(
			f,
			"| `z-nile/check.sh --full` | every project's gate, every spec, always run for real. Used by `land`, `done`, CI and `setup.sh` |"
		)
		says(
			f,
			"| `z-nile/check.sh --full --reuse` | the merge condition: reuses a full gate that passed on the same content (`done`'s), else runs fresh |"
		)
		says(f, "| `z-nile/check.sh --affected --fresh` | the affected gate without reuse |")
		says(
			f,
			"**Graph miss**: a spec fails under `--full` but wasn't selected for the same diff. The full gate finds the file it depends on, records it in the results db and prints the line to commit to the home's `tests/inputs.tsv`."
		)
		never(f, "That's a selector bug. File it as a chore")
		says(f, "**Reuse**:")
		says(f, ".claude/.znile_tests.sqlite")
		says(
			f,
			"the gate's results db (`.claude/.znile_tests.sqlite` in the main checkout, written by `z-nile/specs` outside the jail)"
		)
	end)

	it("AC10: the prompt and raft templates, AGENTS.md and .gitignore", function()
		says(
			"z-nile/templates/prompt.md",
			"Iterate with `z-nile/check.sh --affected`. The full gate runs at the merge, in `./zn done`."
		)
		says(
			"z-nile/templates/raft/check.sh",
			'check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project {{PROJECT}} --affected'
		)
		never("z-nile/templates/raft/check.sh", "--full")
		-- AGENTS.md names the db in its list of what writes the main checkout
		local agents = read("AGENTS.md")
		local line = string.match(agents, "[^\n]*the main checkout is never edited[^\n]*") or ""
		t.expect(string.find(line, ".claude/.znile_tests.sqlite", 1, true) ~= nil).toBe(true)
		-- ignored, sidecars included, and git agrees
		local ignore = read(".gitignore")
		t.expect(string.find(ignore, "\n/.claude/.znile_tests.sqlite*\n", 1, true) ~= nil).toBe(true)
		for _, name in
			{
				".claude/.znile_tests.sqlite",
				".claude/.znile_tests.sqlite-wal",
				".claude/.znile_tests.sqlite-shm",
			}
		do
			local r = process.exec("git", { "check-ignore", "-q", "--no-index", name }, { cwd = root })
			t.expect(r.ok).toBe(true)
		end
	end)

	it("AC10: land, done, CI and setup.sh keep the fresh full gate", function()
		says("z-nile/engine/main.luau", 'local gate = override or "z-nile/check.sh --full"')
		says("z-nile/engine/main.luau", 'sh.stream("bash", { "z-nile/check.sh", "--full" })')
		says(".github/workflows/check.yml", 'z-nile/check.sh --project "$PROJECT" --full')
		says("z-nile/setup.sh", "z-nile/check.sh --full")
		never("z-nile/engine/main.luau", "--reuse")
		never(".github/workflows/check.yml", "--reuse")
		never("z-nile/setup.sh", "--reuse")
	end)
end)
