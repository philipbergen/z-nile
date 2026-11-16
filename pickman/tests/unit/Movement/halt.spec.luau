--!strict
-- Movement: halting and resuming for a wall pick (f0126).
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local t = require("@tests/lib/t")

return t.spec("Movement halt", function(it)
	local m = Maze.parse({ "#######", "#P....#", "#######" })

	it("nextCentre is 0 and the own tile on a centre, else the distance to the tile ahead", function()
		local s = Movement.spawn(m, "E")
		local d, tile = Movement.nextCentre(m, s)
		t.expect(d).toBe(0)
		t.expect(tile).toEqual({ x = 1, y = 1 })
		Movement.step(m, s, {}, { speed = 30, turnBufferTicks = 24 })
		d, tile = Movement.nextCentre(m, s)
		t.expect(d).toBe(Movement.UNITS - 30)
		t.expect(tile).toEqual({ x = 2, y = 1 })
	end)

	it("a halted player stays put until resumed, then moves on", function()
		local s = Movement.spawn(m, "E")
		Movement.halt(s)
		for _ = 1, 10 do
			Movement.step(m, s, {}, Movement.DEFAULT_CONFIG)
		end
		t.expect({ Movement.position(s) }).toEqual({ 1, 1 })
		Movement.resume(m, s)
		for _ = 1, 4 do
			Movement.step(m, s, {}, Movement.DEFAULT_CONFIG)
		end
		t.expect({ Movement.position(s) }).toEqual({ 2, 1 })
	end)

	it("resume facing a wall leaves the player stopped", function()
		local s = Movement.spawn(m, "W")
		Movement.halt(s)
		Movement.resume(m, s)
		Movement.step(m, s, {}, Movement.DEFAULT_CONFIG)
		t.expect({ Movement.position(s) }).toEqual({ 1, 1 })
	end)

	it("halt refuses a player between centres", function()
		local s = Movement.spawn(m, "E")
		Movement.step(m, s, {}, Movement.DEFAULT_CONFIG)
		t.expect(function()
			Movement.halt(s)
		end).toThrow("between")
	end)
end)
