--!strict
-- c0134 AC1: c0131's accept.spec.luau opens with a header that describes what that file tests (AC1: the ref guard
-- accepts an empty transaction from a check.sh flow, and still accepts a fetch that creates or moves a
-- remote-tracking ref), and leaves the refusals to refuse.spec.luau (AC2), which tests them. Reads the file only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local FILE = `{TOP}/z-nile/tests/acceptance/c0131/accept.spec.luau`

-- the header: the comment lines after `--!strict`, up to the first line that is not a comment
local function header(text: string): string
	local out: { string } = {}
	local first = true
	for line in string.gmatch(text, "([^\n]*)\n") do
		if first then
			first = false
		elseif string.sub(line, 1, 2) == "--" then
			table.insert(out, line)
		else
			break
		end
	end
	return table.concat(out, "\n")
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0134 accept.spec's header describes what it tests", function(it)
	it("the header reader takes the comment block after --!strict and stops at the code", function()
		local h = header("--!strict\n-- one\n-- two\nlocal x = 1\n-- not header\n")
		t.expect(h).toBe("-- one\n-- two")
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
