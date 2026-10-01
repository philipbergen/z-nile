--!strict
-- Session defaults and small behaviours the acceptance specs don't pin.
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

return t.spec("Session extras", function(it)
	it("has the designed defaults", function()
		t.expect(Session.DEFAULT_CONFIG.maxIntentsPerTick).toBe(4)
		t.expect(Session.DEFAULT_CONFIG.movement).toEqual({ speed = 30, turnBufferTicks = 24 })
		t.expect(Session.TICK_RATE).toBe(30)
		t.expect(Session.MAX_STEPS_PER_ADVANCE).toBe(5)
		t.expect(Session.SNAPSHOT_VERSION).toBe(1)
	end)

	it("players no longer lists someone who left", function()
		local s = Session.new(classic, 1)
		Session.join(s, "a")
		Session.join(s, "b")
		Session.leave(s, "a")
		t.expect(Session.players(s)).toEqual({ "b" })
	end)

	it("step returns each player's events in player id order", function()
		local s = Session.new(classic, 1)
		Session.join(s, "b")
		Session.join(s, "a")
		local events
		for _ = 1, 2 do
			events = Session.step(s)
		end
		-- each player enters a tile with a pellet on it: Entered and PelletEaten
		t.expect(#events).toBe(4)
		t.expect(events[1].player).toBe("a")
		t.expect(events[2].player).toBe("a")
		t.expect(events[3].player).toBe("b")
		t.expect(events[4].player).toBe("b")
	end)

	it("a player who leaves gets no more events", function()
		local s = Session.new(classic, 1)
		Session.join(s, "a")
		Session.leave(s, "a")
		t.expect(Session.step(s)).toEqual({})
		t.expect(s.tick).toBe(1)
	end)

	it(
		"a pellet eaten on a step that is still paying a pause owes its own pause at the full speed",
		function()
			-- base speed 90 makes a tile take less than two ticks, so a tile is entered while a pause is paid
			local corridor =
				Maze.parse({ "############", "#.........P#", "##########.#", "############" }, "fast")
			local s = Session.new(corridor, 1, {
				movement = { speed = 90, turnBufferTicks = 24 },
				maxIntentsPerTick = 4,
				eatSlowdown = true,
			})
			Session.join(s, "p")
			local x: { number } = { Session.snapshot(s, "p").player.x }
			for k = 1, 9 do
				Session.step(s)
				x[k + 1] = Session.snapshot(s, "p").player.x
			end
			t.expect(x[9] - x[10]).toBeNear(0.375, 1e-9)
			t.expect(x[10]).toBeNear(5.125, 1e-9)
		end
	)
end)
