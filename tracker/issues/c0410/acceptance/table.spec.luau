--!strict
-- c0410 AC2: the issue template carries a Rules and mutants table under Test plan.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

return t.spec("c0410 rules and mutants table", function(it)
	it("the issue template has the table right after Test plan, before Acceptance criteria", function()
		local doc = fs.readFile("tracker/templates/issue/doc.md")
		local plan = string.find(doc, "\n## Test plan", 1, true)
		local rules = string.find(doc, "\n### Rules and mutants", 1, true)
		local ac = string.find(doc, "\n## Acceptance criteria", 1, true)
		t.expect(plan ~= nil and rules ~= nil and ac ~= nil).toBe(true)
		t.expect((plan :: number) < (rules :: number) and (rules :: number) < (ac :: number)).toBe(true)
		t.expect(string.find(doc, "| rule | spec :: case | mutant it kills | checked |", 1, true) ~= nil)
			.toBe(true)
	end)
end)
