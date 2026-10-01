--!strict
-- f0170 AC3: a Session plays the run: a ready countdown, deaths and lives, gameover, play again. The
-- player only moves while the run is in play, and a client can never cause a death.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- a corridor with the spawn at its east end: the player starts walking west. No pellets (spaces), so
-- nothing here depends on eating.
local CORRIDOR = Maze.parse({ "###############", "#            P#", "###############" }, "corridor")

local RULES: Session.Config = {
	movement = { speed = 30, turnBufferTicks = 24 },
	maxIntentsPerTick = 4,
	play = Game.CLASSIC_CONFIG, -- ready 60, dying 45, level clear 60
}

-- Intents "Kill" and "Again" are this test's own stand-ins for the server (a ghost catching the
-- player, and the player asking to play again); everything else is a movement intent.
local function model(config: Session.Config): sim.Model<Session.Session>
	return {
		name = "flow",
		tickRate = Session.TICK_RATE,
		new = function(seed: number): Session.Session
			local s = Session.new(CORRIDOR, seed, config)
			Session.join(s, "p")
			return s
		end,
		step = function(s: Session.Session, intents: { any }, _k: number): { sim.Event }?
			local out: { any } = {}
			for _, i in intents do
				if i == "Kill" then
					for _, e in Session.kill(s, "p") do
						table.insert(out, e)
					end
				elseif i == "Again" then
					local events = Session.playAgain(s, "p")
					for _, e in events do
						table.insert(out, e)
					end
				else
					Session.submit(s, "p", i)
				end
			end
			for _, e in Session.step(s) do
				table.insert(out, e)
			end
			return out :: any
		end,
		observe = function(s: Session.Session): any
			return Session.frame(s, "p")
		end,
	}
end

local function phases(trace: sim.Trace): { { string | number } }
	-- { tick, phase } each time the phase changes
	local out = {}
	local last = ""
	for tk = 0, trace.steps do
		local p = sim.state(trace, tk).play.phase
		if p ~= last then
			table.insert(out, { tk, p })
			last = p
		end
	end
	return out
end

