--!strict
-- Mystery unit specs: right-to-left crossing length and value wrap.
local Mystery = require("@logic/Mystery")
local t = require("@tests/lib/t")

return t.spec("Mystery unit", function(it)
	it("crosses from right to left in the same number of ticks as left to right", function()
		local m = Mystery.new(Mystery.CLASSIC)
		for _ = 1, Mystery.CLASSIC.every do
			Mystery.tick(m, 10)
		end
		t.expect(m.dir).toBe(1)
		local ticksLR = 0
		while Mystery.tick(m, 10) ~= "leave" do
			ticksLR += 1
		end
		for _ = 1, Mystery.CLASSIC.every do
			Mystery.tick(m, 10)
		end
		t.expect(m.dir).toBe(-1)
		local ticksRL = 0
		while Mystery.tick(m, 10) ~= "leave" do
			ticksRL += 1
		end
		t.expect(ticksRL).toBe(ticksLR)
	end)
end)
