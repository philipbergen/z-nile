--!strict
-- f0220 AC8: waves. Wave 1 has 4 large rocks, and each later wave 2 more, up to 11. Each wave's rocks start on
-- the field's edge (draw(width + height) - 1 along the bottom edge, then up the left one), moved half that
-- edge along when they would start within 160 of the ship. Clearing every rock starts the next wave 120 ticks
-- (2 s) later; the clock runs while the ship is lost, and a new wave changes nothing else.
local Classic = require("@logic/Classic")
local Field = require("@logic/Field")
local t = require("@tests/lib/t")

local CFG = Classic.CONFIG
local F = Field.CLASSIC

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

local function count(events: { Classic.Event }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

-- a run whose last rock is a small one about to be shot
local function lastRock(seed: number?): Classic.Game
	local g = Classic.new(seed or 1)
	g.saucerElapsed = -1e9 -- no saucer in this case
	g.rocks = { { id = 900, size = "small", x = 300, y = 100, vx = 0, vy = 0 } }
	g.shots = { { x = 289, y = 100, vx = 2, vy = 0, life = 30 } }
	return g
end

return t.spec("f0220 waves", function(it)
	it("starts wave 1 with 4 large rocks, and each later wave with 2 more, up to 11", function()
		local g = Classic.new(1)
		t.expect(g.wave).toBe(1)
		t.expect(#g.rocks).toBe(4)
		for _, r in g.rocks do
			t.expect(r.size).toBe("large")
		end
		local counts = {}
		for wave = 1, 8 do
			table.insert(counts, Classic.rockCount(CFG, wave))
		end
		t.expect(counts).toEqual({ 4, 6, 8, 10, 11, 11, 11, 11 })
		t.expect(Classic.rockCount(CFG, 30)).toBe(11)
	end)

	it("starts every rock on the field's edge, the bottom or the left, well away from the ship", function()
		local bottom, left = 0, 0
		for seed = 1, 40 do
			for _, r in Classic.new(seed).rocks do
				t.expect(r.x == 0 or r.y == 0).toBe(true)
				t.expect(r.x == math.floor(r.x) and r.y == math.floor(r.y)).toBe(true)
				t.expect(Field.distance(F, r.x, r.y, 512, 384) >= 160).toBe(true)
				if r.y == 0 and r.x > 0 then
					bottom += 1
				elseif r.x == 0 and r.y > 0 then
					left += 1
				end
			end
		end
		-- 1,024 of the 1,792 edge places are on the bottom and 767 on the left: both are used
		t.expect(bottom > 30 and left > 30).toBe(true)
	end)

	it("clears the wave with its last rock, and starts the next 120 ticks later", function()
		local g = lastRock()
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit", "WaveClear" })
		t.expect(e[2].wave).toBe(1)
		e = run(g, 119)
		t.expect(count(e, "WaveStart")).toBe(0)
		t.expect(#g.rocks).toBe(0)
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "WaveStart" })
		t.expect(e[1].wave).toBe(2)
		t.expect(g.wave).toBe(2)
		t.expect(#g.rocks).toBe(6)
		local ids = {}
		for _, r in g.rocks do
			t.expect(r.size).toBe("large")
			t.expect(r.id > 900 or r.id < 900).toBe(true)
			ids[r.id] = true
		end
		local n = 0
		for _ in ids do
			n += 1
		end
		t.expect(n).toBe(6)
		t.expect(CFG.waveTicks).toBe(120)
	end)

	it("moves a rock that would start within 160 of the ship half its edge along", function()
		for _, at in { { 300, 5 }, { 5, 300 }, { 0, 0 } } do
			for seed = 1, 30 do
				local g = lastRock(seed)
				g.ship.x, g.ship.y = at[1], at[2]
				g.shots[1].x, g.shots[1].y = 289, 100
				run(g, 121)
				t.expect(g.wave).toBe(2)
				t.expect(#g.rocks).toBe(6)
				for _, r in g.rocks do
					t.expect(r.x == 0 or r.y == 0).toBe(true)
					local d = Field.distance(F, r.x, r.y, g.ship.x, g.ship.y)
					t.expect(d >= 160).toBe(true)
				end
			end
		end
	end)

	it("runs the wave clock while the ship is lost", function()
		local g = Classic.new(1)
		g.saucerElapsed = -1e9
		g.ship.x, g.ship.y = 200, 600
		g.rocks = { { id = 900, size = "small", x = 215, y = 600, vx = 0, vy = 0 } }
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit", "ShipDestroyed", "WaveClear" })
		e = run(g, 119)
		t.expect(count(e, "WaveStart")).toBe(0)
		t.expect(g.shipState).toBe("dead")
		e = run(g, 1)
		t.expect(count(e, "WaveStart")).toBe(1)
		t.expect(#g.rocks).toBe(6)
	end)

	it("changes nothing else when a wave starts: score, lives, shots, the saucer and its clock", function()
		local g = lastRock()
		g.score = 1230
		g.lives = 2
		g.saucerElapsed = 0
		g.ship.x = 700
		g.saucer = {
			kind = "large",
			x = 100,
			y = 700,
			vx = 0,
			vy = 0,
			travelled = 0,
			fireElapsed = -1e9,
			turnElapsed = -1e9,
		}
		local e = Classic.step(g, nil)
		t.expect(count(e, "WaveClear")).toBe(1)
		g.shots = { { x = 900, y = 700, vx = 0, vy = 0, life = 1e9 } }
		local saucer = g.saucer
		run(g, 120)
		t.expect(g.wave).toBe(2)
		t.expect(g.score).toBe(1330)
		t.expect(g.lives).toBe(2)
		t.expect(#g.shots).toBe(1)
		t.expect(g.saucer).toBe(saucer)
		t.expect(g.saucerElapsed).toBe(0)
		t.expect(g.shipState).toBe("alive")
		t.expect(g.ship.x).toBe(700)

		-- with no saucer, its clock runs on through the new wave
		local h = lastRock()
		h.saucerElapsed = -1000
		run(h, 121)
		t.expect(h.wave).toBe(2)
		t.expect(h.saucerElapsed).toBe(-879)
	end)

	it("ends the run, with no wave cleared, when the last rock is rammed with the last life", function()
		local g = Classic.new(1)
		g.saucerElapsed = -1e9
		g.lives = 1
		g.rocks = { { id = 900, size = "small", x = 512 + 15, y = 384, vx = 0, vy = 0 } }
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit", "ShipDestroyed", "GameOver" })
		t.expect(g.waveTimer).toBe(0)
	end)
end)
