--!strict
-- f0109: game-design.md records the decisions (Inky's colour and the edible walls) and no longer asks for Inky's
-- colour; it keeps the fact f0110 relies on, that the user sees (0, 255, 255) as white.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

return t.spec("f0109 the game design records the colours", function(it)
	it(
		"the decision gives lemon Inky, the green, the power timer, the flash and the gold marked walls",
		function()
			local text = fs.readFile(".tracker/game-design.md")
			local row = string.match(text, "\n[^\n]*Inky's colour and the edible walls[^\n]*") or ""
			t.expect(row ~= "").toBe(true)
			for _, want in
				{ "f0109", "(230, 255, 0)", "(12, 74, 12)", "power timer", "flash", "gold", "(0, 255, 255)" }
			do
				t.expect(string.find(row, want, 1, true) ~= nil).toBe(true)
			end
		end
	)

	it("the Open questions no longer ask for Inky's colour", function()
		local text = fs.readFile(".tracker/game-design.md")
		t.expect((string.find(text, "a new colour is wanted but not chosen", 1, true))).toBe(nil)
	end)
end)
