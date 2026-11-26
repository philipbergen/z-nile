--!strict
-- f0235 AC1: a power pellet's beacon, by View's numbers. It stands on the pellet's tile centre, a square pillar
-- View.BEACON.width wide from the pellet's centre (View.PELLET.height) up to View.BEACON.top; it rises at least 8
-- studs over the wall tops and 4 over the ghosts' heads, and at least 1 stud over the eye at a jump's top (so its
-- tip stands against the sky when the player looks level). Every point of it above the walls is in plain sight of
-- any eye above the walls: a straight line between two points both above the wall tops never dips under them.
-- Measured on the classic maze from a jump's top (eyeHeight + Hop.RISE) at the farthest pair of a walkable tile and
-- a power pellet, the part over the walls is at least 6 px tall and 1.5 px wide on the shortest screen pickman
-- plays on (320 px tall, View.SCALE.fieldOfView vertical), looking level at it.
local Hop = require("@logic/Hop")
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local m = Maze.layout("classic")
local TILE = View.SCALE.tileStuds
local SHORT_SCREEN = 320 -- px: the shortest screen the touch layout is laid out for (R0012, f0110)

local function powerSlots(): { Pellets.Slot }
	local out: { Pellets.Slot } = {}
	for _, slot in Pellets.slots(m) do
		if slot.kind == "power" then
			table.insert(out, slot)
		end
	end
	return out
end

local function beacon(slot: Pellets.Slot): any
	return (View :: any).beacon(slot)
end

return t.spec("f0235 a power pellet's beacon", function(it)
	it("the classic maze has power pellets to mark", function()
		t.expect(#powerSlots()).toBe(4)
	end)

	it(
		"stands on the pellet's tile centre, a pillar BEACON.width wide from the pellet's centre to BEACON.top",
		function()
			local B = (View :: any).BEACON
			t.expect(type(B)).toBe("table")
			for _, slot in powerSlots() do
				local b = beacon(slot)
				t.expect(b.x).toBe(slot.x * TILE)
				t.expect(b.z).toBe(slot.y * TILE)
				t.expect(b.width).toBe(B.width)
				t.expect(b.y - b.height / 2).toBeNear(View.PELLET.height, 1e-9)
				t.expect(b.y + b.height / 2).toBeNear(B.top, 1e-9)
			end
		end
	)

	it("is about as wide as the power pellet, and no wider than half a corridor", function()
		local w = (View :: any).BEACON.width
		t.expect(w >= View.PELLET.power * 0.75).toBe(true)
		t.expect(w <= TILE / 2).toBe(true)
	end)

	it("lets the pellet show through it, and is not invisible", function()
		local tr = (View :: any).BEACON.transparency
		t.expect(tr > 0 and tr <= 0.5).toBe(true)
	end)

	it("rises 8 studs over the walls, 4 over the ghosts and past the eye at a jump's top", function()
		local top = (View :: any).BEACON.top
		t.expect(top >= View.SCALE.wallHeight + 8).toBe(true)
		t.expect(top >= View.GHOST.height + 4).toBe(true)
		t.expect(top >= View.SCALE.eyeHeight + Hop.RISE + 1).toBe(true)
	end)

	it("from a jump's top its part over the walls is big enough to see across the classic maze", function()
		local B = (View :: any).BEACON
		local eye = View.SCALE.eyeHeight + Hop.RISE
		local far = 0
		for y = 0, m.height - 1 do
			for x = 0, m.width - 1 do
				if Maze.passable(m, { x = x, y = y }, "player") then
					for _, slot in powerSlots() do
						local b = beacon(slot)
						local d = math.sqrt((x * TILE - b.x) ^ 2 + (y * TILE - b.z) ^ 2)
						far = math.max(far, d)
					end
				end
			end
		end
		t.expect(far > 200).toBe(true) -- the measure is taken across the maze, not next door
		local perUnit = (SHORT_SCREEN / 2) / math.tan(math.rad(View.SCALE.fieldOfView / 2))
		local tall = perUnit * ((B.top - eye) / far - (View.SCALE.wallHeight - eye) / far)
		local wide = perUnit * B.width / far
		t.expect(tall >= 6).toBe(true)
		t.expect(wide >= 1.5).toBe(true)
	end)
end)
