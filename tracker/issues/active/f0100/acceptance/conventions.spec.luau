--!strict
-- f0100 AC4: heading conventions every other feature relies on.
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

return t.spec("f0100 heading conventions", function(it)
	it("lists headings clockwise from north", function()
		t.expect(Maze.HEADINGS).toEqual({ "N", "E", "S", "W" })
	end)

	it("north is up the text (-y) and east is right (+x)", function()
		local want: { [string]: { number } } = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }
		for h, d in want do
			local dx, dy = Maze.delta(h :: Maze.Heading)
			t.expect({ dx, dy }).toEqual(d)
		end
	end)

	it("left and right are quarter turns, opposite is a half turn", function()
		t.expect(Maze.left("N")).toBe("W")
		t.expect(Maze.left("W")).toBe("S")
		t.expect(Maze.left("S")).toBe("E")
		t.expect(Maze.left("E")).toBe("N")
		t.expect(Maze.right("N")).toBe("E")
		t.expect(Maze.right("E")).toBe("S")
		t.expect(Maze.right("S")).toBe("W")
		t.expect(Maze.right("W")).toBe("N")
		local all: { Maze.Heading } = { "N", "E", "S", "W" }
		for _, h: Maze.Heading in all do
			t.expect(Maze.opposite(h)).toBe(Maze.left(Maze.left(h)))
			t.expect(Maze.right(Maze.left(h))).toBe(h)
		end
	end)
end)
