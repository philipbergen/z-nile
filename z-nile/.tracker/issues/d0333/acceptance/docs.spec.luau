--!strict
-- d0333 AC7: zz-execute says what the fix makes true. Phase 5 commits the table and the final review files with
-- `./zn commit` and then checks the table (before that commit the check reports the Verification log's commit as
-- added before trace.md), and only the top layer may carry commits after its finish commit.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local text = fs.readFile(`{root}/z-nile/skills/zz-execute/SKILL.md`)

local function section(name: string): string
	local from = string.find(text, `\n## {name}`, 1, true)
	if not from then
		error(`zz-execute has no section {name}`)
	end
	local to = string.find(text, "\n## ", from + 1, true) or #text + 1
	return string.sub(text, from, to - 1)
end
local function at(body: string, needle: string): number
	local found = string.find(body, needle, 1, true)
	if not found then
		error(`zz-execute does not say: {needle}`)
	end
	return found
end

return t.spec("d0333 zz-execute commits the table, then checks it", function(it)
	it(
		"AC7: Phase 5 commits trace.md with ./zn commit after step 1's commit, then verifies the check",
		function()
			local p5 = section("Phase 5")
			local commit =
				at(p5, "Commit `trace.md` and the final review files with `./zn commit --phase code-review")
			local verify = at(p5, "then verify that `./zn trace <R-id> --check` passes")
			t.expect(commit < verify).toBe(true)
			at(p5, "after step 1's commit (an issue document committed after the table makes it stale)")
			-- the old order is gone
			t.expect((string.find(p5, "--check` passes and commit `trace.md`", 1, true))).toBe(nil)
		end
	)

	it("AC7: Phase 2B says a lower layer with any commit after its finish is finished again", function()
		local p2b = section("Phase 2B")
		local fix =
			at(p2b, "After a fix on a lower layer, `./zn finish` that layer again and `./zn restack <R-id>`")
		local any = at(
			p2b,
			"The same goes for any other commit on a lower layer after its finish (its review files included)"
		)
		t.expect(fix < any).toBe(true)
		at(p2b, "only the top layer may carry commits after its finish commit")
	end)
end)
