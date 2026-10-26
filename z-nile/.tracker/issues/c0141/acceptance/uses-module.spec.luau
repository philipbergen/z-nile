--!strict
-- c0141 AC2 (design review 001 F2): c0120's promoted check-paths spec takes its scan from the module in its folder
-- (`./checkpaths`) and defines no scanner of its own, so the gate's live scan is the module's, never an old copy.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

return t.spec("c0141 c0120's check-paths spec runs the module's scan", function(it)
	it("c0120's promoted spec takes its scan from the module and keeps no scanner of its own (F2)", function()
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local text = fs.readFile(`{top}/z-nile/tests/acceptance/c0120/check-paths.spec.luau`)
		t.expect(string.find(text, 'require("./checkpaths")', 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "checkpaths.scan(", 1, true) ~= nil).toBe(true)
		for _, name in { "literals", "present", "touched", "under", "items", "scan", "repoPath", "owned" } do
			t.expect((string.find(text, `local function {name}(`, 1, true))).toBe(nil)
		end
		t.expect((string.find(text, "PREFIXES =", 1, true))).toBe(nil)
	end)
end)
