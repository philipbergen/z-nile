--!strict
-- f0197 AC4: the generic server adapter's READS, `src/server/Boards.luau` through `Boards.open(prefix).serve(remote)`:
-- every request for a board id ("all", "day", "week") on the remote the place made is answered once with
-- (id, rows, rank, failed, best) - the rows with their revives, from the stores of the title's prefix. The cases are
-- ported from pickman's lobby Boards specs (f0026/adapters and the read cases of d0124/adapters), whose server-side
-- behaviour the merged adapter must keep, so that no wrong adapter passes only because those specs were left behind:
-- the shared read and its waiters, the failure wait, the page-size fallback, an unreadable companion, a waiter who
-- left, the all-time top-N list (or the per-player board while a title has no list yet) and each player's held best.
-- The adapter's real source runs on a stub `game` of this spec's own: a DataStoreService that copies what it stores
-- and returns, that can fail or hold a read, reject a page size, fail a store open and log every call in order; a
-- clock the case sets. The file is absent until the raft builds it, so this fails on the missing file.
local Hiscores = require("@logic/Hiscores")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local t = require("@tests/lib/t")

local ADAPTER = "src/server/Boards.luau"
local LOGIC_ROOT = "@game/ReplicatedStorage/Arcade/Logic/"
local FRI = 1792108800 -- 2026-10-16, a Friday: day "day:2026-10-16", week "week:2026-10-12"
local JOB = "job-1"
local DAY = "day:2026-10-16"

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out: { [any]: any } = {}
	for k, x in v :: { [any]: any } do
		out[k] = copy(x)
	end
	return out
end

type Store = { kind: string, name: string, scope: string, data: { [string]: any } }
type Sorted = { name: string, scope: string, ascending: boolean, size: number }
type World = {
	Boards: any,
	now: number,
	stores: { [string]: Store },
	log: { string }, -- "budget:<type>", "update:<kind>:<name>", "get:<name>:<key>", "sorted:<name>:<size>" in call order
	opens: { string }, -- "<ordered|companion>|<name>|<scope>" per store open, in order
	sorted: { Sorted }, -- every sorted read
	sortedFails: boolean,
	sortedFailsAt: number?, -- a page size the sorted read rejects
	openFails: number, -- this many GetOrderedDataStore calls throw first
	failGet: { [string]: boolean }, -- "<name>" or "<name>:<key>" whose GetAsync throws
	failUpdate: { [string]: boolean }, -- store names whose UpdateAsync throws
	holdGet: { [string]: boolean }, -- "<name>:<key>" whose GetAsync yields until `release`
	holdSorted: boolean, -- the sorted read yields until `release`
	held: { thread },
	budgetFails: boolean,
	hold: boolean, -- task.spawn keeps the function in `spawned` instead of running it
	spawnFails: boolean, -- task.spawn throws
	spawned: { () -> () },
	warnings: number,
	removing: { (any) -> () },
	errors: { string }, -- errors that escaped a request handler (the engine would only log them)
}
type Remote = { handlers: { (any, any) -> () }, fired: { { any } }, stub: any }

local function slot(w: World, kind: string, name: string, scope: string?): Store
	local id = `{kind}|{name}|{scope or "global"}`
	local found = w.stores[id]
	if found == nil then
		found = { kind = kind, name = name, scope = scope or "global", data = {} }
		w.stores[id] = found
	end
	return found :: Store
end

