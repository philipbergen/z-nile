--!strict
-- Barriers unit specs: blockAt on each bunker's four corners and count.
local Barriers = require("@logic/Barriers")
local t = require("@tests/lib/t")

return t.spec("Barriers unit", function(it)
	it("finds present blocks on all four corners of every bunker", function()
		local b = Barriers.new(Barriers.CLASSIC)
		local lay = Barriers.CLASSIC
		t.expect(Barriers.count(b)).toBe(4 * lay.cols * lay.rows)
		for idx, left in lay.lefts do
			local right = left + lay.cols * lay.block - 1
			local far = lay.near + lay.rows * lay.block - 1
			local b1, c1, r1 = Barriers.blockAt(b, left, lay.near)
			t.expect(b1).toBe(idx)
			t.expect(c1).toBe(1)
			t.expect(r1).toBe(1)
			local b2, c2, r2 = Barriers.blockAt(b, right, far)
			t.expect(b2).toBe(idx)
			t.expect(c2).toBe(lay.cols)
			t.expect(r2).toBe(lay.rows)
		end
	end)
end)
