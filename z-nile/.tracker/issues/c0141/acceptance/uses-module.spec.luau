--!strict
-- c0141 AC2 (design review 001 F2): c0120's promoted check-paths spec takes its scan from the module in its folder
-- (`./checkpaths`) and defines no scanner of its own, so the gate's live scan is the module's, never an old copy.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

return t.spec("c0141 c0120's check-paths spec runs the module's scan", function(it)
	it("c0120's promoted spec takes its scan from the module and keeps no scanner of its own (F2)", function()
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local raw = fs.readFile(`{top}/z-nile/tests/acceptance/c0120/check-paths.spec.luau`)
		-- the code without comments: long comments, then line comments (design review 002 F2)
		local code = string.gsub(string.gsub(raw, "%-%-%[(=*)%[.-%]%1%]", ""), "%-%-[^\n]*", "")
		local function has(needle: string): boolean
			return string.find(code, needle, 1, true) ~= nil
		end
		t.expect(has('require("./checkpaths")')).toBe(true)
		-- the wrapper's body is the module's scan
		t.expect(string.match(code, "local function scanFrom%([^)]*%)[^\n]*\n%s*return checkpaths%.scan%(base,") ~= nil)
			.toBe(true)
		for _, name in
			{ "literals", "present", "touched", "under", "items", "scan", "repoPath", "owned", "patternWords" }
		do
			t.expect(has(`local function {name}(`)).toBe(false)
			t.expect(has(`function {name}(`)).toBe(false)
			t.expect(string.match(code, `local%s+{name}%s*=%s*function`) == nil).toBe(true)
			t.expect(string.match(code, `\n%s*{name}%s*=%s*function`) == nil).toBe(true)
		end
		for _, name in { "PREFIXES", "FILES", "FOLDERS" } do
			t.expect(string.match(code, `{name}%s*=`) == nil).toBe(true)
		end
	end)
end)
