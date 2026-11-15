--!strict
-- f0220 AC1: the wrap-around field. The rules are 2-D on a flat 1,024 x 768 field: leave one edge and you come
-- back on the opposite edge, and every distance is measured the short way across the wrap. Headings are 256
-- whole steps, counter-clockwise from +x (64 is up). A moving point is checked along its whole move, never only
-- where it lands. The ship, the rocks, every shot and the saucers all wrap.
local Classic = require("@logic/Classic")
local Field = require("@logic/Field")
local t = require("@tests/lib/t")

local F = Field.CLASSIC

local function quiet(): Classic.Game
	local g = Classic.new(1)
	g.rocks = {}
	g.waveTimer = 1e9 -- no next wave in this case
	g.saucerElapsed = -1e9 -- no saucer in this case
	return g
end

return t.spec("f0220 field", function(it)
	it("is 1,024 wide and 768 high, and the run plays on it", function()
		t.expect(F.width).toBe(1024)
		t.expect(F.height).toBe(768)
		t.expect(Classic.CONFIG.field).toBe(F)
	end)

	it("wraps a point that leaves any edge onto the opposite edge", function()
		local x, y = Field.wrap(F, 1025, -1)
		t.expect(x).toBe(1)
		t.expect(y).toBe(767)
		x, y = Field.wrap(F, -0.5, 768)
		t.expect(x).toBe(1023.5)
		t.expect(y).toBe(0)
		x, y = Field.wrap(F, 300, 200)
		t.expect(x).toBe(300)
		t.expect(y).toBe(200)
	end)

	it("measures the short way across the wrap", function()
		local dx, dy = Field.delta(F, 1000, 10, 20, 760)
		t.expect(dx).toBe(44)
		t.expect(dy).toBe(-18)
		t.expect(Field.distance(F, 1000, 10, 20, 760)).toBeNear(47.539457296019, 1e-9)
		dx, dy = Field.delta(F, 20, 760, 1000, 10)
		t.expect(dx).toBe(-44)
		t.expect(dy).toBe(18)
		dx, dy = Field.delta(F, 100, 100, 300, 200)
		t.expect(dx).toBe(200)
		t.expect(dy).toBe(100)
		-- exactly half the field away counts as the negative half
		dx, dy = Field.delta(F, 0, 0, 512, 384)
		t.expect(dx).toBe(-512)
		t.expect(dy).toBe(-384)
	end)

	it("has 256 headings, counter-clockwise from +x", function()
		t.expect(Field.HEADINGS).toBe(256)
		local x, y = Field.unit(0)
		t.expect(x).toBeNear(1, 1e-12)
		t.expect(y).toBeNear(0, 1e-12)
		x, y = Field.unit(64)
		t.expect(x).toBeNear(0, 1e-12)
		t.expect(y).toBeNear(1, 1e-12)
		x, y = Field.unit(128)
		t.expect(x).toBeNear(-1, 1e-12)
		t.expect(y).toBeNear(0, 1e-12)
		x, y = Field.unit(32)
		t.expect(x).toBeNear(math.sqrt(0.5), 1e-12)
		t.expect(y).toBeNear(math.sqrt(0.5), 1e-12)
		t.expect(Field.heading(1, 0)).toBe(0)
		t.expect(Field.heading(0, 5)).toBe(64)
		t.expect(Field.heading(-3, 0)).toBe(128)
		t.expect(Field.heading(2, -2)).toBe(224)
		t.expect(Field.heading(0, 0)).toBe(0)
		-- the nearest heading, not the one below
		local a = 10.6 * 2 * math.pi / 256
		t.expect(Field.heading(math.cos(a), math.sin(a))).toBe(11)
		a = 10.4 * 2 * math.pi / 256
		t.expect(Field.heading(math.cos(a), math.sin(a))).toBe(10)
	end)

	it("finds where a moving point first comes within a radius, along its whole move", function()
		-- already inside at the start
		t.expect(Field.sweep(F, 100, 100, 8, 0, 106, 100, 10)).toBe(0)
		-- reaches the circle a quarter of the way along
		t.expect(Field.sweep(F, 100, 100, 8, 0, 112, 100, 10)).toBeNear(0.25, 1e-12)
		-- passes through a chord: both ends are outside, the middle inside
		t.expect(Field.sweep(F, 100, 100, 14, 0, 107, 109, 10)).toBeNear(0.188650075461, 1e-9)
		-- passes just outside
		t.expect(Field.sweep(F, 100, 100, 14, 0, 107, 111, 10)).toBe(nil)
		-- only touches it: closer than the radius is needed
		t.expect(Field.sweep(F, 100, 90, 20, 0, 110, 100, 10)).toBe(nil)
		-- stops short of it
		t.expect(Field.sweep(F, 100, 100, 8, 0, 119, 100, 10)).toBe(nil)
		-- moving away from it
		t.expect(Field.sweep(F, 100, 100, -8, 0, 112, 100, 10)).toBe(nil)
		-- not moving, outside
		t.expect(Field.sweep(F, 100, 100, 0, 0, 112, 100, 10)).toBe(nil)
		-- across the wrap: from x 1020 to the circle round x 4
		t.expect(Field.sweep(F, 1020, 100, 8, 0, 4, 100, 5)).toBeNear(0.375, 1e-12)
		t.expect(Field.sweep(F, 100, 2, 0, -6, 100, 764, 3)).toBeNear(0.5, 1e-12)
	end)

	it("wraps every body on the field: the ship, a rock, a shot and a saucer", function()
		local g = quiet()
		g.ship.x, g.ship.y, g.ship.vx, g.ship.vy = 1023, 0.5, 2, -1
		table.insert(g.rocks, { id = 900, size = "small", x = 1, y = 300, vx = -2, vy = 0 })
		table.insert(g.rocks, { id = 901, size = "small", x = 300, y = 767, vx = 0, vy = 2 })
		table.insert(g.shots, { x = 1020, y = 400, vx = 8, vy = 0, life = 30 })
		g.saucerShots = { { x = 1022, y = 700, vx = 6, vy = 0, life = 30 } }
		g.saucer = {
			kind = "large",
			x = 500,
			y = 767,
			vx = 2,
			vy = 2,
			travelled = 0,
			fireElapsed = -1e9,
			turnElapsed = -1e9,
		}
		Classic.step(g, nil)
		-- the ship loses 1% to drag before it moves
		t.expect(g.ship.x).toBeNear(1023 + 1.98 - 1024, 1e-9)
		t.expect(g.ship.y).toBeNear(0.5 - 0.99 + 768, 1e-9)
		t.expect(g.rocks[1].x).toBe(1023)
		t.expect(g.rocks[1].y).toBe(300)
		t.expect(g.rocks[2].x).toBe(300)
		t.expect(g.rocks[2].y).toBe(1)
		t.expect(g.shots[1].x).toBe(4)
		t.expect(g.shots[1].y).toBe(400)
		local s = g.saucer :: any
		t.expect(s.x).toBe(502)
		t.expect(s.y).toBe(1)
		t.expect(g.saucerShots[1].x).toBe(4)
		t.expect(g.saucerShots[1].y).toBe(700)
	end)

	it("hits across the wrap too: a ram, a saucer's ram, a saucer's shot and the ship's shot", function()
		local function kinds(events: { Classic.Event }): { string }
			local out = {}
			for _, e in events do
				table.insert(out, e.kind)
			end
			return out
		end
		local function still(kind: "large" | "small", x: number, y: number): any
			return {
				kind = kind,
				x = x,
				y = y,
				vx = 0,
				vy = 0,
				travelled = 0,
				fireElapsed = -1e9,
				turnElapsed = -1e9,
			}
		end
		-- a rock 10 away across the side edge, and one 10 away across the top
		local g = quiet()
		g.ship.x, g.ship.y = 1020, 384
		table.insert(g.rocks, { id = 900, size = "small", x = 6, y = 384, vx = 0, vy = 0 })
		local e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit", "ShipDestroyed" })
		t.expect(e[1].by).toBe("ship")
		t.expect(e[2].cause).toBe("rock")
		g = quiet()
		g.ship.x, g.ship.y = 512, 2
		table.insert(g.rocks, { id = 901, size = "small", x = 512, y = 760, vx = 0, vy = 0 })
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit", "ShipDestroyed" })
		-- a small saucer 12 away across the side edge
		g = quiet()
		g.ship.x, g.ship.y = 1020, 384
		g.saucer = still("small", 8, 384)
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "SaucerHit", "ShipDestroyed" })
		t.expect(e[2].cause).toBe("saucer")
		-- a saucer's shot 14 away across the edge, 8 after its move
		g = quiet()
		g.ship.x, g.ship.y = 6, 384
		g.saucerShots = { { x = 1016, y = 384, vx = 6, vy = 0, life = 30 } }
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "ShipDestroyed" })
		t.expect(e[1].cause).toBe("saucershot")
		-- the ship's shot reaching a rock across the edge
		g = quiet()
		g.shots = { { x = 1018, y = 100, vx = 8, vy = 0, life = 30 } }
		table.insert(g.rocks, { id = 902, size = "small", x = 10, y = 100, vx = 0, vy = 0 })
		e = Classic.step(g, nil)
		t.expect(kinds(e)).toEqual({ "RockHit" })
		t.expect(e[1].by).toBe("shot")
	end)
end)
