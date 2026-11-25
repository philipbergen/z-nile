--!strict
-- c0435 AC5: the skills say Solution bullets 3 and 4 of the easy path: an easy ticket's test is written with the code,
-- red first, with no acceptance folder beforehand, and its design has no experiments section and no size record.
-- z-design's easy path paragraph, zz-execute Phase 2 step 2 and zz-rules' Dispatch bullet each say it; the fewest words
-- that carry the rule are pinned, so a rewording keeps them or names this spec under Overrides. Reads the real tree,
-- plain finds only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- runs from z-nile/ (the project's home): every path this spec reads is the repository's, from its top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function skill(name: string): string
	return fs.readFile(`{TOP}/z-nile/skills/{name}/SKILL.md`)
end
local function at(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) == nil then
		error(`{where} is missing: {needle}`, 2)
	end
end

return t.spec("c0435 the skills state the easy path's drafting rules", function(it)
	it(
		"z-design: the test is written with the code, red first, with no acceptance folder, experiments or size",
		function()
			local s = skill("z-design")
			at(s, "**The easy path (c0435).**", "z-design")
			at(
				s,
				"The test is written with the code, red first, in the project's `tests/`: no acceptance folder, no experiments, no `size:`",
				"z-design's easy path paragraph"
			)
		end
	)

	it(
		"zz-execute: an easy ticket's one spec is written in tests/ and committed red on its own before the code",
		function()
			at(
				skill("zz-execute"),
				"An easy ticket with a short note has none: its one spec (the note's `Test:`) is written here, in the project's `tests/`, and committed red on its own before the code.",
				"zz-execute Phase 2 step 2"
			)
		end
	)

	it("zz-rules: the Dispatch bullet says the same", function()
		at(
			skill("zz-rules"),
			"with its test written with the code (red first), no acceptance folder, experiments or `size:`",
			"zz-rules' easy path bullet"
		)
	end)
end)
