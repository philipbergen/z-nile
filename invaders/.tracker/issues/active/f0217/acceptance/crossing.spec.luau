--!strict
-- f0217 AC3: a shot crosses the whole field. A player's shot flies from their cannon to the other player's base
-- line, one unit at a time, and on the way can hit their own bunkers (from the near side) and the other player's
-- (from those bunkers' far side), either group (for the shooter's score) and the ship at the midline. By default it
-- stops at the other player's base line and can't hurt them (shotsHitPlayers = false); with shotsHitPlayers it
-- costs them a life when it reaches their cannon. Player 1's shot moves first.
local Barriers = require("@logic/Barriers")
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local Mystery = require("@logic/Mystery")
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

local CFG = TwoPlayer.CONFIG
local C = Classic.CONFIG
local W = C.fieldWidth
local D = CFG.fieldDepth

-- the kinds of the events this issue defines, in order (a kind a later issue adds is not this spec's)
local KINDS = {}
for _, k in
	{
		"PlayerFire",
		"BarrierHit",
		"AlienHit",
		"MysteryHit",
		"ExtraLife",
		"GroupClear",
		"WaveClear",
		"CannonHit",
		"GameOver",
	}
do
	KINDS[k] = true
end
for _, k in
	{ "March", "Advance", "AlienFire", "MysteryAppear", "MysteryLeave", "Respawn", "WaveStart", "Formed" }
do
	KINDS[k] = true
end

local function kinds(events: { TwoPlayer.Event }): { string }
	local out = {}
	for _, e in events do
		if KINDS[e.kind] then
			table.insert(out, e.kind)
		end
	end
	return out
end

-- only the events of the kinds this issue defines, in order
local function known(events: { TwoPlayer.Event }): { TwoPlayer.Event }
	local out = {}
	for _, e in events do
		if KINDS[e.kind] then
			table.insert(out, e)
		end
	end
	return out
end

local function quiet(g: TwoPlayer.Match)
	for _, side in g.sides do
		side.run.reloadElapsed = -1000000
		side.run.formation.elapsed = -1000000
	end
	g.mystery.elapsed = -1000000
end

-- both groups in place, nothing marching or firing
local function formed(config: TwoPlayer.Config?): TwoPlayer.Match
	local g = TwoPlayer.new(1, config)
	while g.phase == "flyin" do
		TwoPlayer.step(g, nil)
	end
	quiet(g)
	return g
end

local function run(g: TwoPlayer.Match, n: number): { TwoPlayer.Event }
	local all = {}
	for _ = 1, n do
		quiet(g)
		for _, e in TwoPlayer.step(g, nil) do
			table.insert(all, e)
		end
	end
	return known(all)
end

return t.spec("f0217 crossing", function(it)
	it("carries a shot across the whole field and stops it at the other player's base line", function()
		t.expect(CFG.shotsHitPlayers).toBe(false)
		local g = formed()
		-- a clear column: west of the bunkers and the groups; player 2's cannon stands in it
		g.sides[1].run.cannon = 20
		g.sides[2].run.cannon = W - 1 - 20
		TwoPlayer.step(g, { { fire = true } })
		local far, ticks, events = 0, 0, {}
		while g.sides[1].run.shot and ticks < 1000 do
			far = math.max(far, (g.sides[1].run.shot :: Classic.Shot).d)
			for _, e in run(g, 1) do
				table.insert(events, e)
			end
			ticks += 1
		end
		-- its last place is the unit before the other base line (the cannon's depth from the far end)
		t.expect(far).toBe(D - C.cannonDepth - 1)
		t.expect(#kinds(events)).toBe(0)
		t.expect(g.sides[2].run.lives).toBe(3)
		t.expect(g.sides[2].run.phase).toBe("playing")
	end)

	it("lets the shot hit the other player's group, for the shooter's score", function()
		for _, p in { 1, 2 } do
			local o = 3 - p
			local g = formed()
			-- the other group's front-left alien is at (162..174, 336..344) in the shooter's frame
			local x0, d0 = TwoPlayer.fieldBox(g, 2, Formation.box(g.sides[o].run.formation, 1, 1))
			t.expect(x0).toBe(162)
			t.expect(d0).toBe(336)
			g.sides[p].run.shot = { x = 168, d = 330 }
			local e = run(g, 2)
			t.expect(kinds(e)).toEqual({ "AlienHit" })
			t.expect(e[1].player).toBe(o)
			t.expect(e[1].shooter).toBe(p)
			t.expect(e[1].row).toBe(1)
			t.expect(e[1].col).toBe(1)
			t.expect(e[1].points).toBe(10)
			t.expect(g.sides[p].run.score).toBe(10)
			t.expect(g.sides[o].run.score).toBe(0)
			t.expect(g.sides[o].run.formation.live).toBe(39)
			t.expect(Formation.isAlive(g.sides[o].run.formation, 1, 1)).toBe(false)
			t.expect(g.sides[p].run.shot).toBe(nil)
		end
	end)

	it("erodes the other player's bunkers from their far side, and stops there", function()
		local g = formed()
		-- player 2's bunker 1, column 1, is at field x 194; its far row (6) at field depth 422..424
		g.sides[1].run.shot = { x = 194, d = D - 1 - 45 }
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "BarrierHit" })
		t.expect(e[1].player).toBe(2)
		t.expect(e[1].shooter).toBe(1)
		t.expect(e[1].slot).toBe(nil)
		t.expect(g.sides[1].run.shot).toBe(nil)
		local b = g.sides[2].run.barriers
		t.expect(Barriers.present(b, 1, 1, 6)).toBe(false)
		t.expect(Barriers.present(b, 1, 2, 6)).toBe(false)
		t.expect(Barriers.present(b, 1, 1, 5)).toBe(false)
		t.expect(Barriers.present(b, 1, 1, 4)).toBe(true)
		t.expect(Barriers.present(b, 1, 3, 6)).toBe(true)
		t.expect(Barriers.count(b)).toBe(4 * 48 - 3)
		t.expect(Barriers.count(g.sides[1].run.barriers)).toBe(4 * 48)
	end)

	it("hits the shooter's own bunkers from the near side, as in solo", function()
		local g = formed()
		g.sides[2].run.shot = { x = 29, d = 20 }
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "BarrierHit" })
		t.expect(e[1].player).toBe(2)
		t.expect(e[1].shooter).toBe(2)
		local b = g.sides[2].run.barriers
		t.expect(Barriers.present(b, 1, 1, 1)).toBe(false)
		t.expect(Barriers.present(b, 1, 2, 1)).toBe(false)
		t.expect(Barriers.present(b, 1, 1, 2)).toBe(false)
		t.expect(Barriers.count(b)).toBe(4 * 48 - 3)
		t.expect(Barriers.count(g.sides[1].run.barriers)).toBe(4 * 48)
	end)

	it("lets either player hit the ship at the midline, scored by the shooter's own shot count", function()
		t.expect(CFG.mystery.lane).toBe(D // 2 - 4)
		t.expect(CFG.mystery.depth).toBe(8)
		local g = formed()
		g.mystery.x = 100
		g.sides[2].run.shotsFired = 23
		g.sides[1].run.shotsFired = 1
		-- player 2's shot, coming from the far end down field x 105
		g.sides[2].run.shot = { x = W - 1 - 105, d = D - 1 - 240 }
		local e = run(g, 2)
		t.expect(kinds(e)).toEqual({ "MysteryHit" })
		t.expect(e[1].player).toBe(2)
		t.expect(e[1].points).toBe(300)
		t.expect(g.sides[2].run.score).toBe(300)
		t.expect(g.sides[1].run.score).toBe(0)
		t.expect(g.mystery.x).toBe(nil)
		t.expect(g.mystery.elapsed).toBe(0) -- the wait starts on the next tick
		-- player 1's 2nd shot scores by its own count
		g.mystery.x = 100
		g.sides[1].run.shot = { x = 105, d = 222 }
		local e2 = run(g, 2)
		t.expect(kinds(e2)).toEqual({ "MysteryHit" })
		t.expect(e2[1].player).toBe(1)
		t.expect(e2[1].points).toBe(Mystery.value(g.mystery, 1))
	end)

	it("brings the ship once the two groups together have 8 aliens alive", function()
		local function due(left1: number, left2: number): { string }
			local g = formed()
			for p, left in { left1, left2 } do
				local f = g.sides[p].run.formation
				local n = 0
				for row = 1, f.config.rows do
					for col = 1, f.config.cols do
						n += 1
						if n > left then
							Formation.kill(f, row, col)
						end
					end
				end
			end
			for _, side in g.sides do
				side.run.reloadElapsed = -1000000
				side.run.formation.elapsed = -1000000
			end
			g.mystery.elapsed = Mystery.CLASSIC.every - 1
			return kinds(TwoPlayer.step(g, nil))
		end
		t.expect(due(2, 6)).toEqual({ "MysteryAppear" })
		t.expect(due(6, 2)).toEqual({ "MysteryAppear" })
		t.expect(due(2, 5)).toEqual({})
	end)

	it("moves player 1's shot first when both reach the same alien on one tick", function()
		local g = formed()
		-- player 2's front-left alien: player 1 from below it, player 2 from its near side
		g.sides[1].run.shot = { x = 168, d = 334 }
		g.sides[2].run.shot = { x = 55, d = 116 }
		local e = run(g, 1)
		t.expect(kinds(e)).toEqual({ "AlienHit" })
		t.expect(e[1].shooter).toBe(1)
		t.expect(g.sides[1].run.score).toBe(10)
		t.expect(g.sides[2].run.score).toBe(0)
		t.expect(g.sides[2].run.shot ~= nil).toBe(true)
	end)

	it(
		"with shots that hit players, costs the other player a life at their cannon, and misses beside it",
		function()
			local config = table.clone(CFG) :: any
			config.shotsHitPlayers = true
			local g = formed(config)
			g.sides[2].run.cannon = W - 1 - 20
			g.sides[1].run.shot = { x = 20, d = 450 }
			run(g, 1)
			-- the hit's tick: both groups' steps are due; only the hit player's stops
			for p = 1, 2 do
				local f = g.sides[p].run.formation
				f.elapsed = Formation.interval(f) - 1
			end
			local e = known(TwoPlayer.step(g, nil))
			t.expect(kinds(e)).toEqual({ "CannonHit", "March" })
			t.expect(e[1].player).toBe(2)
			t.expect(e[1].shooter).toBe(1)
			t.expect(e[2].player).toBe(1)
			t.expect(e[1].lives).toBe(2)
			t.expect(g.sides[2].run.lives).toBe(2)
			t.expect(g.sides[2].run.phase).toBe("dying")
			t.expect(g.sides[1].run.lives).toBe(3)
			t.expect(g.sides[1].run.score).toBe(0)
			t.expect(g.sides[1].run.shot).toBe(nil)
			-- one unit past the cannon's half-width it goes on, to the field's far end
			local h = formed(config)
			h.sides[2].run.cannon = W - 1 - 20
			h.sides[1].run.shot = { x = 20 - C.cannonHalf - 1, d = 450 }
			local far = 0
			for _ = 1, 10 do
				local s = h.sides[1].run.shot
				if s == nil then
					break
				end
				far = math.max(far, s.d)
				t.expect(#kinds(run(h, 1))).toBe(0)
			end
			t.expect(h.sides[1].run.shot).toBe(nil)
			t.expect(far > D - C.cannonDepth).toBe(true)
			t.expect(h.sides[2].run.lives).toBe(3)
			-- a player who is not playing (here: dying) is not hit again
			g.sides[1].run.shot = { x = 20, d = 450 }
			for _ = 1, 4 do
				t.expect(#kinds(run(g, 1))).toBe(0)
			end
			t.expect(g.sides[2].run.lives).toBe(2)
			t.expect(g.sides[1].run.shot).toBe(nil)
		end
	)
end)