local function world(): World
	local w: World = {
		Boards = nil,
		now = FRI,
		stores = {},
		log = {},
		opens = {},
		sorted = {},
		sortedFails = false,
		sortedFailsAt = nil,
		openFails = 0,
		failGet = {},
		failUpdate = {},
		holdGet = {},
		holdSorted = false,
		held = {},
		budgetFails = false,
		hold = false,
		spawnFails = false,
		spawned = {},
		warnings = 0,
		removing = {},
		errors = {},
	}
	-- a read that is held yields on the coroutine the case drives, and `release(true)` makes it fail
	local function pause()
		table.insert(w.held, coroutine.running())
		if coroutine.yield() then
			error("stub: held read failed", 0)
		end
	end
	local function open(kind: string, name: string, scope: string?): any
		local s = slot(w, kind, name, scope)
		return {
			GetAsync = function(_: any, key: string): any
				table.insert(w.log, `get:{name}:{key}`)
				if w.holdGet[`{name}:{key}`] then
					pause()
				end
				if w.failGet[name] or w.failGet[`{name}:{key}`] then
					error("stub: read failed", 0)
				end
				return copy(s.data[key])
			end,
			UpdateAsync = function(_: any, key: string, transform: (any) -> any): any
				table.insert(w.log, `update:{kind}:{name}`)
				if w.failUpdate[name] then
					error("stub: write failed", 0)
				end
				local value = transform(copy(s.data[key]))
				if value ~= nil then
					s.data[key] = copy(value)
				end
				return copy(value)
			end,
			GetSortedAsync = function(_: any, ascending: boolean, size: number): any
				table.insert(w.log, `sorted:{name}:{size}`)
				table.insert(w.sorted, { name = name, scope = s.scope, ascending = ascending, size = size })
				if w.sortedFails or w.sortedFailsAt == size then
					error("stub: sorted read failed", 0)
				end
				if w.holdSorted then
					pause()
				end
				local list: { { key: string, value: number } } = {}
				for key, value in s.data do
					table.insert(list, { key = key, value = value })
				end
				table.sort(list, function(a, b)
					if ascending then
						return a.value < b.value
					end
					return a.value > b.value
				end)
				while #list > size do
					table.remove(list)
				end
				return {
					GetCurrentPage = function(_: any): any
						return list
					end,
				}
			end,
		}
	end
	local services: { [string]: any } = {
		DataStoreService = {
			GetDataStore = function(_: any, name: string, scope: string?): any
				table.insert(w.opens, `companion|{name}|{scope or "global"}`)
				return open("companion", name, scope)
			end,
			GetOrderedDataStore = function(_: any, name: string, scope: string?): any
				table.insert(w.opens, `ordered|{name}|{scope or "global"}`)
				if w.openFails > 0 then
					w.openFails -= 1
					error("stub: You must publish this place to the web to access DataStore", 0)
				end
				return open("ordered", name, scope)
			end,
			GetRequestBudgetForRequestType = function(_: any, kind: any): number
				if w.budgetFails then
					error("stub: budget query failed", 0)
				end
				table.insert(w.log, `budget:{tostring(kind)}`)
				return 100
			end,
		},
		Players = {
			PlayerRemoving = {
				Connect = function(_: any, fn: (any) -> ())
					table.insert(w.removing, fn)
				end,
			},
		},
	}
	local env: { [string]: any } = {
		game = {
			JobId = JOB,
			GetService = function(_: any, name: string): any
				return assert(services[name], `stub: game:GetService("{name}") is not modelled`)
			end,
		},
		require = function(spec: string): any
			if spec == LOGIC_ROOT .. "Hiscores" then
				return Hiscores
			end
			-- another library feature loads as itself, so a correct later require keeps this spec green
			local feature = string.match(spec, "^@game/ReplicatedStorage/Arcade/Logic/(%w+)$")
			assert(feature ~= nil, `stub: no module for {spec}`)
			return (require :: any)(`@logic/{feature}`)
		end,
		Enum = setmetatable({}, {
			__index = function(_: any, group: string): any
				return setmetatable({}, {
					__index = function(_: any, item: string): string
						return `{group}.{item}`
					end,
				})
			end,
		}),
		task = {
			spawn = function(fn: () -> ())
				if w.spawnFails then
					error("stub: cannot start a thread", 0)
				end
				if w.hold then
					table.insert(w.spawned, fn)
				else
					fn()
				end
			end,
			wait = function(_seconds: number?): number
				return 0
			end,
		},
		os = {
			time = function(): number
				return w.now
			end,
		},
		warn = function()
			w.warnings += 1
		end,
	}
	t.expect(fs.isFile(ADAPTER)).toBe(true)
	local chunk = luau.load(fs.readFile(ADAPTER), { environment = env, debugName = "Boards" })
	w.Boards = chunk()
	return w
end

local function remote(): Remote
	local r: Remote = { handlers = {}, fired = {}, stub = nil }
	r.stub = {
		OnServerEvent = {
			Connect = function(_: any, fn: (any, any) -> ())
				table.insert(r.handlers, fn)
			end,
		},
		FireClient = function(_: any, player: any, ...: any)
			table.insert(r.fired, table.pack(player, ...))
		end,
	}
	return r
end

local function player(userId: number): any
	return { UserId = userId, Parent = {} }
end

-- the player leaves: the engine empties Parent and tells PlayerRemoving
local function leave(w: World, who: any)
	who.Parent = nil
	for _, fn in w.removing do
		fn(who)
	end
end

-- one fired answer's values, nils included: (player, id, rows, rank, failed, best)
local function values(fired: any): ...any
	return table.unpack(fired, 1, fired.n)
end

-- a player asks for a board on the remote, each handler on a coroutine of its own (a held read yields there);
-- returns what the remote fired meanwhile
local function ask(w: World, r: Remote, who: any, id: any): { any }
	local before = #r.fired
	for _, fn in r.handlers do
		local ok, err = coroutine.resume(coroutine.create(fn), who, id)
		if not ok then
			table.insert(w.errors, tostring(err))
		end
	end
	local out: { any } = {}
	for i = before + 1, #r.fired do
		table.insert(out, r.fired[i])
	end
	return out
end

-- let the oldest held read go on; `failure` makes it fail
local function release(w: World, failure: boolean?)
	local co = table.remove(w.held, 1) :: thread
	local ok, err = coroutine.resume(co, failure)
	if not ok then
		error(err, 0)
	end
