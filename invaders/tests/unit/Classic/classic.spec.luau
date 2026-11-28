--!strict
-- Classic unit specs: extra input keys, aimed column tie-break, and extracted public step functions.
local Classic = require("@logic/Classic")
local t = require("@tests/lib/t")

return t.spec("Classic unit", function(it)
	it("ignores extra keys in input and steps deterministically", function()
		local g = Classic.new(7)
		local startX = g.cannon
		local input: any = { move = 1, fire = false, bogus = 999 }
		Classic.step(g, input)
		t.expect(g.cannon).toBe(startX + 1)
		t.expect(g.shot).toBe(nil)
	end)

	it("computes waveDepth and reloadTicks monotonically", function()
		t.expect(Classic.waveDepth(1)).toBe(120)
		t.expect(Classic.waveDepth(9)).toBe(120)
		t.expect(Classic.reloadTicks(0)).toBe(48)
		t.expect(Classic.reloadTicks(3000)).toBe(7)
	end)

	it("breaks aimed-column ties toward the lower column", function()
		local g = Classic.new(7)
		-- col 1 centre = 32, col 2 centre = 48 -> equidistant at cannon = 40
		g.cannon = 40
		g.reloadElapsed = Classic.reloadTicks(0) - 1
		g.nextSlot = 1
		local events: { Classic.Event } = {}
		Classic.alienFire(g, events)
		t.expect(#events).toBe(1)
		t.expect(events[1].kind).toBe("AlienFire")
		t.expect(events[1].slot).toBe(1)
		t.expect(events[1].col).toBe(1)
	end)

	it("accepts a custom config in Classic.new", function()
		local cfg = table.clone(Classic.CONFIG)
		cfg.lives = 5
		cfg.cannonStart = 100
		local g = Classic.new(7, cfg)
		t.expect(g.lives).toBe(5)
		t.expect(g.cannon).toBe(100)
	end)

	it("sanitizes nil, non-table, and junk inputs", function()
		local m1, f1 = Classic.sanitize(nil)
		t.expect({ m1, f1 }).toEqual({ 0, false })

		local m2, f2 = Classic.sanitize(("junk" :: any))
		t.expect({ m2, f2 }).toEqual({ 0, false })

		local m3, f3 = Classic.sanitize({ move = 2, fire = ("yes" :: any) } :: any)
		t.expect({ m3, f3 }).toEqual({ 0, false })

		local m4, f4 = Classic.sanitize({ move = -1, fire = true })
		t.expect({ m4, f4 }).toEqual({ -1, true })

		local m5, f5 = Classic.sanitize({ move = 1, fire = false })
		t.expect({ m5, f5 }).toEqual({ 1, false })
	end)

	it("moves and clamps cannon and fires at most one shot", function()
		local g = Classic.new(7)
		g.cannon = g.config.cannonHalf
		Classic.moveCannon(g, -1)
		t.expect(g.cannon).toBe(g.config.cannonHalf)
		Classic.moveCannon(g, 1)
		t.expect(g.cannon).toBe(g.config.cannonHalf + g.config.cannonSpeed)

		local events: { Classic.Event } = {}
		Classic.fire(g, true, events)
		t.expect(g.shot ~= nil).toBe(true)
		t.expect(g.shotsFired).toBe(1)
		t.expect(#events).toBe(1)
		t.expect(events[1].kind).toBe("PlayerFire")

		Classic.fire(g, true, events)
		t.expect(g.shotsFired).toBe(1)
		t.expect(#events).toBe(1)
	end)

	it("awards an extra life once when crossing extraLifeScore", function()
		local g = Classic.new(7)
		local events: { Classic.Event } = {}
		Classic.addScore(g, g.config.extraLifeScore - 10, events)
		t.expect(g.lives).toBe(3)
		t.expect(#events).toBe(0)

		Classic.addScore(g, 10, events)
		t.expect(g.lives).toBe(4)
		t.expect(g.extraLifeGiven).toBe(true)
		t.expect(#events).toBe(1)
		t.expect(events[1].kind).toBe("ExtraLife")

		Classic.addScore(g, 500, events)
		t.expect(g.lives).toBe(4)
		t.expect(#events).toBe(1)
	end)

	it("moves bombs and detects cannon hits and misses", function()
		local g = Classic.new(7)
		g.bombs = { { x = 0, d = 0, slot = 2 } }
		local events: { Classic.Event } = {}
		t.expect(Classic.moveBombs(g, events)).toBe(false)
		t.expect(#g.bombs).toBe(0)

		g.bombs = { { x = g.cannon, d = g.config.cannonDepth, slot = 1 } }
		t.expect(Classic.moveBombs(g, events)).toBe(true)
	end)

	it("handles Classic.hit on non-last and last life", function()
		local g = Classic.new(7)
		g.lives = 2
		local ev1: { Classic.Event } = {}
		Classic.hit(g, ev1)
		t.expect(g.lives).toBe(1)
		t.expect(g.phase).toBe("dying")
		t.expect(g.timer).toBe(g.config.dyingTicks)
		t.expect(ev1[1].kind).toBe("CannonHit")

		local ev2: { Classic.Event } = {}
		Classic.hit(g, ev2)
		t.expect(g.lives).toBe(0)
		t.expect(g.phase).toBe("gameover")
		t.expect(g.reason).toBe("lives")
		t.expect(ev2[1].kind).toBe("CannonHit")
		t.expect(ev2[2].kind).toBe("GameOver")
		t.expect(ev2[2].reason).toBe("lives")
	end)

	it("returns true from Classic.march on invasion and resets state in Classic.startWave", function()
		local g = Classic.new(7)
		local fc = g.formation.config
		local span = (fc.cols - 1) * fc.colSpacing + fc.width
		g.formation.x = fc.fieldWidth - fc.margin - span
		g.formation.dir = 1
		g.formation.d = g.config.invasionDepth + fc.rowStep
		g.formation.elapsed = g.formation.live - 1
		local events: { Classic.Event } = {}
		t.expect(Classic.march(g, events)).toBe(true)
		t.expect(g.phase).toBe("gameover")
		t.expect(g.reason).toBe("invasion")

		g.wave = 2
		g.shot = { x = 50, d = 50 }
		g.bombs = { { x = 50, d = 50, slot = 1 } }
		Classic.startWave(g)
		t.expect(g.phase).toBe("playing")
		t.expect(g.shot).toBe(nil)
		t.expect(#g.bombs).toBe(0)
		t.expect(g.cannon).toBe(g.config.cannonStart)
		t.expect(g.formation.d).toBe(Classic.waveDepth(2))
	end)
end)
