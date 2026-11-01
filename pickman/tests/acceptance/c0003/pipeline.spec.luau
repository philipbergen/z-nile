--!strict
-- c0030 AC5, overridden by c0172: runtime tests are the local command. The workflow does not run them.
-- SETUP still says how, and the testing skill still lists the tier.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

-- c0120 override: the spec runs from its home: the checkout's files are read from the top
local setup = fs.readFile("../SETUP.md")
local testing = fs.readFile("skills/pickman-test/SKILL.md")

local function has(s: any, needle: string): boolean
	return type(s) == "string" and string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0030 runtime tests in the docs", function(it)
	it("SETUP.md names the key scope the runtime tests need, and how to run them", function()
		for _, needle in { "luau-execution-sessions", "scripts/runtime-test" } do
			t.expect(has(setup, needle)).toBe(true)
		end
	end)

	it("the testing skill lists the runtime tier and how to run it", function()
		t.expect(has(testing, "tests/runtime/")).toBe(true)
		t.expect(has(testing, "scripts/runtime-test")).toBe(true)
		t.expect(has(testing, "Open Cloud")).toBe(true)
	end)
end)
