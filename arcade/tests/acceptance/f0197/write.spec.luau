--!strict
-- f0197 AC4: the generic server adapter's WRITES, `src/server/Boards.luau` through `Boards.open(prefix)`: `submit`
-- stores a finished run (with its revives) on the day, week and all-time boards and the top-N list of runs of that
-- title's stores only, `pending` counts the writes still running, and `listen` hears each run's place. The cases are
-- ported from pickman's HiscoreStore specs (f0024/adapter and the write cases of d0124/adapters), whose server-side
-- behaviour the merged adapter must keep, so that no wrong adapter passes only because those specs were left behind.
-- The adapter's real source runs on a stub `game` of this spec's own: a DataStoreService that copies what it stores
-- and returns, that can fail a read, a write, a page size or the budget query, and that logs every budget request,
-- store open and call in order; a task.spawn that can be held; a clock the case sets. The file is absent until the
-- raft builds it, so this fails on the missing file.
local Hiscores = require("@logic/Hiscores")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local t = require("@tests/lib/t")

local ADAPTER = "src/server/Boards.luau"
local LOGIC_ROOT = "@game/ReplicatedStorage/Arcade/Logic/"
local FRI = 1792108800 -- 2026-10-16, a Friday: day "day:2026-10-16", week "week:2026-10-12"
local JOB = "job-1"
local DAY = "day:2026-10-16"
local WEEK = "week:2026-10-12"

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

-- run the oldest function a held task.spawn kept
local function runNext(w: World)
	local fn = table.remove(w.spawned, 1) :: () -> ()
	fn()
end

local function data(w: World, kind: string, name: string, scope: string): { [string]: any }
	return slot(w, kind, name, scope).data
end

local function names(w: World): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, s in w.stores do
		if next(s.data) ~= nil and not seen[s.name] then
			seen[s.name] = true
			table.insert(out, s.name)
		end
	end
	table.sort(out)
	return out
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

local function list(w: World): { any }
	return (data(w, "companion", "SnakeHiscoreTop", Hiscores.TOP_SCOPE) :: any)[Hiscores.TOP_KEY]
end

local function scores(entries: { any }): { string }
	local out: { string } = {}
	for _, e in entries do
		table.insert(out, `{e.userId}={e.score}`)
	end
	return out
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

-- the Snake handle with its listener recording (userId, run, rank, missed) into `heard`
local function snakeWith(w: World): (any, { { any } })
	local snake = w.Boards.open("Snake")
	local heard: { { any } } = {}
	snake.listen(function(userId: string, run: number, rank: number?, missed: number?)
		table.insert(heard, { userId, run, rank, missed } :: { any })
	end)
	return snake, heard
end

