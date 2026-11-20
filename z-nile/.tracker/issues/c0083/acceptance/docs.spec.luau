--!strict
-- c0083 AC7 and AC10: the skills say what the code does. zz-test names the two suites, `--suite`, the watch-check rule
-- and when both suites run, and zz-rules' Merging still runs the clean clone's bare `--full` for a game pull request
-- (the user's decision of 2026-10-26, c0239: the merge's full gate runs all for real). Reads the checkout's skills.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- the text from the heading `from` to the next heading of the same level
local function section(text: string, from: string): string
	local i = string.find(text, from, 1, true)
	t.expect(i ~= nil).toBe(true)
	local j = string.find(text, "\n## ", (i :: number) + #from, true)
	return string.sub(text, i :: number, (j or #text + 1) - 1)
end

return t.spec("c0083 docs", function(it)
	local test = fs.readFile(`{top}/z-nile/skills/zz-test/SKILL.md`)
	local rules = fs.readFile(`{top}/z-nile/skills/zz-rules/SKILL.md`)

	it(
		"AC7: zz-test's command table lists --suite with its four values and refuses it beside --project",
		function()
			local running = section(test, "## Running tests")
			t.expect(has(running, "`z-nile/check.sh --suite harness\\|game\\|all\\|changed`")).toBe(true)
			t.expect(has(running, "refused beside `--project` and `--slow`")).toBe(true)
		end
	)

	it(
		"AC7: zz-test has a Suites section: the two suites, where a spec lives, shared paths, --suite, watch-check",
		function()
			local suites = section(test, "## Suites")
			t.expect(has(suites, "**harness suite**")).toBe(true)
			t.expect(has(suites, "**game suite**")).toBe(true)
			t.expect(has(suites, "z-nile/lib/suites.luau")).toBe(true)
			t.expect(has(suites, "watch-check")).toBe(true)
			t.expect(has(suites, "`--full --suite changed`")).toBe(true)
			t.expect(has(suites, "**A path's suite is its location**")).toBe(true)
			t.expect(has(suites, "a tracker document (under a project root) none")).toBe(true)
			t.expect(has(suites, "narrows the specs of a `--full` run")).toBe(true)
			t.expect(has(suites, "whatever the item's type")).toBe(true)
		end
	)

	it(
		"AC7: the Suites section says when both suites run: setup, a game pull request's merge, the net",
		function()
			local suites = section(test, "## Suites")
			local when =
				string.sub(suites, string.find(suites, "**When both suites run**", 1, true) :: number)
			t.expect(has(when, "`setup.sh`")).toBe(true)
			t.expect(has(when, "the merge of a pull request that changes a game")).toBe(true)
			t.expect(has(when, "`./zn watch-net`")).toBe(true)
		end
	)

	it("AC10: Merging still runs a game pull request's clean-clone bare --full, with no --suite", function()
		local merging = section(rules, "## Merging")
		t.expect(has(merging, "`z-nile/check.sh --full` there")).toBe(true)
		t.expect(has(merging, "--suite")).toBe(false)
	end)
end)
