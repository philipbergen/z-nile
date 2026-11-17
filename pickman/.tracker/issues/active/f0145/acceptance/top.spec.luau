--!strict
-- f0145 AC7 (runs once d0124, which f0145 depends on, has landed): d0124's all-time top-10 list of runs shows the lives
-- each run spent too. Hiscores.topRun takes the attempt's lives into the run's entry, Hiscores.bestRun the row's into
-- a merged best, and Hiscores.topRows the entry's into the lobby's rows; a run without them (stored before f0145) has
-- none. The lobby's panel then shows them as for the other boards.
local Hiscores = require("@logic/Hiscores")
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local NOW = 1792108800

return t.spec("f0145 lives spent on the top-10 list", function(it)
	it(
		"a run's entry on the list carries its lives; the lobby's rows read from the list show them",
		function()
			local run = Hiscores.topRun(
				{ name = "Ada", userId = "7", level = 3, score = 800, lives = 6 },
				NOW,
				1,
				"s"
			)
			t.expect(run ~= nil).toBe(true)
			t.expect((run :: Hiscores.TopRun).lives).toBe(6)
			local plain = Hiscores.topRun({ name = "Bea", userId = "2", level = 1, score = 600 }, NOW, 1, "s")
			t.expect((plain :: Hiscores.TopRun).lives).toBe(nil)
			local list = (
				Hiscores.addRun((Hiscores.addRun({}, run :: Hiscores.TopRun)), plain :: Hiscores.TopRun)
			)
			local rows = Hiscores.topRows(list) :: { Hiscores.Row }
			t.expect(rows[1].lives).toBe(6)
			t.expect(rows[2].lives).toBe(nil)
			t.expect(Lobby.lines(Lobby.panel(Hiscores.lobbyRows(rows))))
				.toBe(`1 Ada 800 3 {Lobby.LIVES_MARK}6\n2 Bea 600 1`)
		end
	)

	it("a per-player best merged into the list keeps its row's lives; a broken value is none", function()
		local best = Hiscores.bestRun({
			rank = 1,
			name = "Ada",
			userId = "7",
			score = 800,
			level = 3,
			runScore = 800,
			lives = 4,
		})
		t.expect((best :: Hiscores.TopRun).lives).toBe(4)
		local broken =
			Hiscores.topRun({ name = "Ada", userId = "7", level = 3, score = 800, lives = 0 } :: any, NOW, 1)
		t.expect((broken :: Hiscores.TopRun).lives).toBe(nil)
	end)
end)