return t.spec("f0170 play flow through Session", function(it)
	it("the player waits through the ready countdown, then walks", function()
		local trace = sim.run(model(RULES), { seed = 1, ticks = 70 })
		for tk = 0, 59 do
			local f = sim.state(trace, tk)
			if f.play.phase ~= "ready" or f.player.x ~= 13 then
				error(`tick {tk}: phase {f.play.phase} at x {f.player.x}`)
			end
		end
		-- the countdown ends in step 59 (time 60); movement starts with the next step
		t.expect(sim.state(trace, 60).play.phase).toBe("playing")
		t.expect(sim.state(trace, 61).player.x).toBe(12.75)
		t.expect(sim.state(trace, 62).player.x).toBe(12.5)
		t.expect(sim.firstTick(trace, "Playing")).toBe(60)
		t.expect(sim.state(trace, 0).play.timer).toBe(60)
		t.expect(sim.state(trace, 59).play.timer).toBe(1)
		t.expect(sim.state(trace, 60).play.timer).toBe(0)
	end)

	it("intents sent during the countdown are discarded, not remembered", function()
		-- Back at tick 10 would turn the player east into the wall; if it were remembered the player
		-- would be facing east after the countdown
		local trace = sim.run(model(RULES), {
			seed = 1,
			ticks = 64,
			script = { sim.intent(10, "Back") },
		})
		t.expect(sim.state(trace, 62).player.heading).toBe("W")
		t.expect(sim.state(trace, 62).player.x).toBe(12.5)
	end)

	it("a death freezes the player, then the next attempt starts at the spawn with a fresh countdown", function()
		local trace = sim.run(model(RULES), {
			seed = 1,
			ticks = 200,
			script = { sim.intent(80, "Kill") },
		})
		-- walking since time 60; at tick 80 the player is 5 tiles along
		t.expect(sim.state(trace, 80).player.x).toBe(8)
		t.expect(sim.state(trace, 81).play.phase).toBe("dying")
		t.expect(sim.state(trace, 81).play.lives).toBe(2)
		for tk = 81, 124 do
			t.expect(sim.state(trace, tk).player.x).toBe(8) -- frozen while dying
		end
		-- 45 ticks of dying from the kill at 80, then back at the spawn, ready again for 60 ticks
		t.expect(sim.state(trace, 125).play.phase).toBe("ready")
		t.expect(sim.state(trace, 125).player.x).toBe(13)
		t.expect(sim.state(trace, 125).player.heading).toBe("W")
		t.expect(sim.state(trace, 125).play.timer).toBe(60)
		t.expect(sim.state(trace, 184).play.phase).toBe("ready")
		t.expect(sim.state(trace, 185).play.phase).toBe("playing")
		local lost = sim.events(trace, "LifeLost")
		t.expect(#lost).toBe(1)
		t.expect(lost[1].tick).toBe(81)
		t.expect(lost[1].event.lives).toBe(2)
		t.expect(lost[1].event.player).toBe("p")
	end)

	it("the respawn is a teleport: the snapshot's jumpTick marks it", function()
		local trace = sim.run(model(RULES), {
			seed = 1,
			ticks = 130,
			script = { sim.intent(80, "Kill") },
		})
		t.expect(sim.state(trace, 100).player.jumpTick).toBe(-1)
		t.expect(sim.state(trace, 124).player.jumpTick).toBe(-1)
		t.expect(sim.state(trace, 125).player.jumpTick).toBe(125)
		t.expect(sim.state(trace, 130).player.jumpTick).toBe(125)
	end)

	it("three deaths end the run", function()
		local script: { sim.Item } = {}
		-- each attempt: kill 20 ticks into play (kills at 80, 205 and 330), then 45 dying and 60 ready
		local at = 80
		for _ = 1, 3 do
			table.insert(script, sim.intent(at, "Kill"))
			at += 45 + 60 + 20 -- dying, ready, then 20 ticks of play
		end
		local trace = sim.run(model(RULES), { seed = 1, ticks = at + 60, script = script })
		local over = sim.events(trace, "GameOver")
		t.expect(#over).toBe(1)
		t.expect(over[1].event.score).toBe(0)
		t.expect(over[1].event.level).toBe(1)
		local last = sim.state(trace, trace.steps)
		t.expect(last.play.phase).toBe("gameover")
		t.expect(last.play.lives).toBe(0)
		t.expect(#sim.events(trace, "LifeLost")).toBe(3)
		-- nothing moves after gameover
		local x = last.player.x
		t.expect(sim.state(trace, trace.steps - 10).player.x).toBe(x)
	end)

	it("Kill only works while the run is in play", function()
		local s = Session.new(CORRIDOR, 1, RULES)
		Session.join(s, "p")
		t.expect(#Session.kill(s, "p")).toBe(0) -- ready
		t.expect(Session.frame(s, "p").play.lives).toBe(3)
		for _ = 1, 61 do
			Session.step(s)
		end
		t.expect(#Session.kill(s, "p")).toBe(1)
		t.expect(#Session.kill(s, "p")).toBe(0) -- already dying
		t.expect(Session.frame(s, "p").play.lives).toBe(2)
		t.expect(function()
			Session.kill(s, "nobody")
		end).toThrow("unknown player")
	end)

	it("a client cannot kill its own player: no intent string reaches Session.kill", function()
		local s = Session.new(CORRIDOR, 1, RULES)
		Session.join(s, "p")
		for _ = 1, 61 do
			Session.step(s)
		end
		for _, raw in { "Kill", "kill", "Die", "Again", "PlayAgain", "GameOver" } do
			local ok, why = Session.submit(s, "p", raw)
			t.expect(ok).toBe(false)
			t.expect(why).toBe("invalid intent")
		end
		Session.step(s)
		t.expect(Session.frame(s, "p").play.lives).toBe(3)
		t.expect(Session.frame(s, "p").play.phase).toBe("playing")
	end)

	it("play again starts a fresh run, but only at gameover", function()
		local s = Session.new(CORRIDOR, 1, RULES)
		Session.join(s, "p")
		local events, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(false) -- still in the countdown
		t.expect(#events).toBe(0)
		for _ = 1, 61 do
			Session.step(s)
		end
		for _ = 1, 3 do
			Session.kill(s, "p")
			for _ = 1, 45 + 60 + 1 do
				Session.step(s)
			end
		end
		t.expect(Session.frame(s, "p").play.phase).toBe("gameover")
		t.expect((select(2, Session.playAgain(s, "p")))).toBe(true)
		local f = Session.frame(s, "p")
		t.expect(f.play.phase).toBe("ready")
		t.expect(f.play.lives).toBe(3)
		t.expect(f.play.level).toBe(1)
		t.expect(f.play.score).toBe(0)
		t.expect(f.play.timer).toBe(60)
		t.expect(f.player.x).toBe(13) -- back at the spawn
		-- made between steps, so the first frame at the spawn is the next tick's: that is where a camera must cut
		t.expect(f.player.jumpTick).toBe(f.tick + 1)
		t.expect((select(2, Session.playAgain(s, "p")))).toBe(false) -- once is enough
		Session.step(s)
		local after = Session.frame(s, "p")
		t.expect(after.player.jumpTick).toBe(after.tick)
	end)

	it("every phase follows the state machine exactly, for any seed", function()
		for _, seed in sim.seeds(3) do
			local trace = sim.assertDeterministic(model(RULES), {
				seed = seed,
				ticks = 420,
				script = { sim.intent(90, "Kill"), sim.intent(300, "Kill") },
			})
			-- a kill at k shows as dying at k + 1; dying lasts 45 ticks and ready 60
			t.expect(phases(trace)).toEqual({
				{ 0, "ready" },
				{ 60, "playing" },
				{ 91, "dying" },
				{ 135, "ready" },
				{ 195, "playing" },
				{ 301, "dying" },
				{ 345, "ready" },
				{ 405, "playing" },
			})
		end
	end)

	it("with no pauses (the default config) the player plays from tick 0 and a death is instant", function()
		local s = Session.new(CORRIDOR, 1)
		Session.join(s, "p")
		t.expect(Session.frame(s, "p").play.phase).toBe("playing")
		Session.step(s)
		t.expect(Session.snapshot(s, "p").player.x).toBe(12.75)
		Session.kill(s, "p")
		Session.step(s)
		t.expect(Session.frame(s, "p").play.phase).toBe("playing")
		t.expect(Session.frame(s, "p").play.lives).toBe(2)
		t.expect(Session.snapshot(s, "p").player.x).toBe(13)
	end)
end)
