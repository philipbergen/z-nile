--!strict
-- f0102 AC1: the eight places a glow can be. A bearing (from where the camera looks, positive left) falls in the
-- nearest eighth of a turn: 0 ahead (the top of the screen), 1 ahead-left (the top-left corner), 2 left, 3
-- behind-left (bottom-left), 4 behind (the bottom), 5 behind-right, 6 right, 7 ahead-right. Exactly between two,
-- the one ahead, behind or to a side wins over the corner. Awareness.sectorBearing gives the bearing that
-- Awareness.edgePoint maps to that place: the middle of an edge, or the corner itself on any screen shape.
local Awareness = require("@logic/Awareness")
local t = require("@tests/lib/t")

local PI = math.pi
local E = PI / 4

return t.spec("f0102 sectors", function(it)
	it("there are eight", function()
		t.expect(Awareness.SECTORS).toBe(8)
	end)

	it("the middle of each eighth is that sector", function()
		local want = { [0] = 0, [1] = 1, [2] = 2, [3] = 3, [4] = 4, [-1] = 7, [-2] = 6, [-3] = 5 }
		for k, sector in want do
			t.expect(Awareness.sector(k * E)).toBe(sector)
		end
		t.expect(Awareness.sector(PI)).toBe(4)
		t.expect(Awareness.sector(-PI)).toBe(4)
	end)

	it("a bearing goes to the nearest sector, just either side of a boundary", function()
		local d = 1e-6
		t.expect(Awareness.sector(E / 2 - d)).toBe(0)
		t.expect(Awareness.sector(E / 2 + d)).toBe(1)
		t.expect(Awareness.sector(-E / 2 + d)).toBe(0)
		t.expect(Awareness.sector(-E / 2 - d)).toBe(7)
		t.expect(Awareness.sector(3 * E / 2 - d)).toBe(1)
		t.expect(Awareness.sector(3 * E / 2 + d)).toBe(2)
		t.expect(Awareness.sector(PI - E / 2 + d)).toBe(4)
		t.expect(Awareness.sector(-PI + E / 2 - d)).toBe(4)
		t.expect(Awareness.sector(-PI + E / 2 + d)).toBe(5)
	end)

	it("exactly between two, the edge sector wins over the corner", function()
		t.expect(Awareness.sector(0.5 * E)).toBe(0)
		t.expect(Awareness.sector(-0.5 * E)).toBe(0)
		t.expect(Awareness.sector(1.5 * E)).toBe(2)
		t.expect(Awareness.sector(2.5 * E)).toBe(2)
		t.expect(Awareness.sector(3.5 * E)).toBe(4)
		t.expect(Awareness.sector(-3.5 * E)).toBe(4)
		t.expect(Awareness.sector(-2.5 * E)).toBe(6)
		t.expect(Awareness.sector(-1.5 * E)).toBe(6)
	end)

	it("a bearing that is not finite is ahead", function()
		t.expect(Awareness.sector(0 / 0)).toBe(0)
		t.expect(Awareness.sector(math.huge)).toBe(0)
	end)

	it(
		"each sector's bearing lands on its place: edge middles and the four corners, on any screen",
		function()
			for _, aspect in { 16 / 9, 1, 4 / 3, 9 / 16, 2.4 } do
				local want = {
					[0] = { 0, -1 },
					[1] = { -1, -1 },
					[2] = { -1, 0 },
					[3] = { -1, 1 },
					[4] = { 0, 1 },
					[5] = { 1, 1 },
					[6] = { 1, 0 },
					[7] = { 1, -1 },
				}
				for k, uv in want do
					local u, v = Awareness.edgePoint(Awareness.sectorBearing(k, aspect), aspect)
					t.expect(u).toBeNear(uv[1], 1e-9)
					t.expect(v).toBeNear(uv[2], 1e-9)
				end
			end
		end
	)

	it(
		"a sector's bearing is in (-pi, pi], and an aspect that is not a positive number counts as square",
		function()
			for k = 0, 7 do
				local b = Awareness.sectorBearing(k, 16 / 9)
				t.expect(b > -PI and b <= PI).toBe(true)
				for _, bad in { 0, -2, 0 / 0, math.huge } do
					t.expect(Awareness.sectorBearing(k, bad)).toBeNear(Awareness.sectorBearing(k, 1), 1e-12)
				end
			end
			t.expect(Awareness.sectorBearing(1, 1)).toBeNear(E, 1e-12)
		end
	)
end)
