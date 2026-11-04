--!strict
-- Picks: cases beyond the acceptance specs (f0126).
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Picks = require("@logic/Picks")
local t = require("@tests/lib/t")

return t.spec("Picks extras", function(it)
	-- a small maze: interior walls at (2, 2) and (3, 2), a corridor around them
	local m = Maze.parse({ "######", "#P...#", "#.##.#", "#....#", "######" })

	it("starts with no marks and no fast picks", function()
		local p = Picks.new(1)
		t.expect(#p.marked).toBe(0)
		t.expect(p.fast).toBe(0)
	end)

	it("a seed that is not a finite number still gives a usable stream", function()
		for _, seed in { 0 / 0, math.huge, -math.huge, -5, 0 } do
			local p = Picks.new(seed)
			t.expect(p.rng >= 1 and p.rng < 2147483647).toBe(true)
			t.expect(table.find(Picks.BOONS, Picks.roll(p)) ~= nil).toBe(true)
		end
	end)

	it("only the wire string is the intent", function()
		t.expect(Picks.isIntent("Pick")).toBe(true)
		t.expect(Picks.isIntent("pick")).toBe(false)
		t.expect(Picks.isIntent(nil)).toBe(false)
		t.expect(Picks.isIntent({ "Pick" })).toBe(false)
	end)

	it("marks the two interior walls of a small maze and no more", function()
		local p = Picks.new(3)
		local added = Picks.mark(p, m)
		t.expect(#added).toBe(2)
		t.expect(Picks.isMarked(p, { x = 2, y = 2 })).toBe(true)
		t.expect(Picks.isMarked(p, { x = 3, y = 2 })).toBe(true)
		t.expect(#Picks.mark(p, m)).toBe(0)
	end)

	it("unmark frees a wall to be marked again, and unmarking a wall not marked does nothing", function()
		local p = Picks.new(3)
		Picks.mark(p, m)
		Picks.unmark(p, { x = 4, y = 4 })
		t.expect(#p.marked).toBe(2)
		Picks.unmark(p, { x = 2, y = 2 })
		t.expect(Picks.isMarked(p, { x = 2, y = 2 })).toBe(false)
		t.expect(Picks.candidates(p, m)).toEqual({ { x = 2, y = 2 } })
	end)

	it("wallBeside finds nothing beside a tile with no marked neighbour", function()
		local p = Picks.new(3)
		Picks.mark(p, m)
		t.expect(Picks.wallBeside(p, m, { x = 1, y = 1 }, "E")).toBe(nil)
		t.expect(Picks.wallBeside(p, m, { x = 2, y = 1 }, "E")).toEqual({ x = 2, y = 2 })
	end)

	it("a pick is at least one step, even against a very fast ghost", function()
		t.expect(Picks.ticks(10 * Picks.PACES * Movement.UNITS, false)).toBe(1)
		t.expect(Picks.ticks(10 * Picks.PACES * Movement.UNITS, true)).toBe(1)
		t.expect(Picks.ticks(0, false)).toBe(Picks.PACES * Movement.UNITS)
	end)

	it("the tuning tables are frozen", function()
		t.expect(function()
			(Picks.BOONS :: any)[1] = "pill"
		end).toThrow()
	end)
end)
