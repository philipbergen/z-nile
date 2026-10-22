--!strict
-- d0124 AC1: the all-time top-N list of runs. One key holds the N best runs of every player, so one player can
-- hold several places; the per-player boards keep each player's best beside it. These are the pure rules: the
-- run's entry and id, the order, the cap, one entry per id, the place, the merge of the per-player bests and
-- the lobby's rows. The new functions are reached through `:: any` so this spec type-checks before they exist.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

local H = Hiscores :: any
local FRI = 1792108800

local function run(userId: string, score: number, level: number, at: number, id: string?): any
	return {
		id = id or `{userId}:{at}:1:job`,
		name = `P{userId}`,
		userId = userId,
		score = score,
		level = level,
		at = at,
	}
end

local function ids(list: { any }): { string }
	local out: { string } = {}
	for _, e in list do
		table.insert(out, e.id)
	end
	return out
end

return t.spec("d0124 top-N list of runs", function(it)
	it("the list lives in its own store, scope and key", function()
		t.expect(H.TOP_STORE).toBe("HiscoreTop")
		t.expect(H.TOP_SCOPE).toBe("all")
		t.expect(H.TOP_KEY).toBe("runs")
		t.expect(Hiscores.N).toBe(10)
	end)

	it("a run's id is user, instant, run counter and server, and no server is an empty part", function()
		t.expect(H.runId("7", FRI, 3, "job-1")).toBe(`7:{FRI}:3:job-1`)
		t.expect(H.runId("7", FRI, 3, nil)).toBe(`7:{FRI}:3:`)
		t.expect(H.runId("7", FRI, 3, 42)).toBe(`7:{FRI}:3:`)
	end)

	it("a run's entry carries the cleaned name, the score, the level and the instant", function()
		local e = H.topRun({ name = "  Ada\n", userId = "7", score = 50, level = 2 }, FRI, 1, "job-1")
		t.expect(e)
			.toEqual({ id = `7:{FRI}:1:job-1`, name = "Ada", userId = "7", score = 50, level = 2, at = FRI })
	end)

	it("an attempt valid refuses, or a broken instant or run, has no entry", function()
		t.expect(H.topRun({ name = "A", userId = "x", score = 50, level = 2 }, FRI, 1, "j")).toBe(nil)
		t.expect(H.topRun({ name = "A", userId = "7", score = -1, level = 2 }, FRI, 1, "j")).toBe(nil)
		t.expect(H.topRun({ name = "A", userId = "7", score = 50, level = 0 }, FRI, 1, "j")).toBe(nil)
		t.expect(H.topRun({ name = "A", userId = "7", score = 50, level = 2 }, FRI + 0.5, 1, "j")).toBe(nil)
		t.expect(H.topRun({ name = "A", userId = "7", score = 50, level = 2 }, FRI, 1.5, "j")).toBe(nil)
	end)

	it("one player's two runs both stand, the higher first: places 1 and 2", function()
		local first = run("7", 80, 3, FRI, "a")
		local second = run("7", 50, 2, FRI + 60, "b")
		local list, place = H.addRun({}, first)
		t.expect(place).toBe(1)
		local after, second_place = H.addRun(list, second)
		t.expect(second_place).toBe(2)
		t.expect(ids(after)).toEqual({ "a", "b" })
		t.expect(after[1].userId).toBe("7")
		t.expect(after[2].userId).toBe("7")
	end)

	it("order is score, then level, then the earlier run, then the id", function()
		local list = {
			run("1", 50, 2, FRI + 9, "late"),
			run("2", 50, 2, FRI + 1, "early-z"),
			run("3", 50, 2, FRI + 1, "early-a"),
			run("4", 50, 3, FRI + 99, "higher-level"),
			run("5", 60, 1, FRI + 99, "higher-score"),
		}
		local out = H.addRun(list, run("6", 1, 1, FRI, "low"))
		t.expect(ids(out)).toEqual({ "higher-score", "higher-level", "early-a", "early-z", "late", "low" })
	end)

	it("the list is cut to N, and a run below the tenth has no place and changes nothing", function()
		local list: { any } = {}
		for i = 1, 10 do
			table.insert(list, run(tostring(i), 100 + i, 1, FRI, `r{i}`))
		end
		local out, place = H.addRun(list, run("99", 5, 1, FRI, "low"))
		t.expect(place).toBe(nil)
		t.expect(#out).toBe(10)
		t.expect(table.find(ids(out), "low")).toBe(nil)
		local better, at = H.addRun(list, run("98", 105, 1, FRI - 1, "mid"))
		t.expect(at).toBe(6)
		t.expect(#better).toBe(10)
		t.expect(table.find(ids(better), "r1")).toBe(nil)
	end)

	it("a run whose id is already listed is not added again: its place is where it stands", function()
		local list = { run("1", 90, 1, FRI, "x"), run("7", 50, 2, FRI, "mine") }
		local out, place = H.addRun(list, run("7", 50, 2, FRI, "mine"))
		t.expect(place).toBe(2)
		t.expect(#out).toBe(2)
		-- the stored entry stands, even when the one offered again under its id differs
		local kept, at = H.addRun(list, run("7", 95, 2, FRI, "mine"))
		t.expect(at).toBe(2)
		t.expect(#kept).toBe(2)
		t.expect(kept[2].score).toBe(50)
	end)

	it("addRun never changes the list it is given", function()
		local list = { run("1", 10, 1, FRI, "x") }
		H.addRun(list, run("2", 90, 1, FRI, "y"))
		t.expect(#list).toBe(1)
		t.expect(list[1].id).toBe("x")
	end)

	it("broken or repeated stored entries are dropped, not ranked", function()
		local list: { any } = {
			run("1", 40, 1, FRI, "ok"),
			run("1", 40, 1, FRI, "ok"),
			{ id = "no-score", name = "N", userId = "2", level = 1, at = FRI },
			{ id = "", name = "N", userId = "3", score = 9, level = 1, at = FRI },
			{ id = "bad-user", name = "N", userId = "x", score = 9, level = 1, at = FRI },
			{ id = "half-at", name = "N", userId = "4", score = 9, level = 1, at = 0.5 },
			"not a table",
		}
		local out, place = H.addRun(list, run("5", 30, 1, FRI, "new"))
		t.expect(ids(out)).toEqual({ "ok", "new" })
		t.expect(place).toBe(2)
	end)

	-- a per-player row as Hiscores.rows makes it: the page score, and the companion's own score as runScore
	local function best(
		userId: string,
		score: number,
		level: number,
		named: string?,
		at: number?,
		page: number?
	): any
		return {
			rank = 0,
			name = `P{userId}`,
			userId = userId,
			score = page or score,
			level = level,
			runScore = score,
			run = named,
			at = at,
		}
	end

	it("a best that names no run is an older run with the id best:<userId>:<score>:<level>", function()
		t.expect(H.bestRun(best("2", 80, 3)))
			.toEqual({ id = "best:2:80:3", name = "P2", userId = "2", score = 80, level = 3, at = 0 })
	end)

	it("a best whose row names its run is that run: its id, its instant and its own score", function()
		t.expect(H.bestRun(best("7", 500, 3, `7:{FRI}:1:job`, FRI))).toEqual({
			id = `7:{FRI}:1:job`,
			name = "P7",
			userId = "7",
			score = 500,
			level = 3,
			at = FRI,
		})
		t.expect(H.bestRun(best("7", 500, 3, "", FRI)).id).toBe("best:7:500:3")
		t.expect(H.bestRun(best("7", 500, 3, "r", 0.5)))
			.toEqual({ id = "best:7:500:3", name = "P7", userId = "7", score = 500, level = 3, at = 0 })
	end)

	it("a best is its companion row whole: its score, never the page's", function()
		-- the ordered score lags the companion (another write is half done): the companion's run and score
		t.expect(H.bestRun(best("7", 600, 3, "new", FRI, 500)).score).toBe(600)
		-- the companion is older than the ordered score (a cached read): that older run at its own score
		local older = H.bestRun(best("7", 500, 2, "old", FRI - 60, 600))
		t.expect(older.id).toBe("old")
		t.expect(older.score).toBe(500)
		t.expect(H.bestRun(best("7", 500, 2, nil, nil, 600)).id).toBe("best:7:500:2")
		local noScore = best("7", 500, 2)
		noScore.runScore = nil
		t.expect(H.bestRun(noScore)).toBe(nil)
		noScore.runScore = -1
		t.expect(H.bestRun(noScore)).toBe(nil)
	end)

	it("merging adds every best, and the run takes its place among them", function()
		local bests = { best("2", 80, 3), best("1", 50, 2) }
		local out, place = H.mergeRun({}, run("9", 60, 1, FRI, "new"), bests)
		t.expect(ids(out)).toEqual({ "best:2:80:3", "new", "best:1:50:2" })
		t.expect(place).toBe(2)
		-- a new run that ties an old best stands below it: the old one is the earlier run
		local _, tie = H.mergeRun({}, run("9", 50, 2, FRI, "tie"), bests)
		t.expect(tie).toBe(3)
		-- a row without a companion score is skipped
		local noScore = best("4", 999, 1)
		noScore.runScore = nil
		t.expect(ids((H.mergeRun({}, run("9", 60, 1, FRI, "new"), { noScore })))).toEqual({ "new" })
	end)

	it("the run's own best names the run, so it is listed once", function()
		local out, place = H.mergeRun({}, run("7", 95, 2, FRI, "mine"), { best("7", 95, 2, "mine", FRI) })
		t.expect(ids(out)).toEqual({ "mine" })
		t.expect(place).toBe(1)
	end)

	it("an older unlisted best that a later run ties is listed ahead of it", function()
		local older = best("7", 95, 2, "older", FRI - 60)
		local out, place = H.mergeRun({}, run("7", 95, 2, FRI, "later"), { older })
		t.expect(ids(out)).toEqual({ "older", "later" })
		t.expect(place).toBe(2)
	end)

	it("a better listed run of the player does not hide an older best", function()
		local listed = { run("7", 99, 1, FRI - 9, "better") }
		local out = H.mergeRun(listed, run("3", 10, 1, FRI, "other"), { best("7", 95, 2, "older", FRI - 60) })
		t.expect(ids(out)).toEqual({ "better", "older", "other" })
	end)

	it(
		"a raised best joins beside the player's older best entry, and a merged best is listed once",
		function()
			local list = { H.bestRun(best("7", 900, 4)) }
			local raised = { best("7", 950, 4) }
			local out = H.mergeRun(list, run("3", 10, 1, FRI, "other"), raised)
			t.expect(ids(out)).toEqual({ "best:7:950:4", "best:7:900:4", "other" })
			local again = H.mergeRun(out, run("4", 5, 1, FRI, "more"), raised)
			t.expect(ids(again)).toEqual({ "best:7:950:4", "best:7:900:4", "other", "more" })
		end
	)

	it("addRun is mergeRun with no bests", function()
		local list = { run("1", 40, 1, FRI, "a") }
		local a, pa = H.addRun(list, run("2", 50, 1, FRI, "b"))
		local m, pm = H.mergeRun(list, run("2", 50, 1, FRI, "b"), {})
		t.expect(ids(a)).toEqual(ids(m))
		t.expect(pa).toBe(pm)
	end)

	it("the per-player row a run writes names that run, and the board's rows carry it", function()
		local made = Hiscores.commit(
			nil,
			{ name = "Ada", userId = "7", score = 50, level = 2, run = "7:1:1:j", at = 1 } :: any
		) :: any
		t.expect(made).toEqual({ name = "Ada", userId = "7", score = 50, level = 2, run = "7:1:1:j", at = 1 })
		local plain = Hiscores.commit(nil, { name = "Ada", userId = "7", score = 50, level = 2 }) :: any
		t.expect(plain).toEqual({ name = "Ada", userId = "7", score = 50, level = 2 })
		local rows = Hiscores.rows({ { { key = "7", score = 50 } } }, function(): (any, string?)
			return made, nil
		end, Hiscores.N) :: { any }
		t.expect(rows[1].run).toBe("7:1:1:j")
		t.expect(rows[1].at).toBe(1)
		t.expect(rows[1].runScore).toBe(50)
		local broken = Hiscores.rows({ { { key = "7", score = 50 } } }, function(): (any, string?)
			return { name = "Ada", userId = "7", score = 50, level = 2, run = "x", at = 0.5 }, nil
		end, Hiscores.N) :: { any }
		t.expect(broken[1].run).toBe(nil)
		t.expect(broken[1].at).toBe(nil)
		-- the page score can lag its companion: runScore is the companion's
		local lagging = Hiscores.rows({ { { key = "7", score = 40 } } }, function(): (any, string?)
			return { name = "Ada", userId = "7", score = 50, level = 2 }, nil
		end, Hiscores.N) :: { any }
		t.expect(lagging[1].score).toBe(40)
		t.expect(lagging[1].runScore).toBe(50)
	end)

	it("a run cut from the list does not come back as its best ahead of the earlier runs it ties", function()
		local list: { any } = {}
		for i = 1, 10 do
			table.insert(list, run(tostring(100 + i), 50, 1, FRI - 100 + i, `r{i}`))
		end
		local cut = best("7", 50, 1, "late", FRI)
		t.expect(H.bestRun(cut) ~= nil).toBe(true)
		local out = H.mergeRun(list, run("3", 1, 1, FRI, "low"), { cut })
		t.expect(table.find(ids(out), "late")).toBe(nil)
		t.expect(ids(out)).toEqual(ids(list))
	end)

	it("the lobby's rows of a list are ranked 1..N in order, and nothing stored is nil", function()
		local list = { run("2", 50, 2, FRI, "b"), run("1", 80, 3, FRI, "a"), run("1", 70, 1, FRI, "c") }
		t.expect(H.topRows(list)).toEqual({
			{ rank = 1, name = "P1", userId = "1", score = 80, level = 3 },
			{ rank = 2, name = "P1", userId = "1", score = 70, level = 1 },
			{ rank = 3, name = "P2", userId = "2", score = 50, level = 2 },
		})
		t.expect(H.topRows(nil)).toBe(nil)
		t.expect(H.topRows("runs")).toBe(nil)
		t.expect(H.topRows({})).toEqual({})
		local long: { any } = {}
		for i = 1, 12 do
			table.insert(long, run(tostring(i), i, 1, FRI, `r{i}`))
		end
		local rows = H.topRows(long)
		t.expect(#rows).toBe(10)
		t.expect(rows[1].score).toBe(12)
		t.expect(rows[10].rank).toBe(10)
	end)

	it("a player's best is the score and level of their all-time row, or nil", function()
		t.expect(H.best({ name = "Ada", userId = "1", score = 50, level = 2 }))
			.toEqual({ score = 50, level = 2 })
		t.expect(H.best(nil)).toBe(nil)
		t.expect(H.best({ score = 50 })).toBe(nil)
		t.expect(H.best({ score = 1.5, level = 2 })).toBe(nil)
		t.expect(H.best({ score = 5, level = 0 })).toBe(nil)
		t.expect(H.best({ score = -5, level = 1 })).toBe(nil)
	end)

	it("a held best is read again only when nothing is held, or a finished read is stale", function()
		t.expect(H.needsRead(nil, 100, 15)).toBe(true)
		t.expect(H.needsRead({ at = 100, reading = false }, 114, 15)).toBe(false)
		t.expect(H.needsRead({ at = 100, reading = false }, 115, 15)).toBe(true)
		t.expect(H.needsRead({ at = 100, reading = true }, 200, 15)).toBe(false)
	end)

	it("a read stays fresh for less than the time to live, and never from the future", function()
		t.expect(H.fresh(100, 100, 15)).toBe(true)
		t.expect(H.fresh(100, 114, 15)).toBe(true)
		t.expect(H.fresh(100, 115, 15)).toBe(false)
		t.expect(H.fresh(100, 99, 15)).toBe(false)
		t.expect(H.fresh(nil, 100, 15)).toBe(false)
	end)
end)
