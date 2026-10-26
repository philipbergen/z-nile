--!strict
-- c0134 AC1: c0131's accept.spec.luau opens with a header that describes what that file tests (AC1: the ref guard
-- accepts an empty transaction from a check.sh flow, and still accepts a fetch that creates or moves a
-- remote-tracking ref), and leaves the refusals to refuse.spec.luau (AC2), which tests them. Reads the file only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local split = require("./split")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local FILE = `{TOP}/z-nile/tests/acceptance/c0131/accept.spec.luau`

-- the header, cut by the one boundary reader check.sh AC2 uses too (design review 001 F1)
local function header(text: string): string
	return (split.cut(text))
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0134 accept.spec's header describes what it tests", function(it)
	it("only a run of plain line comments after line 1 is header; every other byte is body", function()
		local h, b = split.cut("--!strict\n-- one\n--\n-- two\n--[[x]] y()\nlocal x = 1\n-- not header\nz()")
		t.expect(h).toBe("-- one\n--\n-- two")
		-- line 1, a block comment that hides code, and a last line with no newline are body (review 002 F1)
		t.expect(b).toBe("--!strict\n--[[x]] y()\nlocal x = 1\n-- not header\nz()")
		local h2, b2 = split.cut("--!strict\n--!nonstrict\n-- a\nlocal x = 1\n")
		t.expect(h2).toBe("")
		t.expect(b2).toBe("--!strict\n--!nonstrict\n-- a\nlocal x = 1\n")
		-- a code line at the boundary is body (review 001 F1), and the trailing newline is kept
		t.expect(select(2, split.cut("--!strict\n-- a\n_G.x = true\nx()\n")))
			.toBe("--!strict\n_G.x = true\nx()\n")
	end)

	it("AC1: the header names AC1's two acceptances", function()
		local h = header(fs.readFile(FILE))
		t.expect(has(h, "c0131 AC1")).toBe(true)
		t.expect(has(h, "accepts an empty ref transaction")).toBe(true)
		t.expect(has(h, "creates or moves a remote-tracking ref")).toBe(true)
	end)

	it("AC1: the header leaves the refusals to refuse.spec.luau and lists none of them", function()
		local h = header(fs.readFile(FILE))
		t.expect(has(h, "refuse.spec.luau")).toBe(true)
		for _, refusal in
			{ "refuses everything", "during a spec run", "outside refs/remotes/", "a deleted ref" }
		do
			t.expect({ refusal = refusal, listed = has(h, refusal) })
				.toEqual({ refusal = refusal, listed = false })
		end
	end)
end)
