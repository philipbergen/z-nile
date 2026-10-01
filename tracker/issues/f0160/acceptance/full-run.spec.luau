--!strict
-- f0160 AC2: a whole run plays through Session headless: the countdown, eating, a power pellet,
-- clearing a level and the harder one after it, deaths, gameover and playing again. This is the
-- rules half of the game working together (R0090's end-to-end check).
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

-- walk west over a pellet and then a power pellet, which clears the level: 10 + 50 = 60 points a level.
local SMALL = Maze.parse({ "#####", "#o.P#", "#####" }, "small")

local RULES: Session.Config = {
	movement = { speed = 30, turnBufferTicks = 24 },
	maxIntentsPerTick = 4,
	play = Game.CLASSIC_CONFIG,
	eatSlowdown = true,
}

local function phase(s: Session.Session): string
	return Session.frame(s, "p").play.phase
end

-- steps until the phase is `want`, collecting events; fails if it takes too long
local function untilPhase(s: Session.Session, want: string, events: { Session.Event }?)
	for _ = 1, 400 do
		if phase(s) == want then
			return
		end
		for _, e in Session.step(s) do
			if events then
				table.insert(events, e)
			end
		end
	end
	error(`never reached {want}; stuck in {phase(s)}`)
end

local function count(events: { Session.Event }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

return t.spec("f0160 a whole run", function(it)
	it("plays ready, eats, clears, gets harder, loses lives, ends and starts again", function()
		local s = Session.new(SMALL, 7, RULES)
		Session.join(s, "p")
		local events: { Session.Event } = {}

		-- the countdown
		t.expect(phase(s)).toBe("ready")
		untilPhase(s, "playing", events)
		t.expect(count(events, "Playing")).toBe(1)

		-- level 1: eat both pellets, which clears it
		untilPhase(s, "levelclear", events)
		t.expect(count(events, "PelletEaten")).toBe(2)
		t.expect(count(events, "PowerStarted")).toBe(1)
		t.expect(count(events, "LevelCleared")).toBe(1)
		local f = Session.frame(s, "p")
		t.expect(f.play.score).toBe(60)
		t.expect(f.play.level).toBe(1)
		t.expect(f.play.frightened).toBe(0) -- clearing the level ended the frightened period

		-- level 2: everything is back, and the player is faster
		untilPhase(s, "ready", events)
		f = Session.frame(s, "p")
		t.expect(f.play.level).toBe(2)
		t.expect(f.play.score).toBe(60)
		t.expect(f.player.x).toBe(3)
		untilPhase(s, "playing", events)
		-- the first step of level 2 covers its 34 units, with nothing owed from level 1's last pellet
		for _, e in Session.step(s) do
			table.insert(events, e)
		end
		t.expect(Session.frame(s, "p").player.x).toBeNear(3 - 34 / 120, 1e-9)
		untilPhase(s, "levelclear", events)
		t.expect(count(events, "PelletEaten")).toBe(4)
		t.expect(Session.frame(s, "p").play.score).toBe(120)
		local started2 = {}
		for _, e in events do
			if e.kind == "PowerStarted" then
				table.insert(started2, e.ticks)
			end
		end
		t.expect(started2).toEqual({ 180, 150 }) -- level 1 then level 2

		-- three lives go
		untilPhase(s, "ready", events)
		untilPhase(s, "playing", events)
		for life = 3, 1, -1 do
			t.expect(#Session.kill(s, "p")).toBe(1)
			t.expect(Session.frame(s, "p").play.lives).toBe(life - 1)
			if life > 1 then
				untilPhase(s, "ready", events)
				untilPhase(s, "playing", events)
			end
		end
		untilPhase(s, "gameover", events)
		t.expect(count(events, "GameOver")).toBe(1)
		f = Session.frame(s, "p")
		t.expect(f.play.lives).toBe(0)
		t.expect(f.play.score).toBe(120)
		t.expect(f.play.level).toBe(3)

		-- and again
		local again, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(true)
		t.expect(again[1].reason).toBe("again")
		f = Session.frame(s, "p")
		t.expect(f.play.level).toBe(1)
		t.expect(f.play.score).toBe(0)
		t.expect(f.play.lives).toBe(3)
		t.expect(f.play.phase).toBe("ready")
		untilPhase(s, "playing")
		untilPhase(s, "levelclear") -- the pellets are back
		t.expect(Session.frame(s, "p").play.score).toBe(60)
	end)

	it("the same run twice gives the same frames", function()
		local function play(): { string }
			local s = Session.new(SMALL, 7, RULES)
			Session.join(s, "p")
			local out = {}
			for _ = 1, 400 do
				Session.step(s)
				local f = Session.frame(s, "p")
				table.insert(
					out,
					`{f.tick}:{f.play.phase}:{f.play.level}:{f.play.score}:{f.player.x}:{f.play.frightened}`
				)
			end
			return out
		end
		t.expect(play()).toEqual(play())
	end)
end)
