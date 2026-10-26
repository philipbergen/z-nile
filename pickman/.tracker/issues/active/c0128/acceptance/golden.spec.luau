--!strict
-- c0128 AC4: no other case changes. Both narrowed files are pinned whole, as c0103 pins f0014's: the file is
-- normalised (whitespace collapsed, a trailing comma before `}` dropped, item ids masked so a compaction cannot break
-- it; comments are kept, so no code can hide in one) and its sha256 must equal the digest of the narrowing in
-- R0045/experiments/narrowing.patch applied to origin/main. A digest, not the text, because the files are about 1,300
-- lines. Any later change to either file must update the digest here: run the normalisation below on the file and
-- `serde.hash("sha256", …)` it. On a failure, titles.spec and guards.spec say which case moved or which guard went,
-- and a diff against narrowing.patch shows the rest; this file says that nothing else did.
local fs = require("@lune/fs")
local renamed = require("@tests/lib/renamed")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- spelled in two parts so a compaction does not rewrite it; the ids are mapped through tracker/compaction.txt
local ROOT = "tests/" .. "acceptance/"
local F24 = ROOT .. renamed.id("f0024") .. "/adapter.spec.luau"
local F26 = ROOT .. renamed.id("f0026") .. "/adapters.spec.luau"

local function normalised(path: string): string
	local text = string.gsub(fs.readFile(path), "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	text = string.gsub(text, "%s+", " ")
	text = string.gsub(text, ",%s*}", " }")
	text = string.gsub(text, "^ ", "")
	text = string.gsub(text, " $", "")
	return text
end

return t.spec("c0128 the narrowed files, whole", function(it)
	it("f0024 adapter is exactly the narrowed file", function()
		t.expect(serde.hash("sha256", normalised(F24)))
			.toBe("747696e1d0554524afd9d7d165b67d03b796974155f025d25293f9b2ab5737db")
	end)

	it("f0026 adapters is exactly the narrowed file", function()
		t.expect(serde.hash("sha256", normalised(F26)))
			.toBe("f5a749055e26a0dc35c1ee4c0cef76073f1d87d5c1aa736312f8ed7db091394b")
	end)
end)
