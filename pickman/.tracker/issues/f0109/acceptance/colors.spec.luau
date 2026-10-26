--!strict
-- f0109: Inky gets a colour of its own that stands out (the user: the near-white ghost "is just not very visible"),
-- and the maze walls are green while the ghosts are edible (the power timer runs), blue otherwise, lit white during
-- the level-clear flash, which wins. Visibility is measured: WCAG contrast against what a ghost is seen against, and
-- CIE76 colour distance from the other ghost colours. The pellets' and shots' colours are read from their views
-- (place.spec).
local View = require("@logic/View")
local t = require("@tests/lib/t")

type Rgb = View.Rgb

local function lin(v: number): number
	local c = v / 255
	return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end
local function luminance(c: Rgb): number
	return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
end
local function contrast(a: Rgb, b: Rgb): number
	local la, lb = luminance(a), luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end
local function lab(c: Rgb): (number, number, number)
	local r, g, b = lin(c.r), lin(c.g), lin(c.b)
	local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	local y = 0.2126 * r + 0.7152 * g + 0.0722 * b
	local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	local function f(v: number): number
		return if v > 0.008856 then v ^ (1 / 3) else 7.787 * v + 16 / 116
	end
	return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))
end
local function distance(a: Rgb, b: Rgb): number
	local l1, a1, b1 = lab(a)
	local l2, a2, b2 = lab(b)
	return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end
local function rgb(c: Rgb): string
	return `{c.r},{c.g},{c.b}`
end
local FLOOR: Rgb = { r = 0, g = 0, b = 0 } -- MazeView's floor (black; f0109 does not change it)
local DANGEROUS = { "blinky", "pinky", "clyde", "inky" }

return t.spec("f0109 Inky's colour and green walls", function(it)
	it("Inky is lemon, 230,255,0, for its body and its glow (G1)", function()
		t.expect(rgb(View.GHOST_COLORS.inky)).toBe("230,255,0")
		t.expect(rgb(View.ghostColor("inky", "normal", false))).toBe("230,255,0")
		t.expect(rgb(View.ghostColor("inky", "normal", true))).toBe("230,255,0")
	end)

	it("Inky stands out against the blue walls and the floor", function()
		local inky = View.GHOST_COLORS.inky
		t.expect(contrast(inky, View.WALL_COLOR) >= 4.5).toBe(true)
		t.expect(contrast(inky, FLOOR) >= 4.5).toBe(true)
	end)

	it("Inky's colour is far from every other ghost's and from the frightened and white looks", function()
		local inky = View.GHOST_COLORS.inky
		for _, name in { "blinky", "pinky", "clyde" } do
			t.expect(distance(inky, View.GHOST_COLORS[name]) >= 30).toBe(true)
		end
		for _, other in { View.FRIGHTENED_COLOR, View.WHITE } do
			t.expect(distance(inky, other) >= 30).toBe(true)
		end
	end)

	it("the other ghosts and the frightened, blinking and eyes looks are unchanged", function()
		t.expect(rgb(View.GHOST_COLORS.blinky)).toBe("255,0,0")
		t.expect(rgb(View.GHOST_COLORS.pinky)).toBe("255,184,255")
		t.expect(rgb(View.GHOST_COLORS.clyde)).toBe("255,184,82")
		for _, name in { "blinky", "pinky", "inky", "clyde" } do
			t.expect(rgb(View.ghostColor(name, "frightened", false))).toBe("33,33,255")
			t.expect(rgb(View.ghostColor(name, "blinking", false))).toBe("33,33,255")
			t.expect(rgb(View.ghostColor(name, "blinking", true))).toBe("255,255,255")
			t.expect(rgb(View.ghostColor(name, "eyes", false))).toBe("255,255,255")
		end
	end)

	it("the walls are blue, green while edible, and white in the level-clear flash, which wins", function()
		t.expect(rgb(View.WALL_COLOR)).toBe("33,33,222")
		t.expect(rgb(View.WALL_EDIBLE_COLOR)).toBe("12,74,12")
		t.expect(rgb(View.wallColor(false, false))).toBe("33,33,222")
		t.expect(rgb(View.wallColor(false, true))).toBe("12,74,12")
		t.expect(rgb(View.wallColor(true, false))).toBe("255,255,255")
		t.expect(rgb(View.wallColor(true, true))).toBe("255,255,255")
	end)

	-- The user (2026-10-25, "Darker green"): every dangerous ghost must stand out on the green walls (an eaten ghost
	-- revives dangerous, in its own colour, while they are still green); frightened (blue) ghosts may be harder to
	-- see. The green maximises the weakest dangerous ghost's contrast while the walls keep 2 against the floor (E2).
	it(
		"every dangerous ghost stands out on the green walls, and the walls still stand out from the floor",
		function()
			local g = View.WALL_EDIBLE_COLOR
			t.expect(g.g > g.r and g.g > g.b).toBe(true)
			for _, name in DANGEROUS do
				t.expect(contrast(View.GHOST_COLORS[name], g) >= 2.5).toBe(true)
			end
			t.expect(contrast(g, FLOOR) >= 2).toBe(true)
			-- what the user accepted for the frightened blue on green (1.36), recorded so it can't quietly get worse
			t.expect(contrast(View.FRIGHTENED_COLOR, g) >= 1.3).toBe(true)
		end
	)

	it("the ghosts are edible exactly while the power timer runs", function()
		local function play(frightened: number, phase: string): any
			return { phase = phase, level = 1, score = 0, lives = 3, timer = 0, frightened = frightened }
		end
		t.expect(View.edible(play(1, "playing"))).toBe(true)
		t.expect(View.edible(play(180, "playing"))).toBe(true)
		t.expect(View.edible(play(0, "playing"))).toBe(false) -- no power, or a level with no frightened time
		t.expect(View.edible(play(0, "dying"))).toBe(false)
		t.expect(View.edible(play(0, "levelclear"))).toBe(false)
	end)
end)
