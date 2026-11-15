--!strict
-- f0220 AC4: rocks. A large rock (radius 40, 20 points) splits into 2 medium (radius 20, 50 points), a medium
-- into 2 small (radius 10, 100 points), and a small one is destroyed. The pieces start at the hit rock's centre,
-- each with a drawn heading and a drawn speed from its size's range, and new ids. A rock drifts in a straight
-- line. Ramming one costs a life, and the rock still splits and scores.
local Classic = require("@logic/Classic")
local Rocks = require("@logic/Rocks")
local t = require("@tests/lib/t")

local function quiet(seed: number?): Classic.Game
	local g = Classic.new(seed or 1)
	g.rocks = {}
	g.waveTimer = 1e9 -- no next wave in this case
	g.saucerElapsed = -1e9 -- no saucer in this case
	return g
end

local function kinds(events: { Classic.Event }): { string }
	local out = {}
	for _, e in events do
		table.insert(out, e.kind)
	end
	return out
end

-- a shot one unit short of the rock's edge, moving into it
local function shoot(g: Classic.Game, r: Rocks.Rock)
	local radius = Rocks.SIZES[r.size].radius
	g.shots = { { x = r.x - radius - 1, y = r.y, vx = 2, vy = 0, life = 30 } }
end

local function speedOf(r: Rocks.Rock): number
	return math.sqrt(r.vx ^ 2 + r.vy ^ 2)
end

