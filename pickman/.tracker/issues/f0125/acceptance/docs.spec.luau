--!strict
-- f0125 AC6: game-design.md's Slower-ghosts row records the user's factor and where it lives.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

return t.spec("f0125 the game design records the factor", function(it)
	it("the Slower-ghosts row gives the user's factor, f0125, and Session.GAME_CONFIG.ghostTuning", function()
		local text = fs.readFile(".tracker/game-design.md")
		local row = string.match(text, "\n| Slower ghosts[^\n]*") or ""
		t.expect(row ~= "").toBe(true)
		t.expect(string.find(row, "f0125", 1, true) ~= nil).toBe(true)
		t.expect(string.find(row, "Session.GAME_CONFIG.ghostTuning", 1, true) ~= nil).toBe(true)
		t.expect(string.find(row, "1 / 1.1", 1, true) ~= nil).toBe(true)
		t.expect((string.find(row, "ships at the classic 1 until the user gives the factor", 1, true)))
			.toBe(nil)
	end)
end)
