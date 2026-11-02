--!strict
-- c0156 AC4: the documents that restate the pin rule say what it is now. The testing skill lists `pin` among the shared
-- test libraries; the narrowing lesson sends a pin that tolerates formatting to `pin.digest`, says c0103's gap is
-- closed, and no longer calls c0103's normalisation a model or a gap. The needles are the Design's sentences.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0156 the documents name the shared pin rule", function(it)
	it("the testing skill lists pin among the shared libraries, with what it does", function()
		local s = fs.readFile(`{TOP}/z-nile/skills/zz-test/SKILL.md`)
		t.expect(
			has(
				s,
				"The assertions (`z-nile/tests/lib/t`), `renamed` and `pin` (the whole-file pin rule: `pin.digest` keeps every line break, `pin.joined` and `pin.without` build the comment-join and deleted-assertion mutants) are shared too (`pickman/tests/lib/` re-exports them)"
			)
		).toBe(true)
		t.expect(has(s, "The assertions (`z-nile/tests/lib/t`) and `renamed` are shared too")).toBe(false)
	end)

	it("the narrowing lesson points to pin.digest and says both pins are fixed", function()
		local s = fs.readFile(`{TOP}/z-nile/skills/zz-test/lessons/narrowing-pins-the-whole-file.md`)
		t.expect(has(s, "Is the normaliser `pin.normalise` (`@tests/lib/pin`), not a copy of its rule?"))
			.toBe(true)
		t.expect(
			has(
				s,
				"For each pinned file, weaken its comparison and drop its own mutant case: does a check.sh check go red"
			)
		).toBe(true)
		t.expect(has(s, "use `pin.digest` from `@tests/lib/pin`, which keeps every line break")).toBe(true)
		t.expect(has(s, "so a file with a string holding a run of spaces or a tab keeps the exact-text pin"))
			.toBe(true)
		t.expect(has(s, "c0103's normalisation had the same gap, closed by c0156")).toBe(true)
		t.expect(has(s, "c0103's by c0156, which moved the rule into `pin` so both pins use one copy."))
			.toBe(true)
		t.expect(has(s, "c0103's collapses whitespace")).toBe(false)
		t.expect(has(s, "c0103's normalisation has the same gap")).toBe(false)
	end)
end)
