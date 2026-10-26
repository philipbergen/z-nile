--!strict
-- f0109: Inky gets a colour of its own that stands out (the user: the near-white ghost "is just not very visible"),
-- and the maze walls are green while the ghosts are edible (the power timer runs), blue otherwise, lit white during
-- the level-clear flash, which wins. Visibility is measured: WCAG contrast against what Inky is seen against, and
-- CIE76 colour distance from every other colour a ghost, a pellet or a shot is drawn in.
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
local FLOOR: Rgb = { r = 0, g = 0, b = 0 } -- MazeView's floor
local PELLET: Rgb = { r = 255, g = 184, b = 174 } -- PelletView's pellets
local SHOT: Rgb = { r = 0, g = 255, b = 255 } -- the blaster's beam and shot bars (BlastView, HudView)

return t.spec("f0109 Inky's colour and green walls", function(it)
	it("Inky is yellow, 255,230,0, for its body and its glow (G1)", function()
		t.expect(rgb(View.GHOST_COLORS.inky)).toBe("255,230,0")
		t.expect(rgb(View.ghostColor("inky", "normal", false))).toBe("255,230,0")
		t.expect(rgb(View.ghostColor("inky", "normal", true))).toBe("255,230,0")
	end)

	it("Inky stands out against the walls, edible or not, and the floor", function()
		local inky = View.GHOST_COLORS.inky
		t.expect(contrast(inky, View.WALL_COLOR) >= 4.5).toBe(true)
		t.expect(contrast(inky, FLOOR) >= 4.5).toBe(true)
		-- an eaten ghost comes back dangerous, in its own colour, while the walls are still green
		t.expect(contrast(inky, View.WALL_EDIBLE_COLOR) >= 3).toBe(true)
	end)

	it(
		"Inky's colour is far from every other ghost's, the frightened and white looks, the pellets and the shots",
		function()
			local inky = View.GHOST_COLORS.inky
			for _, name in { "blinky", "pinky", "clyde" } do
				t.expect(distance(inky, View.GHOST_COLORS[name]) >= 30).toBe(true)
			end
			for _, other in { View.FRIGHTENED_COLOR, View.WHITE, PELLET, SHOT } do
				t.expect(distance(inky, other) >= 30).toBe(true)
			end
		end
	)

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
		t.expect(rgb(View.WALL_EDIBLE_COLOR)).toBe("0,152,0")
		t.expect(rgb(View.wallColor(false, false))).toBe("33,33,222")
		t.expect(rgb(View.wallColor(false, true))).toBe("0,152,0")
		t.expect(rgb(View.wallColor(true, false))).toBe("255,255,255")
		t.expect(rgb(View.wallColor(true, true))).toBe("255,255,255")
	end)

	it("the edible green is green, and a frightened ghost and the floor stand out against it", function()
		local g = View.WALL_EDIBLE_COLOR
		t.expect(g.g > g.r and g.g > g.b).toBe(true)
		t.expect(contrast(g, View.FRIGHTENED_COLOR) >= 2).toBe(true)
		t.expect(contrast(g, FLOOR) >= 4.5).toBe(true)
	end)

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
