--!strict
-- c0410 AC4: the second-order rules sit in the right sections of the ticket-prep
-- skills (section-aware, so a phrase in the wrong place, or only inside the template, doesn't count).
local fs = require("@lune/fs")
-- c0120 override: the spec runs from its project's home after the move
local process = require("@lune/process")
local t = require("@tests/lib/t")
-- c0120 override: specs run from their project's home; the repository files live at the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- Text of the section whose "## " heading starts with `prefix`, up to the next "## " heading.
local function section(path: string, prefix: string): string
	local s = "\n" .. fs.readFile(path)
	local start = string.find(s, "\n## " .. prefix, 1, true)
	assert(start, `{path}: no section starting "## {prefix}"`)
	local after = string.find(s, "\n## ", (start :: number) + 1, true)
	return string.sub(s, start :: number, if after then after - 1 else #s)
end

local function has(text: string, phrase: string): boolean
	return string.find(text, phrase, 1, true) ~= nil
end

-- c0120 override: the spec runs from its home: the checkout's files are read from the top
local PREP = `{TOP}/.claude/skills/ticket-prep/SKILL.md`

return t.spec("c0410 ticket-prep sections", function(it)
	it("ticket-prep: step 3 asks for the Rules and mutants table", function()
		local s3 = section(PREP, "3.")
		t.expect(has(s3, "Rules and mutants")).toBe(true)
		t.expect(has(s3, "| rule | spec :: case | mutant it kills | checked |")).toBe(true)
	end)

	it("ticket-prep: step 5 runs the consequence step and records consequences in refutes", function()
		local s5 = section(PREP, "5.")
		t.expect(has(s5, "consequence step")).toBe(true)
		t.expect(has(s5, "consequences:")).toBe(true)
		t.expect(has(s5, "fixed: <what>; consequences:")).toBe(true)
	end)
end)
