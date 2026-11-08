--!strict
-- c0260 AC7: zz-review has an idea mode: the reviewer sees the ask, the interview and the idea only, and checks that
-- nothing was dropped, added or bent. Shape rules over its text (the exact wording is not pinned).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local Z = fs.readFile(`{ROOT}/z-nile/skills/zz-review/SKILL.md`)
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
local function section(title: string): string
	local from = string.find(Z, `\n## {title}`, 1, true)
	if from == nil then
		error(`no section "{title}"`, 0)
	end
	local rest = string.sub(Z, from + 1)
	local to = string.find(rest, "\n## ", 4, true)
	return if to then string.sub(rest, 1, to) else rest
end

return t.spec("c0260 zz-review has an idea mode", function(it)
	it(
		"AC7: it sees only the three sections and attacks dropped, added, bent, ambiguity, splits, overlap, doneness and the record",
		function()
			local idea = section("Idea mode (from z-ticket)")
			t.expect(has(idea, "`## Ask (verbatim)`")).toBe(true)
			t.expect(has(idea, "`## Interview`")).toBe(true)
			t.expect(has(idea, "`## Idea`")).toBe(true)
			t.expect(has(idea, "You do not see the Problem")).toBe(true)
			for _, key in
				{
					"**Dropped**",
					"**Added**",
					"**Bent**",
					"**Ambiguity**",
					"**One issue**",
					"**Overlap and conflict**",
					"**Doneness**",
					"**Interview record**",
				}
			do
				t.expect(has(idea, key)).toBe(true)
			end
			t.expect(has(idea, "Never prescribe a cut")).toBe(true)
		end
	)

	it(
		"AC7: the mode is named in Who reviews and Output file, with the activity whose model it runs on",
		function()
			t.expect(has(Z, "`--mode idea`")).toBe(true)
			t.expect(has(Z, "`idea-review-NNN.md`")).toBe(true)
			t.expect(has(Z, "z-ticket-review")).toBe(true)
			t.expect(has(Z, "`## Idea review`")).toBe(true) -- the author's answers live in the document
		end
	)
end)
