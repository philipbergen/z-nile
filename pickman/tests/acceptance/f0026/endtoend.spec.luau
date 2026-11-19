--!strict
-- f0026 AC5: one server submit shows on the all-time panel and the day board, and the rank line
-- names that run once. A second GameOver in the run does not submit again.
local Flow = require("@logic/Flow")
local Hiscores = require("@logic/Hiscores")
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local FRI = 1792108800

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
		t.expect((store.get(Hiscores.board("all", FRI), "7") :: any).name).toBe("Ada")
		t.expect((store.get(Hiscores.board("all", FRI), "7") :: any).score).toBe(50)
	end)

	it("the same run submits once, and the rank line is that run's all-time place", function()
		local state, sub: any = Hiscores.onStep(
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
		local view = (Flow :: any).hearRank({ over = sub.run }, sub.run, rank, true)
		t.expect((Flow :: any).shownRank(view, true)).toBe("ALL-TIME #1")
		t.expect((Flow :: any).shownRank(view, false)).toBe(nil)
		-- the lobby's retry gap is its own copy of the server's (LobbyView does not require Hiscores)
		t.expect((Lobby :: any).READ_GAP).toBe(Hiscores.READ_GAP)
		t.expect(
			upToLevel(
				(Lobby :: any).lines(
					(Lobby :: any).boardPanel(Hiscores.lobbyRows(Hiscores.top(store, "all", FRI)), "all"),
					rank
				),
				"> 1 Ada 50 2"
			)
		).toBe("> 1 Ada 50 2")
	end)
end)
