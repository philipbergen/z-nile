--!strict
-- c0155 E5: a compaction rewrites every id narrowed.spec names (run from the repository root:
-- lune run pickman/.tracker/issues/c0155/experiments/E5-compaction.luau)
local fs = require("@lune/fs")
local ids = require("../../../../../z-nile/engine/ids")
local text = fs.readFile("pickman/.tracker/issues/c0155/acceptance/narrowed.spec.luau")
local out = ids.rewritePaths(text, { f0110 = "f0901", f0146 = "f0902" }, { "pickman" })
local function count(s: string, needle: string): number
	local n, i = 0, 1
	while true do
		local a, b = string.find(s, needle, i, true)
		if not a then
			return n
		end
		n += 1
		i = (b :: number) + 1
	end
end
print("before", count(text, "tests/acceptance/f0110"), count(text, "tests/acceptance/f0146"))
print("after old", count(out, "tests/acceptance/f0110"), count(out, "tests/acceptance/f0146"))
print("after new", count(out, "tests/acceptance/f0901"), count(out, "tests/acceptance/f0902"))
