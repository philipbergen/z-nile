--!strict
-- f0186 AC1: a run counts the paid revives it used. Game.revives starts at 0; each continue f0145's offer takes
-- (Game.continue during the offer) adds one, and nothing else does; a new run (Game.playAgain) starts at 0 again. Every
-- GameOver carries the count as `revives` (0 for a run without one), whichever way the run ends: the last life without
-- the offer, the offer's countdown, a decline, a departure. Session's events carry it on, and the frame's play shows it
-- (nil while none, so the frame of a run without revives is the frame it was).
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local CORRIDOR = Maze.parse({ "#######", "#..P..#", "#######" }, "corridor")

-- lose lives (no pauses in these rules) until the run is in `phase`
local function lose(g: Game.Game, phase: string): { Game.Event }
	local seen: { Game.Event } = {}
	for _ = 1, 100 do
		if g.phase == phase then
			return seen
		end
		if g.phase == "playing" then
			Game.died(g)
		end
		for _, e in Game.step(g) do
			table.insert(seen, e)
		end
	end
	error(`never reached {phase}`)
end

local function find(events: { any }, kind: string): any
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

local function session(offer: boolean): Session.Session
	local s = Session.new(CORRIDOR, 1, Session.GAME_CONFIG)
	Session.join(s, "p")
	if offer then
		Session.allowOffer(s, "p")
	end
	return s
end

-- step the session, killing the player whenever they play, until the run is in `phase`
local function play(s: Session.Session, phase: string): { Session.Event }
	local seen: { Session.Event } = {}
	for _ = 1, 2000 do
		local now = Session.frame(s, "p").play.phase
		if now == phase then
			return seen
		end
		if now == "playing" then
			Session.kill(s, "p")
		end
		for _, e in Session.step(s) do
			table.insert(seen, e)
		end
	end
	error(`never reached {phase}`)
end

return t.spec("f0186 a run counts its revives", function(it)
	it("a run starts with none; each continue the offer takes counts one", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		t.expect(g.revives).toBe(0)
		Game.allowOffer(g, 50)
		lose(g, "offer")
		t.expect(g.revives).toBe(0) -- the offer itself is no revive
		local _, ok = Game.continue(g, Game.CONTINUE_LIVES)
		t.expect(ok).toBe(true)
		t.expect(g.revives).toBe(1)
		lose(g, "offer")
		t.expect(g.revives).toBe(1) -- lives lost after a continue are no revive either
		Game.continue(g, Game.CONTINUE_LIVES)
		t.expect(g.revives).toBe(2)
	end)

	it("a continue outside the offer counts nothing, before the run ends or after", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		local _, early = Game.continue(g, Game.CONTINUE_LIVES)
		t.expect(early).toBe(false)
		t.expect(g.revives).toBe(0)
		lose(g, "gameover") -- no offer: the last life ends the run
		local _, late = Game.continue(g, Game.CONTINUE_LIVES)
		t.expect(late).toBe(false)
		t.expect(g.revives).toBe(0)
	end)

	it("every game over carries the run's revives, 0 for a run without one", function()
		-- the last life without the offer
		local plain = Game.new(Game.IMMEDIATE_CONFIG)
		local over = find(lose(plain, "gameover"), "GameOver")
		t.expect(over ~= nil).toBe(true)
		t.expect(over.revives).toBe(0)
		-- a decline after two continues
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		Game.allowOffer(g, 50)
		for _ = 1, 2 do
			lose(g, "offer")
			Game.continue(g, Game.CONTINUE_LIVES)
		end
		lose(g, "offer")
		Game.decline(g)
		local declined = find(Game.step(g), "GameOver")
		t.expect(declined ~= nil).toBe(true)
		t.expect(declined.revives).toBe(2)
		-- the countdown running out after one continue
		local h = Game.new(Game.IMMEDIATE_CONFIG)
		Game.allowOffer(h, 2)
		lose(h, "offer")
		Game.continue(h, Game.CONTINUE_LIVES)
		local ran = find(lose(h, "gameover"), "GameOver")
		t.expect(ran ~= nil).toBe(true)
		t.expect(ran.revives).toBe(1)
	end)

	it("a new run starts with none again", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		Game.allowOffer(g, 50)
		lose(g, "offer")
		Game.continue(g, Game.CONTINUE_LIVES)
		lose(g, "offer")
		Game.decline(g)
		Game.step(g)
		t.expect(g.phase).toBe("gameover")
		t.expect(g.revives).toBe(1)
		local _, again = Game.playAgain(g)
		t.expect(again).toBe(true)
		t.expect(g.revives).toBe(0)
		local seen: { Game.Event } = {}
		for _ = 1, 100 do
			if g.phase == "gameover" then
				break
			elseif g.phase == "offer" then
				Game.decline(g)
			elseif g.phase == "playing" then
				Game.died(g)
			end
			for _, e in Game.step(g) do
				table.insert(seen, e)
			end
		end
		t.expect(find(seen, "GameOver").revives).toBe(0)
	end)

	it("a session's game over and frames carry the revives; the frame shows none as nothing", function()
		local s = session(true)
		play(s, "offer")
		t.expect(Session.frame(s, "p").play.revives).toBe(nil)
		local _, ok = Session.continue(s, "p")
		t.expect(ok).toBe(true)
		t.expect(Session.frame(s, "p").play.revives).toBe(1)
		play(s, "offer")
		Session.decline(s, "p")
		local over = find(play(s, "gameover"), "GameOver")
		t.expect(over ~= nil).toBe(true)
		t.expect(over.revives).toBe(1)
		t.expect(over.player).toBe("p")
		t.expect(Session.frame(s, "p").play.revives).toBe(1)
		-- without the offer: no revive, the game over says 0, the frames say nothing
		local o = session(false)
		local plain = find(play(o, "gameover"), "GameOver")
		t.expect(plain.revives).toBe(0)
		t.expect(Session.frame(o, "p").play.revives).toBe(nil)
	end)

	it("a player who departs after a continue ends the run with that revive counted", function()
		local s = session(true)
		play(s, "offer")
		Session.continue(s, "p")
		play(s, "offer")
		Session.depart(s, "p")
		local over = find(play(s, "gameover"), "GameOver")
		t.expect(over ~= nil).toBe(true)
		t.expect(over.revives).toBe(1)
	end)
end)