end

local function data(w: World, kind: string, name: string, scope: string): { [string]: any }
	return slot(w, kind, name, scope).data
end

local function count(w: World, prefix: string): number
	local n = 0
	for _, line in w.log do
		if string.sub(line, 1, #prefix) == prefix then
			n += 1
		end
	end
	return n
end

-- the Snake title's stores
local function ordered(w: World, scope: string): { [string]: any }
	return data(w, "ordered", "SnakeHiscores", scope)
end

local function companion(w: World, scope: string): { [string]: any }
	return data(w, "companion", "SnakeHiscoreEntries", scope)
end

-- a stored all-time per-player best, as a submit leaves it
local function seedBest(w: World, userId: string, name: string, score: number, level: number, revives: number)
	ordered(w, "all")[userId] = Hiscores.pack(score, level)
	companion(w, "all")[userId] =
		{ name = name, userId = userId, score = score, level = level, revives = revives }
end

-- a run as the list stores it
local function stored(
	userId: string,
	score: number,
	level: number,
	at: number,
	runNo: number,
	revives: number
): any
	local attempt: any =
		{ name = `P{userId}`, userId = userId, score = score, level = level, revives = revives }
	return Hiscores.topRun(attempt, at, runNo, JOB)
end

local function setList(w: World, runs: { any })
	data(w, "companion", "SnakeHiscoreTop", Hiscores.TOP_SCOPE)[Hiscores.TOP_KEY] = runs
end

-- a title with its per-player boards seeded as the adapter stores them (two players, revives on the rows)
local function seed(w: World)
	seedBest(w, "1", "Ada", 50, 2, 1)
	seedBest(w, "2", "Bea", 80, 3, 0)
end

local BOTH = {
	{ rank = 1, name = "Bea", score = 80, level = 3, revives = 0 },
	{ rank = 2, name = "Ada", score = 50, level = 2, revives = 1 },
}

-- values as a plain array with its holes, to compare an answer with
local function tup(...: any): { any }
	local out: any = table.pack(...)
	out.n = nil
	return out
end

-- an answer's (id, rows, rank, failed), without the best
local function four(fired: { any }): { any }
	return { fired[2], fired[3], fired[4], fired[5] }
end

local function answers(r: Remote, who: any): { { any } }
	local out: { { any } } = {}
	for _, f in r.fired do
		if f[1] == who then
			table.insert(out, f)
		end
	end
	return out
end

return t.spec("f0197 Boards reads", function(it)
	-- from f0026/adapters :513 (the part that is the adapter's: ignoring any id but all, day or week)
	it("AC4: serve ignores anything but all, day or week, and reads nothing for it", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		local r = remote()
		snake.serve(r.stub)
		local p1 = player(1)
		for _, bad in { 5000, { score = 99999 }, "ALL", "month", "", true } :: { any } do
			t.expect(#ask(w, r, p1, bad)).toBe(0)
		end
		t.expect(#ask(w, r, p1, nil)).toBe(0)
		t.expect(#w.sorted).toBe(0)
		t.expect(#w.opens).toBe(0)
		t.expect(w.errors).toEqual({})
	end)

	-- new for f0197 AC4: every new title starts with no list
	it("AC4: a title with no list yet answers the all-time board with its per-player board", function()
		local w = world()
		local asteroids = w.Boards.open("Asteroids")
		local function put(
			name: string,
			kind: string,
			userId: string,
			nm: string,
			score: number,
			level: number,
			revives: number
		)
			local s = data(w, kind, name, "all")
			if kind == "ordered" then
				s[userId] = Hiscores.pack(score, level)
			else
				s[userId] = { name = nm, userId = userId, score = score, level = level, revives = revives }
			end
		end
		put("AsteroidsHiscores", "ordered", "1", "Ada", 50, 2, 1)
		put("AsteroidsHiscoreEntries", "companion", "1", "Ada", 50, 2, 1)
		put("AsteroidsHiscores", "ordered", "2", "Bea", 80, 3, 0)
		put("AsteroidsHiscoreEntries", "companion", "2", "Bea", 80, 3, 0)
		local r = remote()
		asteroids.serve(r.stub)
		local who = player(1)
		local got = ask(w, r, who, "all")
		t.expect(#got).toBe(1)
		local to, id, rows, rank, failed, best = values(got[1])
		t.expect(to).toBe(who)
		t.expect(id).toBe("all")
		t.expect(rows).toEqual(BOTH)
		t.expect(rank).toBe(2)
		t.expect(failed).toBe(false)
		t.expect(best).toEqual({ score = 50, level = 2, revives = 1 })
		-- the list was asked for first, then the title's own ordered store
		t.expect(count(w, "get:AsteroidsHiscoreTop:runs")).toBe(1)
		t.expect(count(w, "sorted:AsteroidsHiscores:")).toBe(1)
		t.expect(w.errors).toEqual({})
		-- another title's boards are not read
		t.expect(count(w, "get:SnakeHiscore")).toBe(0)
		t.expect(count(w, "sorted:Snake")).toBe(0)
	end)

	-- from f0026/adapters :525
	it(
		"AC4: a failed read still answers once, failed, with the rows it had or none, and waits to read again",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			local r = remote()
			snake.serve(r.stub)
			local p1, p2, p3 = player(1), player(2), player(3)
			w.sortedFails = true
			local got = ask(w, r, p1, "all")
			t.expect(#got).toBe(1)
			t.expect(four(got[1])).toEqual(tup("all", {}, nil, true))
			t.expect(#w.sorted).toBe(2)
			t.expect(w.sorted[1].ascending).toBe(false)
			t.expect(w.sorted[1].size).toBe(10)
			t.expect(w.sorted[2].size).toBe(50)
			t.expect(w.sorted[1].name).toBe("SnakeHiscores")
			t.expect(w.sorted[1].scope).toBe("all")
			-- inside the key's failure window another player is answered from what there is, without a read
			w.now += Hiscores.READ_GAP
			t.expect(four(ask(w, r, p3, "all")[1])).toEqual(tup("all", {}, nil, true))
			t.expect(#w.sorted).toBe(2)
			seed(w)
			w.sortedFails = false
			w.now += Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 1) - Hiscores.READ_GAP
			local healthy = ask(w, r, p1, "all")[1]
			t.expect(four(healthy)).toEqual(tup("all", BOTH, 2, false))
			local reads = #w.sorted
			w.sortedFails = true
			w.now += 2
			t.expect(four(ask(w, r, p3, "all")[1])).toEqual(tup("all", BOTH, nil, false))
			t.expect(#w.sorted).toBe(reads)
			w.now += Hiscores.CACHE_TTL
			local failedAgain = ask(w, r, p1, "all")
			t.expect(#failedAgain).toBe(1)
			t.expect(four(failedAgain[1])).toEqual(tup("all", BOTH, 2, true))
			-- inside that failure window the board the server holds is the answer, never an empty one, and nothing is read
			reads = #w.sorted
			w.now += 1
			t.expect(four(ask(w, r, p2, "all")[1])).toEqual(tup("all", BOTH, 1, true))
			t.expect(four(ask(w, r, p3, "all")[1])).toEqual(tup("all", BOTH, nil, true))
			t.expect(four(ask(w, r, p1, "all")[1])).toEqual(tup("all", BOTH, 2, true))
			t.expect(#w.sorted).toBe(reads)
			t.expect(w.errors).toEqual({})
		end
	)

	-- from f0026/adapters :578
	it(
		"AC4: a request that arrives while the read is under way does not read again, and each gets one answer",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			seed(w)
			local r = remote()
			snake.serve(r.stub)
			local p1, p2, p9 = player(1), player(2), player(9)
			w.holdSorted = true
			ask(w, r, p1, "all")
			ask(w, r, p2, "all")
			ask(w, r, p9, "all")
			t.expect(#w.sorted).toBe(1)
			t.expect(#r.fired).toBe(0)
			w.holdSorted = false
			release(w)
			t.expect(#w.sorted).toBe(1)
			t.expect(#answers(r, p1)).toBe(1)
			t.expect(#answers(r, p2)).toBe(1)
			t.expect(#answers(r, p9)).toBe(1)
			t.expect(#r.fired).toBe(3)
			t.expect(four(answers(r, p1)[1])).toEqual(tup("all", BOTH, 2, false))
			t.expect(four(answers(r, p2)[1])).toEqual(tup("all", BOTH, 1, false))
			t.expect(four(answers(r, p9)[1])).toEqual(tup("all", BOTH, nil, false))
			t.expect(w.errors).toEqual({})
		end
	)

	-- from f0026/adapters :605
	it(
		"AC4: during an outage a client asking every second costs three reads of the board in ten seconds",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			local r = remote()
			snake.serve(r.stub)
			local p1 = player(1)
			w.sortedFails = true
			for _ = 0, 10 do
				ask(w, r, p1, "all")
				w.now += 1
			end
			-- reads at 0, 2 and 6 s (failure waits of 2, 4, then 8 s), each at page sizes 10 and 50
			t.expect(#w.sorted).toBe(6)
			t.expect(#answers(r, p1)).toBe(11)
			for _, answer in answers(r, p1) do
				t.expect(answer[5]).toBe(true)
			end
			seed(w)
			w.sortedFails = false
			w.now = FRI + 14
			ask(w, r, p1, "all")
			t.expect(#w.sorted).toBe(7)
			t.expect(answers(r, p1)[12][5]).toBe(false)
		end
	)

	-- from f0026/adapters :630 (the adapter tries the page twice, so the store open must fail on both tries)
	it(
		"AC4: an error anywhere in the read, opening the store included, is a failed read and not a wedge",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			seed(w)
			local r = remote()
			snake.serve(r.stub)
			w.openFails = 2
			local p1, p2, p9 = player(1), player(2), player(9)
			t.expect(four(ask(w, r, p1, "all")[1])).toEqual(tup("all", {}, nil, true))
			w.now += 1
			t.expect(four(ask(w, r, p2, "all")[1])).toEqual(tup("all", {}, nil, true))
			w.now += Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 1) - 1
			local healthy = ask(w, r, p9, "all")
			t.expect(#healthy).toBe(1)
			t.expect(healthy[1][5]).toBe(false)
			t.expect(#healthy[1][3]).toBe(2)
			local again = ask(w, r, p2, "all")
			t.expect(again[1][4]).toBe(1)
			t.expect(w.errors).toEqual({})
		end
	)

	-- from f0026/adapters :653
	it(
		"AC4: a companion row that cannot be read fails the read: no short board is answered as healthy",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			seed(w)
			local r = remote()
			snake.serve(r.stub)
			w.failGet["SnakeHiscoreEntries:2"] = true
			local p1 = player(1)
			t.expect(four(ask(w, r, p1, "all")[1])).toEqual(tup("all", {}, nil, true))
			w.failGet["SnakeHiscoreEntries:2"] = nil
			w.now += Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 1)
			local answer = ask(w, r, p1, "all")[1]
			t.expect(answer[5]).toBe(false)
			t.expect(#answer[3]).toBe(2)
			t.expect(answer[4]).toBe(2)
			-- a companion that is simply absent is skipped, and the board is healthy
			local v = world()
			local snakeV = v.Boards.open("Snake")
			seed(v)
			companion(v, "all")["2"] = nil
			local rv = remote()
			snakeV.serve(rv.stub)
			t.expect(four(ask(v, rv, p1, "all")[1]))
				.toEqual(tup("all", { { rank = 1, name = "Ada", score = 50, level = 2, revives = 1 } }, 1, false))
		end
	)

	-- from f0026/adapters :680 (its source pins on per-player state become what the adapter does)
	it(
		"AC4: a waiter who left before the read returned gets no answer, and nothing outlives the visitor",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			seed(w)
			local r = remote()
			snake.serve(r.stub)
			local p1, p2 = player(1), player(2)
			w.holdSorted = true
			ask(w, r, p1, "all")
			ask(w, r, p2, "all")
			leave(w, p2)
			w.holdSorted = false
			release(w)
			t.expect(#answers(r, p1)).toBe(1)
			t.expect(#answers(r, p2)).toBe(0)
			t.expect(#r.fired).toBe(1)
			-- the one who left is forgotten: coming back, their best is read again
			local entries = slot(w, "companion", "SnakeHiscoreEntries", "all")
			local before = count(w, "get:SnakeHiscoreEntries:2")
			local back = ask(w, r, player(2), "all")
			t.expect(#back).toBe(1)
			t.expect(back[1][7]).toBe(nil)
			t.expect(count(w, "get:SnakeHiscoreEntries:2")).toBe(before + 1)
			t.expect(entries.data["2"].score).toBe(80)
			t.expect(w.errors).toEqual({})
		end
	)

	-- from f0026/adapters :700
	it("AC4: one player asking all and then day in the same second gets both boards, healthy", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seed(w)
		ordered(w, DAY)["2:2026-10-16"] = Hiscores.pack(80, 3)
		companion(w, DAY)["2:2026-10-16"] = { name = "Bea", userId = "2", level = 3, score = 80, revives = 2 }
		local r = remote()
		snake.serve(r.stub)
		local p2 = player(2)
		ask(w, r, p2, "all")
		ask(w, r, p2, "day")
		t.expect(#w.sorted).toBe(2)
		t.expect(answers(r, p2)[1][5]).toBe(false)
		t.expect(four(answers(r, p2)[2]))
			.toEqual(tup("day", { { rank = 1, name = "Bea", score = 80, level = 3, revives = 2 } }, 1, false))
		t.expect(table.find(w.opens, `companion|SnakeHiscoreEntries|{DAY}`) ~= nil).toBe(true)
		t.expect(table.find(w.opens, `ordered|SnakeHiscores|{DAY}`) ~= nil).toBe(true)
	end)

	-- from f0026/adapters :720
	it(
		"AC4: the board read opens the ordered and the companion store under the title's names and the scope",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			seed(w)
			local r = remote()
			snake.serve(r.stub)
			ask(w, r, player(1), "all")
			local companions, ordereds = 0, 0
			for _, open in w.opens do
				if string.sub(open, 1, 9) == "companion" then
					companions += 1
					-- the per-player rows, and the title's list of runs
					t.expect(
						open == "companion|SnakeHiscoreEntries|all" or open == "companion|SnakeHiscoreTop|all"
					)
						.toBe(true)
				else
					ordereds += 1
					t.expect(open).toBe("ordered|SnakeHiscores|all")
				end
			end
			t.expect(companions >= 1).toBe(true)
			t.expect(ordereds >= 1).toBe(true)
			t.expect(table.find(w.opens, "companion|SnakeHiscoreEntries|all") ~= nil).toBe(true)
			t.expect(table.find(w.opens, "companion|SnakeHiscoreTop|all") ~= nil).toBe(true)
			local name, scope =
				Hiscores.storeTarget(snake.names, "companion", Hiscores.board("all", FRI), true)
			t.expect(`companion|{name}|{scope}`).toBe("companion|SnakeHiscoreEntries|all")
		end
	)

	-- from f0026/adapters :747
	it(
		"AC4: a page of 50 after the size-10 fallback is cut to the top N before any companion is read",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			for i = 1, 30 do
				local id = tostring(100 + i)
				seedBest(w, id, `P{i}`, 1000 - i, 1, i)
			end
			w.sortedFailsAt = 10
			local r = remote()
			snake.serve(r.stub)
			local p1 = player(1)
			local got = ask(w, r, p1, "all")
			t.expect(#w.sorted).toBe(2)
			t.expect(w.sorted[2].size).toBe(50)
			-- only the reads of the board's thirty row keys are counted
			local rowReads = 0
			for _, line in w.log do
				local n = tonumber(string.match(line, "^get:SnakeHiscoreEntries:(%d+)$"))
				if n ~= nil and n >= 101 and n <= 130 then
					rowReads += 1
				end
			end
			t.expect(rowReads > 0 and rowReads <= Hiscores.N).toBe(true)
			local _, _, rows, _, failed = values(got[1])
			t.expect(failed).toBe(false)
			t.expect(#rows).toBe(Hiscores.N)
			t.expect(rows[1].score).toBe(999)
			t.expect(rows[1].revives).toBe(1)
		end
	)

	-- from f0026/adapters :776
	it("AC4: a healthy empty board is an answer, not a failure", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		local r = remote()
		snake.serve(r.stub)
		local p1 = player(1)
		local got = ask(w, r, p1, "day")
		t.expect(#got).toBe(1)
		local to, id, rows, rank, failed, best = values(got[1])
		t.expect(to).toBe(p1)
		t.expect(id).toBe("day")
		t.expect(rows).toEqual({})
		t.expect(rank).toBe(nil)
		t.expect(failed).toBe(false)
		t.expect(best).toBe(nil)
		t.expect(w.sorted[1].scope).toBe(DAY)
	end)

	-- from d0124/adapters :446 (the read half: both runs of one player are listed; the writes are in write.spec)
	it("AC4: the all-time answer lists both runs of one player, each with its revives", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		snake.submit("7", "Ada", 80, 3, 2, 1)
		w.now += 120
		snake.submit("7", "Ada", 50, 2, 0, 2)
		local r = remote()
		snake.serve(r.stub)
		local _, id, rows, rank, failed, best = values(ask(w, r, player(7), "all")[1])
		t.expect(id).toBe("all")
		t.expect(rows).toEqual({
			{ rank = 1, name = "Ada", score = 80, level = 3, revives = 2 },
			{ rank = 2, name = "Ada", score = 50, level = 2, revives = 0 },
		})
		t.expect(rank).toBe(1)
		t.expect(failed).toBe(false)
		t.expect(best).toEqual({ score = 80, level = 3, revives = 2 })
	end)

	-- from d0124/adapters :612
	it("AC4: the all-time answer is the stored list with the asker's own best", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seedBest(w, "7", "Ada", 80, 3, 2)
		setList(
			w,
			{ stored("2", 60, 1, FRI, 1, 0), stored("7", 50, 2, FRI, 2, 1), stored("7", 80, 3, FRI, 1, 2) }
		)
		local r = remote()
		snake.serve(r.stub)
		local got = ask(w, r, player(7), "all")[1]
		t.expect(got.n).toBe(6)
		local _, id, rows, rank, failed, best = values(got)
		t.expect(id).toBe("all")
		t.expect(rows).toEqual({
			{ rank = 1, name = "P7", score = 80, level = 3, revives = 2 },
			{ rank = 2, name = "P2", score = 60, level = 1, revives = 0 },
			{ rank = 3, name = "P7", score = 50, level = 2, revives = 1 },
		})
		t.expect(rank).toBe(1)
		t.expect(failed).toBe(false)
		t.expect(best).toEqual({ score = 80, level = 3, revives = 2 })
		t.expect(count(w, "sorted:")).toBe(0)
	end)

	-- from d0124/adapters :632
	it("AC4: with no list stored, the all-time answer is the per-player board, as before", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seed(w)
		local r = remote()
		snake.serve(r.stub)
		local _, _, rows, _, failed, best = values(ask(w, r, player(9), "all")[1])
		t.expect(rows).toEqual(BOTH)
		t.expect(failed).toBe(false)
		t.expect(best).toBe(nil)
		t.expect(count(w, "sorted:SnakeHiscores:")).toBe(1)
		t.expect(count(w, "get:SnakeHiscoreTop:runs")).toBe(1)
	end)

	-- from d0124/adapters :646
	it("AC4: a list that cannot be read is a failed all-time read, not the per-player board", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seed(w)
		setList(w, { stored("1", 50, 2, FRI, 1, 1) })
		w.failGet.SnakeHiscoreTop = true
		local r = remote()
		snake.serve(r.stub)
		local _, _, rows, _, failed = values(ask(w, r, player(1), "all")[1])
		t.expect(rows).toEqual({})
		t.expect(failed).toBe(true)
		t.expect(count(w, "sorted:")).toBe(0)
	end)

	-- from d0124/adapters :657
	it("AC4: day and week answers are the per-player boards and carry no best", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seedBest(w, "7", "Ada", 80, 3, 2)
		snake.submit("7", "Ada", 60, 2, 1, 1)
		local r = remote()
		snake.serve(r.stub)
		table.clear(w.log)
		for _, id in { "day", "week" } do
			local _, said, rows, rank, _, best = values(ask(w, r, player(7), id)[1])
			t.expect(said).toBe(id)
			t.expect(rows).toEqual({ { rank = 1, name = "Ada", score = 60, level = 2, revives = 1 } })
			t.expect(rank).toBe(1)
			t.expect(best).toBe(nil)
		end
		t.expect(count(w, "get:SnakeHiscoreTop")).toBe(0)
		t.expect(table.find(w.log, "get:SnakeHiscoreEntries:7")).toBe(nil)
	end)

	-- from d0124/adapters :673
	it("AC4: after an all-time answer, the same player's day and week answers still carry no best", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seedBest(w, "7", "Ada", 80, 3, 2)
		snake.submit("7", "Ada", 60, 2, 1, 1)
		local r = remote()
		snake.serve(r.stub)
		local who = player(7)
		t.expect(select(6, values(ask(w, r, who, "all")[1]))).toEqual({ score = 80, level = 3, revives = 2 })
		t.expect(select(6, values(ask(w, r, who, "day")[1]))).toBe(nil)
		t.expect(select(6, values(ask(w, r, who, "week")[1]))).toBe(nil)
	end)

	-- from d0124/adapters :682
	it("AC4: a player's best is read at most once per CACHE_TTL, and again after they leave", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seedBest(w, "7", "Ada", 80, 3, 2)
		-- a stored list, so the board's own read never reads player 7's row
		setList(w, { stored("2", 60, 1, FRI, 1, 0) })
		local r = remote()
		snake.serve(r.stub)
		local ada = player(7)
		local function bestOf(who: any): any
			return select(6, values(ask(w, r, who, "all")[1]))
		end
		local function reads(): number
			return count(w, "get:SnakeHiscoreEntries:7") - count(w, "get:SnakeHiscoreEntries:7:")
		end
		bestOf(ada)
		w.now += Hiscores.CACHE_TTL - 1
		bestOf(ada)
		t.expect(reads()).toBe(1)
		w.now += 1
		seedBest(w, "7", "Ada", 90, 4, 0)
		t.expect(bestOf(ada)).toEqual({ score = 90, level = 4, revives = 0 })
		t.expect(reads()).toBe(2)
		seedBest(w, "7", "Ada", 95, 4, 1)
		leave(w, ada)
		t.expect(bestOf(player(7))).toEqual({ score = 95, level = 4, revives = 1 })
		t.expect(reads()).toBe(3)
		-- another player's best is their own
		seedBest(w, "8", "Cy", 10, 1, 0)
		t.expect(bestOf(player(8))).toEqual({ score = 10, level = 1, revives = 0 })
	end)

	-- from d0124/adapters :704
	it(
		"AC4: requests while a player's best is being read do not read it again, and each is answered",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			seedBest(w, "7", "Ada", 80, 3, 2)
			setList(w, { stored("2", 60, 1, FRI, 1, 0) })
			local r = remote()
			snake.serve(r.stub)
			local ada = player(7)
			w.holdGet["SnakeHiscoreEntries:7"] = true
			for _ = 1, 5 do
				ask(w, r, ada, "all")
			end
			t.expect(count(w, "get:SnakeHiscoreEntries:7")).toBe(1)
			t.expect(#r.fired).toBe(4)
			w.holdGet["SnakeHiscoreEntries:7"] = nil
			release(w)
			t.expect(#r.fired).toBe(5)
			t.expect(select(6, values(r.fired[5]))).toEqual({ score = 80, level = 3, revives = 2 })
			ask(w, r, ada, "all")
			t.expect(count(w, "get:SnakeHiscoreEntries:7")).toBe(1)
			t.expect(w.errors).toEqual({})
		end
	)

	-- from d0124/adapters :722
	it("AC4: while a stale best is read again, requests are answered with the best held before", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seedBest(w, "7", "Ada", 80, 3, 2)
		setList(w, { stored("2", 60, 1, FRI, 1, 0) })
		local r = remote()
		snake.serve(r.stub)
		local ada = player(7)
		ask(w, r, ada, "all")
		w.now += Hiscores.CACHE_TTL
		w.holdGet["SnakeHiscoreEntries:7"] = true
		ask(w, r, ada, "all")
		ask(w, r, ada, "all")
		local during = r.fired[#r.fired]
		t.expect(select(6, values(during))).toEqual({ score = 80, level = 3, revives = 2 })
		w.holdGet["SnakeHiscoreEntries:7"] = nil
		release(w)
	end)

	-- from d0124/adapters :736
	it("AC4: a best read that ends after the player left is dropped, and a rejoin reads again", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seedBest(w, "7", "Ada", 80, 3, 2)
		setList(w, { stored("2", 60, 1, FRI, 1, 0) })
		local r = remote()
		snake.serve(r.stub)
		local ada = player(7)
		w.holdGet["SnakeHiscoreEntries:7"] = true
		ask(w, r, ada, "all")
		leave(w, ada)
		w.holdGet["SnakeHiscoreEntries:7"] = nil
		release(w)
		seedBest(w, "7", "Ada", 95, 4, 1)
		w.now += 1
		t.expect(select(6, values(ask(w, r, player(7), "all")[1])))
			.toEqual({ score = 95, level = 4, revives = 1 })
		t.expect(count(w, "get:SnakeHiscoreEntries:7")).toBe(2)
		t.expect(w.errors).toEqual({})
	end)

	-- the same, where the engine has emptied the player's Parent but not yet told PlayerRemoving
	it("AC4: a best read that ends once the player's Parent is empty is not kept for anyone", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seedBest(w, "7", "Ada", 80, 3, 2)
		setList(w, { stored("2", 60, 1, FRI, 1, 0) })
		local r = remote()
		snake.serve(r.stub)
		local ada = player(7)
		w.holdGet["SnakeHiscoreEntries:7"] = true
		ask(w, r, ada, "all")
		ada.Parent = nil
		w.holdGet["SnakeHiscoreEntries:7"] = nil
		release(w)
		t.expect(select(6, values(ask(w, r, player(7), "all")[1]))).toBe(nil)
		t.expect(w.errors).toEqual({})
	end)

	-- from d0124/adapters :751
	it("AC4: a best that cannot be read again is no best: the stale one is not kept", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seedBest(w, "7", "Ada", 80, 3, 2)
		setList(w, { stored("7", 80, 3, FRI, 1, 2) })
		local r = remote()
		snake.serve(r.stub)
		local ada = player(7)
		t.expect(select(6, values(ask(w, r, ada, "all")[1]))).toEqual({ score = 80, level = 3, revives = 2 })
		w.now += Hiscores.CACHE_TTL
		w.failGet["SnakeHiscoreEntries:7"] = true
		local _, _, _, _, failed, best = values(ask(w, r, ada, "all")[1])
		t.expect(failed).toBe(false)
		t.expect(best).toBe(nil)
	end)

	-- from d0124/adapters :763
	it("AC4: a best that cannot be read is no best, and the board still answers", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		seedBest(w, "7", "Ada", 80, 3, 2)
		w.failGet["SnakeHiscoreEntries:7"] = true
		setList(w, { stored("7", 80, 3, FRI, 1, 2) })
		local r = remote()
		snake.serve(r.stub)
		local _, _, rows, _, failed, best = values(ask(w, r, player(7), "all")[1])
		t.expect(failed).toBe(false)
		t.expect(#rows).toBe(1)
		t.expect(best).toBe(nil)
	end)

	-- from f0026/adapters :525 and :630: two titles in one place never share a failure, a read or a held best
	it("AC4: one title's failed read does not fail another title's board", function()
		local w = world()
		local snake, invaders = w.Boards.open("Snake"), w.Boards.open("Invaders")
		seed(w)
		data(w, "ordered", "InvadersHiscores", "all")["5"] = Hiscores.pack(70, 2)
		data(w, "companion", "InvadersHiscoreEntries", "all")["5"] =
			{ name = "Cy", userId = "5", score = 70, level = 2, revives = 4 }
		local rs, ri = remote(), remote()
		snake.serve(rs.stub)
		invaders.serve(ri.stub)
		w.sortedFails = true
		t.expect(four(ask(w, rs, player(1), "all")[1])).toEqual(tup("all", {}, nil, true))
		w.sortedFails = false
		local _, _, rows, _, failed = values(ask(w, ri, player(5), "all")[1])
		t.expect(failed).toBe(false)
		t.expect(rows).toEqual({ { rank = 1, name = "Cy", score = 70, level = 2, revives = 4 } })
	end)
end)
