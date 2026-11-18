--!strict
-- f0186 AC2: a hiscore entry records how many paid revives its run used. Hiscores takes the game over's `revives` into
-- the run's submission, the stored row (the companion), the rows read back, the lobby's rows, the top-10 list's entries
-- (topRun, the list's own copy, bestRun, topRows) and a player's best. A count is kept only as a whole number from 1 to
-- 2^53 - 1 (`Hiscores.revives`); none (0), a row stored before f0186 and any junk value are nil, which every board
-- shows as no revives. Revives never rank a row, never order the list and never make a row replace another; a row
-- that does replace another carries its own run's revives.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

local NOW = 1792108800

return t.spec("f0186 revives in the hiscore entries", function(it)
	it("Hiscores.revives keeps a whole count from 1 to 2^53 - 1 and nothing else", function()
		t.expect(Hiscores.revives(1)).toBe(1)
		t.expect(Hiscores.revives(4)).toBe(4)
		t.expect(Hiscores.revives(2 ^ 53 - 1)).toBe(2 ^ 53 - 1)
		for _, bad in { 0, -1, 2.5, 0 / 0, math.huge, -math.huge, 2 ^ 53, "3", true, {} } :: { any } do
			t.expect(Hiscores.revives(bad)).toBe(nil)
		end
		t.expect(Hiscores.revives(nil)).toBe(nil)
	end)

	it("a game over's revives go into the run's submission; none is nil", function()
		local function sub(event: { [string]: any }): Hiscores.Submission
			local _, s = Hiscores.onStep(Hiscores.newRun(), { event :: any }, true)
			assert(s, "no submission")
			return s
		end
		t.expect(sub({ kind = "GameOver", score = 900, level = 2, revives = 2 }).revives).toBe(2)
		t.expect(sub({ kind = "GameOver", score = 900, level = 2, revives = 0 }).revives).toBe(nil)
		t.expect(sub({ kind = "GameOver", score = 900, level = 2 }).revives).toBe(nil)
		t.expect(sub({ kind = "GameOver", score = 900, level = 2, revives = "2" }).revives).toBe(nil)
		-- the rest of the submission is as it was
		t.expect(sub({ kind = "GameOver", score = 900, level = 2 }))
			.toEqual({ score = 900, level = 2, run = 1 })
	end)

	it("a stored row keeps the attempt's revives, and the rows read back carry them", function()
		local store = Hiscores.fake()
		Hiscores.submit(store, { name = "Ada", userId = "7", level = 3, score = 800, revives = 2 }, NOW)
		Hiscores.submit(store, { name = "Bea", userId = "2", level = 1, score = 600 }, NOW)
		local function board(id: Hiscores.BoardId)
			local rows = Hiscores.top(store, id, NOW)
			t.expect(#rows).toBe(2)
			t.expect(rows[1].name).toBe("Ada")
			t.expect(rows[1].revives).toBe(2)
			t.expect(rows[2].revives).toBe(nil) -- none
			local sent = Hiscores.lobbyRows(rows)
			t.expect(sent[1].revives).toBe(2)
			t.expect(sent[2].revives).toBe(nil)
		end
		board("all")
		board("day")
		board("week")
	end)

	it("a row that replaces another carries its own run's revives, not the stored row's", function()
		local stored: Hiscores.Companion = { name = "Ada", userId = "7", level = 2, score = 500, revives = 3 }
		local plain = Hiscores.commit(stored, { name = "Ada", userId = "7", level = 3, score = 800 })
		t.expect(plain ~= nil).toBe(true)
		t.expect((plain :: Hiscores.Companion).revives).toBe(nil)
		local bought = Hiscores.commit(
			{ name = "Ada", userId = "7", level = 2, score = 500 },
			{ name = "Ada", userId = "7", level = 3, score = 800, revives = 1 }
		)
		t.expect((bought :: Hiscores.Companion).revives).toBe(1)
		-- a row of a run without revives is the row it was
		t.expect(Hiscores.commit(nil, { name = "Ada", userId = "7", level = 3, score = 800 }))
			.toEqual({ name = "Ada", userId = "7", level = 3, score = 800 })
	end)

	it("revives never make a row replace another, and never rank the boards", function()
		local stored: Hiscores.Companion = { name = "Ada", userId = "7", level = 3, score = 800, revives = 4 }
		t.expect(Hiscores.commit(stored, { name = "Ada", userId = "7", level = 3, score = 800 })).toBe(nil)
		t.expect(Hiscores.commit(stored, { name = "Ada", userId = "7", level = 3, score = 800, revives = 9 }))
			.toBe(nil)
		local store = Hiscores.fake()
		Hiscores.submit(store, { name = "Bea", userId = "2", level = 3, score = 800, revives = 5 }, NOW)
		Hiscores.submit(store, { name = "Cy", userId = "3", level = 3, score = 800 }, NOW)
		Hiscores.submit(store, { name = "Al", userId = "1", level = 3, score = 800, revives = 1 }, NOW)
		local rows = Hiscores.top(store, "all", NOW)
		t.expect({ rows[1].name, rows[2].name, rows[3].name }).toEqual({ "Al", "Bea", "Cy" }) -- the user id breaks the tie
		Hiscores.submit(store, { name = "Bea", userId = "2", level = 3, score = 800 }, NOW)
		t.expect(Hiscores.top(store, "all", NOW)[2].revives).toBe(5) -- not replaced
	end)

	it("a broken stored or sent count reads as none, and never stops a row being stored or read", function()
		local made = Hiscores.commit(
			nil,
			{ name = "Ada", userId = "7", level = 3, score = 800, revives = 0 / 0 } :: any
		)
		t.expect(made ~= nil).toBe(true)
		t.expect((made :: Hiscores.Companion).revives).toBe(nil)
		for _, junk in { "2", 0, -1, 1.5, true } :: { any } do
			local rows = Hiscores.rows(
				{ { { key = "7", score = 800 } } },
				function(): (Hiscores.Companion?, string?)
					return { name = "Ada", userId = "7", level = 3, score = 800, revives = junk } :: any, nil
				end,
				Hiscores.N
			)
			t.expect(#(rows :: { Hiscores.Row })).toBe(1)
			t.expect((rows :: { Hiscores.Row })[1].revives).toBe(nil)
		end
		local rows = Hiscores.rows(
			{ { { key = "7", score = 800 } } },
			function(): (Hiscores.Companion?, string?)
				return { name = "Ada", userId = "7", level = 3, score = 800, revives = 2 }, nil
			end,
			Hiscores.N
		)
		t.expect((rows :: { Hiscores.Row })[1].revives).toBe(2)
	end)

	it("the top-10 list carries each run's revives through every path, and they never order it", function()
		local run =
			Hiscores.topRun({ name = "Ada", userId = "7", level = 3, score = 800, revives = 2 }, NOW, 1, "s")
		t.expect((run :: Hiscores.TopRun).revives).toBe(2)
		local plain = Hiscores.topRun({ name = "Bea", userId = "2", level = 3, score = 800 }, NOW + 5, 1, "s")
		t.expect((plain :: Hiscores.TopRun).revives).toBe(nil)
		for _, junk in { "2", 0, -1, 1.5 } :: { any } do
			local made = Hiscores.topRun(
				{ name = "Ada", userId = "7", level = 3, score = 800, revives = junk } :: any,
				NOW,
				1,
				"s"
			)
			t.expect((made :: Hiscores.TopRun).revives).toBe(nil)
		end
		-- the list's own copy keeps them; the earlier run keeps the tied place, whatever its revives
		local list = Hiscores.addRun((Hiscores.addRun({}, plain :: Hiscores.TopRun)), run :: Hiscores.TopRun)
		t.expect(list[1].revives).toBe(2)
		t.expect(list[1].name).toBe("Ada")
		t.expect(list[2].revives).toBe(nil)
		local rows = Hiscores.topRows(list) :: { Hiscores.Row }
		t.expect(rows[1].revives).toBe(2)
		t.expect(rows[2].revives).toBe(nil)
		t.expect(Hiscores.lobbyRows(rows)[1].revives).toBe(2)
		-- a stored entry with junk, or with none (stored before f0186), reads as none
		local junk: { any } = {
			{ id = "a", name = "Ada", userId = "7", score = 800, level = 3, at = 1, revives = "2" } :: any,
			{ id = "b", name = "Bea", userId = "2", score = 700, level = 3, at = 1 } :: any,
		}
		local stored = Hiscores.topRows(junk) :: { Hiscores.Row }
		t.expect(stored[1].revives).toBe(nil)
		t.expect(stored[2].revives).toBe(nil)
		-- a per-player best merged into the list brings its row's revives, whether or not it names its run
		local named = Hiscores.bestRun({
			rank = 1,
			name = "Ada",
			userId = "7",
			score = 800,
			level = 3,
			runScore = 800,
			run = "7:1:1:s",
			at = 1,
			revives = 3,
		})
		t.expect((named :: Hiscores.TopRun).revives).toBe(3)
		local unnamed = Hiscores.bestRun({
			rank = 1,
			name = "Ada",
			userId = "7",
			score = 800,
			level = 3,
			runScore = 800,
			revives = 4,
		})
		t.expect((unnamed :: Hiscores.TopRun).revives).toBe(4)
		-- a junk count on the row reads as none on both branches
		local junkNamed = Hiscores.bestRun({
			rank = 1,
			name = "Ada",
			userId = "7",
			score = 800,
			level = 3,
			runScore = 800,
			run = "7:1:1:s",
			at = 1,
			revives = 1.5,
		})
		t.expect((junkNamed :: Hiscores.TopRun).revives).toBe(nil)
		local junkUnnamed = Hiscores.bestRun({
			rank = 1,
			name = "Ada",
			userId = "7",
			score = 800,
			level = 3,
			runScore = 800,
			revives = 1.5,
		})
		t.expect((junkUnnamed :: Hiscores.TopRun).revives).toBe(nil)
		local merged = Hiscores.mergeRun({}, plain :: Hiscores.TopRun, {
			{ rank = 1, name = "Cy", userId = "3", score = 900, level = 3, runScore = 900, revives = 1 },
		})
		t.expect(merged[1].name).toBe("Cy")
		t.expect(merged[1].revives).toBe(1)
	end)

	it("a player's best carries its row's revives; a best without them is as it was", function()
		t.expect(Hiscores.best({ name = "Ada", userId = "7", score = 50, level = 2, revives = 2 }))
			.toEqual({ score = 50, level = 2, revives = 2 })
		t.expect(Hiscores.best({ name = "Ada", userId = "7", score = 50, level = 2 }))
			.toEqual({ score = 50, level = 2 })
		t.expect(Hiscores.best({ name = "Ada", userId = "7", score = 50, level = 2, revives = -1 }))
			.toEqual({ score = 50, level = 2 })
	end)
end)
