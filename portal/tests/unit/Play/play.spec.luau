--!strict
local Play = require("@logic/Play")
local t = require("@tests/lib/t")

return t.spec("Play", function(it)
	it("a held play goes at once", function()
		t.expect(Play.decide({ free = false, plays = 1 }, nil, "live", 0)).toBe("go")
	end)
end)
