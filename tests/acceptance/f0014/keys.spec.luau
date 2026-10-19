--!strict
-- f0130 AC5: the key map, by Enum.KeyCode name.
-- Narrowed by c0103: only the movement keys W, A, S and D are pinned. The arrow keys, Space and the number of keys
-- are free to change, so the jump, fire and arrow-look bindings (f0104) can be added without a red main.
local Movement = require("@logic/Movement")
local View = require("@logic/View")
local t = require("@tests/lib/t")

return t.spec("f0130 key map", function(it)
	it("maps W, A, S and D to the movement intents", function()
		local want: { [string]: string } = {
			W = "Forward",
			A = "Left",
			D = "Right",
			S = "Back",
		}
		for key, action in want do
			t.expect(View.action(key)).toBe(action)
		end
		local n = 0
		for _ in View.KEYS do
			n += 1
		end
		t.expect(n >= 4).toBe(true)
	end)

	it("other keys do nothing", function()
		for _, key in { "w", "Return", "LeftShift", "" } do
			t.expect(View.action(key)).toBe(nil)
		end
	end)

	it("every mapped action is a name, and W, A, S and D map to movement intents", function()
		for _, action in View.KEYS do
			t.expect(type(action) == "string" and action ~= "").toBe(true)
		end
		for _, key in { "W", "A", "S", "D" } do
			t.expect(Movement.isIntent(View.action(key))).toBe(true)
		end
	end)
end)
