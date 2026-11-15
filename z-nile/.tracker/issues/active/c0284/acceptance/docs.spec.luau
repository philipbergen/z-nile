--!strict
-- c0284 AC6: zz-rules (the board row of the commands table) and the README name the board's Provenance section.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0284 docs", function(it)
	it("zz-rules and the README name the Provenance section", function()
		local rules = fs.readFile(`{root}/z-nile/skills/zz-rules/SKILL.md`)
		t.expect(has(rules, "its Provenance (the entries `./zn who` prints for it")).toBe(true)
		local readme = fs.readFile(`{root}/z-nile/README.md`)
		t.expect(has(readme, "lists its Provenance, the same entries `./zn who` prints")).toBe(true)
	end)
end)
