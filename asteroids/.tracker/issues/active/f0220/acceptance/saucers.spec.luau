--!strict
-- f0220 AC5: the saucers. One at a time; the next appears once the field has had none for the wave's wait (900
-- ticks in wave 1, 120 fewer each wave, never under 360). It is small when draw(8) is at most the wave's share
-- in eighths (1 in wave 1, one more a wave, 7 from wave 7), else large; it comes in from the left or the right
-- edge at a drawn height, crosses the field edge to edge (wrapping only top to bottom), changes course every
-- 60 ticks, and leaves. The large saucer (200) fires every 60 ticks in a drawn direction; the small one (1,000)
-- fires every 40 ticks at the ship across the wrap, off by at most its spread: 16 headings, 8 from 10,000
-- points, 4 from 20,000 and none from 40,000. A saucer fires only while the ship is on the field. Its shots fly
-- 60 ticks at 6 a tick and destroy an exposed ship. Saucers and their shots pass through rocks (prep).
local Classic = require("@logic/Classic")
local Field = require("@logic/Field")
local Saucers = require("@logic/Saucers")
local t = require("@tests/lib/t")

local CFG = Classic.CONFIG
local SC = Saucers.CLASSIC
local F = Field.CLASSIC

local function quiet(seed: number?): Classic.Game
	local g = Classic.new(seed or 1)
	g.rocks = {}
	g.waveTimer = 1e9 -- no next wave in this case
	return g
end

local function run(g: Classic.Game, n: number, input: Classic.Input?): { Classic.Event }
	local all = {}
	for _ = 1, n do
		for _, e in Classic.step(g, input) do
			table.insert(all, e)
		end
	end
	return all
end

