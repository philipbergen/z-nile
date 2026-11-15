--!strict
-- f0197 AC2: every row records the revives its run used (the paid revives), and every row read shows them: a row
-- written before f0197 has none stored and shows 0. Revives never rank and never replace a row. The new names are
-- reached through `:: any` so this spec type-checks before they exist.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

local H = Hiscores :: any
local FRI = 1792108800

local function attempt(userId: string, score: number, level: number, revives: any): any
	return { userId = userId, score = score, level = level, name = `P{userId}`, revives = revives }
end

local function companion(userId: string, score: number, level: number, revives: any): any
	return { name = `P{userId}`, userId = userId, score = score, level = level, revives = revives }
end

-- a page and a lookup over the given companions, keyed by user id, for Hiscores.rows
local function board(rows: { any }): ({ any }, (string) -> (any, string?))
	local page: { any } = {}
	local byKey: { [string]: any } = {}
	for _, c in rows do
		table.insert(page, { key = c.userId, score = c.score })
		byKey[c.userId] = c
	end
	return { page }, function(key: string): (any, string?)
		return byKey[key], nil
	end
end

local function ids(list: { any }): { string }
	local out: { string } = {}
	for _, e in list do
		table.insert(out, e.id)
	end
	return out
end

return t.spec("f0197 revives on every row", function(it)
	it("AC2: a committed row records the run's revives, and a run that names none records 0", function()
		t.expect((Hiscores.commit(nil, attempt("7", 50, 2, 3)) :: any).revives).toBe(3)
		t.expect((Hiscores.commit(nil, attempt("7", 50, 2, 0)) :: any).revives).toBe(0)
		t.expect((Hiscores.commit(nil, attempt("7", 50, 2, nil)) :: any).revives).toBe(0)
	end)

	it(
		"AC2: revives that are not a whole number from 0 make the attempt invalid, and nothing is written",
		function()
			t.expect(Hiscores.valid(attempt("7", 50, 2, 0))).toBe(true)
			t.expect(Hiscores.valid(attempt("7", 50, 2, 12))).toBe(true)
			t.expect(Hiscores.valid(attempt("7", 50, 2, nil))).toBe(true)
			t.expect(Hiscores.valid(attempt("7", 50, 2, 2 ^ 53 - 1))).toBe(true)
			for _, bad in { -1, 1.5, math.huge, 0 / 0, "2", true, 2 ^ 53 } :: { any } do
				t.expect(Hiscores.valid(attempt("7", 50, 2, bad))).toBe(false)
			end
			local store = Hiscores.fake()
			local wrote = Hiscores.submit(store, attempt("7", 50, 2, -1), FRI)
			t.expect(wrote.all).toBe(false)
			t.expect(store.get(Hiscores.board("all", FRI), "7")).toBe(nil)
		end
	)

	it(
		"AC2: revives never replace a row: the same score and level with fewer revives keeps the stored row",
		function()
			local stored = Hiscores.commit(nil, attempt("7", 50, 2, 4)) :: any
			t.expect(Hiscores.qualifies(stored, attempt("7", 50, 2, 0))).toBe(false)
			t.expect(Hiscores.commit(stored, attempt("7", 50, 2, 0))).toBe(nil)
			-- a better run replaces the row and brings its own revives, more or fewer
			t.expect((Hiscores.commit(stored, attempt("7", 51, 2, 9)) :: any).revives).toBe(9)
			t.expect((Hiscores.commit(stored, attempt("7", 50, 3, 0)) :: any).revives).toBe(0)
		end
	)

	it("AC2: every board the fake writes keeps the run's revives, and its rows show them", function()
		local store = Hiscores.fake()
		Hiscores.submit(store, attempt("7", 50, 2, 2), FRI)
		Hiscores.submit(store, attempt("8", 40, 1, 0), FRI)
		for _, id in { "all", "day", "week" } :: { any } do
			local rows = Hiscores.top(store, id, FRI)
			t.expect(#rows).toBe(2)
			t.expect(rows[1].userId).toBe("7")
			t.expect(rows[1].revives).toBe(2)
			t.expect(rows[2].revives).toBe(0)
		end
	end)

	it(
		"AC2: a row read shows its stored revives, and one stored without them (or with junk) shows 0",
		function()
			local pages, lookup = board({
				companion("1", 90, 1, 5),
				companion("2", 80, 1, nil), -- written before f0197
				companion("3", 70, 1, -2),
				companion("4", 60, 1, 1.5),
				companion("5", 50, 1, "3"),
				companion("6", 40, 1, 0),
			})
			local rows = Hiscores.rows(pages, lookup, 10) :: { any }
			t.expect(#rows).toBe(6)
			local shown: { number } = {}
			for _, row in rows do
				table.insert(shown, row.revives)
			end
			t.expect(shown).toEqual({ 5, 0, 0, 0, 0, 0 })
			t.expect(H.revivesOf(7)).toBe(7)
			t.expect(H.revivesOf(nil)).toBe(0)
			t.expect(H.revivesOf(2 ^ 53 - 1)).toBe(2 ^ 53 - 1)
			t.expect(H.revivesOf(2 ^ 53)).toBe(0)
			t.expect(H.revivesOf("7")).toBe(0)
		end
	)

	it(
		"AC2: revives never rank: rows of equal score and level keep their order whatever their revives",
		function()
			local pages, lookup = board({
				companion("1", 50, 2, 9),
				companion("2", 50, 2, 0),
				companion("3", 40, 1, 0),
				companion("4", 40, 1, 9),
				companion("5", 60, 1, 8),
			})
			local rows = Hiscores.rows(pages, lookup, 10) :: { any }
			local order: { string } = {}
			for _, row in rows do
				table.insert(order, row.userId)
			end
			-- by score, then level, then user id: fewer revives first and more revives first both break a pair
			t.expect(order).toEqual({ "5", "1", "2", "3", "4" })
		end
	)

	it("AC2: the rows a client is sent carry the revives and still no user id", function()
		local pages, lookup = board({ companion("1", 90, 4, 3), companion("2", 80, 1, nil) })
		local shown = H.boardRows(Hiscores.rows(pages, lookup, 10))
		t.expect(shown).toEqual({
			{ rank = 1, name = "P1", score = 90, level = 4, revives = 3 },
			{ rank = 2, name = "P2", score = 80, level = 1, revives = 0 },
		})
	end)

	it("AC2: a run's list entry carries its revives, and the list keeps them through a merge", function()
		local entry = Hiscores.topRun(attempt("7", 50, 2, 3), FRI, 1, "job") :: any
		t.expect(entry.revives).toBe(3)
		t.expect((Hiscores.topRun(attempt("7", 50, 2, nil), FRI, 1, "job") :: any).revives).toBe(0)
		local list = Hiscores.addRun({}, entry)
		local other = Hiscores.topRun(attempt("8", 90, 1, 1), FRI, 1, "job") :: any
		local merged = Hiscores.addRun(list, other)
		t.expect(ids(merged)).toEqual({ other.id, entry.id })
		t.expect(merged[1].revives).toBe(1)
		t.expect(merged[2].revives).toBe(3)
		local rows = Hiscores.topRows(merged) :: { any }
		t.expect(rows[1].revives).toBe(1)
		t.expect(rows[2].revives).toBe(3)
	end)

	it(
		"AC2: a stored list entry without revives (written before f0197) shows 0, and revives never order the list",
		function()
			local function entry(id: string, revives: number?): any
				return {
					id = id,
					name = string.upper(id),
					userId = "1",
					score = 50,
					level = 2,
					revives = revives,
					at = FRI,
				}
			end
			-- equal score, level and instant: the id orders them, whatever their revives
			local rows =
				Hiscores.topRows({ entry("d", 6), entry("c", 0), entry("b", nil), entry("a", 6) }) :: { any }
			local names: { string } = {}
			local revives: { number } = {}
			for _, row in rows do
				table.insert(names, row.name)
				table.insert(revives, row.revives)
			end
			t.expect(names).toEqual({ "A", "B", "C", "D" })
			t.expect(revives).toEqual({ 6, 0, 0, 6 })
		end
	)

	it("AC2: a stored list entry with junk revives reads 0, through the list and through a merge", function()
		local list: { any } = {}
		for i, junk in { -2, 1.5, "3", 2 ^ 53 } :: { any } do
			table.insert(list, {
				id = `j{i}`,
				name = `J{i}`,
				userId = tostring(i),
				score = 100 - i,
				level = 1,
				revives = junk,
				at = FRI,
			})
		end
		for _, row in Hiscores.topRows(list) :: { any } do
			t.expect(row.revives).toBe(0)
		end
		local run = Hiscores.topRun(attempt("9", 1, 1, 0), FRI, 1, "job") :: any
		for _, e in Hiscores.addRun(list, run) do
			t.expect(e.revives).toBe(0)
		end
	end)

	it(
		"AC2: a per-player best merged into the list brings the row's revives, whether or not it names its run",
		function()
			-- every row written since d0124 names its run (`commit` stores run and at); older rows do not
			local named = companion("3", 500, 2, 2)
			named.run, named.at = "3:1:1:j", 1
			local pages, lookup = board({ named, companion("2", 300, 1, 4) })
			local bests = Hiscores.rows(pages, lookup, 10) :: { any }
			local run = Hiscores.topRun(attempt("7", 100, 1, 0), FRI, 1, "job") :: any
			local merged = Hiscores.mergeRun({}, run, bests)
			t.expect(ids(merged)).toEqual({ "3:1:1:j", "best:2:300:1", run.id })
			t.expect(merged[1].revives).toBe(2)
			t.expect(merged[2].revives).toBe(4)
			t.expect(merged[3].revives).toBe(0)
		end
	)

	it("AC2: a player's best carries the revives of their all-time row, 0 when it has none", function()
		t.expect(Hiscores.best(companion("1", 50, 2, 3))).toEqual({ score = 50, level = 2, revives = 3 })
		t.expect(Hiscores.best(companion("1", 50, 2, nil))).toEqual({ score = 50, level = 2, revives = 0 })
		for _, junk in { -2, 1.5, "3", 2 ^ 53 } :: { any } do
			t.expect(Hiscores.best(companion("1", 50, 2, junk)))
				.toEqual({ score = 50, level = 2, revives = 0 })
		end
	end)

	it("AC2: a run's submission carries the game over's revives, and one that names none is 0", function()
		local _, sub = Hiscores.onStep(
			Hiscores.newRun(),
			{ { kind = "GameOver", score = 30, level = 2, revives = 2 } :: any },
			true,
			Hiscores.LEAVE_STEPS
		)
		t.expect((sub :: any).revives).toBe(2)
		local _, plain = Hiscores.onStep(
			Hiscores.newRun(),
			{ { kind = "GameOver", score = 30, level = 2 } },
			true,
			Hiscores.LEAVE_STEPS
		)
		t.expect((plain :: any).revives).toBe(0)
	end)

	it("AC2: drive writes the revives to every board through the store's own transforms", function()
		local rows: { [string]: any } = {}
		local scores: { [string]: number } = {}
		local io: any = {
			get = function(b: any, key: string): (any, string?)
				return rows[`{Hiscores.scope(b)}|{key}`], nil
			end,
			updateEntry = function(b: any, key: string, transform: (any) -> any): (any, string?)
				local at = `{Hiscores.scope(b)}|{key}`
				local made = transform(rows[at])
				if made ~= nil then
					rows[at] = made
				end
				return made, nil
			end,
			updateScore = function(b: any, key: string, transform: (any) -> any): (any, string?)
				local at = `{Hiscores.scope(b)}|{key}`
				scores[at] = transform(scores[at])
				return scores[at], nil
			end,
			top = function(b: any): (any, string?)
				local page: { any } = {}
				for at, value in scores do
					local scope, key = string.match(at, "^(.-)|(.+)$")
					if scope == Hiscores.scope(b) then
						table.insert(page, { key = key, value = value })
					end
				end
				return { Hiscores.scorePage(page) }, nil
			end,
			budget = function(): number
				return 100
			end,
			wait = function() end,
		}
		local result = Hiscores.drive(io, attempt("7", 50, 2, 3), FRI, Hiscores.RETRY)
		t.expect(result.wrote).toEqual({ all = true, day = true, week = true })
		for _, id in { "all", "day", "week" } :: { any } do
			local b = Hiscores.board(id, FRI)
			t.expect(rows[`{Hiscores.scope(b)}|{Hiscores.entryKey("7", b)}`].revives).toBe(3)
		end
		t.expect(((result.rows :: any)[1]).revives).toBe(3)
	end)
end)
