--!strict
-- d0124 AC2: Hiscores.driveTop writes a run to the top-N list with the store's transform, and says where it stands.
-- `bests` is the per-player all-time board that drive read back after its write; every write merges those bests in,
-- so a best stored by a build without the list joins it on the next run. A list is never created without them. It
-- retries like the per-player write (same delays, same budgets), writes nothing when the list would not change, and
-- says nothing (`known = false`) when nothing was written or found. It reads nothing itself. The doubles store
-- whatever the transform returns and hold no policy.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

local H = Hiscores :: any
local FRI = 1792108800

type Top = { held: any, fails: number, calls: number, update: (any) -> (any, string?) }

local function topIo(held: any): Top
	local top: Top
	top = {
		held = held,
		fails = 0,
		calls = 0,
		update = function(transform: any): (any, string?)
			top.calls += 1
			if top.fails > 0 then
				top.fails -= 1
				return nil, "stub: update failed"
			end
			local value = transform(top.held)
			if value ~= nil then
				top.held = value
			end
			return value, nil
		end,
	}
	return top
end

type Io = { budgets: { [string]: number }, waits: { number }, io: any }

-- the per-player side: only the budgets and the clock; any read is an error
local function playerIo(): Io
	local w: Io
	w = { budgets = { get = 100, set = 100, getSorted = 100, setSorted = 100 }, waits = {}, io = nil }
	local function never(): (any, string?)
		error("driveTop reads and writes nothing of the per-player boards")
	end
	w.io = {
		get = never,
		updateEntry = never,
		updateScore = never,
		top = never,
		budget = function(op: string): number
			return w.budgets[op] or 0
		end,
		wait = function(seconds: number)
			table.insert(w.waits, seconds)
		end,
	}
	return w
end

local function entry(userId: string, score: number, level: number, at: number?, runNo: number?): any
	return H.topRun(
		{ name = `P{userId}`, userId = userId, score = score, level = level },
		at or FRI,
		runNo or 1,
		"job-1"
	)
end

-- a per-player row as Hiscores.rows makes it; `named` is the id of the run that wrote it
local function row(userId: string, score: number, level: number, named: any?): Hiscores.Row
	local r: any =
		{ rank = 0, name = `P{userId}`, userId = userId, score = score, level = level, runScore = score }
	if named ~= nil then
		r.run = named.id
		r.at = named.at
	end
	return r
end

local function listed(top: Top): { string }
	local out: { string } = {}
	for _, e in top.held do
		table.insert(out, `{e.id}={e.score}`)
	end
	return out
end

local RUN = `7:{FRI}:1:job-1`

