--!strict
-- c0128 AC4: no other case changes. Both narrowed files are pinned whole: the file is normalised and its sha256 must
-- equal the digest of the narrowing in R0045/experiments/narrowing.patch applied to origin/main. The normalisation is
-- the shared whole-file pin rule, z-nile/tests/lib/pin.luau (c0156, the rule c0103's narrowed.spec uses too): it masks
-- item ids (so a compaction cannot break it), makes line endings LF, collapses runs of spaces and tabs within a line,
-- drops trailing whitespace on a line, a trailing comma before `}` and the text's outer blank lines, and KEEPS every
-- line break: a Luau `--` comment ends at a newline, so collapsing newlines would let a check joined onto the comment
-- line above it vanish into the comment unseen (R0045 code review 001 F1; decided with the user, 2026-10-25: "Fix the
-- pin now"). A digest, not the text, because the files are about 1,300 lines. Every verdict goes through one function
-- per file, `exactly24` and `exactly26`: the "exactly" cases assert it on the file, and the mutant cases (a comment
-- joined with the line below it, a deleted assertion) assert `not exactly…` on the file changed in memory, so a pin
-- whose comparison was weakened turns a mutant case red. Any later change to either file must update its digest here:
-- run `pin.digest` on the file's text. On a failure, titles.spec and guards.spec say which case moved or which guard
-- went, and a diff against narrowing.patch shows the rest; this file says that nothing else did.
local fs = require("@lune/fs")
local pin = require("@tests/lib/pin")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

-- spelled in two parts so a compaction does not rewrite it; the ids are mapped through tracker/compaction.txt
local ROOT = "tests/" .. "acceptance/"
local F24 = ROOT .. renamed.id("f0024") .. "/adapter.spec.luau"
local F26 = ROOT .. renamed.id("f0026") .. "/adapters.spec.luau"

local D24 = "7f791c55bab7441df495cc59a1ed1989ff6daa6494e0719e748ef38bd66b992b"
local D26 = "744eeb0f1d525ee47f52c01dd8cab3c4bcd511fd2edf28919f894712f64cbfc6"

local function exactly24(text: string): boolean
	return pin.digest(text) == D24
end
local function exactly26(text: string): boolean
	return pin.digest(text) == D26
end

-- comment lines whose next line a careless join would turn into comment text
local PER_PLAYER = "-- c0128: the six per-player stores, and besides them only d0124's top-N list of runs"
local READS = "-- reads at 0, 2 and 6 s (failure waits of 2, 4, then 8 s), each at page sizes 10 and 50"
local COMPANION = "-- c0128: the per-player companion store is still read"

local function crlf(text: string): string
	return (string.gsub(string.gsub(text, "\r\n", "\n"), "\n", "\r\n"))
end

return t.spec("c0128 the narrowed files, whole", function(it)
	it("f0024 adapter is exactly the narrowed file", function()
		t.expect(exactly24(fs.readFile(F24))).toBe(true)
	end)

	it(
		"f0024: a line joined onto the comment above it, or a deleted assertion, is not the narrowed file",
		function()
			local src = fs.readFile(F24)
			t.expect(exactly24(pin.joined(src, PER_PLAYER))).toBe(false)
			t.expect(exactly24(pin.without(src, "t.expect(updates).toBe(6)"))).toBe(false)
		end
	)

	it(
		"the review's two joins in f0026 adapters, or a deleted assertion, are not the narrowed file",
		function()
			local src = fs.readFile(F26)
			t.expect(exactly26(pin.joined(src, READS))).toBe(false)
			t.expect(exactly26(pin.joined(src, COMPANION))).toBe(false)
			t.expect(exactly26(pin.without(src, "t.expect(#w.reads).toBe(0)"))).toBe(false)
		end
	)

	it("the pins and the joins do not depend on the files' line endings", function()
		local src24, src26 = fs.readFile(F24), fs.readFile(F26)
		t.expect(exactly24(crlf(src24))).toBe(true)
		t.expect(exactly26(crlf(src26))).toBe(true)
		t.expect(pin.joined(crlf(src24), PER_PLAYER)).toBe(pin.joined(src24, PER_PLAYER))
		t.expect(pin.joined(crlf(src26), READS)).toBe(pin.joined(src26, READS))
		t.expect(pin.joined(crlf(src26), COMPANION)).toBe(pin.joined(src26, COMPANION))
	end)

	it("f0026 adapters is exactly the narrowed file", function()
		t.expect(exactly26(fs.readFile(F26))).toBe(true)
	end)
end)
