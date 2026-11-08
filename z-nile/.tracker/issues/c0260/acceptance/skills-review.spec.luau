--!strict
-- c0260 AC7: zz-review has an idea mode
-- Shape rules over zz-review's text (the exact wording is not pinned).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function skill(name: string): string
	return fs.readFile(`{ROOT}/z-nile/skills/{name}/SKILL.md`)
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
-- The text of "## <title>" up to the next "## " heading.
local function section(text: string, title: string): string
	local from = string.find(text, `\n## {title}`, 1, true)
	if from == nil then
		error(`no section "{title}"`, 0)
	end
	local rest = string.sub(text, from + 1)
	local to = string.find(rest, "\n## ", 4, true)
	return if to then string.sub(rest, 1, to) else rest
end
return t.spec("c0260 zz-review has an idea mode", function(it)
	it(
		"AC7: zz-review has an idea mode that attacks fidelity, ambiguity, splitting, overlap, doneness, scope words and the record",
		function()
			local z = skill("zz-review")
			local idea = section(z, "Idea mode (from z-ticket)")
			for _, key in
				{
					"**Fidelity**",
					"**Ambiguity**",
					"**One issue**",
					"**Overlap and conflict**",
					"**Doneness**",
					"**Non-goals and scope words**",
					"**Interview record**",
				}
			do
				t.expect(has(idea, key)).toBe(true)
			end
			t.expect(has(idea, "Never prescribe a cut")).toBe(true)
			t.expect(has(z, "`--mode idea`")).toBe(true)
			t.expect(has(z, "`idea-review-NNN.md`")).toBe(true)
		end
	)
end)
