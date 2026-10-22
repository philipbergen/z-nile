--!strict
-- c0410 AC1: the review skill's finding template is second-order (Where, Evidence, Critique,
-- Consequences, Recommendation; no bare Fix) and still parses the way `tracker.sh done` reads findings.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
-- c0120 override: specs run from their project's home; the repository files live at the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local SKILL = `{TOP}/.claude/skills/review/SKILL.md`

-- The fenced markdown block that shows the output file format.
local function template(): string
	local s = fs.readFile(SKILL)
	local block = string.match(s, "```markdown\n(# Review NNN.-)```")
	assert(block, "no ```markdown block starting '# Review NNN' in the review skill")
	return block :: string
end

return t.spec("c0410 review finding format", function(it)
	it("a finding lists Where, Evidence, Critique, Consequences and Recommendation, in that order", function()
		local block = template()
		local at = 0
		for _, field in
			{
				"\n### F1 [high]",
				"\nWhere:",
				"\nEvidence:",
				"\nCritique:",
				"\nConsequences:",
				"\nRecommendation:",
			}
		do
			local i = string.find(block, field, at + 1, true)
			if not i then
				error(`missing or out of order: {field}`)
			end
			at = i
		end
	end)

	it("the Recommendation line asks for the fix after its consequences", function()
		local line = string.match(template(), "\nRecommendation:([^\n]*)")
		t.expect(line ~= nil and string.find(line :: string, "consequences", 1, true) ~= nil).toBe(true)
	end)

	it("no longer ends a finding at a bare Fix line", function()
		t.expect((string.find(template(), "\nFix:", 1, true))).toBe(nil)
	end)

	it("keeps finding headings that tracker.sh done parses", function()
		-- the same pattern reviewProblem in scripts/tracker/main.luau uses
		local ids = {}
		for id in string.gmatch("\n" .. template(), "\n###%s+(F%d+)") do
			table.insert(ids, id)
		end
		t.expect(ids).toEqual({ "F1", "F2" })
	end)

	it("keeps the verdict line", function()
		t.expect(string.find(template(), "\nVerdict: approve | changes", 1, true) ~= nil).toBe(true)
	end)
end)
