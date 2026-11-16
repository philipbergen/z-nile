--!strict
-- f0186 AC4: every board shows how many paid revives each run used, in place of f0145's lives spent. A row of the
-- lobby's panel ends with "REVIVES n" after the level, and a run with none (a row stored before f0186 included) shows
-- "REVIVES 0"; the lives a row carries (f0145's "♥n") are not shown. The viewer's own best line under the all-time
-- board shows its revives the same way. What the server sends is read defensively: a count that is not a whole
-- number of at least one shows as none.
local Hiscores = require("@logic/Hiscores")
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local NOW = 1792108800

return t.spec("f0186 the boards show revives", function(it)
	it("a revive count reads REVIVES n, and none (or junk) reads REVIVES 0", function()
		t.expect(Lobby.REVIVES).toBe("REVIVES")
		t.expect(Lobby.revivesText(1)).toBe("REVIVES 1")
		t.expect(Lobby.revivesText(12)).toBe("REVIVES 12")
		for _, none in { nil, 0, -1, 1.5, 0 / 0, math.huge, "2", true } :: { any } do
			t.expect(Lobby.revivesText(none)).toBe("REVIVES 0")
		end
	end)

	it(
		"every row ends with its revives after the level; a row without them shows none; lives are not shown",
		function()
			local rows: { Lobby.Row } = {
				{ rank = 2, name = "Bea", score = 600, level = 1, revives = nil, lives = 3 } :: any,
				{ rank = 1, name = "Ada", score = 800, level = 3, revives = 2, lives = 9 } :: any,
			}
			local p = Lobby.panel(rows)
			t.expect(p.rows[1].revives).toBe(2)
			t.expect(p.rows[2].revives).toBe(nil)
			t.expect(Lobby.lines(p)).toBe("1 Ada 800 3 REVIVES 2\n2 Bea 600 1 REVIVES 0")
			t.expect(Lobby.lines(p, 2)).toBe("1 Ada 800 3 REVIVES 2\n> 2 Bea 600 1 REVIVES 0")
			for _, id in { "all", "day", "week" } do
				t.expect(Lobby.lines(Lobby.boardPanel(rows, id)))
					.toBe("1 Ada 800 3 REVIVES 2\n2 Bea 600 1 REVIVES 0")
			end
			t.expect(Lobby.lines(Lobby.panel({}))).toBe(Lobby.EMPTY) -- an empty board keeps its message
		end
	)

	it("the viewer's best line shows the best's revives, on the all-time board only", function()
		t.expect(Lobby.bestLine({ score = 50, level = 2, revives = 1 }, "all"))
			.toBe("YOUR BEST 50 2 REVIVES 1")
		t.expect(Lobby.bestLine({ score = 50, level = 2 }, "all")).toBe("YOUR BEST 50 2 REVIVES 0")
		t.expect(Lobby.bestLine({ score = 50, level = 2, revives = "1" }, "all"))
			.toBe("YOUR BEST 50 2 REVIVES 0")
		t.expect(Lobby.bestLine({ score = 50, level = 2, revives = 1 }, "day")).toBe(nil)
		local p = Lobby.panel({ { rank = 1, name = "Ada", score = 50, level = 2, revives = 1 } })
		t.expect(Lobby.text(p, 1, { score = 50, level = 2, revives = 1 }, "all"))
			.toBe("> 1 Ada 50 2 REVIVES 1\nYOUR BEST 50 2 REVIVES 1")
	end)

	it("what a board read gives the lobby shows the stored revives, the top-10 list's included", function()
		local store = Hiscores.fake()
		Hiscores.submit(store, { name = "Ada", userId = "7", level = 3, score = 800, revives = 2 }, NOW)
		Hiscores.submit(store, { name = "Bea", userId = "2", level = 1, score = 600 }, NOW)
		local sent = Hiscores.lobbyRows(Hiscores.top(store, "day", NOW))
		t.expect(Lobby.lines(Lobby.boardPanel(sent, "day")))
			.toBe("1 Ada 800 3 REVIVES 2\n2 Bea 600 1 REVIVES 0")
		local run =
			Hiscores.topRun({ name = "Cy", userId = "3", level = 4, score = 900, revives = 1 }, NOW, 1, "s")
		local list = Hiscores.addRun({}, run :: Hiscores.TopRun)
		local listed = Hiscores.lobbyRows(Hiscores.topRows(list) :: { Hiscores.Row })
		t.expect(Lobby.lines(Lobby.boardPanel(listed, "all"))).toBe("1 Cy 900 4 REVIVES 1")
		local best = Hiscores.best({ name = "Ada", userId = "7", score = 800, level = 3, revives = 2 })
		t.expect(Lobby.bestLine(best, "all")).toBe("YOUR BEST 800 3 REVIVES 2")
	end)
end)
