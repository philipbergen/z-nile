--!strict
-- f0148 AC2: a run that starts on level n (Session.join's `start`, which the server takes from the player's stored best)
-- plays level n from its first step: the level's ramped speeds, its ghosts on level n, points worth n times, the extra
-- life at 10,000 x n (f0147's rule, now with a start above 1), and a new run starts on n again. Without a start, level 1.
local Game = require("@logic/Game")
local Ghosts = require("@logic/Ghosts")
local Levels = require("@logic/Levels")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local LONG = Maze.parse(
	{ "##########################", "#                       P#", "##########################" },
	"long"
)
local DOTS = Maze.parse({ "#######", "#...P.#", "#######" }, "dots")
local RAMPED: Session.Config =
	{ movement = Movement.DEFAULT_CONFIG, maxIntentsPerTick = 4, ramp = Levels.RAMP }

local function new(maze: Maze.Maze, config: Session.Config, start: number?): any
	local s = Session.new(maze, 1, config)
	Session.join(s, "p", start)
	return s
end

return t.spec("f0148 a run started on a later level", function(it)
	it(
		"a session joined with a start is on that level from its first frame; without one, on level 1",
		function()
			for _, start in { 1, 3, 7 } do
				local s = new(LONG, RAMPED, start)
				t.expect(Session.frame(s, "p").play.level).toBe(start)
				t.expect(s.members.p.play.start).toBe(start)
			end
			t.expect(Session.frame(new(LONG, RAMPED), "p").play.level).toBe(1)
			t.expect(new(LONG, RAMPED).members.p.play.start).toBe(1)
		end
	)

	it("the player runs the starting level's ramped speed from the first step", function()
		local s = new(LONG, RAMPED, 3)
		Session.step(s)
		local x0 = Movement.position(s.members.p.move)
		Session.step(s)
		local x1 = Movement.position(s.members.p.move)
		t.expect(math.floor(math.abs(x1 - x0) * 120 + 0.5))
			.toBe(Levels.playerSpeed(30, 3, false, Levels.RAMP))
		t.expect(Levels.playerSpeed(30, 3, false, Levels.RAMP)).toBe(23)
	end)

	it("the ghosts start on the starting level", function()
		local s = new(Maze.layout("classic"), Session.GAME_CONFIG, 5)
		local set = s.members.p.ghosts :: Ghosts.Set
		t.expect(set.level).toBe(5)
	end)

	it("every point is worth the starting level's multiple from the first pellet", function()
		local s = new(DOTS, RAMPED, 4)
		local got: number? = nil
		for _ = 1, 30 do
			for _, e in Session.step(s) do
				if e.kind == "PelletEaten" and got == nil then
					got = e.points
				end
			end
		end
		t.expect(got).toBe(40)
	end)

	it("the extra life comes at 10,000 x the starting level", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG, Levels.RAMP, 3)
		t.expect(g.start).toBe(3)
		t.expect(g.level).toBe(3)
		t.expect(#Game.addScore(g, 29999)).toBe(0)
		t.expect(#Game.addScore(g, 1)).toBe(1)
		-- the threshold reads the start, not the level reached since
		local later = Game.new(Game.IMMEDIATE_CONFIG, Levels.RAMP, 3)
		later.level = 6
		t.expect(#Game.addScore(later, 29999)).toBe(0)
		t.expect(#Game.addScore(later, 1)).toBe(1)
	end)

	it("a new run after game over starts on the same level again", function()
		local s = new(LONG, RAMPED, 3)
		for _ = 1, 3 do
			Session.kill(s, "p")
			for _ = 1, 3 do
				Session.step(s)
			end
		end
		t.expect(Session.isOver(s, "p")).toBe(true)
		s.members.p.play.level = 6 -- a run that got further: the next run still starts on its start
		local events, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(true)
		t.expect(s.members.p.play.level).toBe(3)
		local ready = nil
		for _, e in events do
			if e.kind == "Ready" then
				ready = e
			end
		end
		t.expect(ready ~= nil and ready.level == 3).toBe(true)
	end)

	it("a start that is not a whole level of 1 or more is refused", function()
		for _, bad in { 0, -2, 2.5, 0 / 0, math.huge } do
			t.expect((pcall(Session.join, Session.new(LONG, 1, RAMPED), "p", bad))).toBe(false)
			t.expect((pcall(Game.new, Game.IMMEDIATE_CONFIG, Levels.RAMP, bad))).toBe(false)
		end
	end)
end)
