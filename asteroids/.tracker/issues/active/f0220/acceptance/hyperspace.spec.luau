--!strict
-- f0220 AC6: hyperspace. A hyperspace press while the ship is on the field takes it off the field at once (over
-- a fire or a turn the same tick), to a drawn spot (x then y, whole units), at rest. While it is away nothing
-- hits it and it cannot fly or fire. 30 ticks later it comes back there, unless draw(hyperspaceOdds) is 1: then
-- it explodes on re-entry and a life is lost. The odds are 1 in 6, a tuning constant.
local Classic = require("@logic/Classic")
local t = require("@tests/lib/t")

local CFG = Classic.CONFIG

local function config(odds: number): Classic.Config
	local c = table.clone(CFG) :: any
	c.hyperspaceOdds = odds
	return c
end

local function quiet(seed: number?, c: Classic.Config?): Classic.Game
	local g = Classic.new(seed or 1, c)
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

local NEVER = 2 ^ 30 -- odds so long that no re-entry in these cases explodes

return t.spec("f0220 hyperspace", function(it)
	it(
		"takes the ship off the field to a drawn spot, at rest, over a fire and a turn the same tick",
		function()
			local g = quiet(1, config(NEVER))
			g.ship.vx, g.ship.vy, g.ship.heading = 2, 1, 10
			local e = Classic.step(g, { hyperspace = true, fire = true, turn = 1, thrust = true })
			t.expect(kinds(e)).toEqual({ "Hyperspace" })
			local x, y = e[1].x :: number, e[1].y :: number
			t.expect(x == math.floor(x) and x >= 0 and x < 1024).toBe(true)
			t.expect(y == math.floor(y) and y >= 0 and y < 768).toBe(true)
			t.expect(g.ship.x).toBe(x)
			t.expect(g.ship.y).toBe(y)
			t.expect(g.ship.vx).toBe(0)
			t.expect(g.ship.vy).toBe(0)
			t.expect(g.ship.heading).toBe(10)
			t.expect(g.shipState).toBe("hyperspace")
			t.expect(#g.shots).toBe(0)
		end
	)

	it("jumps only on a hyperspace of exactly true", function()
		local g = quiet()
		for _, bad in { 1, "true", {} } :: { any } do
			Classic.step(g, { hyperspace = bad :: any })
		end
		t.expect(g.shipState).toBe("alive")
	end)

	it("sends different runs to different spots", function()
		local spots = {}
		local n = 0
		for seed = 1, 20 do
			local g = quiet(seed, config(NEVER))
			local e = Classic.step(g, { hyperspace = true })
			local key = `{e[1].x},{e[1].y}`
			if not spots[key] then
				spots[key] = true
				n += 1
			end
		end
		t.expect(n).toBe(20)
	end)

	it(
		"keeps the ship away 30 ticks, out of reach and out of control, then brings it back where it went",
		function()
			local g = quiet(1, config(NEVER))
			local e = Classic.step(g, { hyperspace = true })
			local x, y = g.ship.x, g.ship.y
			-- a rock on the spot and a saucer shot through it, while the ship is away
			table.insert(g.rocks, { id = 900, size = "small", x = x, y = y, vx = 0, vy = 0 })
			g.saucerShots = { { x = x - 3, y = y, vx = 6, vy = 0, life = 30 } }
			e = run(g, 28, { fire = true, turn = 1, thrust = true, hyperspace = true })
			t.expect(#e).toBe(0)
			t.expect(g.shipState).toBe("hyperspace")
			t.expect(g.lives).toBe(3)
			t.expect(#g.rocks).toBe(1)
			t.expect(#g.shots).toBe(0)
			t.expect(g.ship.x).toBe(x)
			t.expect(g.ship.heading).toBe(64)
			g.rocks = {}
			e = Classic.step(g, nil)
			t.expect(#e).toBe(0)
			e = Classic.step(g, { fire = true })
			-- the 30th tick: back, and in control at once
			t.expect(kinds(e)).toEqual({ "HyperspaceEnd", "Fire" })
			t.expect(g.shipState).toBe("alive")
			t.expect(g.ship.x).toBe(x)
			t.expect(g.ship.y).toBe(y)
			t.expect(CFG.hyperspaceTicks).toBe(30)
		end
	)

	it("can bring the ship back onto a rock, which then hits it", function()
		local g = quiet(1, config(NEVER))
		Classic.step(g, { hyperspace = true })
		run(g, 29)
		table.insert(g.rocks, { id = 900, size = "small", x = g.ship.x + 5, y = g.ship.y, vx = 0, vy = 0 })
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "HyperspaceEnd", "RockHit", "ShipDestroyed" })
		t.expect(e[3].cause).toBe("rock")
	end)

	it("explodes on re-entry when the draw of its odds is 1, and the life is lost", function()
		local g = quiet(1, config(1))
		Classic.step(g, { hyperspace = true })
		run(g, 29)
		t.expect(g.shipState).toBe("hyperspace")
		local x, y = g.ship.x, g.ship.y
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "ShipDestroyed" })
		t.expect(e[1].cause).toBe("hyperspace")
		t.expect(e[1].lives).toBe(2)
		-- where it came back
		t.expect(e[1].x).toBe(x)
		t.expect(e[1].y).toBe(y)
		t.expect(g.lives).toBe(2)
		t.expect(g.shipState).toBe("dead")
		-- and the lost ship comes back as any other: at the centre once its wait is over
		e = run(g, 120)
		t.expect(kinds(e)).toEqual({ "Respawn" })
		t.expect(g.ship.x).toBe(512)
		t.expect(g.ship.y).toBe(384)
	end)

	it("runs the protection down while the ship is away, and keeps it through the jump", function()
		local g = quiet(1, config(NEVER))
		g.protect = 100
		Classic.step(g, { hyperspace = true })
		t.expect(g.protect).toBe(99)
		run(g, 28)
		t.expect(g.shipState).toBe("hyperspace")
		t.expect(g.protect).toBe(71)
		-- a rock on the spot it comes back to: still protected, the ship passes through and the rock stays whole
		table.insert(g.rocks, { id = 900, size = "small", x = g.ship.x, y = g.ship.y, vx = 0, vy = 0 })
		local e = run(g, 2)
		t.expect(kinds(e)).toEqual({ "HyperspaceEnd" })
		t.expect(g.protect).toBe(69)
		e = run(g, 10)
		t.expect(#e).toBe(0)
		t.expect(g.lives).toBe(3)
		t.expect(#g.rocks).toBe(1)
	end)

	it("explodes on re-entry whether or not the ship is protected", function()
		local g = quiet(1, config(1))
		g.protect = 100
		Classic.step(g, { hyperspace = true })
		local e = run(g, 30)
		t.expect(kinds(e)).toEqual({ "ShipDestroyed" })
		t.expect(e[1].cause).toBe("hyperspace")
	end)

	it("explodes about 1 jump in 6", function()
		t.expect(CFG.hyperspaceOdds).toBe(6)
		local lost = 0
		for seed = 1, 1200 do
			local g = quiet(seed)
			Classic.step(g, { hyperspace = true })
			for _ = 1, 30 do
				Classic.step(g, nil)
			end
			if g.lives == 2 then
				lost += 1
			end
		end
		-- 200 expected; 160 to 240 is about three standard deviations either way
		t.expect(lost >= 160 and lost <= 240).toBe(true)
	end)

	it("cannot jump while the ship is lost", function()
		local g = quiet()
		g.shipState = "dead"
		g.timer = 50
		local e = Classic.step(g, { hyperspace = true })
		t.expect(#e).toBe(0)
		t.expect(g.shipState).toBe("dead")
	end)
end)
