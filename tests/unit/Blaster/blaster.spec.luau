--!strict
-- Blaster extras the acceptance specs don't pin.
local Blaster = require("@logic/Blaster")
local t = require("@tests/lib/t")

return t.spec("Blaster extras", function(it)
	it("a seed that is not a number's whole value still gives a working generator", function()
		for _, seed in { 0, -5, 2.5, 0 / 0, math.huge } do
			local b = Blaster.new(seed)
			t.expect(b.rng >= 1 and b.rng < 2147483647).toBe(true)
			Blaster.drop(b)
			t.expect(b.rng >= 1 and b.rng < 2147483647).toBe(true)
		end
	end)

	it("the intents table is frozen", function()
		t.expect(function()
			(Blaster.INTENTS :: any).N = "x"
		end).toThrow()
	end)
end)
