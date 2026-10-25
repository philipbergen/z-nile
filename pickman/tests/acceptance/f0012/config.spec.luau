--!strict
-- f0110 AC8: spawning, the default config, and config validation.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local t = require("@tests/lib/t")

return t.spec("f0110 spawn and config", function(it)
	it("spawns at the maze's spawn tile, facing west by default, moving if west is open", function()
		local classic = Maze.layout("classic")
		local s = Movement.spawn(classic)
		t.expect({ Movement.position(s) }).toEqual({ 13, 23 })
		t.expect(s.heading).toBe("W")
		t.expect(s.moving).toBe(true)
		local walled = Maze.parse({ "#####", "#P..#", "#####" })
		local w = Movement.spawn(walled)
		t.expect(w.heading).toBe("W")
		t.expect(w.moving).toBe(false)
		local e = Movement.spawn(walled, "E")
		t.expect(e.heading).toBe("E")
		t.expect(e.moving).toBe(true)
	end)

	it("spawned states are independent", function()
		local m = Maze.parse({ "#####", "#P..#", "#####" })
		local a = Movement.spawn(m, "E")
		local b = Movement.spawn(m, "E")
		Movement.step(m, a, {}, Movement.DEFAULT_CONFIG)
		t.expect({ Movement.position(b) }).toEqual({ 1, 1 })
		t.expect(m.spawn).toEqual({ x = 1, y = 1 })
	end)

	it("the default config is valid", function()
		Movement.validateConfig(Movement.DEFAULT_CONFIG)
	end)

	it("rejects a speed that is not a whole number of units in 1..UNITS", function()
		for _, speed in { 0, -30, 1.5, Movement.UNITS + 1 } do
			t.expect(function()
				Movement.validateConfig({ speed = speed, turnBufferTicks = 24 })
			end).toThrow("speed")
		end
		Movement.validateConfig({ speed = Movement.UNITS, turnBufferTicks = 24 })
		Movement.validateConfig({ speed = 1, turnBufferTicks = 1 })
	end)

	it("rejects a turn buffer shorter than one step or fractional", function()
		for _, n in { 0, -1, 2.5 } do
			t.expect(function()
				Movement.validateConfig({ speed = 30, turnBufferTicks = n })
			end).toThrow("turnBufferTicks")
		end
	end)

	it("recognises exactly the four intents", function()
		for _, i in { "Left", "Right", "Back", "Forward" } do
			t.expect(Movement.isIntent(i)).toBe(true)
		end
		local bad: { any } = { "left", "Jump", "", 1, true, {} }
		for _, v in bad do
			t.expect(Movement.isIntent(v)).toBe(false)
		end
	end)
end)
