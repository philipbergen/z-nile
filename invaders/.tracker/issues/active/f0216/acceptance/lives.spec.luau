--!strict
-- f0216 AC5: lives. The game starts with 3; an alien's shot that reaches the cannon costs one, clears every shot
-- and pauses the field for the dying pause (120 ticks: nothing moves, input is ignored), after which the cannon
-- comes back at its start. One extra life comes at 1,500 points, once a game. The last life lost is game over
-- (reason "lives").
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local t = require("@tests/lib/t")

local CFG = Classic.CONFIG

local function run(g: Classic.Game, n: number, input: Classic.Input?): { Classic.Event }
	local all = {}
	for _ = 1, n do
		for _, e in Classic.step(g, input) do
			table.insert(all, e)
		end
	end
	return all
end

local function kinds(events: { Classic.Event }): { string }
	local out = {}
	for _, e in events do
		table.insert(out, e.kind)
	end
	return out
end

-- a bomb one tick from the cannon
local function drop(g: Classic.Game)
	table.insert(g.bombs, { x = g.cannon, d = CFG.cannonDepth, slot = 2 })
end

local function quiet(): Classic.Game
	local g = Classic.new(1)
	g.reloadElapsed = -100000
	g.formation.elapsed = -100000
	return g
end

return t.spec("f0216 lives", function(it)
	it("starts with 3 lives, no score, wave 1, no revives, playing", function()
		local g = Classic.new(1)
		t.expect(g.lives).toBe(3)
		t.expect(g.score).toBe(0)
		t.expect(g.wave).toBe(1)
		t.expect(g.revives).toBe(0)
		t.expect(g.phase).toBe("playing")
		t.expect(g.cannon).toBe(CFG.cannonStart)
		t.expect(CFG.cannonStart).toBe(CFG.fieldWidth // 2)
	end)

	it("loses a life to a hit, clears the shots and pauses 120 ticks with nothing moving", function()
		local g = quiet()
		g.cannon = 40
		g.shot = { x = 10, d = 100 }
		table.insert(g.bombs, { x = 150, d = 100, slot = 3 })
		drop(g)
		g.formation.elapsed = 0
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "CannonHit" })
		t.expect(e[1].lives).toBe(2)
		t.expect(g.lives).toBe(2)
		t.expect(g.phase).toBe("dying")
		t.expect(g.shot).toBe(nil)
		t.expect(#g.bombs).toBe(0)
		t.expect(CFG.dyingTicks).toBe(120) -- 2 s at 60 ticks a second
		local fx, fd = g.formation.x, g.formation.d
		g.reloadElapsed = 1000
		g.mystery.elapsed = CFG.mystery.every
		local during = run(g, CFG.dyingTicks - 1, { move = 1, fire = true })
		t.expect(#during).toBe(0)
		t.expect(g.phase).toBe("dying")
		t.expect(g.cannon).toBe(40)
		t.expect(g.shot).toBe(nil)
		t.expect(#g.bombs).toBe(0)
		t.expect(g.formation.x).toBe(fx)
		t.expect(g.formation.d).toBe(fd)
		t.expect(g.mystery.x).toBe(nil)
		local back = run(g, 1, { move = 1, fire = true })
		t.expect(kinds(back)).toEqual({ "Respawn" })
		t.expect(back[1].lives).toBe(2)
		t.expect(g.phase).toBe("playing")
		t.expect(g.cannon).toBe(CFG.cannonStart)
		-- and the next tick plays
		local after = run(g, 1, { fire = true })
		t.expect(g.shot ~= nil).toBe(true)
		t.expect(table.find(kinds(after), "PlayerFire") ~= nil).toBe(true)
	end)

	it("ends the game when the last life is lost, and then nothing changes", function()
		local g = quiet()
		g.lives = 1
		drop(g)
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "CannonHit", "GameOver" })
		t.expect(e[2].reason).toBe("lives")
		t.expect(g.phase).toBe("gameover")
		t.expect(g.reason).toBe("lives")
		t.expect(g.lives).toBe(0)
		local score, fx = g.score, g.formation.x
		g.formation.elapsed = 0
		t.expect(#run(g, 500, { move = 1, fire = true })).toBe(0)
		t.expect(g.score).toBe(score)
		t.expect(g.formation.x).toBe(fx)
		t.expect(g.shotsFired).toBe(0)
	end)

	it("ends the tick at a hit: no march, no alien fire and no invasion that tick", function()
		local function due(lives: number): Classic.Game
			local g = Classic.new(1)
			g.lives = lives
			local f = g.formation
			-- the formation one advance above the line, its next move due this tick, and that move an advance
			f.d = CFG.invasionDepth + Formation.CLASSIC.rowStep
			f.x = Formation.CLASSIC.fieldWidth - Formation.CLASSIC.margin - 172
			f.elapsed = Formation.interval(f) - 1
			-- an alien shot due this tick too
			g.reloadElapsed = Classic.reloadTicks(0) - 1
			drop(g)
			return g
		end
		local g = due(3)
		local fx, fd = g.formation.x, g.formation.d
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "CannonHit" })
		t.expect(g.phase).toBe("dying")
		t.expect(g.formation.x).toBe(fx)
		t.expect(g.formation.d).toBe(fd)
		t.expect(#g.bombs).toBe(0)
		t.expect(#run(g, CFG.dyingTicks - 1)).toBe(0)
		t.expect(#g.bombs).toBe(0)
		local last = due(1)
		e = run(last, 1)
		t.expect(kinds(e)).toEqual({ "CannonHit", "GameOver" })
		t.expect(e[2].reason).toBe("lives")
		t.expect(last.reason).toBe("lives")
		t.expect(last.formation.d).toBe(fd)
		-- the same set-up with no shot on the cannon does invade that tick: the case can see the order
		local control = due(3)
		control.bombs = {}
		local c = kinds(run(control, 1))
		t.expect(c[#c]).toBe("GameOver")
		t.expect(control.reason).toBe("invasion")
	end)

	it("lets the mystery ship's points win the extra life", function()
		local g = quiet()
		g.cannon = 56 -- in the gaps between bunkers 1 and 2 and between columns 2 and 3
		g.score = 1450
		g.shotsFired = 22 -- the 23rd shot is worth 300
		g.mystery.elapsed = CFG.mystery.every - 1
		local e = {}
		for _ = 1, 400 do
			local fire = g.mystery.x == -10 and g.shot == nil
			for _, ev in Classic.step(g, { fire = fire }) do
				table.insert(e, ev)
			end
			if g.score > 1450 then
				break
			end
		end
		local k = kinds(e)
		t.expect(g.score).toBe(1750)
		t.expect(g.lives).toBe(4)
		t.expect(table.find(k, "MysteryHit") ~= nil).toBe(true)
		t.expect(table.find(k, "ExtraLife") :: number > (table.find(k, "MysteryHit") :: number)).toBe(true)
	end)

	it("gives one extra life at 1,500 points, once", function()
		local g = quiet()
		g.score = 1480
		g.cannon = 112 -- under column 6, between bunkers 2 and 3
		-- the back row of column 6 is the first alien the shot reaches: 30 points takes the score past 1,500
		for row = 1, 4 do
			Formation.kill(g.formation, row, 6)
		end
		run(g, 1, { fire = true })
		local e = run(g, 80)
		t.expect(g.score).toBe(1510)
		t.expect(g.lives).toBe(4)
		local k = kinds(e)
		t.expect(table.find(k, "ExtraLife") ~= nil).toBe(true)
		t.expect(table.find(k, "ExtraLife") :: number > (table.find(k, "AlienHit") :: number)).toBe(true)
		t.expect(e[table.find(k, "ExtraLife") :: number].lives).toBe(4)
		-- past it again (a revive keeps the score): no second extra life
		g.score = 1495
		g.cannon = 160 -- under column 9, between bunkers 3 and 4
		run(g, 1, { fire = true })
		run(g, 80)
		t.expect(g.score >= 1500).toBe(true)
		t.expect(g.lives).toBe(4)
	end)

	it("gives the extra life at exactly 1,500, not before", function()
		local g = quiet()
		g.cannon = 112
		g.score = 1489
		run(g, 1, { fire = true })
		run(g, 60)
		t.expect(g.score).toBe(1499)
		t.expect(g.lives).toBe(3)
		g.score = 1490
		run(g, 1, { fire = true })
		run(g, 60)
		t.expect(g.score).toBe(1500)
		t.expect(g.lives).toBe(4)
	end)
end)