local function count(events: { Classic.Event }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function kinds(events: { Classic.Event }): { string }
	local out = {}
	for _, e in events do
		table.insert(out, e.kind)
	end
	return out
end

-- a draw that returns the given values in turn and records what it was asked for
local function script(values: { number }): (Saucers.Draw, { number })
	local asked = {}
	local i = 0
	return function(n: number): number
		table.insert(asked, n)
		i += 1
		return values[i]
	end, asked
end

local function still(kind: Saucers.Kind, x: number, y: number): Saucers.Saucer
	return { kind = kind, x = x, y = y, vx = 0, vy = 0, travelled = 0, fireElapsed = -1e9, turnElapsed = -1e9 }
end

return t.spec("f0220 saucers", function(it)
	it("waits 900 ticks in wave 1, 120 fewer each wave, never under 360", function()
		t.expect(Saucers.wait(SC, 1)).toBe(900)
		t.expect(Saucers.wait(SC, 2)).toBe(780)
		t.expect(Saucers.wait(SC, 3)).toBe(660)
		t.expect(Saucers.wait(SC, 5)).toBe(420)
		t.expect(Saucers.wait(SC, 6)).toBe(360)
		t.expect(Saucers.wait(SC, 20)).toBe(360)
		t.expect(CFG.saucers).toBe(SC)
	end)

	it(
		"appears once the field has had no saucer for the wave's wait, whether or not the ship is there",
		function()
			local g = quiet()
			local e = run(g, 899)
			t.expect(count(e, "SaucerAppear")).toBe(0)
			t.expect(g.saucer).toBe(nil)
			e = Classic.step(g, nil)
			t.expect(count(e, "SaucerAppear")).toBe(1)
			t.expect(g.saucer ~= nil).toBe(true)
			t.expect(e[1].saucer).toBe((g.saucer :: Saucers.Saucer).kind)
			-- it neither moves nor fires on the tick it appears
			t.expect((g.saucer :: Saucers.Saucer).x).toBe(0)
			t.expect((g.saucer :: Saucers.Saucer).travelled).toBe(0)
			t.expect(count(e, "SaucerFire")).toBe(0)

			-- in wave 3, 660 ticks
			local h = quiet()
			h.wave = 3
			t.expect(count(run(h, 659), "SaucerAppear")).toBe(0)
			t.expect(count(run(h, 1), "SaucerAppear")).toBe(1)

			-- the wait runs while the ship is lost
			local k = quiet()
			k.shipState = "dead"
			k.timer = 1e9
			t.expect(count(run(k, 899), "SaucerAppear")).toBe(0)
			t.expect(count(run(k, 1), "SaucerAppear")).toBe(1)
		end
	)

	it(
		"is small on a draw of at most the wave's share in eighths, and comes in level from a drawn side and height",
		function()
			local draw, asked = script({ 1, 1, 100 })
			local s = Saucers.appear(SC, F, 1, draw)
			t.expect(asked).toEqual({ 8, 2, 768 })
			t.expect(s.kind).toBe("small")
			t.expect(s.x).toBe(0)
			t.expect(s.y).toBe(99)
			t.expect(s.vx).toBe(3)
			t.expect(s.vy).toBe(0)
			s = Saucers.appear(SC, F, 1, (script({ 2, 2, 1 })))
			t.expect(s.kind).toBe("large")
			t.expect(s.x).toBe(0)
			t.expect(s.y).toBe(0)
			t.expect(s.vx).toBe(-2)
			for _, case in { { 2, 2 }, { 3, 3 }, { 6, 6 }, { 7, 7 }, { 12, 7 } } do
				local wave, share = case[1], case[2]
				t.expect(Saucers.appear(SC, F, wave, (script({ share, 1, 1 }))).kind).toBe("small")
				t.expect(Saucers.appear(SC, F, wave, (script({ share + 1, 1, 1 }))).kind).toBe("large")
			end
		end
	)

	it("crosses the field edge to edge and leaves: the large in 512 ticks, the small in 342", function()
		local cases: { { kind: Saucers.Kind, side: number, ticks: number } } =
			{ { kind = "large", side = 1, ticks = 512 }, { kind = "small", side = 2, ticks = 342 } }
		for _, case in cases do
			local kind, side, ticks = case.kind :: Saucers.Kind, case.side, case.ticks
			local g = quiet()
			g.saucerElapsed = -1e9
			local s = Saucers.appear(SC, F, 1, (script({ if kind == "small" then 1 else 8, side, 600 })))
			s.fireElapsed = -1e9
			g.saucer = s
			local e = run(g, 100)
			local speed = SC[kind].speed
			t.expect(s.x).toBe(if side == 1 then 100 * speed else 1024 - 100 * speed)
			t.expect(count(e, "SaucerLeave")).toBe(0)
			e = run(g, ticks - 101)
			t.expect(count(e, "SaucerLeave")).toBe(0)
			t.expect(g.saucer).toBe(s)
			e = Classic.step(g, nil)
			t.expect(kinds(e)).toEqual({ "SaucerLeave" })
			t.expect(e[1].saucer).toBe(kind)
			t.expect(g.saucer).toBe(nil)
		end
	end)

	it("changes course every 60 ticks: down, level or up at its own speed", function()
		local seen = {}
		for seed = 1, 6 do
			local g = quiet(seed)
			g.saucerElapsed = -1e9
			local s = Saucers.appear(SC, F, 1, (script({ 8, 1, 300 })))
			s.fireElapsed = -1e9
			g.saucer = s
			local vy = s.vy
			for tick = 1, 500 do
				Classic.step(g, nil)
				if tick % 60 ~= 0 then
					t.expect(s.vy).toBe(vy)
				end
				vy = s.vy
				t.expect(vy == -2 or vy == 0 or vy == 2).toBe(true)
				if tick >= 60 then
					seen[vy] = true
				end
			end
		end
		t.expect(seen[-2] and seen[0] and seen[2]).toBe(true)
	end)

	it("the large saucer fires every 60 ticks from its centre, in a drawn direction", function()
		local draw, asked = script({ 65 })
		t.expect(Saucers.aim(still("large", 10, 10), SC, F, 0, 500, 500, draw)).toBe(64)
		t.expect(asked).toEqual({ 256 })

		local g = quiet()
		g.saucerElapsed = -1e9
		local s = Saucers.appear(SC, F, 1, (script({ 8, 1, 700 })))
		s.turnElapsed = -1e9
		g.saucer = s
		local e = run(g, 59)
		t.expect(count(e, "SaucerFire")).toBe(0)
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "SaucerFire" })
		t.expect(e[1].saucer).toBe("large")
		t.expect(#g.saucerShots).toBe(1)
		local shot = g.saucerShots[1]
		t.expect(math.sqrt(shot.vx ^ 2 + shot.vy ^ 2)).toBeNear(6, 1e-9)
		-- it started at the saucer's centre and has moved once
		t.expect(shot.x - shot.vx).toBeNear(120, 1e-9)
		t.expect(shot.y - shot.vy).toBeNear(699, 1e-9)
		t.expect(shot.life).toBe(59)
		e = run(g, 59)
		t.expect(count(e, "SaucerFire")).toBe(0)
		e = Classic.step(g, nil)
		t.expect(count(e, "SaucerFire")).toBe(1)
	end)

	it("the small saucer fires every 40 ticks, aimed at the ship", function()
		local g = quiet()
		g.saucerElapsed = -1e9
		g.score = 50000
		local s = Saucers.appear(SC, F, 1, (script({ 1, 1, 384 })))
		s.turnElapsed = -1e9
		g.saucer = s
		local e = run(g, 39)
		t.expect(count(e, "SaucerFire")).toBe(0)
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "SaucerFire" })
		t.expect(e[1].saucer).toBe("small")
		-- the saucer is level with the ship, to its left: the shot heads straight along +x
		local shot = g.saucerShots[1]
		t.expect(shot.vx).toBeNear(6, 1e-9)
		t.expect(shot.vy).toBeNear(0, 1e-9)
	end)

	it("aims the small saucer's shot the short way across the wrap", function()
		local draw, asked = script({ 1 })
		t.expect(Saucers.aim(still("small", 1000, 100), SC, F, 40000, 50, 100, draw)).toBe(0)
		t.expect(asked).toEqual({ 1 })
		t.expect(Saucers.aim(still("small", 100, 700), SC, F, 40000, 100, 20, (script({ 1 })))).toBe(64)
		t.expect(Saucers.aim(still("small", 100, 100), SC, F, 40000, 100, 300, (script({ 1 })))).toBe(64)
	end)

	it(
		"aims more closely as the score rises: a spread of 16, 8 from 10,000, 4 from 20,000, none from 40,000",
		function()
			for _, case in
				{
					{ 0, 33 },
					{ 9999, 33 },
					{ 10000, 17 },
					{ 19999, 17 },
					{ 20000, 9 },
					{ 39999, 9 },
					{ 40000, 1 },
					{ 1e6, 1 },
				}
			do
				local score, n = case[1], case[2]
				local draw, asked = script({ 1 })
				Saucers.aim(still("small", 100, 100), SC, F, score, 300, 100, draw)
				t.expect(asked).toEqual({ n })
			end
			-- the draw's ends are the spread either way
			t.expect(Saucers.aim(still("small", 100, 100), SC, F, 0, 300, 100, (script({ 1 })))).toBe(240)
			t.expect(Saucers.aim(still("small", 100, 100), SC, F, 0, 300, 100, (script({ 33 })))).toBe(16)
			t.expect(Saucers.aim(still("small", 100, 100), SC, F, 0, 300, 100, (script({ 17 })))).toBe(0)
		end
	)

	it("aims from the run's own score", function()
		local hits = 0
		for seed = 1, 40 do
			local h = quiet(seed)
			h.saucerElapsed = -1e9
			h.score = 0
			local s = still("small", 312, 384)
			s.fireElapsed = SC.small.fireTicks - 1
			h.saucer = s
			Classic.step(h, nil)
			local shot = h.saucerShots[1]
			if math.abs(shot.vy) > 1e-9 then
				hits += 1
			end
		end
		-- at score 0 the spread is 16 headings, so nearly every shot is off the straight line
		t.expect(hits >= 30).toBe(true)
	end)

	it("fires only while the ship is on the field, and a shot due while it is away waits for it", function()
		local g = quiet()
		g.saucerElapsed = -1e9
		local s = still("large", 100, 700)
		s.fireElapsed = 0
		g.saucer = s
		g.shipState = "hyperspace"
		g.timer = 1e9
		local e = run(g, 100)
		t.expect(count(e, "SaucerFire")).toBe(0)
		g.shipState = "dead"
		e = run(g, 100)
		t.expect(count(e, "SaucerFire")).toBe(0)
		g.shipState = "alive"
		g.timer = 0
		e = Classic.step(g, nil)
		t.expect(count(e, "SaucerFire")).toBe(1)

		-- a protected ship is on the field: the saucer fires at it
		local h = quiet()
		h.saucerElapsed = -1e9
		h.protect = 50
		local p = still("large", 100, 700)
		p.fireElapsed = 59
		h.saucer = p
		e = Classic.step(h, nil)
		t.expect(count(e, "SaucerFire")).toBe(1)
	end)

	it("its shot destroys an exposed ship, and passes a protected one", function()
		local g = quiet()
		g.saucerElapsed = -1e9
		g.saucerShots = { { x = 512 - 15, y = 384, vx = 6, vy = 0, life = 30 } }
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "ShipDestroyed" })
		t.expect(e[1].cause).toBe("saucershot")
		t.expect(e[1].lives).toBe(2)
		t.expect(#g.saucerShots).toBe(0)

		local h = quiet()
		h.saucerElapsed = -1e9
		h.protect = 50
		h.saucerShots = { { x = 512 - 15, y = 384, vx = 6, vy = 0, life = 30 } }
		e = Classic.step(h, nil)
		t.expect(#e).toBe(0)
		t.expect(h.lives).toBe(3)
		t.expect(#h.saucerShots).toBe(1)
		t.expect(h.saucerShots[1].x).toBe(512 - 9)
		t.expect(SC.shotLife).toBe(60)
		t.expect(SC.shotSpeed).toBe(6)
	end)

	it("scores 200 for a shot large saucer and 1,000 for a small one, and starts the wait again", function()
		local function shoot(kind: Saucers.Kind, points: number)
			local g = quiet()
			g.saucer = still(kind, 300, 100)
			g.saucerElapsed = 500
			g.shots = { { x = 300 - SC[kind].radius - 1, y = 100, vx = 2, vy = 0, life = 30 } }
			local e = Classic.step(g, nil)
			t.expect(kinds(e)).toEqual({ "SaucerHit" })
			t.expect(e[1].saucer).toBe(kind)
			t.expect(e[1].points).toBe(points)
			t.expect(e[1].by).toBe("shot")
			t.expect(g.score).toBe(points)
			t.expect(g.saucer).toBe(nil)
			t.expect(#g.shots).toBe(0)
			e = run(g, 899)
			t.expect(count(e, "SaucerAppear")).toBe(0)
			t.expect(count(run(g, 1), "SaucerAppear")).toBe(1)
		end
		shoot("large", 200)
		shoot("small", 1000)
	end)

	it("costs a life when the ship rams a saucer, and scores it", function()
		local g = quiet()
		g.saucer = still("large", 512 + 31.9, 384)
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "SaucerHit", "ShipDestroyed" })
		t.expect(e[1].by).toBe("ship")
		t.expect(e[1].points).toBe(200)
		t.expect(e[2].cause).toBe("saucer")
		t.expect(g.score).toBe(200)
		t.expect(g.lives).toBe(2)
		t.expect(g.saucer).toBe(nil)

		local h = quiet()
		h.saucer = still("small", 512, 384 - 22.1)
		Classic.step(h, nil)
		t.expect(h.lives).toBe(3)
		h.saucer = still("small", 512, 384 - 21.9)
		Classic.step(h, nil)
		t.expect(h.lives).toBe(2)
	end)

	it("passes through rocks, and so do its shots (prep)", function()
		local g = quiet()
		g.saucerElapsed = -1e9
		table.insert(g.rocks, { id = 900, size = "large", x = 200, y = 200, vx = 0, vy = 0 })
		g.saucer = still("large", 200, 200)
		g.saucerShots = { { x = 180, y = 200, vx = 6, vy = 0, life = 30 } }
		local e = run(g, 5)
		t.expect(#e).toBe(0)
		t.expect(#g.rocks).toBe(1)
		t.expect(g.saucer ~= nil).toBe(true)
		t.expect(#g.saucerShots).toBe(1)
	end)
end)
