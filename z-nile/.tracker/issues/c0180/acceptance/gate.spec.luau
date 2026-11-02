--!strict
-- c0180: the gate's own selection loads the records, and c0165's fingerprints never do. Every line of z-nile/check.sh
-- that runs z-nile/affected to select specs passes --recorded (a line asking for --gate-projects or --graph-only
-- selects nothing by records), and z-nile/specs.luau, which computes the fingerprints, names neither context.commands
-- nor --recorded, so a record a gate run writes never changes a fingerprint. Runs from z-nile's home, read only.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function code(text: string): { string }
	local out = {}
	for line in string.gmatch(text, "[^\n]+") do
		if not string.match(line, "^%s*#") and not string.match(line, "^%s*%-%-") then
			table.insert(out, line)
		end
	end
	return out
end

return t.spec("c0180 the gate selects by records and fingerprints never read them", function(it)
	it("every selection call of z-nile/check.sh passes --recorded", function()
		local selecting = 0
		for _, line in code(fs.readFile("check.sh")) do
			if
				string.find(line, "z-nile/affected", 1, true)
				and not string.find(line, "--gate-projects", 1, true)
				and not string.find(line, "--graph-only", 1, true)
			then
				selecting += 1
				t.expect(`{line}: {string.find(line, "--recorded", 1, true) ~= nil}`).toBe(`{line}: true`)
			end
		end
		t.expect(selecting > 0).toBe(true)
	end)

	it("z-nile/specs.luau never loads the records", function()
		local text = table.concat(code(fs.readFile("specs.luau")), "\n")
		t.expect((string.find(text, "context.commands", 1, true))).toBe(nil)
		t.expect((string.find(text, "--recorded", 1, true))).toBe(nil)
		t.expect(#text > 0).toBe(true)
	end)
end)
