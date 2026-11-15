--!strict
-- c0271 AC3: zz-rules' Landing a change, step 2, holds the rule to read a PR's state, head and newest comments before
-- every push to it and every report that it was updated, word for word, as a line of its own; zz-execute's Phase 4
-- names the exception to its "carry on" for that read; and the lesson the rule names exists. Read from the checkout's
-- top. The lesson's own words are not pinned here (c0181 rewrites lessons): check.sh's AC1 reads them once, before
-- `./zn done`.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local RULES = "z-nile/skills/zz-rules/SKILL.md"
local EXECUTE = "z-nile/skills/zz-execute/SKILL.md"
local LESSON = "z-nile/skills/zz-rules/lessons/read-pr-state-before-pushing.md"
local BULLET = "   - **Read the PR before every push to it.** Before you take a PR as where the work lives, and again before "
	.. "every push to its branch (`git push`, or a `./zn` command that pushes, such as `start` or `commit`) and every "
	.. "report that it was updated, read its state, head and newest comments: `gh pr view <number or branch> --json "
	.. "state,headRefOid,comments --jq '{state, headRefOid, newest: [.comments[-2:][] | {author: .author.login, "
	.. "createdAt, body}]}'`. An `OPEN` PR takes the push. A `CLOSED` or `MERGED` one is this work's when its head is "
	.. "in the history you push or in origin's tip of the branch: after `git fetch origin refs/pull/<n>/head`, `git "
	.. "merge-base --is-ancestor <headRefOid> HEAD` exits 0, or `git ls-remote --heads origin <branch>` prints a tip "
	.. "and, after `git fetch origin <branch>`, `git merge-base --is-ancestor <headRefOid> FETCH_HEAD` exits 0. This "
	.. "work's closed or merged PR takes nothing: push nothing to its branch, report its state and newest comment (it "
	.. "usually says where the work went), and stop. When each test exits 1 (or origin has no such branch), the PR "
	.. "was an earlier use of the branch's name (z-stop's start fresh), and the branch gets its first push and a new "
	.. "PR, as a branch with no PR does (`gh` answers `no pull requests found`). Any other answer (another `gh` or "
	.. "`git` error) is no answer: retry once, then push nothing and stop. A PR you merged yourself (Merging, or the "
	.. "raft `./zn done` landed) is `MERGED` by design: its post-merge report and step 4 go on, and nothing more is "
	.. "pushed to its branch. A report that the PR was updated quotes the state it read (lesson "
	.. "zz-rules/read-pr-state-before-pushing)."
local EXCEPTION = "The state read before each push and each comment that reports the PR is the exception (zz-rules skill, "
	.. "Landing a change, step 2): when it finds this work's PR `CLOSED` or `MERGED`, or fails twice, nothing is "
	.. "carried past it: push nothing, report it, and stop."

-- the text from `from` to the first `to` after it, or an error naming the file
local function between(text: string, file: string, from: string, to: string): string
	local a = string.find(text, from, 1, true)
	if a == nil then
		error(`{file} has no {from}`)
	end
	local b = string.find(text, to, a + #from, true)
	if b == nil then
		error(`{file} has nothing like {to} after {from}`)
	end
	return string.sub(text, a, b)
end

return t.spec("c0271 read the PR's state before pushing", function(it)
	it(
		"[zz-rules/read-pr-state-before-pushing] Landing a change step 2 says to read the PR's state before every push",
		function()
			local section = between(fs.readFile(`{root}/{RULES}`), RULES, "\n## Landing a change\n", "\n## ")
			local step = between(section, RULES, "\n2. **Push and open the PR**", "\n3. **Merge**")
			if string.find(step, "\n" .. BULLET .. "\n", 1, true) == nil then
				error(
					`{RULES} Landing a change step 2 does not hold, as a line of its own, the bullet: {BULLET}`
				)
			end
		end
	)

	it(
		"[zz-rules/read-pr-state-before-pushing] zz-execute Phase 4 does not carry on past the state read",
		function()
			local text = fs.readFile(`{root}/{EXECUTE}`)
			local intro =
				between(text, EXECUTE, "\n## Phase 4: Adversarial code review", "\n1. **Before launching**")
			if string.find(intro, " don't block on it. " .. EXCEPTION .. " ", 1, true) == nil then
				error(`{EXECUTE} Phase 4 does not say, right after "don't block on it.": {EXCEPTION}`)
			end
		end
	)

	it("[zz-rules/read-pr-state-before-pushing] the lesson the rule names exists", function()
		t.expect(fs.isFile(`{root}/{LESSON}`)).toBe(true)
	end)
end)
