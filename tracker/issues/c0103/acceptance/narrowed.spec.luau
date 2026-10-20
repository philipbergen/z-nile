--!strict
-- c0103 AC1: the promoted key map is narrowed, not replaced.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local PATH = "tests/acceptance/f0014/keys.spec.luau"

return t.spec("c0103 narrowed key map", function(it)
	it(
		"the nine mappings remain, the count is not exactly 9, Q is not listed, and Fire and Drop are allowed",
		function()
			local src = fs.readFile(PATH)
			t.expect(string.find(src, 'W = "Forward"', 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, 'Space = "Snap"', 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "toBe(9)", 1, true)).toBe(nil)
			t.expect(string.find(src, '"Q"', 1, true)).toBe(nil)
			t.expect(string.find(src, 'action == "Fire"', 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, 'action == "Drop"', 1, true) ~= nil).toBe(true)
			t.expect(string.find(src, "Movement.isIntent(action)", 1, true) ~= nil).toBe(true)
		end
	)
end)
