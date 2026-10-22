--!strict
-- f0102 AC3: where a glow is drawn. Awareness.glowBox makes a square of GLOW.side times the screen's smaller side
-- times the glow's size, centred on its edge point and moved in until it is whole on the screen. So a glow hugs the
-- edge and never reaches into the middle of the screen, the view ahead.
local Awareness = require("@logic/Awareness")
local t = require("@tests/lib/t")

local SCREENS = { { 1920, 1080 }, { 1280, 720 }, { 390, 844 }, { 844, 390 }, { 1024, 1024 } }

return t.spec("f0102 glow boxes", function(it)
	it("a full-size glow is 12% of the smaller side", function()
		t.expect(Awareness.GLOW.side).toBe(0.12)
		local box = Awareness.glowBox(0, -1, 1, 1920, 1080)
		t.expect(box.w).toBeNear(129.6, 1e-9)
		t.expect(box.h).toBeNear(129.6, 1e-9)
	end)

	it("it is centred on its edge point, then moved in to be whole on the screen", function()
		-- the top middle: centred across, flush with the top
		t.expect(Awareness.glowBox(0, -1, 1, 1000, 500)).toEqual({ x = 470, y = 0, w = 60, h = 60 })
		-- the bottom-right corner: flush with both edges
		t.expect(Awareness.glowBox(1, 1, 1, 1000, 500)).toEqual({ x = 940, y = 440, w = 60, h = 60 })
		-- the left middle
		t.expect(Awareness.glowBox(-1, 0, 1, 1000, 500)).toEqual({ x = 0, y = 220, w = 60, h = 60 })
		-- half size, top-left corner
		t.expect(Awareness.glowBox(-1, -1, 0.5, 1000, 500)).toEqual({ x = 0, y = 0, w = 30, h = 30 })
	end)

	it("it grows with the glow's size", function()
		local small = Awareness.glowBox(0, 1, 0.25, 1280, 720)
		local big = Awareness.glowBox(0, 1, 1, 1280, 720)
		t.expect(small.w < big.w).toBe(true)
		t.expect(big.w).toBeNear(4 * small.w, 1e-9)
	end)

	it("on every screen and in every place, it is whole on the screen and clear of the middle", function()
		for _, screen in SCREENS do
			local w, h = screen[1], screen[2]
			local inset = Awareness.GLOW.side * math.min(w, h)
			for k = 0, 7 do
				local u, v = Awareness.edgePoint(Awareness.sectorBearing(k, w / h), w / h)
				for _, size in { 0.25, 0.6, 1 } do
					local b = Awareness.glowBox(u, v, size, w, h)
					t.expect(b.x >= -1e-9 and b.y >= -1e-9).toBe(true)
					t.expect(b.x + b.w <= w + 1e-9 and b.y + b.h <= h + 1e-9).toBe(true)
					-- it touches an edge, and stays within `inset` of one
					local nearest = math.min(b.x, b.y, w - (b.x + b.w), h - (b.y + b.h))
					t.expect(nearest).toBeNear(0, 1e-9)
					local middle = { x = inset, y = inset, w = w - 2 * inset, h = h - 2 * inset }
					local e = 1e-6 -- a shared edge is not an overlap, even after rounding
					local overlaps = b.x + e < middle.x + middle.w
						and middle.x + e < b.x + b.w
						and b.y + e < middle.y + middle.h
						and middle.y + e < b.y + b.h
					t.expect(overlaps).toBe(false)
				end
			end
		end
	end)

	it("nonsense in gives an empty box on the screen, never NaN", function()
		for _, args in
			{
				{ 0 / 0, 0 / 0, 1, 1280, 720 },
				{ 0, -1, 0 / 0, 1280, 720 },
				{ 0, -1, 1, 0 / 0, 720 },
				{ 0, -1, 1, -5, 720 },
				{ 0, -1, -3, 1280, 720 },
				{ 7, -9, 1, 1280, 720 },
			}
		do
			local b = Awareness.glowBox(args[1], args[2], args[3], args[4], args[5])
			for _, n in { b.x, b.y, b.w, b.h } do
				t.expect(n == n).toBe(true)
				t.expect(n >= 0).toBe(true)
			end
		end
		t.expect(Awareness.glowBox(0, -1, 1, 0 / 0, 720).w).toBe(0)
		t.expect(Awareness.glowBox(0, -1, -3, 1280, 720).w).toBe(0)
		t.expect(Awareness.glowBox(7, -9, 1, 1280, 720)).toEqual(Awareness.glowBox(1, -1, 1, 1280, 720))
	end)
end)
