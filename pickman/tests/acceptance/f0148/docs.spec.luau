--!strict
-- f0148 AC5: game-design.md records the start level: the user's decisions (the best is the highest level reached, the
-- picker starts on it, the hiscore rows unchanged), the prep's choices marked (prep), and the rows it changes.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local design = fs.readFile(".tracker/game-design.md")

local function has(needle: string): boolean
	return string.find(design, needle, 1, true) ~= nil
end

local function section(): string
	local from =
		string.find(design, "\n## Start on any level up to your best (user, 2026-10-25; f0148)\n", 1, true)
	assert(from, "the section's heading")
	local to = string.find(design, "\n## ", from + 1, true) or #design
	return string.sub(design, from, to)
end

return t.spec("f0148 game-design.md", function(it)
	it("has a Start on any level section with each of the user's decisions and the prep's choices", function()
		local s = section()
		for _, needle in
			{
				"Once you clear a level you can choose to start on any level from 1-your best level.",
				"Highest reached",
				"Your best",
				"No, keep rows as they are",
				"**Your best** is the highest level a player has reached by clearing the one before it",
				"START has ◀ and ▶ either side of it and says START LEVEL n",
				"it starts on the best",
				"the extra life at 10,000 × that level",
				"a new run after game over starts on the same level again",
				"Through the store",
				"Lobby now, portal later",
				"**The choice travels through the store:**",
				"START GAME, with no picker, starts level 1",
				"**Only the server decides:**",
				"**(prep)**, the user may veto any",
				"the Left and Right arrow keys",
				"does not answer within 10 s starts the run on level 1",
				"the next arrival starts on the late choice",
			}
		do
			if string.find(s, needle, 1, true) == nil then
				error(`the section lacks: {needle}`)
			end
		end
	end)

	it("the rows it changes say so", function()
		t.expect(has("each player's best level reached, which the lobby's level picker offers (f0148"))
			.toBe(true)
		t.expect(has("on the level the picker shows, once the player has reached level 2: f0148")).toBe(true)
		t.expect(select(2, string.gsub(design, "%(picked in the lobby, f0148%)", ""))).toBe(2) -- Lives and Points × level
		t.expect(has("(1 until f0148)")).toBe(false)
	end)
end)
