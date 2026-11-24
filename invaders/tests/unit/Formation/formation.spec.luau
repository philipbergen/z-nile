--!strict
-- Formation unit specs: single-column extent and corner alien boxes.
local Formation = require("@logic/Formation")
local t = require("@tests/lib/t")

return t.spec("Formation unit", function(it)
	it("computes extent when only one column remains", function()
		local f = Formation.new(Formation.CLASSIC, 120)
		for r = 1, 5 do
			for c = 1, 11 do
				if c ~= 6 then
					Formation.kill(f, r, c)
				end
			end
		end
		local x0, x1, d0 = Formation.extent(f)
		local bx0, bd0, bx1 = Formation.box(f, 1, 6)
		t.expect(x0).toBe(bx0)
		t.expect(x1).toBe(bx1)
		t.expect(d0).toBe(bd0)
	end)

	it("returns exact boxes for corner aliens", function()
		local f = Formation.new(Formation.CLASSIC, 120)
		local x0, d0, x1, d1 = Formation.box(f, 1, 1)
		t.expect(x1 - x0).toBe(Formation.CLASSIC.width)
		t.expect(d1 - d0).toBe(Formation.CLASSIC.depth)
		local bx0, bd0, bx1, bd1 = Formation.box(f, 5, 11)
		t.expect(bx1 > x1 and bd1 > d1).toBe(true)
		t.expect(bx1 - bx0).toBe(Formation.CLASSIC.width)
		t.expect(bd1 - bd0).toBe(Formation.CLASSIC.depth)
	end)
end)
