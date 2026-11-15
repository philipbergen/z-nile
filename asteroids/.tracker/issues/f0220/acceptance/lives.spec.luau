--!strict
-- f0220 AC7: lives. A run starts with 3, and gains one each time the score reaches another 10,000 (after the
-- hit that earned it, and before a life the same hit costs). A lost ship waits 120 ticks, unseen at the centre,
-- then comes back there at rest, pointing up, on the first tick no rock or saucer comes within 80 of the centre.
-- It is protected for 120 ticks: nothing hits it, and it can fly and fire. The ship's shots in flight fly on
-- while it is lost. One ship is lost at most once a tick. The last life lost is game over, and then nothing
-- changes.
local Classic = require("@logic/Classic")
local t = require("@tests/lib/t")

local CFG = Classic.CONFIG

local function quiet(): Classic.Game
	local g = Classic.new(1)
	g.rocks = {}
	g.waveTimer = 1e9 -- no next wave in this case
	g.saucerElapsed = -1e9 -- no saucer in this case
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

-- the ship rams a small rock (which leaves no pieces) where it stands
local function ram(g: Classic.Game): { Classic.Event }
	table.insert(
		g.rocks,
		{ id = 900 + #g.rocks, size = "small", x = g.ship.x + 15, y = g.ship.y, vx = 0, vy = 0 }
	)
	return Classic.step(g, nil)
end

local function still(kind: "large" | "small", x: number, y: number): any
	return { kind = kind, x = x, y = y, vx = 0, vy = 0, travelled = 0, fireElapsed = -1e9, turnElapsed = -1e9 }
end

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

return t.spec("f0220 lives", function(it)
	it("starts with 3 lives, no score, wave 1, playing", function()
		local g = Classic.new(1)
		t.expect(g.lives).toBe(3)
		t.expect(g.score).toBe(0)
		t.expect(g.wave).toBe(1)
		t.expect(g.phase).toBe("playing")
		t.expect(g.protect).toBe(0)
		t.expect(CFG.lives).toBe(3)
	end)

	it(
		"waits 120 ticks after a loss, ignoring input, then comes back at the centre, at rest, pointing up",
		function()
			local g = quiet()
			g.ship.x, g.ship.y, g.ship.vx, g.ship.heading = 300, 200, 0, 10
			local e = ram(g)
			t.expect(kinds(e)).toEqual({ "RockHit", "ShipDestroyed" })
			-- the loss says where it happened
			t.expect(e[2].x).toBe(300)
			t.expect(e[2].y).toBe(200)
			t.expect(g.shipState).toBe("dead")
			e = run(g, 119, { fire = true, thrust = true, turn = 1, hyperspace = true })
			t.expect(#e).toBe(0)
			t.expect(g.shipState).toBe("dead")
			t.expect(#g.shots).toBe(0)
			-- it comes back and acts on the same tick
			e = Classic.step(g, { fire = true })
			t.expect(kinds(e)).toEqual({ "Respawn", "Fire" })
			t.expect(e[1].lives).toBe(2)
			t.expect(g.shipState).toBe("alive")
			t.expect(g.ship.x).toBe(512)
			t.expect(g.ship.y).toBe(384)
			t.expect(g.ship.vx).toBe(0)
			t.expect(g.ship.vy).toBe(0)
			t.expect(g.ship.heading).toBe(64)
			t.expect(CFG.respawnTicks).toBe(120)
		end
	)

	it("waits until no rock or saucer comes within 80 of the centre", function()
		local g = quiet()
		ram(g)
		-- a large rock (radius 40) 119 from the centre is within 80 of it
		table.insert(g.rocks, { id = 950, size = "large", x = 512 + 119, y = 384, vx = 0, vy = 0 })
		local e = run(g, 200)
		t.expect(count(e, "Respawn")).toBe(0)
		-- exactly 80 beyond its radius is clear
		g.rocks[1].x = 512 + 120
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "Respawn" })

		local h = quiet()
		ram(h)
		-- a small rock (radius 10) 89 from the centre is within 80 of it
		table.insert(h.rocks, { id = 951, size = "small", x = 512, y = 384 - 89, vx = 0, vy = 0 })
		e = run(h, 200)
		t.expect(count(e, "Respawn")).toBe(0)
		h.rocks[1].y = 384 - 91
		e = Classic.step(h, nil)
		t.expect(kinds(e)).toEqual({ "Respawn" })

		local k = quiet()
		ram(k)
		-- a large saucer (radius 20) 99 from the centre
		k.saucer = still("large", 512, 384 + 99)
		e = run(k, 200)
		t.expect(count(e, "Respawn")).toBe(0)
		k.saucer = still("large", 512, 384 + 101)
		e = Classic.step(k, nil)
		t.expect(kinds(e)).toEqual({ "Respawn" })
	end)

	it("protects the respawned ship for 120 ticks, from rocks, the saucer and its shots", function()
		local g = quiet()
		ram(g)
		run(g, 120)
		t.expect(g.shipState).toBe("alive")
		t.expect(g.protect).toBe(120)
		table.insert(g.rocks, { id = 960, size = "small", x = 512, y = 384, vx = 0, vy = 0 })
		g.saucer = still("small", 512 + 5, 384)
		g.saucerShots = { { x = 512 - 3, y = 384, vx = 0, vy = 0, life = 1e9 } }
		local e = run(g, 119)
		t.expect(#e).toBe(0)
		t.expect(g.lives).toBe(2)
		t.expect(#g.rocks).toBe(1)
		t.expect(g.saucer ~= nil).toBe(true)
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "ShipDestroyed" })
		t.expect(e[1].cause).toBe("saucershot")
		t.expect(CFG.protectTicks).toBe(120)
	end)

	it("lets the protected ship fly and fire", function()
		local g = quiet()
		ram(g)
		run(g, 120)
		local e = Classic.step(g, { fire = true, thrust = true })
		t.expect(kinds(e)).toEqual({ "Fire" })
		t.expect(g.ship.vy > 0).toBe(true)
		t.expect(g.protect).toBe(119)
	end)

	it("keeps the lost ship's shots flying, and they still score", function()
		local g = quiet()
		Classic.step(g, { fire = true })
		ram(g)
		t.expect(g.shipState).toBe("dead")
		t.expect(#g.shots).toBe(1)
		local s = g.shots[1]
		table.insert(g.rocks, { id = 970, size = "small", x = s.x, y = s.y + 40, vx = 0, vy = 0 })
		local e = run(g, 5)
		t.expect(count(e, "RockHit")).toBe(1)
		t.expect(g.score).toBe(200)
	end)

	it("gives a life each time the score reaches another 10,000, after the hit that earned it", function()
		local g = quiet()
		g.score = 9990
		table.insert(g.rocks, { id = 980, size = "large", x = 300, y = 100, vx = 0, vy = 0 })
		g.shots = { { x = 259, y = 100, vx = 2, vy = 0, life = 30 } }
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit", "ExtraLife" })
		t.expect(e[2].lives).toBe(4)
		t.expect(g.lives).toBe(4)
		-- the next comes at exactly 20,000
		g.rocks = { { id = 981, size = "small", x = 300, y = 100, vx = 0, vy = 0 } }
		g.score = 19900
		g.shots = { { x = 289, y = 100, vx = 2, vy = 0, life = 30 } }
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit", "ExtraLife" })
		t.expect(g.lives).toBe(5)
		-- and none before 30,000
		g.rocks = { { id = 982, size = "small", x = 300, y = 100, vx = 0, vy = 0 } }
		g.score = 29800
		g.shots = { { x = 289, y = 100, vx = 2, vy = 0, life = 30 } }
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit" })
		t.expect(g.lives).toBe(5)
		t.expect(CFG.extraLifeEvery).toBe(10000)
	end)

	it("gives the life a ram earns before the ram's own loss, so the last ship plays on", function()
		local g = quiet()
		g.lives = 1
		g.score = 9990
		local e = ram(g)
		t.expect(kinds(e)).toEqual({ "RockHit", "ExtraLife", "ShipDestroyed" })
		t.expect(e[3].lives).toBe(1)
		t.expect(g.lives).toBe(1)
		t.expect(g.phase).toBe("playing")
	end)

	it(
		"moves the ship's shots before the collisions: a shot breaks the rock the ship is about to ram",
		function()
			local g = quiet()
			-- 45 from the ship: overlapping it (45 < 52); its mediums, 45 away, do not (45 > 32)
			table.insert(g.rocks, { id = 992, size = "large", x = 557, y = 384, vx = 0, vy = 0 })
			g.shots = { { x = 557, y = 384, vx = 0.1, vy = 0, life = 30 } }
			local e = Classic.step(g, nil)
			t.expect(kinds(e)).toEqual({ "RockHit" })
			t.expect(e[1].by).toBe("shot")
			t.expect(g.lives).toBe(3)
		end
	)

	it(
		"moves the ship's shots before the saucer's: the life a shot earns comes before a saucer shot's loss",
		function()
			local g = quiet()
			g.lives = 1
			g.score = 9990
			table.insert(g.rocks, { id = 993, size = "large", x = 300, y = 100, vx = 0, vy = 0 })
			g.shots = { { x = 259, y = 100, vx = 2, vy = 0, life = 30 } }
			g.saucerShots = { { x = 497, y = 384, vx = 6, vy = 0, life = 30 } }
			local e = Classic.step(g, nil)
			t.expect(kinds(e)).toEqual({ "RockHit", "ExtraLife", "ShipDestroyed" })
			t.expect(g.phase).toBe("playing")
			t.expect(g.lives).toBe(1)
		end
	)

	it("loses the ship once a tick: a saucer shot and a rock on the same tick cost one life", function()
		local g = quiet()
		table.insert(g.rocks, { id = 990, size = "small", x = 512 + 15, y = 384, vx = 0, vy = 0 })
		g.saucerShots = { { x = 512 - 15, y = 384, vx = 6, vy = 0, life = 30 } }
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "ShipDestroyed" })
		t.expect(e[1].cause).toBe("saucershot")
		t.expect(g.lives).toBe(2)
		t.expect(#g.rocks).toBe(1)
	end)

	it("ends the run when the last life is lost, and then nothing changes", function()
		local g = quiet()
		g.lives = 1
		local e = ram(g)
		t.expect(kinds(e)).toEqual({ "RockHit", "ShipDestroyed", "GameOver" })
		t.expect(e[2].lives).toBe(0)
		t.expect(g.phase).toBe("gameover")
		t.expect(g.lives).toBe(0)
		table.insert(g.rocks, { id = 991, size = "large", x = 100, y = 100, vx = 1, vy = 1 })
		local s = still("small", 700, 100)
		s.fireElapsed = 0
		g.saucer = s
		g.shots = { { x = 10, y = 10, vx = 1, vy = 0, life = 30 } }
		local before = copy(g)
		e = run(g, 300, { fire = true, thrust = true, turn = 1, hyperspace = true })
		t.expect(#e).toBe(0)
		t.expect(g).toEqual(before)
	end)
end)
