--!strict
-- f0145 AC2: the continue offer in a run. Game counts the lives a run loses (`lost`). With the offer switched on for a
-- run (Session.allowOffer, which the game place's paid-play adapter does for each player), the last life opens the
-- offer (phase "offer", an Offer event, OFFER_TICKS steps) instead of ending the run; the offer's end is the
-- GameOver, carrying the lives lost. During the offer a continue gives CONTINUE_LIVES new lives and a respawn: the
-- score, the level, the pellets eaten and the extra life's once-per-run flag are kept, and the lives lost keep
-- counting. A held offer (a purchase screen open) does not count down; a decline ends it at the next step. Without
-- the offer switched on (every config's default, GAME_CONFIG included) the last life ends the run as before.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local CORRIDOR = Maze.parse({ "#######", "#..P..#", "#######" }, "corridor")

local function new(offer: boolean): Session.Session
	local s = Session.new(CORRIDOR, 1, Session.GAME_CONFIG)
	Session.join(s, "p")
	if offer then
		Session.allowOffer(s, "p")
	end
	return s
end

local function stepUntil(s: Session.Session, phase: string, limit: number?): { Session.Event }
	local seen: { Session.Event } = {}
	for _ = 1, limit or 400 do
		if Session.frame(s, "p").play.phase == phase then
			return seen
		end
		for _, e in Session.step(s) do
			table.insert(seen, e)
		end
	end
	error(`never reached {phase}`)
end

local function find(events: { Session.Event }, kind: string): Session.Event?
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

return t.spec("f0145 the continue offer", function(it)
	it(
		"the offer's numbers: 150 steps (10 s of real time), three lives a continue; off by default",
		function()
			t.expect(Game.OFFER_TICKS).toBe(150)
			t.expect(Game.CONTINUE_LIVES).toBe(3)
			t.expect(Game.new(Game.CLASSIC_CONFIG).offer).toBe(0)
			t.expect(Session.GAME_CONFIG.play).toEqual(Game.CLASSIC_CONFIG)
		end
	)

	it(
		"without the offer the last life ends the run as before, and the game over carries the lives lost",
		function()
			local g = Game.new(Game.IMMEDIATE_CONFIG)
			local over: Game.Event? = nil
			for _ = 1, 3 do
				Game.died(g)
				for _, e in Game.step(g) do
					if e.kind == "GameOver" then
						over = e
					end
				end
			end
			t.expect(g.phase).toBe("gameover")
			t.expect(over ~= nil).toBe(true)
			t.expect((over :: Game.Event).lives).toBe(3)
			t.expect(g.lost).toBe(3)
		end
	)

	it("with the offer on, the last life opens it for OFFER_TICKS steps; its end is the game over", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		Game.allowOffer(g, 5)
		for _ = 1, 2 do
			Game.died(g)
			Game.step(g)
		end
		Game.died(g)
		local opened = Game.step(g)
		t.expect(g.phase).toBe("offer")
		t.expect(g.timer).toBe(5)
		t.expect(opened[1].kind).toBe("Offer")
		t.expect(opened[1].ticks).toBe(5)
		for _ = 1, 4 do
			t.expect(#Game.step(g)).toBe(0)
			t.expect(g.phase).toBe("offer")
		end
		local ended = Game.step(g)
		t.expect(g.phase).toBe("gameover")
		t.expect(ended[1].kind).toBe("GameOver")
		t.expect(ended[1].lives).toBe(3)
	end)

	it("a held offer does not count down; released, it does again", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		Game.allowOffer(g, 3)
		for _ = 1, 3 do
			Game.died(g)
			Game.step(g)
		end
		t.expect(g.phase).toBe("offer")
		Game.hold(g, true)
		for _ = 1, 10 do
			Game.step(g)
		end
		t.expect(g.phase).toBe("offer")
		t.expect(g.timer).toBe(3)
		Game.hold(g, false)
		for _ = 1, 3 do
			Game.step(g)
		end
		t.expect(g.phase).toBe("gameover")
	end)

	it("a decline ends the offer at the next step, with the game over", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		Game.allowOffer(g, 100)
		for _ = 1, 3 do
			Game.died(g)
			Game.step(g)
		end
		Game.hold(g, true)
		t.expect(Game.decline(g)).toBe(true)
		t.expect(g.phase).toBe("offer")
		local ended = Game.step(g)
		t.expect(g.phase).toBe("gameover")
		t.expect(ended[1].kind).toBe("GameOver")
		t.expect(Game.decline(g)).toBe(false)
	end)

	it(
		"a continue gives three new lives and a respawn; the score, level and extra-life flag stay; lives lost go on",
		function()
			local g = Game.new(Game.IMMEDIATE_CONFIG)
			Game.allowOffer(g, 50)
			Game.addScore(g, 12000) -- the extra life: 4 lives
			t.expect(g.lives).toBe(4)
			for _ = 1, 4 do
				Game.died(g)
				Game.step(g)
			end
			t.expect(g.phase).toBe("offer")
			local events, ok = Game.continue(g, Game.CONTINUE_LIVES)
			t.expect(ok).toBe(true)
			t.expect(events[1].kind).toBe("Ready")
			t.expect(events[1].reason).toBe("continue")
			t.expect(g.lives).toBe(3)
			t.expect(g.score).toBe(12000)
			t.expect(g.phase).toBe("playing") -- no ready pause in these rules
			Game.addScore(g, 10000)
			t.expect(g.lives).toBe(3) -- the extra life is once per run, continues included
			for _ = 1, 3 do
				Game.died(g)
				Game.step(g)
			end
			t.expect(g.phase).toBe("offer") -- the offer stays on for the rest of the run
			Game.decline(g)
			local ended = Game.step(g)
			t.expect(ended[1].lives).toBe(7)
		end
	)

	it("a continue outside the offer does nothing; a bad offer length changes nothing", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		local events, ok = Game.continue(g, 3)
		t.expect(ok).toBe(false)
		t.expect(#events).toBe(0)
		Game.allowOffer(g, -1)
		Game.allowOffer(g, 1.5)
		t.expect(g.offer).toBe(0)
		for _ = 1, 3 do
			Game.died(g)
			Game.step(g)
		end
		t.expect(g.phase).toBe("gameover")
		t.expect((select(2, Game.continue(g, 3)))).toBe(false)
	end)

	it(
		"in a session: the offer keeps the run alive, a continue respawns at the start with the pellets eaten kept",
		function()
			local s = new(true)
			stepUntil(s, "playing")
			for _ = 1, 8 do
				Session.submit(s, "p", "Left")
				Session.step(s)
			end
			local left = Pellets.remaining(s.members.p.pellets)
			t.expect(left < Pellets.total(s.members.p.pellets)).toBe(true)
			local score = Session.frame(s, "p").play.score
			for i = 1, 3 do
				stepUntil(s, "playing")
				if i == 3 then
					for _ = 1, 8 do -- the last death away from the start, so the continue must bring the player back
						Session.submit(s, "p", "Right")
						Session.step(s)
					end
					t.expect(Session.frame(s, "p").player.x ~= 3).toBe(true)
				end
				Session.kill(s, "p")
				Session.step(s)
			end
			stepUntil(s, "offer")
			t.expect(Session.offering(s, "p")).toBe(true)
			t.expect(Session.isOver(s, "p")).toBe(false)
			local _, ok = Session.continue(s, "p")
			t.expect(ok).toBe(true)
			local f = Session.frame(s, "p")
			t.expect(f.play.lives).toBe(Game.CONTINUE_LIVES)
			t.expect(f.play.score).toBe(score)
			t.expect(f.player.x).toBe(3)
			t.expect(f.player.y).toBe(1)
			t.expect(Pellets.remaining(s.members.p.pellets)).toBe(left)
			t.expect(Session.offering(s, "p")).toBe(false)
		end
	)

	it("in a session without the offer the last life is the game over, at once", function()
		local s = new(false)
		for _ = 1, 3 do
			stepUntil(s, "playing")
			Session.kill(s, "p")
			Session.step(s)
		end
		local seen = stepUntil(s, "gameover")
		local over = find(seen, "GameOver")
		t.expect(over ~= nil).toBe(true)
		t.expect((over :: Session.Event).lives).toBe(3)
		t.expect(Session.offering(s, "p")).toBe(false)
	end)
end)
