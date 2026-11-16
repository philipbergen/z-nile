--!strict
-- c0266 AC1: the promoted c0114 classified spec is exactly its rewritten text (lesson zz-test/narrowing-pins-the-whole-file):
-- the case that wanted every issue in z-nile's root to be a chore is replaced by one that holds chores, features and
-- defects there, each issue's `type:` naming its id's letter, and the defect main-red-specs-after-cuts staying one;
-- nothing else in the file changes but one comment. The digest is SHA-256 of the exact text with item ids masked and
-- CRLF made LF (c0172's normaliser): no other whitespace is tolerated, since a newline ends a line comment and the
-- spaces inside a string are part of what it asserts. Reads the real tree, no writes.
local fs = require("@lune/fs")
local process = require("@lune/process")
local renamed = require("@tests/lib/renamed")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function exact(rel: string): string
	local text = string.gsub(fs.readFile(`{TOP}/{rel}`), "\r\n", "\n")
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return text
end

-- the digest of the rewritten text (prototype.patch beside c0266's document), and of the text it replaces
local REWRITTEN = "476298f16a58597f2ca08ad0a50e5853fa18afecf6cfb9c3cc0e4835ab51fa21"
local BEFORE = "5141763cc51067bc6077cbbbf48a9e48a50e55db1046a75b53ccbdb910c3b8b8"

return t.spec("c0266 the classified spec allows every type in z-nile's root", function(it)
	it("the promoted classified spec is exactly the rewritten text", function()
		local rel = `z-nile/tests/acceptance/{renamed.id("c0114")}/classified.spec.luau`
		t.expect(fs.isFile(`{TOP}/{rel}`)).toBe(true)
		local digest = serde.hash("sha256", exact(rel))
		if digest == BEFORE then
			error(`{rel} is still the text before c0266: its chores-only case is not rewritten`)
		end
		t.expect(digest).toBe(REWRITTEN)
	end)
end)
