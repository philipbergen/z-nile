--!strict
-- f0104 AC1: the desktop key map (user, 2026-10-17). W A S D move as before; Space jumps (f0101); E fires (f0100);
-- the arrow keys look (up, down, left, right); no key snaps the look any more. Ten keys, frozen.
-- Narrowed by c0150: the ten bindings are still pinned (through View.action and View.KEYS), but the map may hold
-- more keys, each bound to an action none of the ten use, and F is no longer required to do nothing, so f0126 can
-- bind F to the wall pick without a red main.
local Movement = require("@logic/Movement")
local View = require("@logic/View")
local t = require("@tests/lib/t")

return t.spec("f0104 key map", function(it)
	it("maps the ten keys, and may map more", function()
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
		local taken: { [string]: boolean } = {}
		for key, action in want do
			t.expect(View.action(key)).toBe(action)
			t.expect(View.KEYS[key]).toBe(action)
			taken[action] = true
		end
		-- a key beyond the ten binds an action of its own: none of the ten's, and not a movement intent
		local n = 0
		for key, action in View.KEYS do
			n += 1
			if want[key] == nil then
				t.expect(taken[action]).toBe(nil)
				t.expect(Movement.isIntent(action)).toBe(false)
			end
		end
		t.expect(n >= 10).toBe(true)
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
		for _, key in { "Q", "e", "space", "w", "Return", "LeftShift", "KeypadEnter", "" } do
			t.expect(View.action(key)).toBe(nil)
		end
	end)

	it("the map is frozen", function()
		t.expect(function()
			(View.KEYS :: any).Q = "Fire"
		end).toThrow()
	end)
end)
