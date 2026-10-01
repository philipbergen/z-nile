--!strict
-- f0150 AC2: walking through the maze eats the pellets, once, when the player enters their tile, and
-- scores them. No pause for eating here (slowdown is off), so the ticks are the plain walking ticks.
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- the spawn is at the east end (x = 6) and the player walks west over five pellets at x = 5 .. 1. One
-- more pellet sits in a pocket below the spawn that these walks never reach, so the level never clears.
local CORRIDOR = Maze.parse({ "########", "#.....P#", "######.#", "########" }, "corridor")
-- three pellets and then a power pellet, with the same kind of pocket
local WITH_POWER = Maze.parse({ "#######", "#o...P#", "#####.#", "#######" }, "with-power")

-- a row of mixed values; a table literal of mixed element types does not type-check
local function row(...: any): { any }
	return { ... }
end

local PLAIN: Session.Config = { movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4 }

local function model(maze: Maze.Maze, players: { string }): sim.Model<Session.Session>
	return {
		name = "eating",
		tickRate = Session.TICK_RATE,
		new = function(seed: number): Session.Session
			local s = Session.new(maze, seed, PLAIN)
			for _, id in players do
				Session.join(s, id)
			end
			return s
		end,
		step = function(s: Session.Session, intents: { any }, _k: number): { sim.Event }?
			for _, i in intents do
				Session.submit(s, players[1], i)
			end
			return Session.step(s) :: any
		end,
		observe = function(s: Session.Session): any
			return Session.frame(s, players[1])
		end,
	}
end

local function eaten(trace: sim.Trace): { { any } }
	local out = {}
	for _, e in sim.events(trace, "PelletEaten") do
		table.insert(out, { e.tick, e.event.x, e.event.y, e.event.item, e.event.points })
	end
	return out
end

return t.spec("f0150 eating", function(it)
	it("the player eats each pellet the tick it enters the tile, 10 points each", function()
		local trace = sim.run(model(CORRIDOR, { "p" }), { seed = 1, ticks = 30 })
		t.expect(eaten(trace)).toEqual({
			row(2, 5, 1, "pellet", 10),
			row(6, 4, 1, "pellet", 10),
			row(10, 3, 1, "pellet", 10),
			row(14, 2, 1, "pellet", 10),
			row(18, 1, 1, "pellet", 10),
		})
		-- the event comes from the same step as the tile entry
		local entered = sim.events(trace, "Entered")
		t.expect(entered[1].tick).toBe(2)
		t.expect(entered[1].event.x).toBe(5)
	end)

	it("the score is 10 a pellet and shows in the frame", function()
		local trace = sim.run(model(CORRIDOR, { "p" }), { seed = 1, ticks = 30 })
		t.expect(sim.state(trace, 1).play.score).toBe(0)
		t.expect(sim.state(trace, 2).play.score).toBe(10)
		t.expect(sim.state(trace, 5).play.score).toBe(10)
		t.expect(sim.state(trace, 6).play.score).toBe(20)
		t.expect(sim.state(trace, 18).play.score).toBe(50)
		t.expect(sim.state(trace, 30).play.score).toBe(50)
	end)

	it("a power pellet is worth 50 and is reported as one", function()
		local trace = sim.run(model(WITH_POWER, { "p" }), { seed = 1, ticks = 30 })
		t.expect(eaten(trace)).toEqual({
			row(2, 4, 1, "pellet", 10),
			row(6, 3, 1, "pellet", 10),
			row(10, 2, 1, "pellet", 10),
			row(14, 1, 1, "power", 50),
		})
		t.expect(sim.state(trace, 14).play.score).toBe(80)
	end)

	it("a pellet is never eaten twice: going back over eaten tiles scores nothing", function()
		local trace = sim.run(model(CORRIDOR, { "p" }), {
			seed = 1,
			ticks = 100,
			script = {
				sim.intent(22, "Back"), -- at the west end: turn round and walk east
				sim.intent(60, "Back"), -- and back west again
			},
		})
		t.expect(#eaten(trace)).toBe(5)
		t.expect(sim.state(trace, 100).play.score).toBe(50)
		-- the player really did walk back over the eaten tiles
		t.expect(#sim.events(trace, "Entered") > 12).toBe(true)
	end)

	it("the spawn tile has no pellet, and entering an empty tile scores nothing", function()
		local trace = sim.run(model(CORRIDOR, { "p" }), {
			seed = 1,
			ticks = 60,
			script = { sim.intent(22, "Back") },
		})
		for _, e in sim.events(trace, "PelletEaten") do
			t.expect(e.event.x ~= 6).toBe(true)
		end
		-- it did enter the spawn tile on the way back
		local entered = {}
		for _, e in sim.events(trace, "Entered") do
			if e.event.x == 6 then
				table.insert(entered, e.tick)
			end
		end
		t.expect(#entered > 0).toBe(true)
	end)

	it("events name the player who ate", function()
		local trace = sim.run(model(CORRIDOR, { "p" }), { seed = 1, ticks = 10 })
		t.expect(sim.events(trace, "PelletEaten")[1].event.player).toBe("p")
	end)

	it("each player eats their own pellets: two players in one session don't share them", function()
		local s = Session.new(CORRIDOR, 1, PLAIN)
		Session.join(s, "a")
		Session.join(s, "b")
		local events: { Session.Event } = {}
		for _ = 1, 4 do
			for _, e in Session.step(s) do
				table.insert(events, e)
			end
		end
		local byPlayer: { [string]: number } = {}
		for _, e in events do
			if e.kind == "PelletEaten" then
				byPlayer[e.player] = (byPlayer[e.player] or 0) + 1
			end
		end
		t.expect(byPlayer.a).toBe(1)
		t.expect(byPlayer.b).toBe(1)
		t.expect(Session.frame(s, "a").play.score).toBe(10)
		t.expect(Session.frame(s, "b").play.score).toBe(10)
	end)

	it("eating is deterministic per seed", function()
		for _, seed in sim.seeds(3) do
			sim.assertDeterministic(model(CORRIDOR, { "p" }), {
				seed = seed,
				ticks = 80,
				script = { sim.intent(22, "Back"), sim.intent(50, "Back") },
			})
		end
	end)
end)
