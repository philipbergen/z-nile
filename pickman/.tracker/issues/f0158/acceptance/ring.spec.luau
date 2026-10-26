--!strict
-- f0158 AC1: the danger ring's geometry (Awareness.ring). Every sector has Awareness.RING.dots dots on one circle
-- centred on the screen, as wide as Awareness.RING.share of the screen's smaller side (the dots' outer edge), each
-- Awareness.RING.dot of that side across. Sector 0 (ahead) is at the top and the sectors go round to the left as
-- Awareness.sector counts them, with a gap between neighbouring sectors wider than the step inside one. Only a
-- ghost that can kill (look "normal") lights a sector, at the nearest such ghost's brightness (clamped to 0..1);
-- frightened and blinking ghosts never light it, nor hide a dangerous one farther away in the same sector
-- (decided with the user, 2026-10-26: one warning colour, not a colour match; edible ghosts not shown, prep's choice).
local Awareness = require("@logic/Awareness")
local t = require("@tests/lib/t")

local SCREENS = { { 1280, 720 }, { 1920, 1080 }, { 1024, 768 }, { 390, 844 }, { 844, 390 } }

local function centre(d: Awareness.RingDot): (number, number)
	return d.x + d.w / 2, d.y + d.h / 2
end

-- an indicator in `sector` (its bearing: an eighth of a turn per sector, positive left), as Awareness.indicators makes
local function ind(
	index: number,
	sector: number,
	distance: number,
	brightness: number,
	look: Awareness.Look
): Awareness.Indicator
	return {
		index = index,
		bearing = sector * math.pi / 4,
		distance = distance,
		size = 1,
		brightness = brightness,
		look = look,
		inView = false,
	}
end

return t.spec("f0158 the danger ring", function(it)
	it("the ring's numbers are the capture's: about 60% of the smaller side, eight sectors", function()
		t.expect(Awareness.RING.share).toBe(0.6)
		t.expect(Awareness.SECTORS).toBe(8)
		t.expect(Awareness.RING.dots >= 3).toBe(true)
		t.expect(Awareness.RING.dot > 0 and Awareness.RING.dot < 0.1).toBe(true)
	end)

	it(
		"every sector has its dots, on one circle centred on the screen, 60% of the smaller side across",
		function()
			for _, s in SCREENS do
				local w, h = s[1], s[2]
				local small = math.min(w, h)
				local dots = Awareness.ring({}, w, h)
				t.expect(#dots).toBe(Awareness.SECTORS * Awareness.RING.dots)
				local per: { [number]: number } = {}
				local sx, sy = 0, 0
				for _, d in dots do
					per[d.sector] = (per[d.sector] or 0) + 1
					t.expect(math.abs(d.w - Awareness.RING.dot * small) < 1e-6).toBe(true)
					t.expect(d.w).toBe(d.h)
					local x, y = centre(d)
					sx += x
					sy += y
					-- the dot's outer edge is on the ring's outer circle
					local r = math.sqrt((x - w / 2) ^ 2 + (y - h / 2) ^ 2)
					t.expect(math.abs(r + d.w / 2 - Awareness.RING.share * small / 2) < 1e-6).toBe(true)
				end
				for k = 0, Awareness.SECTORS - 1 do
					t.expect(per[k]).toBe(Awareness.RING.dots)
				end
				t.expect(math.abs(sx / #dots - w / 2) < 1e-6).toBe(true)
				t.expect(math.abs(sy / #dots - h / 2) < 1e-6).toBe(true)
			end
		end
	)

	it("sector 0 is at the top and the sectors go round to the left: 2 left, 4 bottom, 6 right", function()
		local w, h = 1280, 720
		local mean: { [number]: { x: number, y: number, n: number } } = {}
		for _, d in Awareness.ring({}, w, h) do
			local x, y = centre(d)
			local m = mean[d.sector] or { x = 0, y = 0, n = 0 }
			m.x += x - w / 2
			m.y += y - h / 2
			m.n += 1
			mean[d.sector] = m
		end
		local function at(k: number): (number, number)
			return mean[k].x / mean[k].n, mean[k].y / mean[k].n
		end
		local x0, y0 = at(0)
		t.expect(y0 < 0 and math.abs(x0) < 1e-6).toBe(true)
		local x2, y2 = at(2)
		t.expect(x2 < 0 and math.abs(y2) < 1e-6).toBe(true)
		local x4, y4 = at(4)
		t.expect(y4 > 0 and math.abs(x4) < 1e-6).toBe(true)
		local x6, y6 = at(6)
		t.expect(x6 > 0 and math.abs(y6) < 1e-6).toBe(true)
		local x1, y1 = at(1)
		t.expect(x1 < 0 and y1 < 0).toBe(true) -- top-left
	end)

	it("a sector's dots are evenly spaced, and the gap to the next sector is wider than that step", function()
		local dots = Awareness.ring({}, 1280, 720)
		local function angle(d: Awareness.RingDot): number
			local x, y = centre(d)
			return math.atan2(-(x - 640), -(y - 360)) -- positive to the left, 0 at the top
		end
		local n = Awareness.RING.dots
		local a1, a2 = angle(dots[1]), angle(dots[2])
		local inside = math.abs(a2 - a1)
		local lastOf0, firstOf1 = angle(dots[n]), angle(dots[n + 1])
		local across = math.abs(firstOf1 - lastOf0)
		t.expect(inside > 0).toBe(true)
		t.expect(across > inside * 1.5).toBe(true)
		for i = 2, n - 1 do
			t.expect(math.abs(math.abs(angle(dots[i + 1]) - angle(dots[i])) - inside) < 1e-9).toBe(true)
		end
	end)

	it("only dangerous ghosts light a sector, the nearest one's brightness, clamped", function()
		local dots = Awareness.ring({
			ind(1, 2, 3, 0.5, "normal"),
			ind(2, 5, 1, 1.7, "normal"),
			ind(3, 0, 1, 0.9, "frightened"),
			ind(4, 6, 1, 0.9, "blinking"),
			-- in sector 3 a nearer frightened ghost does not hide a farther dangerous one
			ind(5, 3, 1, 0.9, "frightened"),
			ind(6, 3, 6, 0.4, "normal"),
			-- in sector 7 the nearer of two dangerous ghosts gives the brightness
			ind(7, 7, 8, 0.2, "normal"),
			ind(8, 7, 2, 0.8, "normal"),
		}, 1280, 720)
		local want: { [number]: number } = { [2] = 0.5, [5] = 1, [3] = 0.4, [7] = 0.8 }
		for _, d in dots do
			local b = want[d.sector]
			if b then
				t.expect(d.lit).toBe(true)
				t.expect(d.brightness).toBe(b)
			else
				t.expect(d.lit).toBe(false)
				t.expect(d.brightness).toBe(0)
			end
		end
	end)

	it("a screen side that is not a positive finite number gives empty dots at the centre", function()
		for _, bad in { 0, -5, 0 / 0, math.huge } do
			for _, d in Awareness.ring({}, bad, 720) do
				t.expect(d.w).toBe(0)
				t.expect(d.x).toBe(0)
			end
		end
	end)
end)
