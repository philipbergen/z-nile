--!strict
-- c0163 AC1: which lines are conflict markers, and the gate's verdict (@znile/engine/markers, pure). A marker line
-- starts with seven `<`, `>` or `|` followed by a space or the end of the line (git's `<<<<<<< HEAD`,
-- `>>>>>>> origin/main`, and `||||||| base` in the diff3 and zdiff3 styles), or is exactly seven `=`; a trailing
-- carriage return is ignored. Mid-line, indented, six or eight long, or glued to a word, it is not. A binary text
-- (a NUL in its first 8000 bytes) has none. markers.check names each as `<path>:<line>: conflict marker`, sorted by
-- path, skips an exempted file and names an exemption that is no tracked text file. The exemption list takes one
-- plain repository-relative path per line (blank lines and # comments allowed) and names the line of a pattern, an
-- absolute path, a .. step, a backslash or a repeat. Markers are built with string.rep here, so this file has none.
-- Casts keep the spec type-legal before the module exists; a missing member fails at the call.
local markers: any = require("@znile/engine/markers")
local t = require("@tests/lib/t")

local LT, GT, BAR, EQ = string.rep("<", 7), string.rep(">", 7), string.rep("|", 7), string.rep("=", 7)

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0163 conflict markers", function(it)
	it("git's four marker lines are markers, with a label or none, and with a CRLF ending", function()
		for _, line in
			{
				LT .. " HEAD",
				GT .. " origin/main",
				BAR .. " merged common ancestors",
				EQ,
				LT,
				GT,
				LT .. " HEAD\r",
				EQ .. "\r",
			}
		do
			if not markers.isMarker(line) then
				error(`not seen as a marker: {line}`, 0)
			end
		end
	end)

	it(
		"look-alikes are not: mid-line, indented, too short or long, glued to a word, = with a trailer",
		function()
			for _, line in
				{
					"see " .. LT .. " HEAD",
					" " .. LT .. " HEAD",
					string.rep("<", 6) .. " x",
					string.rep("<", 8) .. " x",
					LT .. "x",
					EQ .. "=",
					string.rep("=", 6),
					EQ .. " ",
					"",
					"| a | b |",
				}
			do
				if markers.isMarker(line) then
					error(`seen as a marker: {line}`, 0)
				end
			end
		end
	)

	it("scan gives each marker's 1-based line; a binary text has none", function()
		local text = table.concat({ "a", LT .. " HEAD", "b", EQ, "c", GT .. " x", "" }, "\n")
		local hits = markers.scan("f.md", text)
		t.expect(#hits).toBe(3)
		t.expect(hits[1].line).toBe(2)
		t.expect(hits[2].line).toBe(4)
		t.expect(hits[3].line).toBe(6)
		t.expect(hits[1].path).toBe("f.md")
		t.expect(#markers.scan("b.bin", "x\0y\n" .. LT .. " HEAD\n")).toBe(0)
		t.expect(#markers.scan("last.md", "a\n" .. EQ)).toBe(1) -- no final newline
	end)

	it("check names every marker as <path>:<line>, sorted by path, and skips an exempted file", function()
		local files = {
			{ path = "z/b.md", text = "x\n" .. EQ .. "\n" },
			{ path = "a/c.md", text = LT .. " HEAD\nok\n" },
			{ path = "doc.md", text = LT .. " HEAD\n" },
			{ path = "clean.md", text = "fine\n" },
		}
		local tracked = { ["z/b.md"] = true, ["a/c.md"] = true, ["doc.md"] = true, ["clean.md"] = true }
		local problems = markers.check(files, { ["doc.md"] = true }, tracked)
		t.expect(problems).toEqual({ "a/c.md:1: conflict marker", "z/b.md:2: conflict marker" })
		t.expect(#markers.check({ { path = "clean.md", text = "fine\n" } }, {}, tracked)).toBe(0)
	end)

	it("an exemption that names no tracked text file is a problem", function()
		local problems = markers.check({}, { ["gone.md"] = true }, { ["here.md"] = true })
		t.expect(#problems).toBe(1)
		t.expect(has(problems[1], "gone.md")).toBe(true)
		t.expect(has(problems[1], markers.EXEMPTIONS)).toBe(true)
	end)

	it("the exemption list: plain paths, blank lines and comments; every other line is named", function()
		local ok, problems = markers.parseExemptions("# a comment\n\ndocs/markers.md\n  z-nile/x.md  \n")
		t.expect(#problems).toBe(0)
		t.expect(ok["docs/markers.md"]).toBe(true)
		t.expect(ok["z-nile/x.md"]).toBe(true)
		for _, bad in { "docs/*.md", "a?.md", "[ab].md", "/etc/x", "a/../b.md", "..", "a\\b.md" } do
			local _, p = markers.parseExemptions("# c\n" .. bad .. "\n")
			t.expect(#p).toBe(1)
			t.expect(has(p[1], `{markers.EXEMPTIONS}:2:`)).toBe(true)
		end
		local _, twice = markers.parseExemptions("a.md\na.md\n")
		t.expect(#twice).toBe(1)
		t.expect(has(twice[1], ":2:")).toBe(true)
	end)

	it("the exemption list is z-nile/marker-exemptions.txt and starts with no path", function()
		t.expect(markers.EXEMPTIONS).toBe("z-nile/marker-exemptions.txt")
		local fs = require("@lune/fs")
		local list, problems = markers.parseExemptions(fs.readFile("marker-exemptions.txt"))
		t.expect(#problems).toBe(0)
		t.expect(next(list)).toBe(nil)
	end)
end)
