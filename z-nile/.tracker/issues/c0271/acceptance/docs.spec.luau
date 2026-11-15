--!strict
-- c0271 AC3: zz-rules' Landing a change, step 2, holds the rule to read a PR's state and newest comments before every
-- push to it and every report that it was updated, word for word, and the lesson it names exists. Read from the
-- checkout's top. The lesson's own words are not pinned here (c0181 rewrites lessons): check.sh's AC1 reads them once,
-- before `./zn done`.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local RULES = "z-nile/skills/zz-rules/SKILL.md"
local LESSON = "z-nile/skills/zz-rules/lessons/read-pr-state-before-pushing.md"
local BULLET = "   - **Read the PR before every push to it.** Before you take a PR as where the work lives, and again "
	.. "before every push to its branch (`git push`, or a `./zn` command that pushes, such as `commit`) and every "
	.. "report that it was updated, read `gh pr view <number or branch> --json state,comments`: its state and its "
	.. "newest comments. Only an `OPEN` PR takes the push. A `CLOSED` or `MERGED` one takes nothing: push nothing to "
	.. "its branch, report its state and newest comment (it usually says where the work went), and stop. A report "
	.. "that the PR was updated quotes the state it read. A branch with no PR yet (`gh` answers `no pull requests "
	.. "found`) gets its first push and PR as above (lesson zz-rules/read-pr-state-before-pushing)."

-- the text of `## Landing a change`, from its heading to the next `## ` heading
local function landing(text: string): string
	local start = string.find(text, "\n## Landing a change\n", 1, true)
	if start == nil then
		error(`{RULES} has no "## Landing a change" section`)
	end
	local after = string.find(text, "\n## ", start + 1, true)
	return string.sub(text, start, if after then after else #text)
end

-- step 2 of Landing a change: from its `2. **Push and open the PR**` line to the `3. **Merge**` line
local function stepTwo(section: string): string
	local a = string.find(section, "\n2. **Push and open the PR**", 1, true)
	local b = string.find(section, "\n3. **Merge**", 1, true)
	if a == nil or b == nil or b < a then
		error(`{RULES} Landing a change has no step 2 followed by step 3`)
	end
	return string.sub(section, a, b)
end

return t.spec("c0271 read the PR's state before pushing", function(it)
	it(
		"[zz-rules/read-pr-state-before-pushing] Landing a change step 2 says to read the PR's state before every push",
		function()
			local step = stepTwo(landing(fs.readFile(`{root}/{RULES}`)))
			if string.find(step, "\n" .. BULLET .. "\n", 1, true) == nil then
				error(
					`{RULES} Landing a change step 2 does not hold, as a line of its own, the bullet: {BULLET}`
				)
			end
		end
	)

	it("[zz-rules/read-pr-state-before-pushing] the lesson the rule names exists", function()
		t.expect(fs.isFile(`{root}/{LESSON}`)).toBe(true)
	end)
end)
