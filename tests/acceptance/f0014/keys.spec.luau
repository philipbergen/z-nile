--!strict
-- f0130 AC5: the key map, by Enum.KeyCode name.
local Movement = require("@logic/Movement")
local View = require("@logic/View")
local t = require("@tests/lib/t")

return t.spec("f0130 key map", function(it)
	it("maps WASD and the arrow keys to intents, and Space to snap", function()
		local want: { [string]: string } = {
			W = "Forward",
			Up = "Forward",
			A = "Left",
			Left = "Left",
			D = "Right",
			Right = "Right",
			S = "Back",
			Down = "Back",
			Space = "Snap",
		}
		for key, action in want do
			t.expect(View.action(key)).toBe(action)
		end
		local n = 0
		for _ in View.KEYS do
			n += 1
		end
		t.expect(n).toBe(9)
	end)

	it("other keys do nothing", function()
		for _, key in { "Q", "E", "w", "Return", "LeftShift", "" } do
			t.expect(View.action(key)).toBe(nil)
		end
	end)

	it("every action is a movement intent or Snap", function()
		for _, action in View.KEYS do
			t.expect(action == "Snap" or Movement.isIntent(action)).toBe(true)
		end
	end)
end)
