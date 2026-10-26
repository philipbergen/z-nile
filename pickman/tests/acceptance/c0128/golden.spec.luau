--!strict
-- c0128 AC4: no other case changes. Both narrowed files are pinned whole: the file is normalised and its sha256 must
-- equal the digest of the narrowing in R0045/experiments/narrowing.patch applied to origin/main. The normalisation
-- masks item ids (so a compaction cannot break it), makes line endings LF, collapses runs of spaces and tabs within a
-- line, drops trailing whitespace and a trailing comma before `}`, and KEEPS every line break: a Luau `--` comment
-- ends at a newline, so collapsing newlines would let a check joined onto the comment line above it vanish into the
-- comment unseen (R0045 code review 001 F1; decided with the user, 2026-10-25: "Fix the pin now"). A digest, not the
-- text, because the files are about 1,300 lines. Any later change to either file must update the digest here: run
-- `normalise` on the file's text and `serde.hash("sha256", …)` it. On a failure, titles.spec and guards.spec say which
-- case moved or which guard went, and a diff against narrowing.patch shows the rest; this file says that nothing else
-- did. c0103's promoted narrowed.spec has the old, newline-collapsing rule: c0156 fixes it.
local fs = require("@lune/fs")
local renamed = require("@tests/lib/renamed")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- spelled in two parts so a compaction does not rewrite it; the ids are mapped through tracker/compaction.txt
local ROOT = "tests/" .. "acceptance/"
local F24 = ROOT .. renamed.id("f0024") .. "/adapter.spec.luau"
local F26 = ROOT .. renamed.id("f0026") .. "/adapters.spec.luau"

local function normalise(text: string): string
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	text = string.gsub(text, "\r\n?", "\n")
	text = string.gsub(text, "[ \t]+", " ")
	text = string.gsub(text, " \n", "\n")
	text = string.gsub(text, ",( ?\n?[ ]?)}", "%1}")
	text = string.gsub(text, "^[%s]+", "")
	text = string.gsub(text, "[%s]+$", "")
	return text
end
local function normalised(path: string): string
	return normalise(fs.readFile(path))
end
local function digest(text: string): string
	return serde.hash("sha256", normalise(text))
end

-- one line of the file joined onto the comment line above it (a newline turned into a space)
local function joined(path: string, comment: string): string
	local src = fs.readFile(path)
	local at = string.find(src, comment .. "\n", 1, true)
	assert(at ~= nil, `no comment line "{comment}" in {path}`)
	local cut = at + #comment
	local rest = string.gsub(string.sub(src, cut + 1), "^[ \t]+", "", 1)
	return string.sub(src, 1, cut - 1) .. " " .. rest
end

return t.spec("c0128 the narrowed files, whole", function(it)
	it("f0024 adapter is exactly the narrowed file", function()
		t.expect(serde.hash("sha256", normalised(F24)))
			.toBe("7f791c55bab7441df495cc59a1ed1989ff6daa6494e0719e748ef38bd66b992b")
	end)

	it("a check joined onto the comment line above it changes the normalised text", function()
		t.expect(normalise("-- x\nassert()") == normalise("-- x assert()")).toBe(false)
		t.expect(normalise("a  =\t1  \n}") == normalise("a = 1\n}")).toBe(true)
	end)

	it("the review's two joins in f0026 adapters each change its digest", function()
		local pinned = digest(fs.readFile(F26))
		local first = joined(
			F26,
			"-- reads at 0, 2 and 6 s (failure waits of 2, 4, then 8 s), each at page sizes 10 and 50"
		)
		local second = joined(F26, "-- c0128: the per-player companion store is still read")
		t.expect(digest(first) == pinned).toBe(false)
		t.expect(digest(second) == pinned).toBe(false)
	end)

	it("f0026 adapters is exactly the narrowed file", function()
		t.expect(serde.hash("sha256", normalised(F26)))
			.toBe("744eeb0f1d525ee47f52c01dd8cab3c4bcd511fd2edf28919f894712f64cbfc6")
	end)
end)
