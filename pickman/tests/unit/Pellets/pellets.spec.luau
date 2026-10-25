--!strict
-- Pellets: API cases beyond the acceptance spec.
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local t = require("@tests/lib/t")

local TINY = Maze.parse({ "#####", "#.oP#", "#####" }, "tiny")

return t.spec("Pellets extras", function(it)
	it("counts what a maze holds and what is left", function()
		local p = Pellets.new(TINY)
		t.expect(Pellets.total(p)).toBe(2)
		Pellets.eat(p, { x = 1, y = 1 })
		t.expect(Pellets.remaining(p)).toBe(1)
		t.expect(Pellets.total(p)).toBe(2)
	end)

	it("lists the tiles that are left", function()
		local p = Pellets.new(TINY)
		Pellets.eat(p, { x = 2, y = 1 })
		t.expect(Pellets.tiles(p)).toEqual({ { x = 1, y = 1 } })
	end)

	it("slots list the layout's pellets in row-major order", function()
		t.expect(Pellets.slots(TINY))
			.toEqual({ { x = 1, y = 1, kind = "pellet" }, { x = 2, y = 1, kind = "power" } })
	end)

	it("encode and decode round-trip what is left", function()
		local p = Pellets.new(TINY)
		t.expect(Pellets.encode(p)).toBe("D")
		Pellets.eat(p, { x = 2, y = 1 })
		t.expect(Pellets.decode(TINY, Pellets.encode(p))).toEqual({ true, false })
	end)

	it("decode refuses a code for another maze size", function()
		t.expect(function()
			Pellets.decode(TINY, "DD")
		end).toThrow("pellets:")
	end)
end)
