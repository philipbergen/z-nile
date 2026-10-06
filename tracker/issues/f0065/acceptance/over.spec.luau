--!strict
-- f0065 AC2: Logic says when a player's run is over, so the server never reads a phase itself: Session.isOver is
-- true at game over and only then, for that player only, and false for a player the session does not know.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local SMALL = Maze.parse({ "######", "#o..P#", "######" }, "small")
local PAUSES: Game.Config =
	{ lives = 3, extraLifeScore = 10000, readyTicks = 3, dyingTicks = 4, levelClearTicks = 12, tickRate = 30 }
local RULES: Session.Config = {
	movement = { speed = 30, turnBufferTicks = 24 },
	maxIntentsPerTick = 4,
	play = PAUSES,
	eatSlowdown = true,
}

local function phaseOf(s: Session.Session, id: string): string
	return Session.frame(s, id).play.phase
end

-- steps until the player's run is in `phase`, checking isOver on every step on the way
local function until_(s: Session.Session, id: string, phase: string)
	for _ = 1, 400 do
		if phaseOf(s, id) == phase then
			return
		end
		t.expect(Session.isOver(s, id)).toBe(false)
		Session.step(s)
	end
	error(`never reached {phase}`)
end

-- three lives lost: the run is over
local function finish(s: Session.Session, id: string)
	for _ = 1, 3 do
		until_(s, id, "playing")
		Session.kill(s, id)
	end
	until_(s, id, "gameover")
end

return t.spec("f0065 Session.isOver", function(it)
	it("is false through ready, play and dying, and true once the run is over", function()
		local s = Session.new(SMALL, 3, RULES)
		Session.join(s, "p")
		t.expect(Session.isOver(s, "p")).toBe(false)
		finish(s, "p")
		t.expect(Session.isOver(s, "p")).toBe(true)
		for _ = 1, 30 do
			Session.step(s)
		end
		t.expect(Session.isOver(s, "p")).toBe(true)
	end)

	it("is false during a level clear and the dying pause", function()
		local s = Session.new(SMALL, 3, RULES)
		Session.join(s, "p")
		until_(s, "p", "levelclear")
		t.expect(Session.isOver(s, "p")).toBe(false)
		until_(s, "p", "playing")
		Session.kill(s, "p")
		t.expect(phaseOf(s, "p")).toBe("dying")
		t.expect(Session.isOver(s, "p")).toBe(false)
	end)

	it("is false again once a new run starts", function()
		local s = Session.new(SMALL, 3, RULES)
		Session.join(s, "p")
		finish(s, "p")
		local _, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(true)
		t.expect(Session.isOver(s, "p")).toBe(false)
	end)

	it("is per player, and false for a player the session does not know", function()
		local s = Session.new(SMALL, 3, RULES)
		Session.join(s, "a")
		Session.join(s, "b")
		finish(s, "a")
		t.expect(Session.isOver(s, "a")).toBe(true)
		t.expect(Session.isOver(s, "b")).toBe(false)
		t.expect(Session.isOver(s, "nobody")).toBe(false)
		Session.leave(s, "a")
		t.expect(Session.isOver(s, "a")).toBe(false)
	end)
end)
