--!strict
-- f0221 AC1: two ships share one field. They start on opposite sides (player 1 a quarter of the way across,
-- player 2 three quarters), at rest and pointing up, on the solo field. The waves are the solo waves with 1.5 x
-- the rocks, rounded down (6, 9, 12, 15, then 16), and every other solo number stays. The rocks, the saucer and
-- the wave are the match's, one of each for both players. A new wave's rock that would start within 160 of a ship
-- still playing moves half its edge along, unless that puts it nearer a ship.
local Classic = require("@logic/Classic")
local Field = require("@logic/Field")
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

-- the match's step, taking any inputs (the cases hand it junk and mixed lists too)
local step = TwoPlayer.step :: (TwoPlayer.Match, any) -> { Classic.Event }

-- both players' inputs for one tick
local function pair(a: Classic.Input?, b: Classic.Input?): { Classic.Input? }
	return { a, b }
end

local CFG = TwoPlayer.CONFIG
local SOLO = Classic.CONFIG
local F = SOLO.field

local function quiet(seed: number?): TwoPlayer.Match
	local m = TwoPlayer.new(seed or 1)
	m.rocks = {}
	m.waveTimer = 1e9
	m.saucerElapsed = -1e9
	return m
end

local function larges(m: TwoPlayer.Match): number
	local n = 0
	for _, r in m.rocks do
		if r.size == "large" then
			n += 1
		end
	end
	return n
end

-- the rocks of the wave that starts on the next tick, with nothing else on the field
local function nextWave(m: TwoPlayer.Match): { Classic.Rock }
	m.rocks = {}
	m.waveTimer = 1
	step(m, nil)
	return m.rocks
end

local function nearest(x: number, y: number, ships: { any }): number
	local best = math.huge
	for _, s in ships do
		best = math.min(best, Field.distance(F, x, y, s.x, s.y))
	end
	return best
end

-- the other point a rock at (x, y) on the bottom or left edge could have started at: half that edge along
local function alternatives(x: number, y: number): { { x: number, y: number } }
	local out = {}
	if y == 0 then
		table.insert(out, { x = (x + F.width / 2) % F.width, y = 0 })
	end
	if x == 0 then
		table.insert(out, { x = 0, y = (y + F.height / 2) % F.height })
	end
	return out
end

-- the rock starts 160 from every ship, or at the point of its two that is farther from its nearest ship
local function placedWell(r: Classic.Rock, ships: { any }): boolean
	local here = nearest(r.x, r.y, ships)
	if here >= SOLO.spawnClear then
		return true
	end
	for _, a in alternatives(r.x, r.y) do
		if nearest(a.x, a.y, ships) <= here then
			return true
		end
	end
	return false
end

