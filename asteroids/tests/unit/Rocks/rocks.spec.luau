--!strict
-- Rocks unit specs: rock sizes, points, and splitting.
local Field = require("@logic/Field")
local Rocks = require("@logic/Rocks")
local t = require("@tests/lib/t")

local function draw(n: number): number
	return if n >= 1 then 1 else error("bad n")
end

return t.spec("Rocks unit", function(it)
	it("splits large -> 2 medium -> 2 small -> none", function()
		local r = Rocks.launch(1, "large", 100, 100, draw)
		local med = Rocks.split(r, 2, draw)
		t.expect(#med).toBe(2)
		t.expect(med[1].size).toBe("medium")
		local small = Rocks.split(med[1], 4, draw)
		t.expect(#small).toBe(2)
		t.expect(small[1].size).toBe("small")
		local none = Rocks.split(small[1], 6, draw)
		t.expect(#none).toBe(0)
		Rocks.move(r, Field.CLASSIC)
	end)
end)
