--!strict
-- c0172 AC2: deliver and merge on the local full gate. The skills do not send the agent to GitHub Actions.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0172 local merge", function(it)
	it("merging is the local full gate and does not read Actions", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		t.expect(has(rules, "That is the verification. A merge does not read GitHub Actions.")).toBe(true)
		t.expect(has(rules, "statusCheckRollup")).toBe(false)
		t.expect(has(rules, "ci-verify")).toBe(false)
		t.expect(has(rules, "CI runs one gate job per project")).toBe(false)
		t.expect(has(rules, "A missing `beta` check")).toBe(false)
	end)

	it("the testing skill's gate is local", function()
		local text = read("z-nile/skills/zz-test/SKILL.md")
		t.expect(
			has(
				text,
				"The local full gate runs every project (`z-nile/check.sh --full` with no `--project`). GitHub Actions does not run it."
			)
		).toBe(true)
		t.expect(
			has(
				text,
				"A game raft's `done` does not prove z-nile is green; the merger's `z-nile/check.sh --full` does, because it runs every project."
			)
		).toBe(true)
		t.expect(has(text, "ci-verify")).toBe(false)
		t.expect(has(text, "gate (<project>)")).toBe(false)
	end)

	it("the architecture table does not list a CI dispatch", function()
		local text = read("z-nile/skills/zz-arch/SKILL.md")
		t.expect(has(text, "ci-verify")).toBe(false)
		t.expect(
			has(
				text,
				"`z-nile/check.sh`, `affected.luau`, `roots.luau`, `setup.sh` | the gate, the affected-spec selector, the registry's shell reader and the bootstrap"
			)
		).toBe(true)
	end)

	it("SETUP says verification is local", function()
		local text = read("SETUP.md")
		t.expect(has(text, "Verification is local.")).toBe(true)
		t.expect(has(text, "It does not run the gate or the runtime tests.")).toBe(true)
		t.expect(has(text, "ci-verify")).toBe(false)
		t.expect(has(text, "gate (pickman)")).toBe(false)
	end)

	it("the gate's own comment does not say CI runs it", function()
		local text = read("z-nile/check.sh")
		t.expect(has(text, "(`./zn done`, `./zn land`)")).toBe(true)
		t.expect(has(text, "CI")).toBe(false)
	end)

	it("the design lesson does not send a prep to Actions", function()
		local text = read("z-nile/skills/z-design/lessons/prove-specs-pass-on-a-prototype.md")
		t.expect(has(text, "the local full gate on the machine that merges")).toBe(true)
		t.expect(has(text, "ci-verify")).toBe(false)
	end)

	it("zz-execute names the local full gate in a clean clone", function()
		local text = read("z-nile/skills/zz-execute/SKILL.md")
		t.expect(
			has(
				text,
				"the local full gate, `z-nile/check.sh --full`, in a clone of the exact head whose parent directories are not a checkout of this repo"
			)
		).toBe(true)
		t.expect(has(text, "CI green")).toBe(false)
	end)

	it("the worktree paragraph names that clone as the final check", function()
		local text = read("z-nile/skills/zz-rules/SKILL.md")
		t.expect(
			has(
				text,
				"The final check for a pull request that changes a game is `z-nile/check.sh --full` in a clone of the exact head whose parent directories are not a checkout of this repo."
			)
		).toBe(true)
		t.expect(has(text, "CI, which checks out the branch alone, is the final check")).toBe(false)
	end)

	it("the merging close refuses a missing local full gate", function()
		local text = read("z-nile/skills/zz-rules/SKILL.md")
		t.expect(has(text, "never merge on a red or missing gate for what the pull request changes"))
			.toBe(true)
		t.expect(has(text, "missing CI")).toBe(false)
	end)

	it("a main move reruns the local full gate", function()
		local text = read("z-nile/skills/zz-rules/SKILL.md")
		t.expect(has(text, "rerun `z-nile/check.sh --full`")).toBe(true)
	end)

	it("a new raft's check says the merger's full gate covers the other project", function()
		local text = read("z-nile/templates/raft/check.sh")
		t.expect(
			has(text, "a game pull request's merger runs `z-nile/check.sh --full`, which covers the others")
		)
			.toBe(true)
		t.expect(has(text, "CI's job per project")).toBe(false)
	end)

	it("the testing skill says GitHub Actions does not run the specs", function()
		local text = read("z-nile/skills/zz-test/SKILL.md")
		t.expect(has(text, "GitHub Actions does not run the specs.")).toBe(true)
		t.expect(has(text, "CI's checkout")).toBe(false)
	end)

	it("the worktree rule names the clone as its one exception", function()
		local sentence =
			"The one exception is Merging's final check and `lune run scripts/cicd` in that clone, a clone outside the repo that is not a worktree."
		t.expect(has(read("z-nile/skills/zz-rules/SKILL.md"), sentence)).toBe(true)
		t.expect(has(read("SETUP.md"), sentence)).toBe(true)
	end)

	it("the final check removes origin and fences the real repository", function()
		local text = read("z-nile/skills/zz-rules/SKILL.md")
		t.expect(has(text, "git clone --no-hardlinks")).toBe(true)
		t.expect(has(text, "git remote remove origin")).toBe(true)
		t.expect(has(text, "PICKMAN_FENCE_REAL_GIT")).toBe(true)
	end)

	it("the skills do not wait for green CI", function()
		t.expect(has(read("z-nile/skills/zz-rules/SKILL.md"), "green CI")).toBe(false)
		t.expect(has(read("z-nile/skills/zz-execute/SKILL.md"), "green CI")).toBe(false)
	end)

	it("the board cell says -O only writes the page, as the specs do", function()
		local text = read("z-nile/skills/zz-rules/SKILL.md")
		local row = ""
		for line in string.gmatch(text, "[^\n]+") do
			if string.sub(line, 1, 9) == "| board |" then
				row = line
			end
		end
		t.expect(has(row, "as the specs do")).toBe(true)
		t.expect(has(row, "as CI")).toBe(false)
	end)

	it("a merge runs the local cicd command and the runtime tier is not run by CI", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		t.expect(
			has(
				rules,
				"In `$dir/pickman`, on the detached head from step 2 (`git checkout --detach`), `lune run scripts/cicd` passes."
			)
		).toBe(true)
		local mergingAt = string.find(rules, "## Merging\n", 1, true) :: number
		local merging = string.sub(rules, mergingAt)
		local step3Start = string.find(merging, "\n3. ", 1, true) :: number
		local step4Start = string.find(merging, "\n4. ", step3Start, true) :: number
		local step3 = string.sub(merging, step3Start, step4Start - 1)
		t.expect(
			has(
				step3,
				"In `$dir/pickman`, on the detached head from step 2 (`git checkout --detach`), `lune run scripts/cicd` passes."
			)
		).toBe(true)
		local rerun = ""
		for line in string.gmatch(rules, "[^\n]+") do
			if has(line, "rerun `z-nile/check.sh --full`") then
				rerun = line
			end
		end
		t.expect(has(rerun, "lune run scripts/cicd")).toBe(true)
		t.expect(
			has(
				rules,
				"A missing file, a lease held by someone else, a publish failure, or a runtime failure stops the merge."
			)
		).toBe(true)
		t.expect(has(rules, "This command is not part of `z-nile/check.sh --full`.")).toBe(true)
		t.expect(has(rules, "a red or missing `lune run scripts/cicd`")).toBe(true)
		local testing = read("pickman/skills/pickman-test/SKILL.md")
		t.expect(has(testing, "run by CI")).toBe(false)
		t.expect(has(testing, "lune run scripts/cicd")).toBe(true)
		t.expect(has(testing, "scripts/runtime-test")).toBe(true)
		t.expect(has(testing, "Open Cloud")).toBe(true)
		local setup = read("SETUP.md")
		t.expect(has(setup, "not a merge condition")).toBe(false)
		t.expect(has(setup, "lune run scripts/cicd")).toBe(true)
	end)
end)
