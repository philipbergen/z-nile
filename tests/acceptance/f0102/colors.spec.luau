--!strict
-- f0102 AC4: one table of ghost colours for every view of a ghost (its body and its glow). Each ghost has its own:
-- Blinky red, Pinky pink, Inky cyan, Clyde orange. Frightened is blue; blinking is blue, white on the white half of
-- its flash; eyes going home are white. (Inky's own colour is left to f0109; it must only differ from the others.) View.ghostColor gives a fresh table each time.
local View = require("@logic/View")
local t = require("@tests/lib/t")

local function rgb(c: View.Rgb): string
	return `{c.r},{c.g},{c.b}`
end

return t.spec("f0102 ghost colours", function(it)
	it("each ghost has its own colour while normal, flash or not", function()
		-- Inky's is left open: f0109 will choose a new one, and it needs only be its own (below)
		local want: { [string]: string } = { blinky = "255,0,0", pinky = "255,184,255", clyde = "255,184,82" }
		for name, colour in want do
			t.expect(rgb(View.ghostColor(name, "normal", false))).toBe(colour)
			t.expect(rgb(View.ghostColor(name, "normal", true))).toBe(colour)
			t.expect(rgb(View.GHOST_COLORS[name])).toBe(colour)
		end
		local n = 0
		local seen: { [string]: boolean } = {}
		for _, c in View.GHOST_COLORS do
			n += 1
			seen[rgb(c)] = true
		end
		t.expect(n).toBe(4)
		local inky = rgb(View.ghostColor("inky", "normal", false))
		t.expect(inky).toBe(rgb(View.GHOST_COLORS.inky))
		t.expect(inky ~= "33,33,255" and inky ~= "255,255,255").toBe(true)
		local count = 0
		for _ in seen do
			count += 1
		end
		t.expect(count).toBe(4) -- four different colours
	end)

	it("frightened is blue for everyone, and blinking flashes white", function()
		for _, name in { "blinky", "pinky", "inky", "clyde" } do
			t.expect(rgb(View.ghostColor(name, "frightened", false))).toBe("33,33,255")
			t.expect(rgb(View.ghostColor(name, "frightened", true))).toBe("33,33,255")
			t.expect(rgb(View.ghostColor(name, "blinking", false))).toBe("33,33,255")
			t.expect(rgb(View.ghostColor(name, "blinking", true))).toBe("255,255,255")
			t.expect(rgb(View.ghostColor(name, "eyes", false))).toBe("255,255,255")
		end
	end)

	it("a name without a colour is white, and every answer is a fresh table", function()
		t.expect(rgb(View.ghostColor("sue", "normal", false))).toBe("255,255,255")
		local a = View.ghostColor("blinky", "normal", false)
		local b = View.ghostColor("blinky", "normal", false)
		t.expect(a ~= b).toBe(true)
		t.expect(a ~= View.GHOST_COLORS.blinky).toBe(true)
		t.expect(table.isfrozen(a)).toBe(false)
		a.r = 0
		t.expect(View.ghostColor("blinky", "normal", false).r).toBe(255)
		t.expect(View.GHOST_COLORS.blinky.r).toBe(255)
		t.expect(function()
			(View.GHOST_COLORS :: any).blinky = { r = 1, g = 2, b = 3 }
		end).toThrow()
	end)
end)
