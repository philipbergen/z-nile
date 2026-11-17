--!strict
-- c0402 AC3 (f0399 part): f0399 is a dependency, so its promoted plan.spec exists when this runs; it must use chores that
-- fit the 3,000 cap (1,600 each: two make 3,200, over it). Reads the real tree as text with plain finds only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0402 f0399's promoted plan.spec fits the new cap", function(it)
	it("f0399's plan.spec uses 1,600-line chores and a cap of 3,000 in its comment", function()
		local plan = read("z-nile/tests/acceptance/f0399/plan.spec.luau")
		t.expect(has(plan, "passes the cap of 3,000")).toBe(true)
		t.expect(has(plan, "cap of 1,500")).toBe(false)
		t.expect(has(plan, "size = 900")).toBe(false)
		t.expect(has(plan, "no dependency: 1,600 + 1,600")).toBe(true)
	end)
end)
