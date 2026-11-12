--!strict
-- c0264 AC10: no issue id has more than one row in z-nile/README.md's Roadmap table. Two PRs that each append a row
-- for one ticket would make whichever lands second red here, whatever order they land in. Reads the checkout's own
-- README as text, never writes.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local README = fs.readFile(`{ROOT}/z-nile/README.md`)

-- the lines of "### Roadmap", up to the next heading
local function roadmap(): { string }
	local out: { string } = {}
	local on = false
	for line in string.gmatch(README, "[^\n]*") do
		if line == "### Roadmap" then
			on = true
		elseif on and (string.sub(line, 1, 3) == "## " or string.sub(line, 1, 4) == "### ") then
			break
		elseif on then
			table.insert(out, line)
		end
	end
	return out
end

return t.spec("c0264 the Roadmap has one row per issue", function(it)
	it("AC10: no issue id is the issue column of two Roadmap rows", function()
		local seen: { [string]: boolean } = {}
		local rows = 0
		for _, line in roadmap() do
			local id = string.match(line, "^| .* | ([cdf]%d%d%d%d) | %a+ | *$")
			if id then
				rows += 1
				if seen[id] then
					error(`two Roadmap rows for {id}`, 0)
				end
				seen[id] = true
			end
		end
		t.expect(rows >= 8).toBe(true)
	end)
end)
