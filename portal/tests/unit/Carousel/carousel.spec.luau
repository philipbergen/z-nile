--!strict
local Carousel = require("@logic/Carousel")
local t = require("@tests/lib/t")

return t.spec("Carousel", function(it)
	it("wraps round", function()
		t.expect(Carousel.step(Carousel.new(4), -1).index).toBe(4)
	end)
end)
