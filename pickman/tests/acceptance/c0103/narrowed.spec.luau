--!strict
-- c0103 AC1: f0014's promoted key-map spec is narrowed, not deleted. It no longer pins the arrow keys, Space, the
-- exact number of keys or that Q and E are unbound (f0104 binds jump, fire and arrow look), and it still pins the
-- movement keys W, A, S and D, that other keys do nothing and that every mapped action is a real name.
-- The narrowed file is pinned whole, by the SHA-256 of its text under the shared whole-file pin rule,
-- z-nile/tests/lib/pin.luau (c0156, the rule c0128's golden.spec uses too): only item ids, line endings, the spaces
-- within a line, a line's trailing whitespace, a trailing comma before `}` and the text's outer blank lines are
-- tolerated, and every line break is kept, so a case whose loops or lists were emptied cannot pass, and neither can a
-- check joined onto the comment line above it. Comments are pinned too, so no code can hide in one; the require lines
-- are pinned, so a stub for View or Movement must not pass. Every verdict goes through `exactly`: the "exactly" case
-- asserts it on the file, and the mutant cases (a line joined onto the comment above it, a deleted assertion) assert
-- it is false on the file changed in memory, so a weakened comparison turns a mutant case red. This spec reads
-- f0014's spec as text, so `--affected` never selects it (only `--full` runs it): any later change to
-- tests/acceptance/f0014/keys.spec.luau must update the digest here (`pin.digest` of the file's text). On a
-- mismatch, diff the file against experiments/narrowing.patch in c0103's folder.
local fs = require("@lune/fs")
local pin = require("@tests/lib/pin")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

-- spelled in two parts so a compaction does not rewrite it; the id is mapped through tracker/compaction.txt
local DIR = "tests/" .. "acceptance/" .. renamed.id("f0014")
local FILE = `{DIR}/keys.spec.luau`

local DIGEST = "ed27eb8bf258d9019129336876becd8133428099b4653d7b6546fcc5db052be6"

-- the one verdict: a text is the narrowed file when its pin digest is the recorded one
local function exactly(text: string): boolean
	return pin.digest(text) == DIGEST
end

-- the narrowed file's header comments, whose next lines a careless join would turn into comment text
local HEADER =
	"-- are free to change, so the jump, fire and arrow-look bindings (f0104) can be added without a red main."
local TITLE = "-- f0130 AC5: the key map, by Enum.KeyCode name."

return t.spec("c0103 the key-map spec, narrowed", function(it)
	it("the spec is still there, and f0014's check.sh still runs it", function()
		-- c0120 override: the spec runs from its project's home after the move
		local check = fs.readFile(".tracker/issues/done/" .. renamed.id("f0014") .. "/check.sh")
		t.expect(fs.isFile(FILE)).toBe(true)
		t.expect(string.find(check, '"$A/keys.spec.luau"', 1, true) ~= nil).toBe(true)
	end)

	it("the spec is exactly the narrowed one: W, A, S and D, unbound keys, the shape of the map", function()
		t.expect(exactly(fs.readFile(FILE))).toBe(true)
	end)

	it("a line joined onto the comment line above it is not the narrowed spec", function()
		local src = fs.readFile(FILE)
		-- the require of Movement, swallowed by the comment above it
		t.expect(exactly(pin.joined(src, HEADER))).toBe(false)
		t.expect(exactly(pin.joined(src, TITLE))).toBe(false)
	end)

	it("a deleted assertion is not the narrowed spec, and another line ending is", function()
		local src = fs.readFile(FILE)
		t.expect(exactly(pin.without(src, "t.expect(n >= 4).toBe(true)"))).toBe(false)
		t.expect(exactly((string.gsub(string.gsub(src, "\r\n", "\n"), "\n", "\r\n")))).toBe(true)
	end)
end)