return t.spec("d0124 driveTop", function(it)
	it("with no list yet, the stored bests start it and the run takes its place among them", function()
		local top = topIo(nil)
		local p = playerIo()
		local result =
			H.driveTop(top, p.io, entry("7", 60, 1), { row("2", 80, 3), row("1", 50, 2) }, Hiscores.RETRY)
		t.expect(result).toEqual({ known = true, place = 2 })
		t.expect(listed(top)).toEqual({ "best:2:80:3=80", `{RUN}=60`, "best:1:50:2=50" })
		t.expect(top.calls).toBe(1)
		t.expect(p.waits).toEqual({})
	end)

	it("with no list and no stored best, the run alone is the list", function()
		local top = topIo(nil)
		local result = H.driveTop(top, playerIo().io, entry("7", 60, 1), {}, Hiscores.RETRY)
		t.expect(result).toEqual({ known = true, place = 1 })
		t.expect(listed(top)).toEqual({ `{RUN}=60` })
	end)

	it("a run that is the player's new best is listed once", function()
		local top = topIo(nil)
		local mine = entry("7", 60, 1)
		local result = H.driveTop(top, playerIo().io, mine, { row("7", 60, 1, mine) }, Hiscores.RETRY)
		t.expect(result).toEqual({ known = true, place = 1 })
		t.expect(listed(top)).toEqual({ `{RUN}=60` })
	end)

	it("a best stored without the list (an older build) joins an existing list on the next run", function()
		local listedRun = entry("2", 80, 3, FRI - 100)
		local top = topIo({ listedRun })
		local result = H.driveTop(
			top,
			playerIo().io,
			entry("7", 60, 1),
			{ row("9", 900, 4), row("2", 80, 3, listedRun) },
			Hiscores.RETRY
		)
		t.expect(result).toEqual({ known = true, place = 3 })
		t.expect(listed(top)).toEqual({ "best:9:900:4=900", `2:{FRI - 100}:1:job-1=80`, `{RUN}=60` })
	end)

	it("another server merged this run's best before its own write: the run is listed once", function()
		local mine = entry("7", 500, 3)
		local q = entry("2", 100, 1, FRI, 1)
		local named = row("7", 500, 3, mine)
		local top = topIo(nil)
		local p = playerIo()
		-- Q's game over read P's new row first
		t.expect(H.driveTop(top, p.io, q, { named, row("2", 100, 1, q) }, Hiscores.RETRY).place).toBe(2)
		local result = H.driveTop(top, p.io, mine, { named, row("2", 100, 1, q) }, Hiscores.RETRY)
		t.expect(result).toEqual({ known = true, place = 1 })
		t.expect(listed(top)).toEqual({ `{RUN}=500`, `2:{FRI}:1:job-1=100` })
		-- and in the other order
		local other = topIo(nil)
		t.expect(H.driveTop(other, p.io, mine, { named }, Hiscores.RETRY).place).toBe(1)
		H.driveTop(other, p.io, q, { named, row("2", 100, 1, q) }, Hiscores.RETRY)
		t.expect(listed(other)).toEqual({ `{RUN}=500`, `2:{FRI}:1:job-1=100` })
	end)

	it("a best merged from a half-written row is listed once, at the run's own score", function()
		local mine = entry("7", 600, 3)
		local half = row("7", 600, 3, mine)
		half.score = 500 -- the ordered score still holds the older best
		local top = topIo(nil)
		local p = playerIo()
		H.driveTop(top, p.io, entry("2", 100, 1, FRI, 1), { half }, Hiscores.RETRY)
		local result = H.driveTop(top, p.io, mine, { half }, Hiscores.RETRY)
		t.expect(result).toEqual({ known = true, place = 1 })
		t.expect(listed(top)).toEqual({ `{RUN}=600`, `2:{FRI}:1:job-1=100` })
	end)

	it("a lower second run of the same player stands second", function()
		local top = topIo(nil)
		local p = playerIo()
		local first = entry("7", 80, 3, FRI, 1)
		t.expect(H.driveTop(top, p.io, first, { row("7", 80, 3, first) }, Hiscores.RETRY).place).toBe(1)
		local second =
			H.driveTop(top, p.io, entry("7", 50, 2, FRI + 60, 2), { row("7", 80, 3, first) }, Hiscores.RETRY)
		t.expect(second).toEqual({ known = true, place = 2 })
		t.expect(listed(top)).toEqual({ `{RUN}=80`, `7:{FRI + 60}:2:job-1=50` })
	end)

	it("a run below a full list is known to have missed it, and nothing is written", function()
		local full: { any } = {}
		for i = 1, 10 do
			table.insert(full, entry(tostring(i), 100 + i, 1, FRI - i))
		end
		local top = topIo(full)
		local result =
			H.driveTop(top, playerIo().io, entry("7", 5, 1), { row("10", 110, 1, full[10]) }, Hiscores.RETRY)
		t.expect(result).toEqual({ known = true, missed = Hiscores.N })
		t.expect(top.held).toBe(full)
		t.expect(top.calls).toBe(1)
	end)

	it("a run already on the list (a retry that landed) keeps its place and is not written again", function()
		local stored = { entry("2", 80, 3, FRI - 5), entry("7", 60, 1) }
		local top = topIo(stored)
		local result = H.driveTop(top, playerIo().io, entry("7", 60, 1), {}, Hiscores.RETRY)
		t.expect(result).toEqual({ known = true, place = 2 })
		t.expect(top.held).toBe(stored)
	end)

	it("the write applies to what the store holds when it runs, so another server's run is kept", function()
		local top = topIo(nil)
		local other = entry("3", 70, 1, FRI - 1)
		top.fails = 1
		local update = top.update
		top.update = function(transform: any): (any, string?)
			if top.calls == 1 then
				top.held = { other } -- another server wrote the list while this one waited
			end
			return update(transform)
		end
		local result = H.driveTop(top, playerIo().io, entry("7", 60, 1), {}, Hiscores.RETRY)
		t.expect(result).toEqual({ known = true, place = 2 })
		t.expect(listed(top)).toEqual({ `3:{FRI - 1}:1:job-1=70`, `{RUN}=60` })
	end)

	-- the store runs the transform again when the key changed under it (UpdateAsync does): first on `stale`, then on
	-- what it holds; only the last call's value is written
	local function rerun(top: Top, stale: any)
		top.update = function(transform: any): (any, string?)
			top.calls += 1
			transform(stale)
			local value = transform(top.held)
			if value ~= nil then
				top.held = value
			end
			return value, nil
		end
	end

	it("a transform run again says the place of its last call, not an earlier one", function()
		local stale: { any } = {}
		for i = 1, 8 do
			table.insert(stale, entry(tostring(i), 100 + i, 1, FRI - i))
		end
		local full: { any } = {}
		for i = 1, 10 do
			table.insert(full, entry(tostring(i), 100 + i, 1, FRI - i))
		end
		local top = topIo(full)
		rerun(top, stale) -- on the stale list the run would be 9th; on the real one it is cut
		t.expect(H.driveTop(top, playerIo().io, entry("7", 5, 1), {}, Hiscores.RETRY))
			.toEqual({ known = true, missed = Hiscores.N })
		local back = topIo(stale)
		rerun(back, full) -- cut first, then placed
		t.expect(H.driveTop(back, playerIo().io, entry("7", 5, 1), {}, Hiscores.RETRY))
			.toEqual({ known = true, place = 9 })
	end)

	it("a transform that first saw no list and then a list writes and says the place", function()
		local top = topIo({ entry("2", 80, 3, FRI - 5) })
		rerun(top, nil) -- another server created the list between the two calls
		local result = H.driveTop(top, playerIo().io, entry("7", 60, 1), nil, Hiscores.RETRY)
		t.expect(result).toEqual({ known = true, place = 2 })
		t.expect(#top.held).toBe(2)
	end)

	it("a failed write is retried after 0.25 and 0.5 s, and three failures say nothing", function()
		local top = topIo({})
		top.fails = 2
		local p = playerIo()
		t.expect(H.driveTop(top, p.io, entry("7", 60, 1), {}, Hiscores.RETRY))
			.toEqual({ known = true, place = 1 })
		t.expect(p.waits).toEqual({ 0.25, 0.5 })
		local stuck = topIo({})
		stuck.fails = 99
		local q = playerIo()
		t.expect(H.driveTop(stuck, q.io, entry("7", 60, 1), {}, Hiscores.RETRY)).toEqual({ known = false })
		t.expect(stuck.calls).toBe(3)
		t.expect(q.waits).toEqual({ 0.25, 0.5 })
	end)

	it("no list and no bests (the board could not be read): no list is made and nothing is said", function()
		local top = topIo(nil)
		local p = playerIo()
		t.expect(H.driveTop(top, p.io, entry("7", 60, 1), nil, Hiscores.RETRY)).toEqual({ known = false })
		t.expect(top.held).toBe(nil)
		t.expect(top.calls).toBe(1)
		t.expect(p.waits).toEqual({})
	end)

	it("an existing list takes the run even when the bests could not be read", function()
		local top = topIo({ entry("2", 80, 3, FRI - 5) })
		local result = H.driveTop(top, playerIo().io, entry("7", 60, 1), nil, Hiscores.RETRY)
		t.expect(result).toEqual({ known = true, place = 2 })
		t.expect(#top.held).toBe(2)
	end)

	it("a zero read or write budget skips the write, still waits, and says nothing", function()
		for _, op in { "get", "set" } do
			local top = topIo({})
			local p = playerIo()
			p.budgets[op] = 0
			t.expect(H.driveTop(top, p.io, entry("7", 60, 1), {}, Hiscores.RETRY)).toEqual({ known = false })
			t.expect(top.calls).toBe(0)
			t.expect(p.waits).toEqual({ 0.25, 0.5 })
		end
	end)

	it("no entry, or one that is not a valid run, writes nothing and says nothing", function()
		local broken: { any } = {
			nil :: any,
			{ id = "", name = "A", userId = "7", score = 1, level = 1, at = FRI },
			{ id = "x", name = "A", userId = "7", score = -1, level = 1, at = FRI },
			{ id = "x", name = "A", userId = "7", score = 1, level = 1, at = 0.5 },
		}
		for i = 1, 4 do
			local top = topIo({})
			t.expect(H.driveTop(top, playerIo().io, broken[i], {}, Hiscores.RETRY)).toEqual({ known = false })
			t.expect(top.calls).toBe(0)
		end
	end)
end)
