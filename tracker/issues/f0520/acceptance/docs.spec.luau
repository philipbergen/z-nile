--!strict
-- f0520 AC3: the product decision is recorded where the game's design lives.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local design = fs.readFile("tracker/game-design.md")

local function has(needle: string): boolean
	return string.find(design, needle, 1, true) ~= nil
end

return t.spec("f0520 game-design records the half speed", function(it)
	it("says level 1 is 3.75 tiles/s in real time, at half speed", function()
		t.expect(has("3.75 tiles/s")).toBe(true)
		t.expect(has("half speed")).toBe(true)
	end)

	it(
		"says the rules still count 30 ticks per game second and the server steps 15 times a real second",
		function()
			t.expect(has("30 ticks per game second")).toBe(true)
			t.expect(has("15 steps per real second")).toBe(true)
			t.expect(has("STEP_RATE")).toBe(true)
		end
	)
end)
