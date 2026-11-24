--!strict
-- f0235 AC6: game-design.md records the beacons as a (prep) decision the user may veto, in one bullet after the spy
-- hop's glows (f0102): what they are for (power pellets hard to find from the floor; while jumping, f0234's wait
-- included), the numbers (3 studs wide, up to 20 studs, the pellets' colour, 30% see-through), when they show (the
-- drawn eye above the wall tops, never standing, none within 1.5 tiles of the eye), that an eaten pellet's beacon goes
-- and comes back with it, and that f0236's glow must be clearly distinct from them. architecture.md's View row names
-- the beacons (f0235).
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function bullet(): string
	local text = fs.readFile(".tracker/game-design.md")
	return string.match(text, "\n(%- %*%*Power pellet beacons%*%* %(f0235%)[^\n]*)") or ""
end

return t.spec("f0235 the game design records the beacons", function(it)
	it("has one Power pellet beacons bullet for f0235, a (prep) decision the user may veto", function()
		local row = bullet()
		t.expect(row ~= "").toBe(true)
		t.expect(string.find(row, "**(prep)**", 1, true) ~= nil).toBe(true)
		t.expect(string.find(row, "veto", 1, true) ~= nil).toBe(true)
		local text = fs.readFile(".tracker/game-design.md")
		local n = 0
		for _ in string.gmatch(text, "%*%*Power pellet beacons%*%* %(f0235%)") do
			n += 1
		end
		t.expect(n).toBe(1)
	end)

	it("comes after the glows (f0102)", function()
		local text = fs.readFile(".tracker/game-design.md")
		local glows = string.find(text, "- **Glows** (f0102)", 1, true)
		local beacons = string.find(text, "- **Power pellet beacons** (f0235)", 1, true)
		t.expect(glows ~= nil and beacons ~= nil and (beacons :: number) > (glows :: number)).toBe(true)
	end)

	it("says what they are for, their numbers, when they show, and how they follow the pellets", function()
		local row = bullet()
		for _, want in
			{
				"from the floor",
				"f0234",
				"3 studs wide",
				"20 studs",
				"colour",
				"30% see-through",
				"above the wall tops",
				"never standing",
				"1.5 tiles",
				"eaten",
				"pellets back",
				"f0236",
				"clearly distinct",
			}
		do
			t.expect(string.find(row, want, 1, true) ~= nil).toBe(true)
		end
	end)

	it("architecture.md's View row names the beacons", function()
		local text = fs.readFile(".tracker/architecture.md")
		local row = string.match(text, "\n(| View |[^\n]*)") or ""
		t.expect(row ~= "").toBe(true)
		t.expect(string.find(row, "beacon", 1, true) ~= nil).toBe(true)
		t.expect(string.find(row, "(f0235)", 1, true) ~= nil).toBe(true)
	end)
end)
