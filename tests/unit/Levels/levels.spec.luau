--!strict
-- Levels: a few row lookups beyond the acceptance table.
local Levels = require("@logic/Levels")
local t = require("@tests/lib/t")

return t.spec("Levels extras", function(it)
	it("level 1 is the base speed and 6 s of frightened time", function()
		t.expect(Levels.row(1).speedFactor).toBe(1)
		t.expect(Levels.row(1).frightenedSeconds).toBe(6)
		t.expect(Levels.playerSpeed(30, 1)).toBe(30)
	end)

	it("levels past the table use the last row", function()
		t.expect(Levels.row(40)).toEqual(Levels.row(Levels.COUNT))
	end)
end)
