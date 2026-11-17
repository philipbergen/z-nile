--!strict
-- R0068 review-001 F2 (c0156): the pin rule's `--affected` selector. c0103's and c0128's promoted pins hold digests
-- computed through `pin.normalise`, so any change to what the rule outputs moves every one of them; but a change to
-- `z-nile/tests/lib/pin.luau` selects only c0156's own specs (a game spec's watch keeps game paths, and the pins'
-- watches are written by `./zn finish`). This spec has its own watch naming the module and pins the rule's exact
-- output on a sample that exercises each of its steps, so a change to the rule turns z-nile's `--affected` gate red
-- before a merge, naming what else must move. It reads no pickman file (lesson zz-test/specs-pin-only-their-own-project):
-- the pins themselves run in the full gate.
local pin = require("@tests/lib/pin")
local t = require("@tests/lib/t")

-- every tolerance of the rule, and what it keeps: ids, CRLF and a lone CR, tabs and runs of spaces (in a string too),
-- trailing whitespace, a comma before a brace (same line and across one line break), blank lines inside, the outer
-- blank lines, and a vertical tab and a form feed inside a line (kept, as a Luau comment runs through them)
local SAMPLE = "\r\n\n-- c0156: a comment\t with  tabs   \r\nlocal t = { a = 1, }\nlocal u = {\n\tb = 2,\n}\n\n"
	.. '\tt.expect(f0024).toBe("x  y")  \r\nlocal v = 1 \r-- R0045 lone CR\nlocal w = 2\v-- vt\f ff\n\n\n'

local EXPECTED = table.concat({
	"-- ID: a comment with tabs",
	"local t = { a = 1 }",
	"local u = {",
	" b = 2",
	"}",
	"",
	' t.expect(ID).toBe("x y")',
	"local v = 1",
	"-- ID lone CR",
	"local w = 2\v-- vt\f ff",
}, "\n")

local DIGEST = "7f52e14e954959d2e04ba10f78506ff347700480555fe91f5111f8f8971f7349"

local MOVED = "the pin rule's output changed: every whole-file pin computed through it moves too (c0103's DIGEST and "
	.. "c0128's D24 and D26 in pickman's promoted specs); recompute them in the same change, and this sample's values"

return t.spec("the whole-file pin rule's exact output (the selector for a change to pin.luau)", function(it)
	it("normalises the sample to exactly the expected text", function()
		local got = pin.normalise(SAMPLE)
		t.expect(if got == EXPECTED then "same" else `{MOVED}; got {string.format("%q", got)}`).toBe("same")
	end)

	it("hashes the sample to exactly the expected digest", function()
		local got = pin.digest(SAMPLE)
		t.expect(if got == DIGEST then "same" else `{MOVED}; got digest {got}`).toBe("same")
	end)
end)
