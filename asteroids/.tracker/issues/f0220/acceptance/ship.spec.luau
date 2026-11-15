--!strict
-- f0220 AC2: the ship. It starts at the field's centre, at rest, pointing up (heading 64). It turns at a fixed
-- 3 headings a tick (a turn of 1 is to the left, -1 to the right), thrusts 0.1 a tick along its new heading
-- with inertia, loses 1% of its velocity to drag every tick, and never goes faster than 6 a tick. One tick is
-- turn, thrust, drag, the top speed, then the move. Input counts only as exactly 1 or -1, and exactly true.
local Classic = require("@logic/Classic")
local Ship = require("@logic/Ship")
local t = require("@tests/lib/t")

local CFG = Classic.CONFIG

local function quiet(): Classic.Game
	local g = Classic.new(1)
	g.rocks = {}
	g.waveTimer = 1e9 -- no next wave in this case
	g.saucerElapsed = -1e9 -- no saucer in this case
	return g
end

local function speed(g: Classic.Game): number
	return math.sqrt(g.ship.vx ^ 2 + g.ship.vy ^ 2)
end

return t.spec("f0220 ship", function(it)
	it("starts at the centre of the field, at rest, pointing up", function()
		local g = Classic.new(1)
		t.expect(g.ship.x).toBe(512)
		t.expect(g.ship.y).toBe(384)
		t.expect(g.ship.vx).toBe(0)
		t.expect(g.ship.vy).toBe(0)
		t.expect(g.ship.heading).toBe(64)
		t.expect(g.shipState).toBe("alive")
		t.expect(CFG.ship).toBe(Ship.CLASSIC)
	end)

	it("turns 3 headings a tick: 1 to the left, -1 to the right, round past 0", function()
		local g = quiet()
		Classic.step(g, { turn = 1 })
		t.expect(g.ship.heading).toBe(67)
		Classic.step(g, { turn = 1 })
		t.expect(g.ship.heading).toBe(70)
		Classic.step(g, { turn = -1 })
		t.expect(g.ship.heading).toBe(67)
		g.ship.heading = 1
		Classic.step(g, { turn = -1 })
		t.expect(g.ship.heading).toBe(254)
		g.ship.heading = 254
		Classic.step(g, { turn = 1 })
		t.expect(g.ship.heading).toBe(1)
		-- turning moves nothing: the ship stays at rest
		t.expect(g.ship.x).toBe(512)
		t.expect(g.ship.y).toBe(384)
	end)

	it("turns only on a turn of exactly 1 or -1", function()
		local g = quiet()
		for _, bad in { 2, -2, 0.5, 3, "1", true } :: { any } do
			Classic.step(g, { turn = bad :: any })
		end
		t.expect(g.ship.heading).toBe(64)
		Classic.step(g, nil)
		Classic.step(g, "turn" :: any)
		t.expect(g.ship.heading).toBe(64)
	end)

	it("thrusts 0.1 along the heading it has after this tick's turn", function()
		local g = quiet()
		Classic.step(g, { turn = 1, thrust = true })
		t.expect(g.ship.heading).toBe(67)
		-- 0.1 along heading 67, less 1% drag
		t.expect(g.ship.vx).toBeNear(-0.007282891796, 1e-9)
		t.expect(g.ship.vy).toBeNear(0.098731755211, 1e-9)
		t.expect(g.ship.x).toBeNear(512 - 0.007282891796, 1e-9)
		t.expect(g.ship.y).toBeNear(384 + 0.098731755211, 1e-9)
	end)

	it(
		"keeps its velocity when the thrust stops, and drifts on it, losing 1% a tick before it moves",
		function()
			local g = quiet()
			g.ship.vx, g.ship.vy = 5, -2
			Classic.step(g, { turn = 1 })
			t.expect(g.ship.vx).toBeNear(4.95, 1e-12)
			t.expect(g.ship.vy).toBeNear(-1.98, 1e-12)
			t.expect(g.ship.x).toBeNear(516.95, 1e-9)
			t.expect(g.ship.y).toBeNear(382.02, 1e-9)
			Classic.step(g, nil)
			t.expect(g.ship.vx).toBeNear(4.9005, 1e-12)
			t.expect(g.ship.x).toBeNear(521.8505, 1e-9)
		end
	)

	it("drags while it thrusts too", function()
		local g = quiet()
		g.ship.heading = 0
		g.ship.vx = 3
		Classic.step(g, { thrust = true })
		t.expect(g.ship.vx).toBeNear(3.069, 1e-12)
		t.expect(g.ship.x).toBeNear(515.069, 1e-9)
	end)

	it("never goes faster than 6 a tick, however long it thrusts", function()
		local g = quiet()
		g.ship.heading = 0
		g.ship.vx = 6
		Classic.step(g, { thrust = true })
		-- 6.1 less 1% is 6.039, held to 6
		t.expect(g.ship.vx).toBeNear(6, 1e-12)
		t.expect(g.ship.x).toBeNear(518, 1e-9)
		local h = quiet()
		h.ship.heading = 32
		local top = 0
		for _ = 1, 300 do
			Classic.step(h, { thrust = true })
			top = math.max(top, speed(h))
		end
		t.expect(top).toBeNear(6, 1e-9)
		t.expect(speed(h)).toBeNear(6, 1e-9)
		t.expect(h.ship.vx).toBeNear(h.ship.vy, 1e-9)
	end)

	it("reaches its top speed after 93 ticks of thrust from rest (about 1.5 s)", function()
		local g = quiet()
		g.ship.heading = 0
		local ticks = 0
		while speed(g) < 6 - 1e-9 and ticks < 1000 do
			Classic.step(g, { thrust = true })
			ticks += 1
		end
		-- the drag slows the climb (9.9 x (1 - 0.99^n) reaches 6 at n = 92.7); 0.1 a tick alone would take 60
		t.expect(ticks).toBe(93)
	end)

	it("thrusts only on a thrust of exactly true", function()
		local g = quiet()
		for _, bad in { 1, "true", {} } :: { any } do
			Classic.step(g, { thrust = bad :: any })
		end
		t.expect(g.ship.vx).toBe(0)
		t.expect(g.ship.vy).toBe(0)
	end)
end)
