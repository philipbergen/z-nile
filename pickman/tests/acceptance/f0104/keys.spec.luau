--!strict
-- f0104 AC1: the desktop key map (user, 2026-10-17). W A S D move as before; Space jumps (f0101); E fires (f0100);
-- the arrow keys look (up, down, left, right); no key snaps the look any more. Ten keys, frozen.
local Movement = require("@logic/Movement")
local View = require("@logic/View")
local t = require("@tests/lib/t")

return t.spec("f0104 key map", function(it)
	it("maps exactly the ten keys", function()
		local want: { [string]: string } = {
			W = "Forward",
			A = "Left",
			D = "Right",
			S = "Back",
			Space = "Jump",
			E = "Fire",
			Up = "LookUp",
			Down = "LookDown",
			Left = "LookLeft",
			Right = "LookRight",
		}
		local n = 0
		for key, action in View.KEYS do
			n += 1
			t.expect(want[key]).toBe(action)
		end
		t.expect(n).toBe(10)
		for key, action in want do
			t.expect(View.action(key)).toBe(action)
		end
	end)

	it("the arrows and Space no longer move or snap; only W A S D are movement intents", function()
		for _, key in { "Up", "Down", "Left", "Right", "Space", "E" } do
			t.expect(Movement.isIntent(View.action(key))).toBe(false)
		end
		for _, action in View.KEYS do
			t.expect(action ~= "Snap").toBe(true)
		end
	end)

	it("other keys do nothing, the old drop and fire keys included", function()
		for _, key in { "Q", "F", "e", "space", "w", "Return", "LeftShift", "KeypadEnter", "" } do
			t.expect(View.action(key)).toBe(nil)
		end
	end)

	it("the map is frozen", function()
		t.expect(function()
			(View.KEYS :: any).Q = "Fire"
		end).toThrow()
	end)
end)
