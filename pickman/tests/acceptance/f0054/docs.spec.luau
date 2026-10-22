--!strict
-- f0520 AC3: the product decision is recorded where the game's design lives.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local design = fs.readFile(".tracker/game-design.md")

local function has(needle: string): boolean
	return string.find(design, needle, 1, true) ~= nil
end

return t.spec("f0520 game-design records the half speed", function(it)
	it("says level 1 is 3.75 tiles/s in real time, at half speed", function()
		t.expect(has("3.75 tiles/s")).toBe(true)
		t.expect(has("half speed")).toBe(true)
	end)

	it("says all the document's durations and speeds are game time", function()
		t.expect(has("All durations and speeds in this document are game time")).toBe(true)
	end)

	it(
		"never states a bare real-time number for what is in game time: 7.5 tiles/s, 0.8 s and the 2 s pause carry 'game'",
		function()
			for line in string.gmatch(design, "[^\n]+") do
				for _, needle in { "7.5 tiles/s", "0.8 s", "2 s before play" } do
					if string.find(line, needle, 1, true) then
						t.expect(string.find(line, "game", 1, true) ~= nil).toBe(true)
					end
				end
			end
		end
	)

	it(
		"records that turn smoothing and mouse look stay in real time as the author's choice, with the input latency",
		function()
			t.expect(has("TURN_SECONDS")).toBe(true)
			t.expect(has("user may veto")).toBe(true)
			t.expect(has("67 ms")).toBe(true)
		end
	)

	it(
		"says the rules still count 30 ticks per game second and the server steps 15 times a real second",
		function()
			t.expect(has("30 ticks per game second")).toBe(true)
			t.expect(has("15 steps per real second")).toBe(true)
			t.expect(has("STEP_RATE")).toBe(true)
		end
	)
end)
