--!strict
-- f0290 AC2: Session.frame carries the pellets still to eat, as Pellets.encode of the player's pellets,
-- in every frame: the client draws from it and never decides what is eaten.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local Session = require("@logic/Session")
local plain = require("@tests/lib/plain")
local t = require("@tests/lib/t")

-- the spawn is at x = 4; walking west eats (3,1), (2,1) and then the power pellet at (1,1), which clears the level
local SMALL = Maze.parse({ "######", "#o..P#", "######" }, "small")
local PAUSES: Game.Config =
	{ lives = 3, extraLifeScore = 10000, readyTicks = 2, dyingTicks = 2, levelClearTicks = 3, tickRate = 30 }
local RULES: Session.Config =
	{ movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4, play = PAUSES }

local function present(s: Session.Session): { boolean }
	return Pellets.decode(SMALL, Session.frame(s, "p").pellets)
end

local function stepUntil(s: Session.Session, done: (Session.Event) -> boolean): number
	for n = 1, 200 do
		for _, e in Session.step(s) do
			if done(e) then
				return n
			end
		end
	end
	error("never happened")
end

local function eaten(x: number): (Session.Event) -> boolean
	return function(e)
		return e.kind == "PelletEaten" and e.x == x
	end
end

return t.spec("f0290 Session.frame pellets", function(it)
	it("a new player's frame has every pellet", function()
		local s = Session.new(SMALL, 1, RULES)
		Session.join(s, "p")
		local frame = Session.frame(s, "p")
		t.expect(type(frame.pellets)).toBe("string")
		t.expect(frame.pellets).toBe(Pellets.encode(Pellets.new(SMALL)))
		t.expect(present(s)).toEqual({ true, true, true })
	end)

	it("the frame after a PelletEaten event shows that pellet gone, and only that one", function()
		local s = Session.new(SMALL, 1, RULES)
		Session.join(s, "p")
		stepUntil(s, eaten(3))
		t.expect(present(s)).toEqual({ true, true, false })
		stepUntil(s, eaten(2))
		t.expect(present(s)).toEqual({ true, false, false })
	end)

	it("a death keeps the eaten pellets gone", function()
		local s = Session.new(SMALL, 1, RULES)
		Session.join(s, "p")
		stepUntil(s, eaten(3))
		Session.kill(s, "p")
		stepUntil(s, function(e)
			return e.kind == "Ready" and e.reason == "respawn"
		end)
		t.expect(Session.frame(s, "p").play.phase).toBe("ready")
		t.expect(present(s)).toEqual({ true, true, false })
	end)

	it("the next level's frame has every pellet back", function()
		local s = Session.new(SMALL, 1, RULES)
		Session.join(s, "p")
		stepUntil(s, function(e)
			return e.kind == "LevelCleared"
		end)
		t.expect(present(s)).toEqual({ false, false, false })
		stepUntil(s, function(e)
			return e.kind == "Ready" and e.reason == "level"
		end)
		t.expect(Session.frame(s, "p").play.level).toBe(2)
		t.expect(present(s)).toEqual({ true, true, true })
	end)

	it("playing again brings every pellet back in the very next frame", function()
		local s = Session.new(SMALL, 1, RULES)
		Session.join(s, "p")
		stepUntil(s, eaten(3))
		-- three deaths, each in play: the run is over
		for life = 1, 3 do
			t.expect(#Session.kill(s, "p")).toBe(1)
			stepUntil(s, function(e)
				return e.kind == "Ready" or e.kind == "GameOver"
			end)
			if life < 3 then
				stepUntil(s, function(e)
					return e.kind == "Playing"
				end)
			end
		end
		t.expect(Session.frame(s, "p").play.phase).toBe("gameover")
		t.expect(present(s)[3]).toBe(false)
		local _, ok = Session.playAgain(s, "p")
		t.expect(ok).toBe(true)
		t.expect(present(s)).toEqual({ true, true, true })
	end)

	it("each player's frame shows their own pellets", function()
		local s = Session.new(SMALL, 1, RULES)
		Session.join(s, "a")
		stepUntil(s, function(e)
			return e.kind == "PelletEaten" and e.player == "a"
		end)
		Session.join(s, "b")
		t.expect(Pellets.decode(SMALL, Session.frame(s, "a").pellets)).toEqual({ true, true, false })
		t.expect(Pellets.decode(SMALL, Session.frame(s, "b").pellets)).toEqual({ true, true, true })
	end)

	it("the frame with pellets still round-trips through JSON, and the v1 snapshot has no pellets", function()
		local s = Session.new(SMALL, 1, RULES)
		Session.join(s, "p")
		stepUntil(s, eaten(3))
		local frame = Session.frame(s, "p")
		-- c0153: plain data, and a JSON round trip within 1e-9 (Lune's JSON decoder can return a number one ulp off)
		t.expect({ plain.roundTrip(frame, 1e-9) }).toEqual({ true })
		t.expect((Session.snapshot(s, "p") :: any).pellets).toBe(nil)
	end)

	it("a classic frame's pellets are 41 characters, whatever has been eaten", function()
		local m = Maze.layout(Maze.DEFAULT)
		local s = Session.new(m, 1, Session.GAME_CONFIG)
		Session.join(s, "p")
		t.expect(#Session.frame(s, "p").pellets).toBe(41)
		for _ = 1, 300 do
			Session.step(s)
		end
		t.expect(#Session.frame(s, "p").pellets).toBe(41)
		t.expect(Session.frame(s, "p").pellets ~= string.rep("_", 40) .. "P").toBe(true)
	end)
end)