return t.spec("f0221 field", function(it)
	it("starts both ships on one solo field, on opposite sides, at rest and pointing up", function()
		local m = TwoPlayer.new(1)
		t.expect(m.config.field.width).toBe(1024)
		t.expect(m.config.field.height).toBe(768)
		t.expect(#m.pilots).toBe(2)
		local want = { { 256, 384 }, { 768, 384 } }
		for i, p in m.pilots do
			t.expect(p.slot).toBe(i)
			t.expect(p.ship.x).toBe(want[i][1])
			t.expect(p.ship.y).toBe(want[i][2])
			t.expect(p.ship.vx).toBe(0)
			t.expect(p.ship.vy).toBe(0)
			t.expect(p.ship.heading).toBe(64)
			t.expect(p.shipState).toBe("alive")
			t.expect(p.protect).toBe(0)
			t.expect(p.phase).toBe("playing")
		end
		t.expect(m.phase).toBe("playing")
		t.expect(m.wave).toBe(1)
	end)

	it("has 1.5 x the solo rocks in every wave, rounded down: 6, 9, 12, 15, then 16", function()
		local want = { 6, 9, 12, 15, 16, 16, 16 }
		for wave = 1, #want do
			t.expect(Classic.rockCount(CFG.classic, wave)).toBe(want[wave])
			t.expect(Classic.rockCount(CFG.classic, wave))
				.toBe(math.floor(1.5 * Classic.rockCount(SOLO, wave)))
		end
		for seed = 1, 5 do
			local m = TwoPlayer.new(seed)
			t.expect(#m.rocks).toBe(6)
			t.expect(larges(m)).toBe(6)
		end
	end)

	it("starts each later wave with its 1.5 x count, after the shared wave clears", function()
		local m = quiet()
		m.waveTimer = 0
		local seen = {}
		for _ = 1, 3 * (SOLO.waveTicks + 1) do
			for _, e in step(m, nil) do
				if e.kind == "WaveStart" then
					table.insert(seen, { wave = e.wave, rocks = #m.rocks })
					t.expect(e.player).toBe(nil)
					m.rocks = {}
				end
			end
		end
		t.expect(seen)
			.toEqual({ { wave = 2, rocks = 9 }, { wave = 3, rocks = 12 }, { wave = 4, rocks = 15 } })
		m.wave = 5
		t.expect(#nextWave(m)).toBe(16)
	end)

	it("keeps every other solo number", function()
		local changed = { firstRocks = true, rocksStep = true, maxRocks = true }
		local keys = 0
		for k, v in SOLO :: any do
			keys += 1
			if not changed[k] then
				t.expect((CFG.classic :: any)[k]).toEqual(v)
			end
		end
		for _ in CFG.classic :: any do
			keys -= 1
		end
		t.expect(keys).toBe(0)
		t.expect(TwoPlayer.new(1).config).toBe(CFG.classic)
	end)

	it("shares one set of rocks, one saucer and one wave between both players", function()
		local m = quiet()
		local p1, p2 = m.pilots[1], m.pilots[2]
		-- a large rock ahead of player 1: player 1 breaks it, and player 2 breaks a piece of it
		table.insert(m.rocks, { id = 500, size = "large", x = p1.ship.x, y = p1.ship.y + 60, vx = 0, vy = 0 })
		local hit1 = nil :: Classic.Event?
		for _ = 1, 10 do
			for _, e in step(m, pair({ fire = true }, nil)) do
				if e.kind == "RockHit" then
					hit1 = e
				end
			end
			if hit1 then
				break
			end
		end
		t.expect(hit1 and hit1.player).toBe(1)
		t.expect(#m.rocks).toBe(2)
		local piece = m.rocks[1]
		piece.vx, piece.vy = 0, 0
		piece.x, piece.y = p2.ship.x, p2.ship.y + 60
		m.rocks = { piece }
		local hit2 = nil :: Classic.Event?
		for _ = 1, 10 do
			for _, e in step(m, pair(nil, { fire = true })) do
				if e.kind == "RockHit" then
					hit2 = e
				end
			end
			if hit2 then
				break
			end
		end
		t.expect(hit2 and hit2.player).toBe(2)
		t.expect(hit2 and hit2.size).toBe("medium")
		t.expect(p1.score).toBe(20)
		t.expect(p2.score).toBe(50)
		-- one saucer clock for the match
		local s = TwoPlayer.new(2)
		s.rocks = {}
		s.waveTimer = 1e9
		local appear = 0
		for _ = 1, Classic.CONFIG.saucers.firstWait do
			for _, e in step(s, nil) do
				if e.kind == "SaucerAppear" then
					appear += 1
				end
			end
		end
		t.expect(appear).toBe(1)
		t.expect(s.saucer ~= nil).toBe(true)
	end)

	it("starts every rock 160 from both ships, or at the farther of its two points", function()
		local away = 0
		for seed = 1, 60 do
			local m = TwoPlayer.new(seed)
			for _, r in m.rocks do
				t.expect(nearest(r.x, r.y, { m.pilots[1].ship, m.pilots[2].ship }) >= SOLO.spawnClear)
					.toBe(true)
			end
			-- wave 1 too, with player 2's home by the bottom-left corner
			local cfg = table.clone(CFG :: any)
			cfg.homes = { CFG.homes[1], { x = 40, y = 0 } }
			local h = TwoPlayer.new(seed, cfg)
			for _, r in h.rocks do
				t.expect(placedWell(r, { h.pilots[1].ship, h.pilots[2].ship })).toBe(true)
				t.expect(nearest(r.x, r.y, { h.pilots[2].ship }) >= SOLO.spawnClear).toBe(true)
			end
			-- player 2 by the bottom-left corner, player 1 out in the open
			local q = quiet(seed)
			q.pilots[2].ship.x, q.pilots[2].ship.y = 40, 0
			local ships = { q.pilots[1].ship, q.pilots[2].ship }
			for _, r in nextWave(q) do
				t.expect(placedWell(r, ships)).toBe(true)
				t.expect(nearest(r.x, r.y, ships) >= SOLO.spawnClear).toBe(true)
			end
			-- player 2 just past half the bottom edge from player 1: some rocks are near one ship either way
			local w = quiet(seed)
			w.pilots[1].ship.x, w.pilots[1].ship.y = 100, 0
			w.pilots[2].ship.x, w.pilots[2].ship.y = 632, 0
			local both = { w.pilots[1].ship, w.pilots[2].ship }
			for _, r in nextWave(w) do
				t.expect(placedWell(r, both)).toBe(true)
				if nearest(r.x, r.y, both) < SOLO.spawnClear then
					away += 1
				end
			end
		end
		t.expect(away > 0).toBe(true)
	end)
end)
