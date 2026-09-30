--!strict
-- Movement defaults and small behaviours the acceptance specs don't pin.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local t = require("@tests/lib/t")

return t.spec("Movement extras", function(it)
	it("the default config is level 1: 7.5 tiles/s at 30 Hz, a 0.8 s turn buffer", function()
		t.expect(Movement.DEFAULT_CONFIG).toEqual({ speed = 30, turnBufferTicks = 24 })
		t.expect(Movement.UNITS / Movement.DEFAULT_CONFIG.speed).toBe(4)
	end)

	it("lists the four intents", function()
		t.expect(Movement.INTENTS).toEqual({ "Left", "Right", "Back", "Forward" })
	end)

	it("the config and intent tables are frozen", function()
		t.expect(function()
			(Movement.DEFAULT_CONFIG :: any).speed = 1
		end).toThrow()
		t.expect(function()
			(Movement.INTENTS :: any)[1] = "Back"
		end).toThrow()
	end)

	it("step reports no events while cruising inside a tile", function()
		local m = Maze.parse({ "##########", "#P.......#", "##########" })
		local s = Movement.spawn(m, "E")
		t.expect(Movement.step(m, s, {}, Movement.DEFAULT_CONFIG)).toEqual({})
	end)

	it("a spawn facing a wall is stopped and stays put", function()
		local m = Maze.parse({ "#####", "#P..#", "#####" })
		local s = Movement.spawn(m)
		t.expect(Movement.step(m, s, {}, Movement.DEFAULT_CONFIG)).toEqual({})
		t.expect({ Movement.position(s) }).toEqual({ 1, 1 })
	end)
end)
