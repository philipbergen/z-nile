--!strict
local Card = require("@logic/Card")
local t = require("@tests/lib/t")

return t.spec("Card", function(it)
	it("shows coming soon for a place that is not published", function()
		local b = Card.badge({ published = false }, { struck = "a", price = "b", sale = "c" }, Card.WORDS)
		t.expect(b.text).toBe(Card.WORDS.soon)
	end)
end)
