--!strict
local Pairing = require("@logic/Pairing")
local t = require("@tests/lib/t")

return t.spec("Pairing", function(it)
	it("the second player in a line is paired with the first", function()
		local q = Pairing.join(Pairing.new(), "invaders", "1")
		local _, pair = Pairing.join(q, "invaders", "2")
		t.expect(pair).toEqual({ "1", "2" })
	end)
end)
