--!strict
-- f0290 AC3: where pellets are drawn and how big, from View (pure): each sits at its tile's centre at
-- View.PELLET.height, sized by kind, inside the corridor and below the eye line; a power pellet pulses in
-- real time and stays visible down the longest corridor even at its smallest.
local View = require("@logic/View")
local t = require("@tests/lib/t")

local LONGEST_CORRIDOR_TILES = 26 -- the classic maze's rows 5 and 29 run 26 tiles

local function degrees(diameter: number, tiles: number): number
	local distance = tiles * View.SCALE.tileStuds
	return math.deg(2 * math.atan((diameter / 2) / distance))
end

return t.spec("f0290 pellet placement", function(it)
	it("a pellet sits at its tile's centre, at the pellet height, with the pellet diameter", function()
		local part = View.pellet({ x = 3, y = 5, kind = "pellet" })
		local wx, wz = View.world(3, 5)
		t.expect(part).toEqual({ x = wx, y = View.PELLET.height, z = wz, diameter = View.PELLET.pellet })
	end)

	it("a power pellet uses the power diameter at the same height", function()
		local part = View.pellet({ x = 26, y = 3, kind = "power" })
		local wx, wz = View.world(26, 3)
		t.expect(part).toEqual({ x = wx, y = View.PELLET.height, z = wz, diameter = View.PELLET.power })
	end)

	it("the position depends on the tile, not only the kind", function()
		local a = View.pellet({ x = 1, y = 1, kind = "pellet" })
		local b = View.pellet({ x = 2, y = 7, kind = "pellet" })
		t.expect(b.x - a.x).toBe(View.SCALE.tileStuds)
		t.expect(b.z - a.z).toBe(6 * View.SCALE.tileStuds)
	end)

	it(
		"both kinds clear the floor and the ceiling of the walls, centred below the eye line, inside one tile",
		function()
			local s = View.SCALE
			for _, kind in { "pellet", "power" } do
				local d = View.pellet({ x = 0, y = 0, kind = kind :: any }).diameter
				t.expect(View.PELLET.height - d / 2 > 0).toBe(true)
				t.expect(View.PELLET.height < s.eyeHeight).toBe(true)
				t.expect(View.PELLET.height + d / 2 < s.wallHeight).toBe(true)
				t.expect(d < s.tileStuds).toBe(true)
			end
		end
	)

	it("a power pellet is at least 2.5 times a pellet's diameter", function()
		t.expect(View.PELLET.power >= 2.5 * View.PELLET.pellet).toBe(true)
	end)

	it("a power pellet at its smallest spans at least half a degree down the longest corridor", function()
		local smallest = math.huge
		for i = 0, 100 do
			smallest = math.min(smallest, View.pulse("power", i * View.PELLET.pulseSeconds / 100))
		end
		t.expect(degrees(View.PELLET.power * smallest, LONGEST_CORRIDOR_TILES) >= 0.5).toBe(true)
	end)

	it("a pellet never pulses", function()
		for _, s in { 0, 0.1, 0.25, 0.37, 1, 12.5 } do
			t.expect(View.pulse("pellet", s)).toBe(1)
		end
	end)

	it("a power pellet pulses between pulseMin and full size, one cycle per pulseSeconds", function()
		local p = View.PELLET
		t.expect(View.pulse("power", 0)).toBeNear(1, 1e-9)
		t.expect(View.pulse("power", p.pulseSeconds / 2)).toBeNear(p.pulseMin, 1e-9)
		t.expect(View.pulse("power", p.pulseSeconds)).toBeNear(1, 1e-9)
		t.expect(View.pulse("power", 3 * p.pulseSeconds + p.pulseSeconds / 2)).toBeNear(p.pulseMin, 1e-9)
		t.expect(p.pulseMin < 1).toBe(true)
		for i = 0, 40 do
			local v = View.pulse("power", i * 0.037)
			t.expect(v >= p.pulseMin - 1e-9 and v <= 1 + 1e-9).toBe(true)
		end
	end)

	it("the pulse is smooth: a quarter cycle is halfway", function()
		local p = View.PELLET
		t.expect(View.pulse("power", p.pulseSeconds / 4)).toBeNear((1 + p.pulseMin) / 2, 1e-9)
	end)

	it("a NaN or infinite time is full size", function()
		t.expect(View.pulse("power", 0 / 0)).toBe(1)
		t.expect(View.pulse("power", math.huge)).toBe(1)
	end)
end)
