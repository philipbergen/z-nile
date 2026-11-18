--!strict
-- c0156 AC1: the shared whole-file pin rule (z-nile/tests/lib/pin.luau) keeps every line break and tolerates only
-- what the Design lists, and its join helper reads through the same normaliser as the digest. One case per rule, so a
-- plausible wrong rule (a collapse of newlines, a missing LF step, a widened comma rule) fails the case that owns it.
-- The ids in the inputs are not real items (f9001 ...), so a compaction never rewrites them.
local pin = require("@tests/lib/pin")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- a spec-like text with a header comment, an indented comment, a trailing comment, a block comment, a table with a
-- trailing comma, a blank line and an id
local SAMPLE = table.concat({
	"--!strict",
	"-- f9001 AC1: the header",
	"local t = 1",
	"\t-- an indented comment",
	"\tt.expect(a).toBe(1) -- a trailing comment",
	"\tt.expect(b).toBe(2)",
	"--[[ block",
	"comment ]] local want = {",
	"\tW = 1,",
	"}",
	"",
	"return want",
}, "\n")

return t.spec("c0156 the whole-file pin rule", function(it)
	it("every line break counts: turning any one into a space changes the text", function()
		local pinned = pin.digest(SAMPLE)
		local n = 0
		for at in string.gmatch(SAMPLE, "()\n") do
			local joined = string.sub(SAMPLE, 1, at - 1) .. " " .. string.sub(SAMPLE, at + 1)
			t.expect(pin.digest(joined) == pinned).toBe(false)
			n += 1
		end
		t.expect(n).toBe(11)
		t.expect(pin.normalise("-- x\nassert()") == pin.normalise("-- x assert()")).toBe(false)
	end)

	it(
		"a vertical tab or a form feed, which a Luau comment runs through, is kept as it is: no space, no line break",
		function()
			local base = pin.normalise("-- x\nassert()")
			t.expect(pin.normalise("-- x\vassert()") == base).toBe(false)
			t.expect(pin.normalise("-- x\fassert()") == base).toBe(false)
			-- neither is a space (collapsed) nor a line break (a Luau lexer probe: only LF and CR end a comment)
			t.expect(pin.normalise("a\vb")).toBe("a\vb")
			t.expect(pin.normalise("a\fb")).toBe("a\fb")
			t.expect(pin.normalise("a\vb") == pin.normalise("a b")).toBe(false)
			t.expect(pin.normalise("a\vb") == pin.normalise("a\nb")).toBe(false)
		end
	)

	it("blank lines are kept: one more or one fewer changes the text", function()
		t.expect(pin.normalise("x\n\ny")).toBe("x\n\ny")
		t.expect(pin.normalise("x\n\ny") == pin.normalise("x\ny")).toBe(false)
	end)

	it(
		"runs of spaces and tabs within a line are one space, and a line's trailing whitespace goes",
		function()
			t.expect(pin.normalise("a  =\t1")).toBe("a = 1")
			t.expect(pin.normalise("a\t \nb")).toBe("a\nb")
			t.expect(pin.normalise("a\n\t\tb")).toBe(pin.normalise("a\n  b"))
		end
	)

	it("CRLF and a lone CR are line breaks like LF", function()
		t.expect(pin.normalise("a\r\nb\r\n")).toBe("a\nb")
		t.expect(pin.normalise("a\rb")).toBe("a\nb")
		t.expect(pin.normalise("-- x\r\nassert()") == pin.normalise("-- x assert()")).toBe(false)
		t.expect(pin.digest((string.gsub(SAMPLE, "\n", "\r\n")))).toBe(pin.digest(SAMPLE))
	end)

	it("item ids are masked, as whole words of f, d, c or R", function()
		t.expect(pin.normalise("-- f9001 and R9002 and c9003 and d9004")).toBe("-- ID and ID and ID and ID")
		t.expect(pin.normalise("xf9001 f9001x e9001 f_9001 f")).toBe("xf9001 f9001x e9001 f_9001 f")
	end)

	it("a comma before a closing brace goes, across at most one line break", function()
		t.expect(pin.normalise("{ a, }")).toBe("{ a }")
		t.expect(pin.normalise("a,\n}")).toBe("a\n}")
		t.expect(pin.normalise("a,\n }")).toBe("a\n }")
		t.expect(pin.normalise("a,\n\n}") == pin.normalise("a\n\n}")).toBe(false)
		t.expect(pin.normalise("a,\nb") == pin.normalise("a\nb")).toBe(false)
		t.expect(pin.normalise("f(a, b)") == pin.normalise("f(a b)")).toBe(false)
	end)

	it("the blank lines at the start and end of the text go", function()
		t.expect(pin.normalise("\n\n x\n\n")).toBe("x")
	end)

	it(
		"nothing else is tolerated: a changed token, a deleted line, a comment prefix, a swapped order",
		function()
			local base = pin.digest(SAMPLE)
			local function differs(text: string)
				t.expect(pin.digest(text) == base).toBe(false)
			end
			differs((string.gsub(SAMPLE, "toBe%(1%)", "toBe(2)")))
			differs((string.gsub(SAMPLE, "\tt%.expect%(b%)%.toBe%(2%)\n", "")))
			differs((string.gsub(SAMPLE, "\tt%.expect%(b%)", "\t-- t.expect(b)")))
			differs((string.gsub(SAMPLE, "an indented comment", "a changed comment")))
			differs((string.gsub(SAMPLE, "(local t = 1\n)(.-\n)(.-\n)", "%1%3%2", 1)))
		end
	)

	it("normalising twice is normalising once", function()
		local messy = "\r\n-- f9001 x\r\n\ta\t=  { 1,\r\n}  \r\n\r\n"
		t.expect(pin.normalise(pin.normalise(messy))).toBe(pin.normalise(messy))
		t.expect(pin.normalise(pin.normalise(SAMPLE))).toBe(pin.normalise(SAMPLE))
	end)

	it("the digest is the SHA-256 of the normalised text, as lowercase hex", function()
		t.expect(pin.digest("")).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
		t.expect(pin.digest("  a\t=  1 \r\n")).toBe(serde.hash("sha256", "a = 1"))
		t.expect(pin.digest("-- f9001\nx")).toBe(pin.digest("-- c9002\r\nx"))
		t.expect(#pin.digest(SAMPLE)).toBe(64)
	end)

	it("joined: the line after the comment goes onto it, with one space, and nothing else changes", function()
		t.expect(pin.joined("-- x\n\tassert()\nend", "-- x")).toBe("-- x assert()\nend")
		t.expect(pin.joined("a\n-- x\nb\n-- x\nc", "-- x")).toBe("a\n-- x b\n-- x\nc")
		t.expect(pin.joined("end -- note\nassert()", "-- note")).toBe("end -- note assert()")
		t.expect(pin.digest(pin.joined(SAMPLE, "-- f9001 AC1: the header")) == pin.digest(SAMPLE)).toBe(false)
	end)

	it(
		"joined reads its text and its comment through the normaliser: line endings, ids, indentation",
		function()
			local crlf = "\t-- f9001 note\r\n\tassert()\r\n"
			t.expect(pin.joined(crlf, "-- c9002 note")).toBe("-- ID note assert()")
			t.expect(pin.joined(crlf, "-- f9001   note"))
				.toBe(pin.joined("-- f9001 note\nassert()", "-- f9001 note"))
			t.expect(pin.joined("a\rb", "a")).toBe("a b")
		end
	)

	it("joined refuses a comment no line ends in, and a comment followed by a blank line", function()
		t.expect(function()
			pin.joined("-- x\nassert()", "-- y")
		end).toThrow("no line ends in the comment")
		t.expect(function()
			pin.joined("-- x", "-- x")
		end).toThrow("no line ends in the comment")
		t.expect(function()
			pin.joined("assert()\n-- x\n", "-- x")
		end).toThrow("no line ends in the comment")
		t.expect(function()
			pin.joined("-- x\n\nassert()", "-- x")
		end).toThrow("followed by a blank line")
	end)

	it(
		"without: deletes the one occurrence, read through the normaliser, and nothing else changes",
		function()
			t.expect(pin.without("a\n\tt.expect(x)\nb", "t.expect(x)")).toBe("a\n \nb")
			t.expect(pin.without("a\r\n\tt.expect(x)\r\nb", "\t\tt.expect(x)\n")).toBe("a\n \nb")
			t.expect(pin.without("-- f9001\nx", "-- c9002")).toBe("\nx")
			t.expect(pin.digest(pin.without(SAMPLE, "t.expect(b).toBe(2)")) == pin.digest(SAMPLE)).toBe(false)
		end
	)

	it("without refuses a piece that is empty, absent or repeated", function()
		t.expect(function()
			pin.without("a\nb", "c")
		end).toThrow('no "c" to delete')
		t.expect(function()
			pin.without("a\nb", "  ")
		end).toThrow("to delete")
		t.expect(function()
			pin.without("a\nb\na", "a")
		end).toThrow("occurs more than once")
	end)
end)
