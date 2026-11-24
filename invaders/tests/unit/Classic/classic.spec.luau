--!strict
-- Classic unit specs: extra input keys ignored and aimed column tie-break.
local Classic = require("@logic/Classic")
local t = require("@tests/lib/t")

return t.spec("Classic unit", function(it)
	it("ignores extra keys in input and steps deterministically", function()
		local g = Classic.new(7)
		local startX = g.cannon
		local input: any = { move = 1, fire = false, bogus = 999 }
		Classic.step(g, input)
		t.expect(g.cannon).toBe(startX + 1)
		t.expect(g.shot).toBe(nil)
	end)

	it("computes waveDepth and reloadTicks monotonically", function()
		t.expect(Classic.waveDepth(1)).toBe(120)
		t.expect(Classic.waveDepth(9)).toBe(120)
		t.expect(Classic.reloadTicks(0)).toBe(48)
		t.expect(Classic.reloadTicks(3000)).toBe(7)
	end)
end)