return t.spec("f0197 Boards writes", function(it)
	-- from f0024/adapter :239
	it("AC4: two submits for one user id and run both drive, and the better one is stored", function()
		local w = world()
		local snake, heard = snakeWith(w)
		snake.submit("7", "Ada", 50, 2, 0, 1)
		snake.submit("7", "Ada", 80, 3, 1, 1)
		t.expect(ordered(w, "all")["7"]).toBe(Hiscores.pack(80, 3))
		t.expect(companion(w, "all")["7"].score).toBe(80)
		t.expect(companion(w, "all")["7"].revives).toBe(1)
		t.expect(ordered(w, DAY)["7:2026-10-16"]).toBe(Hiscores.pack(80, 3))
		t.expect(ordered(w, WEEK)["7:2026-10-12"]).toBe(Hiscores.pack(80, 3))
		t.expect(#heard).toBe(2)
		t.expect(heard[2]).toEqual({ "7", 1, 1, nil } :: { any })
		t.expect(w.warnings).toBe(0)
	end)

	-- from f0024/adapter :252
	it("AC4: the ordered write is the max: a higher value already stored stays", function()
		local w = world()
		local snake = snakeWith(w)
		snake.submit("9", "Old", 1, 1, 0, 1)
		-- another server's better run reached the ordered key first; its companion is not here yet
		ordered(w, "all")["7"] = Hiscores.pack(8000, 1)
		snake.submit("7", "Ada", 5000, 2, 1, 1)
		t.expect(companion(w, "all")["7"].score).toBe(5000)
		t.expect(ordered(w, "all")["7"]).toBe(Hiscores.pack(8000, 1))
		t.expect(ordered(w, DAY)["7:2026-10-16"]).toBe(Hiscores.pack(5000, 2))
	end)

	-- from f0024/adapter :263
	it("AC4: a lower submit rewrites neither the row nor the ordered key", function()
		local w = world()
		local snake = snakeWith(w)
		snake.submit("7", "Ada", 50, 2, 1, 1)
		snake.submit("7", "Nope", 10, 9, 2, 2)
		t.expect(companion(w, "all")["7"].name).toBe("Ada")
		t.expect(companion(w, "all")["7"].score).toBe(50)
		t.expect(companion(w, "all")["7"].revives).toBe(1)
		t.expect(ordered(w, "all")["7"]).toBe(Hiscores.pack(50, 2))
	end)

	-- from f0024/adapter :272 (the stores are the title's, scoped by period; budgets are the modern request types)
	it(
		"AC4: a title's stores are its own names scoped by period, and budgets are the modern types",
		function()
			local w = world()
			local snake = snakeWith(w)
			snake.submit("7", "Ada", 50, 2, 1, 1)
			local opened: { string } = {}
			for _, s in w.stores do
				table.insert(opened, `{s.name}|{s.scope}`)
			end
			table.sort(opened)
			t.expect(opened).toEqual({
				"SnakeHiscoreEntries|all",
				`SnakeHiscoreEntries|{DAY}`,
				`SnakeHiscoreEntries|{WEEK}`,
				"SnakeHiscoreTop|all",
				"SnakeHiscores|all",
				`SnakeHiscores|{DAY}`,
				`SnakeHiscores|{WEEK}`,
			})
			local kinds: { [string]: boolean } = {}
			for _, line in w.log do
				local kind = string.match(line, "^budget:(.+)$")
				if kind then
					kinds[kind] = true
				end
			end
			t.expect(kinds).toEqual({
				["DataStoreRequestType.StandardRead"] = true,
				["DataStoreRequestType.StandardWrite"] = true,
				["DataStoreRequestType.OrderedRead"] = true,
				["DataStoreRequestType.OrderedWrite"] = true,
			})
		end
	)

	-- from f0024/adapter :307: each update is preceded by the read and write budgets of its own store
	it("AC4: each update is preceded by the read and write budgets of its own store", function()
		local w = world()
		local snake = snakeWith(w)
		snake.submit("7", "Ada", 50, 2, 1, 1)
		local since: { [string]: boolean } = {}
		local companions, ordereds = 0, 0
		for _, entry in w.log do
			local kind = string.match(entry, "^budget:(.+)$")
			if kind then
				since[kind] = true
			elseif string.sub(entry, 1, #"update:ordered:") == "update:ordered:" then
				ordereds += 1
				t.expect(since["DataStoreRequestType.OrderedRead"]).toBe(true)
				t.expect(since["DataStoreRequestType.OrderedWrite"]).toBe(true)
				since = {}
			elseif string.sub(entry, 1, #"update:companion:") == "update:companion:" then
				companions += 1
				t.expect(since["DataStoreRequestType.StandardRead"]).toBe(true)
				t.expect(since["DataStoreRequestType.StandardWrite"]).toBe(true)
				since = {}
			end
		end
		-- three boards, each a row and an ordered integer, and then the list of runs
		t.expect(ordereds).toBe(3)
		t.expect(companions).toBe(4)
		-- the first board's two updates, in the order and with the exact budgets drive asks
		t.expect({ table.unpack(w.log, 1, 6) }).toEqual({
			"budget:DataStoreRequestType.StandardRead",
			"budget:DataStoreRequestType.StandardWrite",
			"update:companion:SnakeHiscoreEntries",
			"budget:DataStoreRequestType.OrderedRead",
			"budget:DataStoreRequestType.OrderedWrite",
			"update:ordered:SnakeHiscores",
		})
	end)

	-- from f0024/adapter :334
	it("AC4: a submit is pending from the call until its drive ends, also when the drive fails", function()
		local w = world()
		local snake, asteroids = snakeWith(w), w.Boards.open("Asteroids")
		t.expect(snake.pending()).toBe(0)
		w.hold = true
		snake.submit("7", "Ada", 50, 2, 1, 1)
		snake.submit("8", "Bea", 40, 1, 0, 1)
		t.expect(snake.pending()).toBe(2)
		t.expect(asteroids.pending()).toBe(0)
		runNext(w)
		t.expect(snake.pending()).toBe(1)
		w.budgetFails = true
		runNext(w)
		t.expect(snake.pending()).toBe(0)
		t.expect(w.warnings).toBe(1)
	end)

	-- the thread for a write cannot start: the submit is not pending, and says so (no counterpart in pickman's specs)
	it("AC4: a submit whose write cannot start is not left pending, and warns once", function()
		local w = world()
		local snake = snakeWith(w)
		w.spawnFails = true
		snake.submit("7", "Ada", 50, 2, 1, 1)
		t.expect(snake.pending()).toBe(0)
		t.expect(w.warnings).toBe(1)
		t.expect(names(w)).toEqual({})
	end)

	-- from f0024/adapter :350
	it(
		"AC4: a page size of 10 that the store rejects is tried once at 50, cut to N, and the rank comes",
		function()
			local w = world()
			local snake, heard = snakeWith(w)
			for i = 1, 30 do
				snake.submit(tostring(100 + i), `P{i}`, 1000 + i, 1, 0, 1)
			end
			w.sortedFailsAt = 10
			table.clear(w.sorted)
			table.clear(heard)
			table.clear(w.log)
			snake.submit("7", "Ada", 5000, 2, 1, 1)
			local sizes: { number } = {}
			for _, read in w.sorted do
				table.insert(sizes, read.size)
			end
			t.expect(sizes).toEqual({ 10, 50 })
			-- the companions read for the board's rows are cut to the top N
			t.expect(count(w, "get:SnakeHiscoreEntries:") <= Hiscores.N).toBe(true)
			t.expect(heard).toEqual({ { "7", 1, 1, nil } :: { any } })
		end
	)

	-- from f0024/adapter :367
	it("AC4: no rank is heard when the board cannot be read, and the write still happens", function()
		local w = world()
		local snake, heard = snakeWith(w)
		w.sortedFails = true
		snake.submit("7", "Ada", 50, 2, 1, 1)
		t.expect(ordered(w, "all")["7"]).toBe(Hiscores.pack(50, 2))
		t.expect(companion(w, "all")["7"].revives).toBe(1)
		t.expect(#heard).toBe(0)
	end)

	-- a run the library refuses (no counterpart in pickman's specs): nothing is written, and the submit says so
	it(
		"AC4: a run with no progress or a bad revives count writes nothing, warns, and is not pending",
		function()
			local w = world()
			local snake, heard = snakeWith(w)
			snake.submit("7", "Ada", 50, 0, 0, 1)
			snake.submit("7", "Ada", 50, 2, -1, 2)
			snake.submit("7", "Ada", 50, 2, 1.5, 3)
			t.expect(names(w)).toEqual({})
			t.expect(#heard).toBe(0)
			t.expect(snake.pending()).toBe(0)
			t.expect(w.warnings).toBe(3)
		end
	)

	-- from d0124/adapters :446 (the write half; the lobby's answer is checked here too)
	it(
		"AC4: one player's two runs in a row, the second lower, are places 1 and 2 and both are listed",
		function()
			local w = world()
			local snake, heard = snakeWith(w)
			snake.submit("7", "Ada", 80, 3, 2, 1)
			w.now += 120
			snake.submit("7", "Ada", 50, 2, 0, 2)
			t.expect(heard).toEqual({ { "7", 1, 1, nil } :: { any }, { "7", 2, 2, nil } :: { any } })
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
			-- the per-player best stays the better run
			t.expect(companion(w, "all")["7"].score).toBe(80)
			t.expect(ordered(w, "all")["7"]).toBe(Hiscores.pack(80, 3))
			t.expect(w.warnings).toBe(0)
		end
	)

	-- from d0124/adapters :472
	it(
		"AC4: runs of several players fill the list in order, cut to ten, and a later lower run is missed",
		function()
			local w = world()
			local snake, heard = snakeWith(w)
			for i = 1, 12 do
				w.now += 1
				snake.submit(tostring(100 + i), `P{i}`, 1000 + i, 1, i, 1)
			end
			t.expect(#list(w)).toBe(10)
			t.expect(list(w)[1].score).toBe(1012)
			t.expect(list(w)[1].revives).toBe(12)
			t.expect(list(w)[10].score).toBe(1003)
			snake.submit("7", "Ada", 5, 1, 3, 1)
			t.expect(heard[#heard]).toEqual({ "7", 1, nil, Hiscores.N } :: { any })
			t.expect(#list(w)).toBe(10)
			t.expect(companion(w, "all")["7"].score).toBe(5)
			local r = remote()
			snake.serve(r.stub)
			local _, _, rows, rank, _, best = values(ask(w, r, player(7), "all")[1])
			t.expect(#rows).toBe(10)
			t.expect(rank).toBe(nil)
			t.expect(best).toEqual({ score = 5, level = 1, revives = 3 })
		end
	)

	-- from d0124/adapters :495
	it(
		"AC4: a first run with no list starts it from the stored bests, the player's older best included",
		function()
			local w = world()
			local snake, heard = snakeWith(w)
			seedBest(w, "7", "Ada", 900, 4, 1)
			seedBest(w, "2", "Bea", 300, 1, 0)
			snake.submit("7", "Ada", 500, 2, 1, 1)
			t.expect(scores(list(w))).toEqual({ "7=900", "7=500", "2=300" })
			t.expect(list(w)[1].id).toBe("best:7:900:4")
			t.expect(heard).toEqual({ { "7", 1, 2, nil } :: { any } })
			t.expect(companion(w, "all")["7"].score).toBe(900)
		end
	)

	-- from d0124/adapters :509
	it(
		"AC4: the per-player boards are written before the list, and a first run that is a new best is listed once",
		function()
			local w = world()
			local snake = snakeWith(w)
			seedBest(w, "2", "Bea", 300, 1, 0)
			snake.submit("7", "Ada", 950, 2, 1, 1)
			t.expect(scores(list(w))).toEqual({ "7=950", "2=300" })
			local firstTop = table.find(w.log, "update:companion:SnakeHiscoreTop") :: number
			local lastRow = 0
			for i, line in w.log do
				if
					line == "update:companion:SnakeHiscoreEntries"
					or line == "update:ordered:SnakeHiscores"
				then
					lastRow = i
				end
			end
			t.expect(firstTop ~= nil and lastRow > 0 and lastRow < firstTop).toBe(true)
			t.expect(count(w, "update:companion:SnakeHiscoreTop")).toBe(1)
			t.expect(companion(w, "all")["7"].score).toBe(950)
		end
	)

	-- from d0124/adapters :529
	it("AC4: a best written by a build without the list joins the list on anyone's next run", function()
		local w = world()
		local snake, heard = snakeWith(w)
		snake.submit("2", "Bea", 300, 1, 0, 1)
		-- another build, or an old server, writes only the per-player boards
		seedBest(w, "9", "Old", 900, 4, 0)
		w.now += 60
		snake.submit("7", "Ada", 100, 1, 0, 1)
		t.expect(scores(list(w))).toEqual({ "9=900", "2=300", "7=100" })
		t.expect(list(w)[1].id).toBe("best:9:900:4")
		t.expect(heard[2]).toEqual({ "7", 1, 3, nil } :: { any })
	end)

	-- from d0124/adapters :541
	it("AC4: the per-player all-time row a run writes names that run and its instant", function()
		local w = world()
		local snake = snakeWith(w)
		snake.submit("7", "Ada", 60, 2, 1, 3)
		local row = companion(w, "all")["7"]
		t.expect(row.run).toBe(`7:{FRI}:3:{JOB}`)
		t.expect(row.at).toBe(FRI)
		t.expect(list(w)[1].id).toBe(row.run)
	end)

	-- from d0124/adapters :550
	it("AC4: a run whose ordered write fails is listed at its own score by the next run", function()
		local w = world()
		local snake = snakeWith(w)
		snake.submit("2", "Bea", 100, 1, 0, 1)
		w.failUpdate.SnakeHiscores = true
		w.failUpdate.SnakeHiscoreTop = true
		snake.submit("7", "Ada", 600, 3, 1, 1)
		w.failUpdate.SnakeHiscores = false
		w.failUpdate.SnakeHiscoreTop = false
		-- Ada's companion row holds 600 and names her run; her ordered score never landed
		t.expect(ordered(w, "all")["7"]).toBe(nil)
		w.now += 60
		snake.submit("2", "Bea", 50, 1, 0, 2)
		t.expect(scores(list(w))).toEqual({ "2=100", "2=50" })
		-- her next run repairs the ordered key: her row joins with its own score and her run's id
		snake.submit("7", "Ada", 10, 1, 0, 2)
		t.expect(scores(list(w))).toEqual({ "7=600", "2=100", "2=50", "7=10" })
		t.expect(list(w)[1].id).toBe(`7:{FRI}:1:{JOB}`)
		t.expect(list(w)[1].revives).toBe(1)
	end)

	-- from d0124/adapters :569, with revives
	it(
		"AC4: a run's entry is keyed by the user, the server's clock, the run counter and the job id",
		function()
			local w = world()
			local snake = snakeWith(w)
			snake.submit("7", "  Ada  ", 60, 2, 4, 3)
			t.expect(list(w)).toEqual({
				{
					id = `7:{FRI}:3:{JOB}`,
					name = "Ada",
					userId = "7",
					score = 60,
					level = 2,
					revives = 4,
					at = FRI,
				},
			})
		end
	)

	-- from d0124/adapters :577
	it("AC4: the place heard is the run's place on the list, not the player's per-player rank", function()
		local w = world()
		local snake, heard = snakeWith(w)
		local cy = stored("8", 990, 1, FRI - 9, 1, 0)
		seedBest(w, "8", "Cy", 990, 1, 0)
		-- Cy's row was written by that listed run, so it names it
		companion(w, "all")["8"].run = cy.id
		companion(w, "all")["8"].at = cy.at
		setList(w, { cy, stored("8", 980, 1, FRI - 8, 2, 0) })
		snake.submit("7", "Ada", 500, 2, 1, 1)
		-- on the per-player board Ada is second; on the list two of Cy's runs stand above her
		t.expect(heard).toEqual({ { "7", 1, 3, nil } :: { any } })
	end)

	-- from d0124/adapters :590
	it(
		"AC4: a list that cannot be written says nothing, and the per-player boards are still written",
		function()
			local w = world()
			local snake, heard = snakeWith(w)
			w.failUpdate.SnakeHiscoreTop = true
			snake.submit("7", "Ada", 60, 2, 1, 1)
			t.expect(#heard).toBe(0)
			t.expect(companion(w, "all")["7"].score).toBe(60)
			t.expect(ordered(w, DAY)["7:2026-10-16"]).toBe(Hiscores.pack(60, 2))
			t.expect(count(w, "update:companion:SnakeHiscoreTop")).toBe(3)
			t.expect(w.warnings).toBe(0)
			t.expect(snake.pending()).toBe(0)
		end
	)

	-- from d0124/adapters :601
	it("AC4: no list and a per-player board that cannot be read: no list is made, nothing is said", function()
		local w = world()
		local snake, heard = snakeWith(w)
		seedBest(w, "2", "Bea", 300, 1, 0)
		w.failGet["SnakeHiscoreEntries:2"] = true
		snake.submit("7", "Ada", 60, 2, 1, 1)
		t.expect(data(w, "companion", "SnakeHiscoreTop", Hiscores.TOP_SCOPE)[Hiscores.TOP_KEY]).toBe(nil)
		t.expect(#heard).toBe(0)
		t.expect(companion(w, "all")["7"].score).toBe(60)
	end)

	-- from f0024/adapter :239 / :272 and the f0197 split: a run belongs to the title that wrote it
	it("AC4: a run is written to its own title's stores only, and a title's pending is its own", function()
		local w = world()
		local snake = snakeWith(w)
		local invaders = w.Boards.open("Invaders")
		w.hold = true
		invaders.submit("8", "Bea", 40, 2, 3, 1)
		t.expect(snake.pending()).toBe(0)
		t.expect(invaders.pending()).toBe(1)
		runNext(w)
		t.expect(names(w)).toEqual({ "InvadersHiscoreEntries", "InvadersHiscoreTop", "InvadersHiscores" })
		t.expect(data(w, "companion", "InvadersHiscoreEntries", "all")["8"].revives).toBe(3)
	end)
end)
