--!strict
-- World unit specs: goal, speed, event fields, turn validation, and advance dt validation.
local World = require("@logic/World")
local t = require("@tests/lib/t")

local function fixedDraw(n: number): number
	return if n >= 1 then 1 else error("bad n")
end

return t.spec("World unit", function(it)
	it("reports goal, speed, and exact map and placed event fields", function()
		local w, events = World.new(1, fixedDraw)
		local sp = w.layout.spawns[1]
		t.expect(World.goal(w)).toBe(12)
		t.expect(World.speed(w)).toBe(4)
		t.expect(events).toEqual({
			{ kind = "map", map = 1 },
			{ kind = "placed", id = 1, x = sp.x, y = sp.y, heading = sp.heading },
		})
	end)

	it("emits exact fields for go, ate, cleared, died, and over events", function()
		local w = World.new(1, fixedDraw)
		-- go event after readySeconds (2s)
		local goEvents = World.advance(w, 2, fixedDraw)
		t.expect(goEvents).toEqual({ { kind = "go", id = 1 } })

		-- ate event: place apple directly ahead of snake 1 and advance one step
		local head = w.snakes[1].body[1]
		local ax, ay = head.x + 1, head.y
		w.apples = { { x = ax, y = ay } }
		local ateEvents = World.advance(w, 0.25, fixedDraw)
		t.expect(ateEvents).toEqual({ { kind = "ate", id = 1, x = ax, y = ay } })

		-- cleared event: grow snake to goal - 1 and feed one more apple
		local goal = World.goal(w)
		local body = {}
		for i = 0, goal - 2 do
			table.insert(body, { x = 12 - i, y = 10 })
		end
		w.snakes[1].body = body
		w.snakes[1].heading = "E"
		w.snakes[1].grow = 0
		w.apples = { { x = 13, y = 10 } }
		local clearEvents = World.advance(w, 0.25, fixedDraw)
		t.expect(clearEvents).toEqual({
			{ kind = "ate", id = 1, x = 13, y = 10 },
			{ kind = "cleared", map = 1, ids = { 1 } },
		})

		-- died and over events: put snake at right border with 1 life and step off
		local w2 = World.new(1, fixedDraw)
		World.advance(w2, 2, fixedDraw)
		local side = w2.layout.side
		w2.snakes[1].body = {
			{ x = side, y = 10 },
			{ x = side - 1, y = 10 },
			{ x = side - 2, y = 10 },
			{ x = side - 3, y = 10 },
		}
		w2.snakes[1].heading = "E"
		w2.snakes[1].lives = 1
		local overEvents = World.advance(w2, 0.25, fixedDraw)
		t.expect(overEvents).toEqual({
			{ kind = "died", id = 1, x = side + 1, y = 10 },
			{ kind = "over", id = 1 },
		})
	end)

	it("returns empty events for invalid dt in advance", function()
		local w = World.new(1, fixedDraw)
		t.expect(World.advance(w, 0, fixedDraw)).toEqual({})
		t.expect(World.advance(w, -1, fixedDraw)).toEqual({})
		t.expect(World.advance(w, 0 / 0, fixedDraw)).toEqual({})
		t.expect(World.advance(w, math.huge, fixedDraw)).toEqual({})
	end)

	it("rejects invalid turns and buffers up to two", function()
		local w = World.new(1, fixedDraw)
		t.expect(World.turn(w, 1, ("Back" :: any))).toBe(false)
		t.expect(World.turn(w, 1, "Left")).toBe(true)
		t.expect(World.turn(w, 1, "Right")).toBe(true)
		t.expect(World.turn(w, 1, "Left")).toBe(false)
		t.expect(World.turn(w, 99, "Left")).toBe(false)
	end)
end)