return t.spec("f0220 rocks", function(it)
	it("has three sizes: large, medium and small, of radius 40, 20 and 10, worth 20, 50 and 100", function()
		t.expect(Rocks.SIZES.large.radius).toBe(40)
		t.expect(Rocks.SIZES.medium.radius).toBe(20)
		t.expect(Rocks.SIZES.small.radius).toBe(10)
		t.expect(Rocks.SIZES.large.points).toBe(20)
		t.expect(Rocks.SIZES.medium.points).toBe(50)
		t.expect(Rocks.SIZES.small.points).toBe(100)
	end)

	it("splits a large rock hit by a shot into 2 medium at its centre, and scores 20", function()
		local g = quiet()
		local r = { id = 900, size = "large" :: Rocks.SizeName, x = 300, y = 200, vx = 0, vy = 0 }
		table.insert(g.rocks, r)
		shoot(g, r)
		local idBefore = g.nextId
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit" })
		t.expect(e[1].id).toBe(900)
		t.expect(e[1].size).toBe("large")
		t.expect(e[1].points).toBe(20)
		t.expect(e[1].by).toBe("shot")
		t.expect(g.score).toBe(20)
		t.expect(#g.rocks).toBe(2)
		for _, p in g.rocks do
			t.expect(p.size).toBe("medium")
			t.expect(p.x).toBe(300)
			t.expect(p.y).toBe(200)
			t.expect(p.id >= idBefore).toBe(true)
		end
		t.expect(g.rocks[1].id ~= g.rocks[2].id).toBe(true)
		t.expect(g.nextId).toBe(idBefore + 2)
	end)

	it("splits a medium rock into 2 small and scores 50", function()
		local g = quiet()
		local r = { id = 900, size = "medium" :: Rocks.SizeName, x = 300, y = 200, vx = 0, vy = 0 }
		table.insert(g.rocks, r)
		shoot(g, r)
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit" })
		t.expect(e[1].points).toBe(50)
		t.expect(g.score).toBe(50)
		t.expect(#g.rocks).toBe(2)
		t.expect(g.rocks[1].size).toBe("small")
		t.expect(g.rocks[2].size).toBe("small")
	end)

	it("destroys a small rock and scores 100", function()
		local g = quiet()
		local r = { id = 900, size = "small" :: Rocks.SizeName, x = 300, y = 200, vx = 0, vy = 0 }
		table.insert(g.rocks, r)
		shoot(g, r)
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit" })
		t.expect(e[1].points).toBe(100)
		t.expect(g.score).toBe(100)
		t.expect(#g.rocks).toBe(0)
	end)

	it("gives each piece its own drawn heading and a speed from its size's range", function()
		local mediums, smalls = {}, {}
		for seed = 1, 40 do
			local g = quiet(seed)
			local r = { id = 900, size = "large" :: Rocks.SizeName, x = 300, y = 200, vx = 0, vy = 0 }
			if seed % 2 == 0 then
				-- a moving parent: the pieces' speeds are still their own
				r.vx, r.vy = 1.5, -0.5
				g.shots = { { x = 301.5, y = 199.5, vx = 1, vy = 0, life = 30 } }
			else
				shoot(g, r)
			end
			table.insert(g.rocks, r)
			Classic.step(g, nil)
			for _, p in g.rocks do
				table.insert(mediums, p)
			end
			local h = quiet(seed)
			local m = { id = 900, size = "medium" :: Rocks.SizeName, x = 300, y = 200, vx = 0, vy = 0 }
			table.insert(h.rocks, m)
			shoot(h, m)
			Classic.step(h, nil)
			for _, p in h.rocks do
				table.insert(smalls, p)
			end
		end
		local function check(list: { Rocks.Rock }, lo: number, hi: number)
			local slow, fast, dirs = math.huge, 0, {}
			for _, p in list do
				local s = speedOf(p)
				t.expect(s >= lo - 1e-9 and s <= hi + 1e-9).toBe(true)
				slow, fast = math.min(slow, s), math.max(fast, s)
				dirs[math.floor(math.atan2(p.vy, p.vx) * 4 / math.pi) % 8] = true
			end
			-- the speeds spread over the range, and the pieces fly every way
			t.expect(slow < lo + (hi - lo) / 4).toBe(true)
			t.expect(fast > hi - (hi - lo) / 4).toBe(true)
			local n = 0
			for _ in dirs do
				n += 1
			end
			t.expect(n).toBe(8)
		end
		check(mediums, 1, 2.25)
		check(smalls, 1.25, 3)
		-- the two pieces of one hit fly apart
		t.expect(mediums[1].vx == mediums[2].vx and mediums[1].vy == mediums[2].vy).toBe(false)
	end)

	it("starts each wave's large rocks at a speed from the large range", function()
		local slow, fast = math.huge, 0
		for seed = 1, 30 do
			for _, r in Classic.new(seed).rocks do
				local s = speedOf(r)
				t.expect(s >= 0.75 - 1e-9 and s <= 1.5 + 1e-9).toBe(true)
				slow, fast = math.min(slow, s), math.max(fast, s)
			end
		end
		t.expect(slow < 0.95).toBe(true)
		t.expect(fast > 1.3).toBe(true)
	end)

	it("drifts in a straight line at a steady speed", function()
		local g = quiet()
		table.insert(g.rocks, { id = 900, size = "large", x = 100, y = 100, vx = 1.5, vy = -0.5 })
		g.ship.x = 900 -- out of its way
		for _ = 1, 100 do
			Classic.step(g, nil)
		end
		t.expect(g.rocks[1].x).toBeNear(250, 1e-9)
		t.expect(g.rocks[1].y).toBeNear(50, 1e-9)
		t.expect(g.rocks[1].vx).toBe(1.5)
		t.expect(g.rocks[1].vy).toBe(-0.5)
	end)

	it("costs a life when the ship rams a rock, and the rock still splits and scores", function()
		local g = quiet()
		table.insert(g.rocks, { id = 900, size = "large", x = 512 + 30, y = 384, vx = 0, vy = 0 })
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit", "ShipDestroyed" })
		t.expect(e[1].by).toBe("ship")
		t.expect(e[1].points).toBe(20)
		t.expect(e[2].cause).toBe("rock")
		t.expect(e[2].lives).toBe(2)
		t.expect(g.lives).toBe(2)
		t.expect(g.score).toBe(20)
		t.expect(#g.rocks).toBe(2)
		t.expect(g.rocks[1].size).toBe("medium")
		t.expect(g.shipState).toBe("dead")
	end)

	it("rams one rock a tick: the first the ship overlaps", function()
		local g = quiet()
		table.insert(g.rocks, { id = 901, size = "small", x = 512 + 15, y = 384, vx = 0, vy = 0 })
		table.insert(g.rocks, { id = 902, size = "small", x = 512 - 15, y = 384, vx = 0, vy = 0 })
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit", "ShipDestroyed" })
		t.expect(e[1].id).toBe(901)
		t.expect(g.lives).toBe(2)
		t.expect(#g.rocks).toBe(1)
		t.expect(g.rocks[1].id).toBe(902)
	end)

	it("touches the ship when their centres are closer than the two radii added up", function()
		local function edge(size: Rocks.SizeName, reach: number)
			local near = quiet()
			local inside: Rocks.Rock =
				{ id = 900, size = size, x = 512 + reach - 0.1, y = 384, vx = 0, vy = 0 }
			table.insert(near.rocks, inside)
			Classic.step(near, nil)
			t.expect(near.shipState).toBe("dead")
			local far = quiet()
			local outside: Rocks.Rock =
				{ id = 900, size = size, x = 512, y = 384 - reach - 0.1, vx = 0, vy = 0 }
			table.insert(far.rocks, outside)
			Classic.step(far, nil)
			t.expect(far.shipState).toBe("alive")
			t.expect(far.lives).toBe(3)
		end
		edge("large", 52)
		edge("medium", 32)
		edge("small", 22)
		-- exactly the two radii apart is touching, not closer
		local g = quiet()
		table.insert(g.rocks, { id = 900, size = "large", x = 564, y = 384, vx = 0, vy = 0 })
		Classic.step(g, nil)
		t.expect(g.shipState).toBe("alive")
	end)
end)
