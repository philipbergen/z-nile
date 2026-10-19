--!strict
-- f0026 AC5: one server submit shows on the all-time panel and the day board, and the rank line
-- names that run once. A second GameOver in the run does not submit again.
local Flow = require("@logic/Flow")
local Hiscores = require("@logic/Hiscores")
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local FRI = 1792108800

return t.spec("f0026 score reaches the lobby", function(it)
	it("the all-time panel and the day board show the qualified row", function()
		local store = Hiscores.fake()
		local wrote = Hiscores.submit(store, { name = "Ada", userId = "7", score = 50, level = 2 }, FRI)
		t.expect(wrote.all).toBe(true)
		t.expect(wrote.day).toBe(true)
		t.expect(wrote.week).toBe(true)
		local allRows = Hiscores.lobbyRows(Hiscores.top(store, "all", FRI))
		local all = (Lobby :: any).boardPanel(allRows, "all")
		t.expect(all.title).toBe("HISCORES")
		t.expect(#all.rows).toBe(1)
		t.expect(all.rows[1].name).toBe("Ada")
		t.expect(all.rows[1].score).toBe(50)
		t.expect(all.rows[1].level).toBe(2)
		local dayRows = Hiscores.lobbyRows(Hiscores.top(store, "day", FRI))
		local day = (Lobby :: any).boardPanel(dayRows, "day")
		t.expect(day.title).toBe("TODAY")
		t.expect(day.rows[1].score).toBe(50)
		t.expect(day.rows[1].name).toBe("Ada")
		local lower = Hiscores.submit(store, { name = "Nope", userId = "7", score = 10, level = 9 }, FRI)
		t.expect(lower.all).toBe(false)
		t.expect(store.get(Hiscores.board("all", FRI), "7").name).toBe("Ada")
		t.expect(store.get(Hiscores.board("all", FRI), "7").score).toBe(50)
	end)

	it("the same run submits once, and the rank line is that run's all-time place", function()
		local state, sub = Hiscores.onStep(
			Hiscores.newRun(),
			{ { kind = "GameOver", score = 50, level = 2, run = 99 } },
			true
		)
		t.expect(sub.run).toBe(1)
		t.expect(sub.score).toBe(50)
		local _, again = Hiscores.onStep(state, { { kind = "GameOver", score = 80, level = 3 } }, true)
		t.expect(again).toBe(nil)
		local store = Hiscores.fake()
		Hiscores.submit(store, { name = "Ada", userId = "7", score = sub.score, level = sub.level }, FRI)
		local rank = Hiscores.rankOf(Hiscores.top(store, "all", FRI), "7")
		t.expect(rank).toBe(1)
		local off = Hiscores.rankOf(Hiscores.top(store, "all", FRI), "8")
		t.expect(off).toBe(nil)
		local view = (Flow :: any).hearRank({ over = sub.run }, sub.run, rank)
		t.expect((Flow :: any).shownRank(view, true)).toBe("ALL-TIME #1")
		t.expect((Flow :: any).shownRank(view, false)).toBe(nil)
		t.expect(
			(Lobby :: any).lines(
				(Lobby :: any).boardPanel(Hiscores.lobbyRows(Hiscores.top(store, "all", FRI)), "all"),
				rank
			)
		).toBe("> 1 Ada 50 2")
	end)
end)
