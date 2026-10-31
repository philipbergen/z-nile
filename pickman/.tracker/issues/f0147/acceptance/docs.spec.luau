--!strict
-- f0147 AC4: game-design.md records levels by picked walls: the user's decisions (ten picks a level, the fresh maze,
-- the ramp and its top, level 1's rules, the multiplier and the extra life, the bonanza, the counter), the prep's
-- choices marked (prep), and the restated rules that changed (the Movement speeds, the Lives, the classic Levels
-- line, the pick's length).
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local design = fs.readFile(".tracker/game-design.md")

local function has(needle: string): boolean
	return string.find(design, needle, 1, true) ~= nil
end

-- the section, from its heading to the next one
local function section(): string
	local from = string.find(design, "\n## Levels by picked walls (user, 2026-10-25; f0147)\n", 1, true)
	assert(from, "the section's heading")
	local to = string.find(design, "\n## ", from + 1, true) or #design
	return string.sub(design, from, to)
end

return t.spec("f0147 game-design.md", function(it)
	it("has a Levels by picked walls section with each of the user's decisions", function()
		local s = section()
		for _, needle in
			{
				"**Ten picks a level.**",
				"an emptied maze stays empty",
				"A death keeps the level's count",
				"**A fresh maze each level:**",
				"level 1 is 70% of the classic level 1 for the player and every ghost",
				"each level is 5% faster than the one before",
				"up to level 34",
				"later levels keep level 34's speeds",
				"The eyes follow the ramp but never pass a tile a step",
				"**Level 1's rules on every level:**",
				"**Points × level:**",
				"10,000 × the level the run started on",
				"**The bonanza:**",
				"a long ghost pill (twice the power time)",
				"BONANZA!",
				"**The counter:** the HUD shows PICKS n/10",
				"**(prep)**, the user may veto any",
				"the counter sits in the row under the score",
				"Stop at level 34",
				"Carry into next level",
				"carrying the fraction from step to step",
				"Carry fractions",
			}
		do
			if string.find(s, needle, 1, true) == nil then
				error(`the section lacks: {needle}`)
			end
		end
	end)

	it("the rules it changes say so where they are stated", function()
		t.expect(has("**In the shipped game the levels follow the speed ramp instead** (f0147")).toBe(true)
		t.expect(
			has("With levels by picked walls (f0147) it comes at 10,000 × the level the run started on")
		)
			.toBe(true)
		t.expect(has("- **Levels** (the classic rules, kept for the default config the specs use")).toBe(true)
		t.expect(has("on f0147's ramp, 67 steps on level 1")).toBe(true)
		t.expect(has("on the shipped speed ramp, 2.625 tiles/s of real time, f0147")).toBe(true)
		t.expect(has("at the shipped ramp's level 1 speed of 21 units, 10 and 31, f0147")).toBe(true)
		t.expect(
			has("on the shipped ramp, twice the level's ramped player speed, never past a tile a step, f0147")
		)
			.toBe(true)
		t.expect(
			has("on the shipped ramp the house limits and the idle timer are level 1's on every level, f0147")
		)
			.toBe(true)
	end)
end)
