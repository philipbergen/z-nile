--!strict
-- c0450: prep and its design review look for promoted specs that a new issue overrides.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- c0120 override: specs run from z-nile's home, so the repository's files are read from the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- the text from the line containing `from` up to (not including) the next line that starts with `stop`
local function section(text: string, from: string, stop: string): string
	local out, on = {}, false
	for line in string.gmatch(text, "[^\n]*") do
		if on and string.sub(line, 1, #stop) == stop then
			break
		end
		if not on and string.find(line, from, 1, true) then
			on = true
		end
		if on then
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n")
end

local function has(text: string, token: string): boolean
	return string.find(text, token, 1, true) ~= nil
end

return t.spec("c0450 override check", function(it)
	it(
		"ticket-prep step 3 has an Override check naming the selector, the promoted specs and the chore route",
		function()
			local prep = fs.readFile(`{TOP}/.claude/skills/ticket-prep/SKILL.md`)
			local step = section(prep, "**Override check**", "- **")
			t.expect(step ~= "").toBe(true)
			for _, token in
				{
					"z-nile/affected",
					"grep -rlF",
					"tests/acceptance",
					"ALL",
					"depends_on",
					"chore",
					"carries no list",
					"remove or narrow",
					"prefer narrowing",
					"Order & dependencies",
					"Overrides: none",
				}
			do
				t.expect(has(step, token)).toBe(true)
			end
		end
	)

	it("the Override check sits in step 3, before the Test plan bullet", function()
		local prep = fs.readFile(`{TOP}/.claude/skills/ticket-prep/SKILL.md`)
		local at = string.find(prep, "**Override check**", 1, true)
		t.expect(at ~= nil).toBe(true)
		t.expect((at :: number) > (string.find(prep, "## 3. Design each issue", 1, true) :: number))
			.toBe(true)
		t.expect((at :: number) < (string.find(prep, "- **Test plan**", 1, true) :: number)).toBe(true)
	end)

	it("the design-mode review attacks an unnamed override as high", function()
		local review = fs.readFile(`{TOP}/.claude/skills/review/SKILL.md`)
		local design = section(review, "## Design mode", "## Stream mode")
		local item = section(design, "4. **Regressions**", "5. ")
		for _, token in
			{
				"Overrides:",
				"z-nile/affected",
				"grep -rlF",
				"carries no list",
				"tests/acceptance",
				"depends_on",
				"placeholder",
				"high",
			}
		do
			t.expect(has(item, token)).toBe(true)
		end
	end)

	it("ready-raft's readiness check refuses a raft whose issue depends on an unfinished item", function()
		local skill = fs.readFile(`{TOP}/.claude/skills/ready-raft/SKILL.md`)
		local ready = section(skill, "2. **Check readiness", "3. ")
		for _, token in { "depends_on", "isn't a member", "done/", "stop" } do
			t.expect(has(ready, token)).toBe(true)
		end
	end)

	it("the issue template's Regression guard has a visible Overrides line, outside the comment", function()
		local tpl = fs.readFile(`{TOP}/z-nile/templates/issue/doc.md`)
		local guard = section(tpl, "## Regression guard", "## ")
		local visible = string.gsub(guard, "<!%-%-.-%-%->", "")
		t.expect(has(visible, "Overrides:")).toBe(true)
	end)
end)
