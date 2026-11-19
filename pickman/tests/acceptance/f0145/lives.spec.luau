--!strict
-- f0145 AC3: the hiscore shows how many lives a run spent. The game over carries the lives the run lost (every death,
-- continues included); Hiscores takes them into the run's submission, the stored row and the rows read back, as
-- `lives` (a whole number >= 1; anything else, or a row stored before lives were kept, is nil). Narrowed by c0380:
-- f0186 replaces the lives on the boards with the revives a run used, so the lobby's panel is pinned only for what
-- both show, each row's rank, name, score and level first and no lives mark on a row without lives.
local Hiscores = require("@logic/Hiscores")
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local NOW = 1792108800

-- c0380: what follows the level changes (f0145's lives, then f0186's revives), so a board's lines are pinned up to
-- the level: each line of `text` that is the line `want` has there, or starts with it and a space, is cut back to it;
-- every other line, and the number of lines, stay as they are, so a compare with `want` still shows them.
local function upToLevel(text: any, want: string): any
	if type(text) ~= "string" then
		return text
	end
	local got, keep = string.split(text, "\n"), string.split(want, "\n")
	for i, line in got do
		local w = keep[i]
		if w ~= nil and (line == w or string.sub(line, 1, #w + 1) == w .. " ") then
			got[i] = w
		end
	end
	return table.concat(got, "\n")
end

return t.spec("f0145 lives spent on the hiscore rows", function(it)
	it("Hiscores.lives keeps a whole count of at least one and nothing else", function()
		t.expect(Hiscores.lives(3)).toBe(3)
		t.expect(Hiscores.lives(7)).toBe(7)
		for _, bad in { 0, -1, 2.5, 0 / 0, math.huge, "3", true } :: { any } do
			t.expect(Hiscores.lives(bad)).toBe(nil)
		end
		t.expect(Hiscores.lives(nil)).toBe(nil)
	end)

	it("a game over's lives go into the run's submission", function()
		local _, sub = Hiscores.onStep(
			Hiscores.newRun(),
			{ { kind = "GameOver", score = 900, level = 2, lives = 6 } },
			true
		)
		t.expect(sub ~= nil).toBe(true)
		t.expect((sub :: Hiscores.Submission).lives).toBe(6)
		local _, old =
			Hiscores.onStep(Hiscores.newRun(), { { kind = "GameOver", score = 900, level = 2 } }, true)
		t.expect((old :: Hiscores.Submission).lives).toBe(nil)
	end)

	it("a stored row keeps the attempt's lives, and the rows read back carry them", function()
		local store = Hiscores.fake()
		Hiscores.submit(store, { name = "Ada", userId = "7", level = 3, score = 800, lives = 6 }, NOW)
		Hiscores.submit(store, { name = "Bea", userId = "2", level = 1, score = 600 }, NOW)
		local rows = Hiscores.top(store, "all", NOW)
		t.expect(#rows).toBe(2)
		t.expect(rows[1].name).toBe("Ada")
		t.expect(rows[1].lives).toBe(6)
		t.expect(rows[2].lives).toBe(nil) -- a run without lives (an older build) shows none
		t.expect(Hiscores.lobbyRows(rows)[1].lives).toBe(6)
	end)

	it("a broken lives value is stored and read as nothing, never as a count", function()
		local made =
			Hiscores.commit(nil, { name = "Ada", userId = "7", level = 3, score = 800, lives = 0 / 0 } :: any)
		t.expect(made ~= nil).toBe(true)
		t.expect((made :: Hiscores.Companion).lives).toBe(nil)
		local rows = Hiscores.rows(
			{ { { key = "7", score = 800 } } },
			function(): (Hiscores.Companion?, string?)
				return { name = "Ada", userId = "7", level = 3, score = 800, lives = "6" } :: any, nil
			end,
			Hiscores.N
		)
		t.expect((rows :: { Hiscores.Row })[1].lives).toBe(nil)
	end)

	it(
		"the lobby's panel keeps each row's rank, name, score and level first, and no lives mark for a row without lives",
		function()
			local rows: { Lobby.Row } = {
				{ rank = 1, name = "Ada", score = 800, level = 3, lives = 6 },
				{ rank = 2, name = "Bea", score = 600, level = 1, lives = nil },
			}
			local p = Lobby.panel(rows)
			local text = Lobby.lines(p)
			t.expect(upToLevel(text, "1 Ada 800 3\n2 Bea 600 1")).toBe("1 Ada 800 3\n2 Bea 600 1")
			t.expect(string.find(string.split(text, "\n")[2], "♥", 1, true) == nil).toBe(true)
		end
	)
end)
