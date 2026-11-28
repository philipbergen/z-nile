--!strict
-- Formation unit specs: single-column extent and all four corner alien boxes.
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

	it("returns exact boxes for all four corner aliens", function()
		local f = Formation.new(Formation.CLASSIC, 120)
		-- f.x = (224 - ((11 - 1) * 16 + 12)) // 2 = 26, f.d = 120
		local x0, d0, x1, d1 = Formation.box(f, 1, 1)
		t.expect({ x0, d0, x1, d1 }).toEqual({ 26, 120, 38, 128 })

		local rx0, rd0, rx1, rd1 = Formation.box(f, 1, 11)
		t.expect({ rx0, rd0, rx1, rd1 }).toEqual({ 186, 120, 198, 128 })

		local bx0, bd0, bx1, bd1 = Formation.box(f, 5, 1)
		t.expect({ bx0, bd0, bx1, bd1 }).toEqual({ 26, 184, 38, 192 })

		local brx0, brd0, brx1, brd1 = Formation.box(f, 5, 11)
		t.expect({ brx0, brd0, brx1, brd1 }).toEqual({ 186, 184, 198, 192 })
	end)
end)
