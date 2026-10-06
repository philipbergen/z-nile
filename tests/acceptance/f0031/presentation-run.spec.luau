--!strict
-- f0300 AC4 (and R0150 RC1): a whole run as the client presents it. Every frame the server would send is
-- turned into what the screen shows, by Hud.model, Flow.overlay and Pellets.decode, from the countdown
-- through eating, a level clear and the next level, deaths, game over and a new run from Logic.
-- Narrowed by c0063: the game-over prompt is f0065's, not pinned here.
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
local Hud = require("@logic/Hud")
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

-- the spawn is at x = 4: walking west eats (3,1), (2,1) and the power pellet at (1,1), which clears the level
local SMALL = Maze.parse({ "######", "#o..P#", "######" }, "small")
local PAUSES: Game.Config =
	{ lives = 3, extraLifeScore = 10000, readyTicks = 3, dyingTicks = 4, levelClearTicks = 12, tickRate = 30 }
local RULES: Session.Config = {
	movement = { speed = 30, turnBufferTicks = 24 },
	maxIntentsPerTick = 4,
	play = PAUSES,
	eatSlowdown = true,
}

type Screen = { hud: Hud.Model, overlay: Flow.Overlay, pellets: { boolean } }

local function screen(s: Session.Session): Screen
	local frame = Session.frame(s, "p")
	return {
		hud = Hud.model(frame.play),
		overlay = Flow.overlay(frame.play, PAUSES),
		pellets = Pellets.decode(SMALL, frame.pellets),
	}
end

-- steps until an event matches, recording the screen after every step
local function until_(s: Session.Session, match: (Session.Event) -> boolean, seen: { Screen }?)
	for _ = 1, 400 do
		local hit = false
		for _, e in Session.step(s) do
			hit = hit or match(e)
		end
		if seen then
			table.insert(seen, screen(s))
		end
		if hit then
			return
		end
	end
	error("never happened")
end

local function kind(k: string, reason: string?): (Session.Event) -> boolean
	return function(e)
		return e.kind == k and (reason == nil or e.reason == reason)
	end
end

return t.spec("f0300 a whole run on screen", function(it)
	it(
		"shows the countdown, the score, the flash, the next level, the deaths, game over and a new run",
		function()
			local s = Session.new(SMALL, 3, RULES)
			Session.join(s, "p")

			-- joining: READY! over level 1, a fresh HUD, every pellet
			local first = screen(s)
			t.expect(first.overlay.banner).toBe("READY!")
			t.expect(first.overlay.detail).toBe("LEVEL 1")
			t.expect(first.hud).toEqual({ score = "0", level = "LEVEL 1", lives = 3, power = 0 })
			t.expect(first.pellets).toEqual({ true, true, true })

			-- play: the banner goes, eating shows in the score and the pellets
			until_(s, kind("Playing"))
			t.expect(screen(s).overlay.banner).toBe(nil)
			until_(s, function(e)
				return e.kind == "PelletEaten" and e.x == 3
			end)
			t.expect(screen(s).hud.score).toBe("10")
			t.expect(screen(s).pellets).toEqual({ true, true, false })

			-- the last pellet is the power pellet: the level clears and the walls flash through the pause
			until_(s, kind("LevelCleared"))
			local cleared = screen(s)
			t.expect(cleared.hud.score).toBe("70")
			t.expect(cleared.pellets).toEqual({ false, false, false })
			local pause: { Screen } = {}
			until_(s, kind("Ready", "level"), pause)
			local lit = 0
			for i = 1, #pause - 1 do
				if pause[i].overlay.flash then
					lit += 1
				end
			end
			t.expect(lit).toBe(6)
			t.expect(pause[#pause].overlay.flash).toBe(false)

			-- level 2: READY! again, every pellet back, the score kept
			local level2 = screen(s)
			t.expect(level2.overlay.banner).toBe("READY!")
			t.expect(level2.overlay.detail).toBe("LEVEL 2")
			t.expect(level2.hud).toEqual({ score = "70", level = "LEVEL 2", lives = 3, power = 0 })
			t.expect(level2.pellets).toEqual({ true, true, true })

			-- three deaths: each fades in, the lives count down, and the last one ends the run
			for life = 1, 3 do
				until_(s, kind("Playing"))
				Session.kill(s, "p")
				local dying = screen(s)
				t.expect(dying.overlay.fade).toBe(0)
				t.expect(dying.hud.lives).toBe(3 - life)
				local fading: { Screen } = {}
				until_(s, if life < 3 then kind("Ready", "respawn") else kind("GameOver"), fading)
				t.expect(fading[#fading - 1].overlay.fade > 0).toBe(true)
				if life < 3 then
					t.expect(fading[#fading].overlay.fade).toBe(0)
					t.expect(fading[#fading].overlay.banner).toBe("READY!")
				end
			end

			-- game over: the final score and level, fully faded
			local over = screen(s)
			t.expect(over.overlay.banner).toBe("GAME OVER")
			t.expect(over.overlay.detail).toBe("SCORE 70   LEVEL 2")
			t.expect(over.overlay.fade).toBe(0.6)
			t.expect(over.hud.lives).toBe(0)

			-- the results stay up
			for _ = 1, 30 do
				Session.step(s)
			end
			t.expect(screen(s).overlay.banner).toBe("GAME OVER")
			t.expect(screen(s).overlay.detail).toBe("SCORE 70   LEVEL 2")

			-- playing again: a fresh run on screen at once
			local _, ok = Session.playAgain(s, "p")
			t.expect(ok).toBe(true)
			local again = screen(s)
			t.expect(again.overlay.banner).toBe("READY!")
			t.expect(again.overlay.detail).toBe("LEVEL 1")
			t.expect(again.overlay.fade).toBe(0)
			t.expect(again.hud).toEqual({ score = "0", level = "LEVEL 1", lives = 3, power = 0 })
			t.expect(again.pellets).toEqual({ true, true, true })
		end
	)

	it("a play-again request outside game over changes nothing on screen", function()
		local s = Session.new(SMALL, 3, RULES)
		Session.join(s, "p")
		until_(s, function(e)
			return e.kind == "PelletEaten" and e.x == 3
		end)
		local before = screen(s)
		local _, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(false)
		t.expect(screen(s)).toEqual(before)
	end)
end)
