--!strict
local Board = require("@logic/Board")
local t = require("@tests/lib/t")

return t.spec("Board", function(it)
	it("shows a dash for a row with no revives", function()
		t.expect(Board.revives(0)).toBe(Board.NONE)
	end)
end)
