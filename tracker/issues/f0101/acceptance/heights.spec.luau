--!strict
-- f0101 AC2: the heights the spy hop is built on. The walls are a stud lower (9, from 10); the ghosts keep the
-- walls' old height (10) and the 6-stud width; the eye stays at 4, below the wall top, and the top of a jump is above
-- both the walls and the ghosts. Hop.CLEARANCE, the rise that makes the player airborne, is exactly the eye's climb
-- to the wall top. Pellets stay below the eye and the walls.
local Hop = require("@logic/Hop")
local View = require("@logic/View")
local t = require("@tests/lib/t")

return t.spec("f0101 heights", function(it)
	it("the walls are 9 studs tall, the ghosts 10 by 6, the eye 4", function()
		t.expect(View.SCALE.wallHeight).toBe(9)
		t.expect(View.SCALE.eyeHeight).toBe(4)
		t.expect(View.SCALE.tileStuds).toBe(8)
		t.expect(View.GHOST.height).toBe(10)
		t.expect(View.GHOST.width).toBe(6)
		t.expect(function()
			(View.GHOST :: any).height = 7
		end).toThrow()
	end)

	it(
		"a ghost stands over the walls, the standing eye is below their top, and a jump's top is above both",
		function()
			local s = View.SCALE
			t.expect(View.GHOST.height > s.wallHeight).toBe(true)
			t.expect(s.eyeHeight < s.wallHeight).toBe(true)
			t.expect(s.eyeHeight + Hop.RISE > View.GHOST.height).toBe(true)
			t.expect(View.GHOST.width < s.tileStuds).toBe(true)
		end
	)

	it("the player is airborne exactly while the eye is over the wall tops", function()
		t.expect(Hop.CLEARANCE).toBe(View.SCALE.wallHeight - View.SCALE.eyeHeight)
	end)

	it("every pellet is drawn below the eye and the walls", function()
		local p = View.PELLET
		for _, d in { p.pellet, p.power } do
			t.expect(p.height + d / 2 < View.SCALE.wallHeight).toBe(true)
		end
		t.expect(p.height < View.SCALE.eyeHeight).toBe(true)
	end)
end)
