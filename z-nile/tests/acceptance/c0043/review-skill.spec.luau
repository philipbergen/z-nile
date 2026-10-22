--!strict
-- c0410 AC3: the second-order rules sit in the right sections of the review
-- skills (section-aware, so a phrase in the wrong place, or only inside the template, doesn't count).
local fs = require("@lune/fs")
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

-- The text with fenced code blocks removed.
local function prose(s: string): string
	return (string.gsub(s, "```.-```", ""))
end

local function has(text: string, phrase: string): boolean
	return string.find(text, phrase, 1, true) ~= nil
end

local REVIEW = `{TOP}/.claude/skills/review/SKILL.md`

return t.spec("c0410 review skill sections", function(it)
	it("review: the one-step-further rule is prose, outside the template", function()
		t.expect(has(prose(fs.readFile(REVIEW)), "one step further")).toBe(true)
	end)

	it("review: design mode starts with item 0, the Rules and mutants audit", function()
		local d = section(REVIEW, "Design mode")
		t.expect(string.find(d, "\n0%. %*%*Rules and mutants%*%*") ~= nil).toBe(true)
		t.expect(has(d, "missing row")).toBe(true)
		t.expect(has(d, "reasoned")).toBe(true) -- spot-run only doubtful reasoned rows
		local zero = string.find(d, "\n0%. ")
		local one = string.find(d, "\n1%. ")
		t.expect(zero ~= nil and one ~= nil and (zero :: number) < (one :: number)).toBe(true)
	end)

	it("review: code mode doesn't audit the table, and escalates instead of changing locked files", function()
		local c = section(REVIEW, "Code mode")
		t.expect(has(c, "Rules and mutants")).toBe(false)
		t.expect(has(c, "escalat")).toBe(true)
	end)
end)
