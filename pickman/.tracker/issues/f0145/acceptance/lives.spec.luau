--!strict
-- f0145 AC3: the hiscore shows how many lives a run spent. The game over carries the lives the run lost (every death,
-- continues included); Hiscores takes them into the run's submission, the stored row and the rows read back, as
-- `lives` (a whole number >= 1; anything else, or a row stored before lives were kept, is nil); and the lobby's panel
-- shows them after the level as " ♥n", nothing for a row without them.
local Hiscores = require("@logic/Hiscores")
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local NOW = 1792108800

return t.spec("f0145 lives spent on the boards", function(it)
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

	it("the lobby's panel shows the lives after the level, and nothing for a row without them", function()
		t.expect(Lobby.livesText(6)).toBe(` {Lobby.LIVES_MARK}6`)
		t.expect(Lobby.livesText(nil)).toBe("")
		t.expect(Lobby.livesText(0)).toBe("")
		local rows: { Lobby.Row } = {
			{ rank = 1, name = "Ada", score = 800, level = 3, lives = 6 },
			{ rank = 2, name = "Bea", score = 600, level = 1, lives = nil },
		}
		local p = Lobby.panel(rows)
		t.expect(Lobby.lines(p)).toBe(`1 Ada 800 3 {Lobby.LIVES_MARK}6\n2 Bea 600 1`)
	end)
end)
