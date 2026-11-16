--!strict
-- Session: the pick intent and the frame's walls (f0126).
local Maze = require("@logic/Maze")
local Picks = require("@logic/Picks")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

return t.spec("Session pick", function(it)
	it("a joined player's frame has three marks and no holes", function()
		local s = Session.new(classic, 7)
		Session.join(s, "a")
		local f = Session.frame(s, "a")
		t.expect(f.walls ~= nil).toBe(true)
		local walls = f.walls :: Session.Walls
		t.expect(#walls.opened).toBe(0)
		t.expect(#walls.marked).toBe(Picks.MARKED)
		t.expect(f.pick).toBe(nil)
		t.expect(f.boon).toBe(nil)
	end)

	it("submit accepts the pick string and refuses look-alikes", function()
		local s = Session.new(classic, 7)
		Session.join(s, "a")
		t.expect((Session.submit(s, "a", Picks.INTENT))).toBe(true)
		t.expect((Session.submit(s, "a", "pick"))).toBe(false)
	end)

	it("the same seed marks the same walls", function()
		local function marks(seed: number)
			local s = Session.new(classic, seed)
			Session.join(s, "a")
			return (Session.frame(s, "a").walls :: Session.Walls).marked
		end
		t.expect(marks(11)).toEqual(marks(11))
		local function key(list: { { x: number, y: number } }): string
			local parts = {}
			for _, tile in list do
				table.insert(parts, `{tile.x},{tile.y}`)
			end
			return table.concat(parts, ";")
		end
		local differs = false
		for seed = 12, 20 do
			if key(marks(seed)) ~= key(marks(11)) then
				differs = true
			end
		end
		t.expect(differs).toBe(true)
	end)
end)
