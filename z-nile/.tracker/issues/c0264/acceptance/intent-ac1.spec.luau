--!strict
-- c0264: z-nile/README.md states the intent in its own "## Intent" section, the first `##` section, right before
-- "## How it should work". This spec: the heading order. The section's exact text is check.sh's (AC4, sequestered), so the promoted
-- specs pin structure only. Reads the checkout's own README as text, never writes.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local README = fs.readFile(`{ROOT}/z-nile/README.md`)

-- the `## ` headings, in order
local function headings(): { string }
	local out = {}
	for line in string.gmatch(README, "[^\n]+") do
		if string.sub(line, 1, 3) == "## " then
			table.insert(out, line)
		end
	end
	return out
end

return t.spec("c0264 the README states the intent (AC1)", function(it)
	it("AC1: '## Intent' is the first '##' section and '## How it should work' follows it at once", function()
		local hs = headings()
		t.expect(hs[1]).toBe("## Intent")
		t.expect(hs[2]).toBe("## How it should work")
	end)
end)
