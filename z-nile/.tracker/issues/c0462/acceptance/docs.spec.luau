--!strict
-- c0462: the skill and the lesson say what the runner now catches and what only review catches.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(rel: string): string
	return fs.readFile(`{root}/{rel}`)
end
local function at(text: string, needle: string, where: string)
	t.assert(string.find(text, needle, 1, true) ~= nil, `{where} lacks: {needle}`)
end

return t.spec("c0462 docs", function(it)
	it("the lesson's added line says the runner catches zero assertions and names what review still catches", function()
		local text = read("z-nile/skills/zz-test/lessons/no-vacuous-pass.md")
		local line: string? = nil
		for l in string.gmatch(text, "[^\n]+") do
			if string.find(l, "the runner now fails a case with zero assertions", 1, true) then
				line = l
			end
		end
		t.assert(line ~= nil, "no line says: the runner now fails a case with zero assertions")
		for _, needle in {
			"greps that find nothing",
			"`|| true`",
			"`diff <(a) <(b)`",
			"assertions that cannot fail",
			"cases that read each other's output",
		} do
			at(line :: string, needle, "the added line of no-vacuous-pass")
		end
	end)

	it("zz-test and z-design say a no-assertion failure is never an expected red", function()
		for _, rel in { "z-nile/skills/zz-test/SKILL.md", "z-nile/skills/z-design/SKILL.md" } do
			at(read(rel), "case made no assertion", rel)
			at(read(rel), "never an expected red", rel)
		end
	end)

	it("both re-executions that start a measured child drop an inherited ZN_VACUOUS_PARENT", function()
		for _, rel in { "z-nile/check.sh", "z-nile/tests/run.luau" } do
			local s = read(rel)
			t.assert(
				string.find(s, '%-u"?,?%s*"?ZN_VACUOUS_PARENT') ~= nil,
				`{rel} does not unset ZN_VACUOUS_PARENT where it sets ZN_MEASURED=1`
			)
		end
	end)

	it("zz-test names t.assert, --require-assertions and the exempt list", function()
		local s = read("z-nile/skills/zz-test/SKILL.md")
		at(s, "t.assert", "zz-test")
		at(s, "--require-assertions", "zz-test")
		at(s, "z-nile/tests/vacuous-exempt.txt", "zz-test")
	end)
end)
