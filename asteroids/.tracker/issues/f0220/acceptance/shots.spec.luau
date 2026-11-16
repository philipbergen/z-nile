--!strict
-- f0220 AC3: the ship's shots. A fire starts a shot at the ship's nose, along its heading at 8 a tick plus the
-- ship's own velocity. Up to 4 are on the field at a time (a fire beyond that is ignored, not remembered), each
-- flies 60 ticks (about 1 s) and wraps. A shot hits the first rock or saucer its move comes within reach of,
-- checked along the whole move (a tie between rocks goes to the one listed first, a tie with the saucer to the
-- rock), and the hit ends it.
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

local function count(events: { Classic.Event }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function still(kind: "large" | "small", x: number, y: number): any
	return { kind = kind, x = x, y = y, vx = 0, vy = 0, travelled = 0, fireElapsed = -1e9, turnElapsed = -1e9 }
end

return t.spec("f0220 shots", function(it)
	it(
		"fires from the ship's nose along its heading at 8 a tick, and moves on the tick it is fired",
		function()
			local g = quiet()
			local e = Classic.step(g, { fire = true })
			t.expect(count(e, "Fire")).toBe(1)
			t.expect(#g.shots).toBe(1)
			local s = g.shots[1]
			-- the nose is 12 ahead of the centre (512, 384); the shot has moved once
			t.expect(s.x).toBeNear(512, 1e-9)
			t.expect(s.y).toBeNear(404, 1e-9)
			t.expect(s.vx).toBeNear(0, 1e-9)
			t.expect(s.vy).toBeNear(8, 1e-12)
			t.expect(CFG.shotSpeed).toBe(8)
		end
	)

	it("adds the ship's velocity to the shot's", function()
		local g = quiet()
		g.ship.vx, g.ship.vy = 3, -1
		Classic.step(g, { fire = true })
		local s = g.shots[1]
		-- the ship flies first: 3 and -1 less 1% drag
		t.expect(s.vx).toBeNear(2.97, 1e-9)
		t.expect(s.vy).toBeNear(8 - 0.99, 1e-9)
	end)

	it("flies 60 ticks: the tick it is fired and 59 more, wrapping round the field", function()
		local g = quiet()
		Classic.step(g, { fire = true })
		run(g, 57)
		t.expect(#g.shots).toBe(1)
		Classic.step(g, nil)
		-- 59 moves: 396 + 8 x 59 = 868, past the top edge and back from the bottom
		t.expect(#g.shots).toBe(1)
		t.expect(g.shots[1].y).toBeNear(100, 1e-9)
		t.expect(g.shots[1].life).toBe(1)
		Classic.step(g, nil)
		t.expect(#g.shots).toBe(0)
		t.expect(CFG.shotLife).toBe(60)
	end)

	it("has at most 4 shots on the field, ignores a fifth fire and does not remember it", function()
		local g = quiet()
		local e = run(g, 6, { fire = true })
		t.expect(count(e, "Fire")).toBe(4)
		t.expect(#g.shots).toBe(4)
		-- the first shot's last tick is tick 60 and the second's tick 61; nothing fires on its own when they go
		e = run(g, 54)
		t.expect(#g.shots).toBe(3)
		t.expect(count(e, "Fire")).toBe(0)
		e = Classic.step(g, nil)
		t.expect(count(e, "Fire")).toBe(0)
		t.expect(#g.shots).toBe(2)
		e = Classic.step(g, { fire = true })
		t.expect(count(e, "Fire")).toBe(1)
		t.expect(CFG.shotLimit).toBe(4)
	end)

	it("fires only on a fire of exactly true", function()
		local g = quiet()
		for _, bad in { 1, "true", {} } :: { any } do
			Classic.step(g, { fire = bad :: any })
		end
		t.expect(#g.shots).toBe(0)
	end)

	it("hits a rock its move passes within reach of, though neither end of the move is inside it", function()
		local g = quiet()
		g.shots = { { x = 100, y = 100, vx = 14, vy = 0, life = 30 } }
		table.insert(g.rocks, { id = 900, size = "small", x = 107, y = 109, vx = 0, vy = 0 })
		local e = Classic.step(g, nil)
		t.expect(count(e, "RockHit")).toBe(1)
		t.expect(e[1].id).toBe(900)
		t.expect(e[1].by).toBe("shot")
		t.expect(#g.shots).toBe(0)
		t.expect(#g.rocks).toBe(0)
	end)

	it("passes a rock it never comes within reach of", function()
		local g = quiet()
		g.shots = { { x = 100, y = 100, vx = 14, vy = 0, life = 30 } }
		table.insert(g.rocks, { id = 900, size = "small", x = 107, y = 111, vx = 0, vy = 0 })
		local e = Classic.step(g, nil)
		t.expect(count(e, "RockHit")).toBe(0)
		t.expect(g.shots[1].x).toBe(114)
		t.expect(g.shots[1].life).toBe(29)
	end)

	it("hits the target nearest along its move, whatever the order they are listed in", function()
		local g = quiet()
		g.shots = { { x = 100, y = 100, vx = 14, vy = 0, life = 30 } }
		table.insert(g.rocks, { id = 901, size = "small", x = 115, y = 100, vx = 0, vy = 0 })
		table.insert(g.rocks, { id = 902, size = "small", x = 112, y = 100, vx = 0, vy = 0 })
		local e = Classic.step(g, nil)
		t.expect(count(e, "RockHit")).toBe(1)
		t.expect(e[1].id).toBe(902)
		t.expect(#g.rocks).toBe(1)
		t.expect(g.rocks[1].id).toBe(901)

		-- a saucer nearer than the rock is hit instead of it
		local h = quiet()
		h.shots = { { x = 100, y = 100, vx = 14, vy = 0, life = 30 } }
		table.insert(h.rocks, { id = 903, size = "small", x = 115, y = 100, vx = 0, vy = 0 })
		h.saucer = still("small", 112, 100)
		e = Classic.step(h, nil)
		t.expect(count(e, "SaucerHit")).toBe(1)
		t.expect(count(e, "RockHit")).toBe(0)
		t.expect(#h.rocks).toBe(1)

		-- a rock nearer than the saucer is hit instead of it
		local k = quiet()
		k.shots = { { x = 100, y = 100, vx = 14, vy = 0, life = 30 } }
		table.insert(k.rocks, { id = 904, size = "small", x = 112, y = 100, vx = 0, vy = 0 })
		k.saucer = still("small", 115, 100)
		e = Classic.step(k, nil)
		t.expect(count(e, "RockHit")).toBe(1)
		t.expect(count(e, "SaucerHit")).toBe(0)
		t.expect(k.saucer ~= nil).toBe(true)

		-- a tie between two rocks goes to the one listed first
		local n = quiet()
		n.shots = { { x = 100, y = 100, vx = 14, vy = 0, life = 30 } }
		table.insert(n.rocks, { id = 906, size = "small", x = 112, y = 100, vx = 0, vy = 0 })
		table.insert(n.rocks, { id = 907, size = "small", x = 112, y = 100, vx = 0, vy = 0 })
		e = Classic.step(n, nil)
		t.expect(count(e, "RockHit")).toBe(1)
		t.expect(e[1].id).toBe(906)

		-- a tie with the saucer goes to the rock
		local m = quiet()
		m.shots = { { x = 100, y = 100, vx = 14, vy = 0, life = 30 } }
		m.saucer = still("small", 112, 100)
		table.insert(m.rocks, { id = 905, size = "small", x = 112, y = 100, vx = 0, vy = 0 })
		e = Classic.step(m, nil)
		t.expect(count(e, "RockHit")).toBe(1)
		t.expect(count(e, "SaucerHit")).toBe(0)
	end)

	it("lets two shots in one tick split a rock and then hit one of its pieces", function()
		local g = quiet()
		table.insert(g.rocks, { id = 900, size = "large", x = 300, y = 300, vx = 0, vy = 0 })
		g.shots = {
			{ x = 300, y = 290, vx = 1, vy = 0, life = 30 },
			{ x = 300, y = 295, vx = 1, vy = 0, life = 30 },
		}
		local e = Classic.step(g, nil)
		t.expect(count(e, "RockHit")).toBe(2)
		t.expect(e[1].size).toBe("large")
		t.expect(e[2].size).toBe("medium")
		t.expect(#g.shots).toBe(0)
		-- one medium and the two smalls of the other
		t.expect(#g.rocks).toBe(3)
	end)
end)
