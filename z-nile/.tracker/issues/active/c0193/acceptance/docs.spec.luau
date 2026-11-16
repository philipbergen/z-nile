--!strict
-- c0193 AC8: the rule is restated where the rules are read: zz-arch's ninth rule and zz-test's hostile-inputs bullet
-- name the same checks. (The lesson's own text is pinned by check.sh at AC9, not here: it is the paragraph that c0181
-- turns into a field, and a promoted spec must not block that.)
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

-- the files and calls every restatement names
local NAMES = {
	"z-nile/engine/scan.luau",
	"z-nile/tests/lib/loops.luau",
	"z-nile/tests/lib/scanners.luau",
	"z-nile/tests/lib/hostile.luau",
}

return t.spec("c0193 the scanning-loop rule is restated where it is read", function(it)
	it(
		"the architecture skill's ninth rule says every scanning loop advances or fails closed, and names its checks",
		function()
			local s = read("z-nile/skills/zz-arch/SKILL.md")
			t.expect(has(s, "9. **Every scanning loop advances on every pass, or fails closed.**")).toBe(true)
			local rule = string.match(s, "\n9%. %*%*Every scanning loop[^\n]*") or ""
			for _, n in NAMES do
				t.expect(`{n} {has(rule, n)}`).toBe(`{n} true`)
			end
			t.expect(has(rule, "scan.advance")).toBe(true)
			t.expect(has(rule, "a loop that reads text is never proven, always listed and swept")).toBe(true)
			t.expect(has(s, "the ninth by `z-nile/tests/acceptance/c0193/tree.spec.luau`")).toBe(true)
		end
	)

	it("the testing skill tells spec writers to sweep a text scanner over hostile texts", function()
		local s = read("z-nile/skills/zz-test/SKILL.md")
		local line = string.match(s, "\n%- %*%*Hostile inputs%.%*%*[^\n]*") or ""
		t.expect(line ~= "").toBe(true)
		t.expect(has(line, "hostile.finishes")).toBe(true)
		t.expect(has(line, "z-nile/tests/lib/hostile.luau")).toBe(true)
		t.expect(has(line, "z-nile/tests/lib/scanners.luau")).toBe(true)
	end)
end)
