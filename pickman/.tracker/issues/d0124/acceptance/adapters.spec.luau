--!strict
-- d0124 AC3, AC4 (adapter part), AC5 (adapter part) and AC6: the adapters' real sources on this spec's own stub
-- engine. One stub DataStoreService serves the game server (HiscoreStore) and the lobby (Boards), so a run written
-- by one is read back by the other. The stub copies every value it stores or returns, as the engine serializes,
-- and an UpdateAsync whose transform returns nil changes nothing.
local Flow = require("@logic/Flow")
local Hiscores = require("@logic/Hiscores")
local Lobby = require("@logic/Lobby")
local Travel = require("@logic/Travel")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local t = require("@tests/lib/t")

local H = Hiscores :: any
local LOGIC = "@game/ReplicatedStorage/Shared/Logic/"
local FRI = 1792108800
local JOB = "job-1"

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

-- A small instance model ----------------------------------------------------------------------------------------

type Signal = { fns: { (...any) -> () }, Connect: (any, (...any) -> ()) -> any, fire: (any, ...any) -> () }

local function signal(): Signal
	local s: Signal
	s = {
		fns = {},
		Connect = function(_: any, fn: (...any) -> ()): any
			table.insert(s.fns, fn)
			return { Disconnect = function() end }
		end,
		fire = function(_: any, ...: any)
			for _, fn in s.fns do
				local ok, err = coroutine.resume(coroutine.create(fn), ...)
				if not ok then
					error(err, 0)
				end
			end
		end,
	}
	return s
end

local raws: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
local methods: { [string]: any } = {}

local function node(className: string, name: string?): any
	local raw: { [string]: any } = { ClassName = className, Name = name or className, children = {} }
	local proxy: any = {}
	setmetatable(proxy, {
		__index = function(_: any, key: string): any
			local v = raw[key]
			if v ~= nil then
				return v
			end
			local m = methods[key]
			if m ~= nil then
				return m
			end
			return methods.FindFirstChild(proxy, key)
		end,
		__newindex = function(_: any, key: string, value: any)
			if key == "Parent" then
				local old = raw.Parent
				if old ~= nil then
					local siblings = raws[old].children
					local at = table.find(siblings, proxy)
					if at then
						table.remove(siblings, at)
					end
				end
				raw.Parent = value
				if value ~= nil then
					table.insert(raws[value].children, proxy)
				end
			else
				raw[key] = value
			end
		end,
	})
	raws[proxy] = raw
	if className == "RemoteEvent" then
		raw.OnServerEvent = signal()
		raw.OnClientEvent = signal()
		raw.toClient = {}
		raw.toServer = {}
		raw.FireClient = function(self: any, player: any, ...: any)
			table.insert(raws[self].toClient, { player = player, args = table.pack(...) })
		end
		raw.FireServer = function(self: any, ...: any)
			table.insert(raws[self].toServer, { ... })
		end
	elseif className == "TextButton" then
		raw.Activated = signal()
	end
	return proxy
end

function methods.FindFirstChild(self: any, name: string): any
	for _, c in raws[self].children do
		if c.Name == name then
			return c
		end
	end
	return nil
end

function methods.WaitForChild(self: any, name: string): any
	local found = methods.FindFirstChild(self, name)
	assert(found ~= nil, `stub: {raws[self].Name}:WaitForChild("{name}") would wait for ever`)
	return found
end

function methods.GetDescendants(self: any): { any }
	local out: { any } = {}
	local function walk(n: any)
		for _, c in raws[n].children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

local function child(parent: any, className: string, name: string): any
	local n = node(className, name)
	n.Parent = parent
	return n
end

local function proxyEnum(): any
	return setmetatable({}, {
		__index = function(_: any, group: string): any
			return setmetatable({}, {
				__index = function(_: any, item: string): string
					return `{group}.{item}`
				end,
			})
		end,
	})
end

local function env(services: { [string]: any }, modules: { [string]: any }, extra: { [string]: any }?): any
	local e: { [string]: any } = {
		game = {
			GetService = function(_: any, name: string): any
				local found = services[name]
				assert(found ~= nil, `stub: game:GetService("{name}") is not modelled`)
				return found
			end,
			BindToClose = function() end,
		},
		require = function(spec: string): any
			local found = modules[spec]
			assert(found ~= nil, `stub: no module for {spec}`)
			return found
		end,
		Instance = {
			new = function(className: string): any
				return node(className)
			end,
		},
		Enum = proxyEnum(),
		UDim2 = {
			new = function(xs: number, xo: number, ys: number, yo: number): any
				return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
			end,
			fromScale = function(x: number, y: number): any
				return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } }
			end,
			fromOffset = function(x: number, y: number): any
				return { X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } }
			end,
		},
		Vector2 = {
			new = function(x: number, y: number): any
				return { X = x, Y = y }
			end,
		},
		Color3 = {
			new = function(r: number, g: number, b: number): any
				return { R = r, G = g, B = b }
			end,
			fromRGB = function(r: number, g: number, b: number): any
				return { R = r / 255, G = g / 255, B = b / 255 }
			end,
		},
	}
	for k, v in (extra or {}) :: { [string]: any } do
		e[k] = v
	end
	return e
end

local function load(path: string, e: any): any
	return luau.load(fs.readFile(path), { environment = e, debugName = path })()
end

-- One world: a stub DataStoreService, a clock, the game server's HiscoreStore and the lobby's Boards -------------

type World = {
	now: number,
	data: { [string]: { [string]: any } }, -- "<name>|<scope>" -> key -> value
	log: { string }, -- "update:<name>", "get:<name>:<key>", "sorted:<name>", in call order
	failUpdate: { [string]: boolean }, -- store names whose UpdateAsync throws
	failGet: { [string]: boolean }, -- "<name>" or "<name>:<key>" whose GetAsync throws
	holdGet: { [string]: boolean }, -- "<name>:<key>" whose GetAsync yields until `release`
	held: { thread },
	release: () -> (),
	send: (userId: number, id: string) -> (),
	leave: (userId: number) -> (),
	warnings: number,
	heard: { { any } },
	store: any,
	board: any,
	removing: Signal,
	players: { [number]: any },
	ask: (userId: number, id: string) -> any,
	count: (prefix: string) -> number,
	exactly: (line: string) -> number,
}

local function world(): World
	local w: World
	local function opened(name: string, scope: string?): { [string]: any }
		local at = `{name}|{scope or "global"}`
		w.data[at] = w.data[at] or {}
		return w.data[at]
	end
	local function store(name: string, scope: string?): any
		local data = opened(name, scope)
		return {
			GetAsync = function(_: any, key: string): any
				table.insert(w.log, `get:{name}:{key}`)
				if w.holdGet[`{name}:{key}`] then
					table.insert(w.held, coroutine.running())
					coroutine.yield()
				end
				if w.failGet[name] or w.failGet[`{name}:{key}`] then
					error("stub: read failed", 0)
				end
				return copy(data[key])
			end,
			UpdateAsync = function(_: any, key: string, transform: (any) -> any): any
				table.insert(w.log, `update:{name}`)
				if w.failUpdate[name] then
					error("stub: write failed", 0)
				end
				local value = transform(copy(data[key]))
				if value ~= nil then
					data[key] = copy(value)
				end
				return copy(value)
			end,
			GetSortedAsync = function(_: any, ascending: boolean, size: number): any
				table.insert(w.log, `sorted:{name}`)
				local list: { { key: string, value: number } } = {}
				for key, value in data do
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
	local dataStores = {
		GetDataStore = function(_: any, name: string, scope: string?): any
			return store(name, scope)
		end,
		GetOrderedDataStore = function(_: any, name: string, scope: string?): any
			return store(name, scope)
		end,
		GetRequestBudgetForRequestType = function(): number
			return 100
		end,
	}
	local removing = signal()
	w = {
		now = FRI,
		data = {},
		log = {},
		failUpdate = {},
		failGet = {},
		holdGet = {},
		held = {},
		release = function()
			local co = table.remove(w.held, 1) :: thread
			local ok, err = coroutine.resume(co)
			if not ok then
				error(err, 0)
			end
		end,
		send = function(userId: number, id: string)
			local p = w.players[userId]
			if p == nil then
				p = node("Player", `Player{userId}`)
				p.UserId = userId
				p.Parent = node("Players")
				w.players[userId] = p
			end
			w.board.OnServerEvent:fire(p, id)
		end,
		leave = function(userId: number)
			local p = w.players[userId]
			p.Parent = nil
			w.players[userId] = nil
			w.removing:fire(p)
		end,
		warnings = 0,
		heard = {},
		store = nil,
		board = nil,
		removing = removing,
		players = {},
		ask = function(userId: number, id: string): any
			local p = w.players[userId]
			if p == nil then
				p = node("Player", `Player{userId}`)
				p.UserId = userId
				p.Parent = node("Players")
				w.players[userId] = p
			end
			local before = #w.board.toClient
			w.board.OnServerEvent:fire(p, id)
			t.expect(#w.board.toClient).toBe(before + 1)
			local sent = w.board.toClient[#w.board.toClient]
			t.expect(sent.player).toBe(p)
			return sent.args
		end,
		count = function(prefix: string): number
			local n = 0
			for _, line in w.log do
				if string.sub(line, 1, #prefix) == prefix then
					n += 1
				end
			end
			return n
		end,
		exactly = function(line: string): number
			local n = 0
			for _, l in w.log do
				if l == line then
					n += 1
				end
			end
			return n
		end,
	}
	local clock = {
		time = function(): number
			return w.now
		end,
	}
	-- the game server's store adapter
	local gameEnv = env({ DataStoreService = dataStores }, { [LOGIC .. "Hiscores"] = Hiscores }, {
		task = {
			spawn = function(fn: () -> ())
				fn()
			end,
			wait = function() end,
		},
		os = clock,
		warn = function()
			w.warnings += 1
		end,
	})
	gameEnv.game.JobId = JOB
	w.store = load("src/server/HiscoreStore.luau", gameEnv)
	w.store.listen(function(...: any)
		table.insert(w.heard, table.pack(...))
	end)
	-- the lobby's board adapter
	local storage = node("ReplicatedStorage")
	child(storage, "Folder", "Remotes")
	local lobbyEnv = env({
		ReplicatedStorage = storage,
		DataStoreService = dataStores,
		Players = { PlayerRemoving = removing },
	}, { [LOGIC .. "Hiscores"] = Hiscores }, { os = clock })
	load("src/lobby/server/Boards.luau", lobbyEnv).start()
	w.board = storage.Remotes:FindFirstChild("Board")
	return w
end

local function list(w: World): { any }
	return ((w.data["HiscoreTop|all"] or {}) :: any).runs
end

local function scores(entries: { any }): { string }
	local out: { string } = {}
	for _, e in entries do
		table.insert(out, `{e.userId}={e.score}`)
	end
	return out
end

-- a stored per-player best, as f0024's write leaves it
local function best(w: World, userId: string, name: string, score: number, level: number)
	w.data["Hiscores|all"] = w.data["Hiscores|all"] or {}
	w.data["HiscoreEntries|all"] = w.data["HiscoreEntries|all"] or {}
	w.data["Hiscores|all"][userId] = Hiscores.pack(score, level)
	w.data["HiscoreEntries|all"][userId] = { name = name, userId = userId, score = score, level = level }
end

local function stored(userId: string, score: number, level: number, at: number, runNo: number): any
	return H.topRun({ name = `P{userId}`, userId = userId, score = score, level = level }, at, runNo, JOB)
end

-- the heard tuple (userId, run, rank, missed) as a plain array with its holes
local function heard(w: World, i: number): { any }
	local h = w.heard[i]
	return { h[1], h[2], h[3], h[4] }
end

return t.spec("d0124 adapters", function(it)
	-- AC3 ------------------------------------------------------------------------------------------------------------
	it(
		"one player's two runs in a row, the second lower, are places 1 and 2 and the lobby lists both",
		function()
			local w = world()
			w.store.submit("7", "Ada", 80, 3, 1)
			w.now += 120
			w.store.submit("7", "Ada", 50, 2, 2)
			t.expect(#w.heard).toBe(2)
			t.expect(heard(w, 1)).toEqual({ "7", 1, 1, nil } :: { any })
			t.expect(heard(w, 2)).toEqual({ "7", 2, 2, nil } :: { any })
			local answer = w.ask(7, "all")
			t.expect(answer[1]).toBe("all")
			t.expect(answer[2]).toEqual({
				{ rank = 1, name = "Ada", score = 80, level = 3 },
				{ rank = 2, name = "Ada", score = 50, level = 2 },
			})
			t.expect(answer[3]).toBe(1)
			t.expect(answer[4]).toBe(false)
			t.expect(answer[5]).toEqual({ score = 80, level = 3 })
			-- the per-player best stays the better run
			t.expect(w.data["HiscoreEntries|all"]["7"].score).toBe(80)
			t.expect(w.data["Hiscores|all"]["7"]).toBe(Hiscores.pack(80, 3))
			t.expect(w.warnings).toBe(0)
		end
	)

	it(
		"runs of several players fill the list in order, cut to ten, and a later lower run is missed",
		function()
			local w = world()
			for i = 1, 12 do
				w.now += 1
				w.store.submit(tostring(100 + i), `P{i}`, 1000 + i, 1, 1)
			end
			t.expect(#list(w)).toBe(10)
			t.expect(list(w)[1].score).toBe(1012)
			t.expect(list(w)[10].score).toBe(1003)
			w.store.submit("7", "Ada", 5, 1, 1)
			t.expect(heard(w, #w.heard)).toEqual({ "7", 1, nil, Hiscores.N } :: { any })
			t.expect(#list(w)).toBe(10)
			t.expect(w.data["HiscoreEntries|all"]["7"].score).toBe(5)
			local answer = w.ask(7, "all")
			t.expect(#answer[2]).toBe(10)
			t.expect(answer[3]).toBe(nil)
			t.expect(answer[5]).toEqual({ score = 5, level = 1 })
		end
	)

	-- AC6 ------------------------------------------------------------------------------------------------------------
	it(
		"a first run with no list starts it from the stored bests, the player's older best included",
		function()
			local w = world()
			best(w, "7", "Ada", 900, 4)
			best(w, "2", "Bea", 300, 1)
			w.store.submit("7", "Ada", 500, 2, 1)
			t.expect(scores(list(w))).toEqual({ "7=900", "7=500", "2=300" })
			t.expect(list(w)[1].id).toBe("best:7:900:4")
			t.expect(heard(w, 1)).toEqual({ "7", 1, 2, nil } :: { any })
			t.expect(w.data["HiscoreEntries|all"]["7"].score).toBe(900)
		end
	)

	it(
		"the per-player boards are written before the list, and a first run that is a new best is listed once",
		function()
			local w = world()
			best(w, "2", "Bea", 300, 1)
			w.store.submit("7", "Ada", 950, 2, 1)
			t.expect(scores(list(w))).toEqual({ "7=950", "2=300" })
			local firstTop = table.find(w.log, "update:HiscoreTop") :: number
			local lastEntry = 0
			for i, line in w.log do
				if line == "update:HiscoreEntries" or line == "update:Hiscores" then
					lastEntry = i
				end
			end
			t.expect(firstTop ~= nil and lastEntry > 0 and lastEntry < firstTop).toBe(true)
			t.expect(w.count("update:HiscoreTop")).toBe(1)
			t.expect(w.data["HiscoreEntries|all"]["7"].score).toBe(950)
		end
	)

	it("a best written by a build without the list joins the list on anyone's next run", function()
		local w = world()
		w.store.submit("2", "Bea", 300, 1, 1)
		-- another build, or an old server, writes only the per-player boards
		best(w, "9", "Old", 900, 4)
		w.now += 60
		w.store.submit("7", "Ada", 100, 1, 1)
		t.expect(scores(list(w))).toEqual({ "9=900", "2=300", "7=100" })
		t.expect(list(w)[1].id).toBe("best:9:900:4")
		t.expect(heard(w, 2)).toEqual({ "7", 1, 3, nil } :: { any })
	end)

	it("the per-player all-time row a run writes names that run and its instant", function()
		local w = world()
		w.store.submit("7", "Ada", 60, 2, 3)
		local row = w.data["HiscoreEntries|all"]["7"]
		t.expect(row.run).toBe(`7:{FRI}:3:{JOB}`)
		t.expect(row.at).toBe(FRI)
		t.expect(list(w)[1].id).toBe(row.run)
	end)

	it("a run whose ordered write fails is listed at its own score by the next run", function()
		local w = world()
		w.store.submit("2", "Bea", 100, 1, 1)
		w.failUpdate.Hiscores = true
		w.failUpdate.HiscoreTop = true
		w.store.submit("7", "Ada", 600, 3, 1)
		w.failUpdate.Hiscores = false
		w.failUpdate.HiscoreTop = false
		-- Ada's companion row holds 600 and names her run; her ordered score never landed
		t.expect(w.data["Hiscores|all"]["7"]).toBe(nil)
		w.now += 60
		w.store.submit("2", "Bea", 50, 1, 2)
		t.expect(scores(list(w))).toEqual({ "2=100", "2=50" })
		-- her next run repairs the ordered key: her row joins with its own score and her run's id
		w.store.submit("7", "Ada", 10, 1, 2)
		t.expect(scores(list(w))).toEqual({ "7=600", "2=100", "2=50", "7=10" })
		t.expect(list(w)[1].id).toBe(`7:{FRI}:1:{JOB}`)
	end)

	it("a run's entry is keyed by the user, the server's clock, the run counter and the job id", function()
		local w = world()
		w.store.submit("7", "  Ada  ", 60, 2, 3)
		t.expect(list(w)).toEqual({
			{ id = `7:{FRI}:3:{JOB}`, name = "Ada", userId = "7", score = 60, level = 2, at = FRI },
		})
	end)

	it("the place heard is the run's place on the list, not the player's per-player rank", function()
		local w = world()
		local cy = stored("8", 990, 1, FRI - 9, 1)
		best(w, "8", "Cy", 990, 1)
		-- Cy's row was written by that listed run, so it names it
		w.data["HiscoreEntries|all"]["8"].run = cy.id
		w.data["HiscoreEntries|all"]["8"].at = cy.at
		w.data["HiscoreTop|all"] = { runs = { cy, stored("8", 980, 1, FRI - 8, 2) } }
		w.store.submit("7", "Ada", 500, 2, 1)
		-- on the per-player board Ada is second; on the list two of Cy's runs stand above her
		t.expect(heard(w, 1)).toEqual({ "7", 1, 3, nil } :: { any })
	end)

	it("a list that cannot be written says nothing, and the per-player boards are still written", function()
		local w = world()
		w.failUpdate.HiscoreTop = true
		w.store.submit("7", "Ada", 60, 2, 1)
		t.expect(#w.heard).toBe(0)
		t.expect(w.data["HiscoreEntries|all"]["7"].score).toBe(60)
		t.expect(w.data["Hiscores|day:2026-10-16"]["7:2026-10-16"]).toBe(Hiscores.pack(60, 2))
		t.expect(w.count("update:HiscoreTop")).toBe(3)
		t.expect(w.warnings).toBe(0)
	end)

	it("no list and a per-player board that cannot be read: no list is made, nothing is said", function()
		local w = world()
		best(w, "2", "Bea", 300, 1)
		w.failGet["HiscoreEntries:2"] = true
		w.store.submit("7", "Ada", 60, 2, 1)
		t.expect(list(w)).toBe(nil)
		t.expect(#w.heard).toBe(0)
		t.expect(w.data["HiscoreEntries|all"]["7"].score).toBe(60)
	end)

	-- AC5 ------------------------------------------------------------------------------------------------------------
	it("the all-time answer is the stored list with the asker's own best", function()
		local w = world()
		best(w, "7", "Ada", 80, 3)
		w.data["HiscoreTop|all"] = {
			runs = { stored("2", 60, 1, FRI, 1), stored("7", 50, 2, FRI, 2), stored("7", 80, 3, FRI, 1) },
		}
		local answer = w.ask(7, "all")
		t.expect(answer.n).toBe(5)
		t.expect(answer[1]).toBe("all")
		t.expect(answer[2]).toEqual({
			{ rank = 1, name = "P7", score = 80, level = 3 },
			{ rank = 2, name = "P2", score = 60, level = 1 },
			{ rank = 3, name = "P7", score = 50, level = 2 },
		})
		t.expect(answer[3]).toBe(1)
		t.expect(answer[4]).toBe(false)
		t.expect(answer[5]).toEqual({ score = 80, level = 3 })
		t.expect(w.count("sorted:")).toBe(0)
	end)

	it("with no list stored, the all-time answer is the per-player board, as before", function()
		local w = world()
		best(w, "1", "Ada", 50, 2)
		best(w, "2", "Bea", 80, 3)
		local answer = w.ask(9, "all")
		t.expect(answer[2]).toEqual({
			{ rank = 1, name = "Bea", score = 80, level = 3 },
			{ rank = 2, name = "Ada", score = 50, level = 2 },
		})
		t.expect(answer[4]).toBe(false)
		t.expect(answer[5]).toBe(nil)
		t.expect(w.count("sorted:Hiscores")).toBe(1)
	end)

	it("a list that cannot be read is a failed all-time read, not the per-player board", function()
		local w = world()
		best(w, "1", "Ada", 50, 2)
		w.data["HiscoreTop|all"] = { runs = { stored("1", 50, 2, FRI, 1) } }
		w.failGet.HiscoreTop = true
		local answer = w.ask(1, "all")
		t.expect(answer[2]).toEqual({})
		t.expect(answer[4]).toBe(true)
		t.expect(w.count("sorted:")).toBe(0)
	end)

	it("day and week answers are the per-player boards and carry no best", function()
		local w = world()
		best(w, "7", "Ada", 80, 3)
		w.store.submit("7", "Ada", 60, 2, 1)
		table.clear(w.log)
		for _, id in { "day", "week" } do
			local answer = w.ask(7, id)
			t.expect(answer[1]).toBe(id)
			t.expect(answer[2]).toEqual({ { rank = 1, name = "Ada", score = 60, level = 2 } })
			t.expect(answer[3]).toBe(1)
			t.expect(answer[5]).toBe(nil)
		end
		t.expect(w.count("get:HiscoreTop")).toBe(0)
		t.expect(w.exactly("get:HiscoreEntries:7")).toBe(0)
	end)

	it("after an all-time answer, the same player's day and week answers still carry no best", function()
		local w = world()
		best(w, "7", "Ada", 80, 3)
		w.store.submit("7", "Ada", 60, 2, 1)
		t.expect(w.ask(7, "all")[5]).toEqual({ score = 80, level = 3 })
		t.expect(w.ask(7, "day")[5]).toBe(nil)
		t.expect(w.ask(7, "week")[5]).toBe(nil)
	end)

	it("a player's best is read at most once per CACHE_TTL, and again after they leave", function()
		local w = world()
		best(w, "7", "Ada", 80, 3)
		-- a stored list, so the board's own read never reads player 7's row
		w.data["HiscoreTop|all"] = { runs = { stored("2", 60, 1, FRI, 1) } }
		w.ask(7, "all")
		w.now += Hiscores.CACHE_TTL - 1
		w.ask(7, "all")
		t.expect(w.exactly("get:HiscoreEntries:7")).toBe(1)
		w.now += 1
		best(w, "7", "Ada", 90, 4)
		t.expect(w.ask(7, "all")[5]).toEqual({ score = 90, level = 4 })
		t.expect(w.exactly("get:HiscoreEntries:7")).toBe(2)
		best(w, "7", "Ada", 95, 4)
		w.removing:fire(w.players[7])
		t.expect(w.ask(7, "all")[5]).toEqual({ score = 95, level = 4 })
		t.expect(w.exactly("get:HiscoreEntries:7")).toBe(3)
		-- another player's best is their own
		best(w, "8", "Cy", 10, 1)
		t.expect(w.ask(8, "all")[5]).toEqual({ score = 10, level = 1 })
	end)

	it("requests while a player's best is being read do not read it again, and each is answered", function()
		local w = world()
		best(w, "7", "Ada", 80, 3)
		w.data["HiscoreTop|all"] = { runs = { stored("2", 60, 1, FRI, 1) } }
		w.holdGet["HiscoreEntries:7"] = true
		for _ = 1, 5 do
			w.send(7, "all")
		end
		t.expect(w.exactly("get:HiscoreEntries:7")).toBe(1)
		t.expect(#w.board.toClient).toBe(4)
		w.release()
		t.expect(#w.board.toClient).toBe(5)
		t.expect(w.board.toClient[5].args[5]).toEqual({ score = 80, level = 3 })
		w.holdGet["HiscoreEntries:7"] = nil
		w.ask(7, "all")
		t.expect(w.exactly("get:HiscoreEntries:7")).toBe(1)
	end)

	it("while a stale best is read again, requests are answered with the best held before", function()
		local w = world()
		best(w, "7", "Ada", 80, 3)
		w.data["HiscoreTop|all"] = { runs = { stored("2", 60, 1, FRI, 1) } }
		w.ask(7, "all")
		w.now += Hiscores.CACHE_TTL
		w.holdGet["HiscoreEntries:7"] = true
		w.send(7, "all")
		w.send(7, "all")
		local during = w.board.toClient[#w.board.toClient].args
		t.expect(during[5]).toEqual({ score = 80, level = 3 })
		w.release()
	end)

	it("a best read that ends after the player left is dropped, and a rejoin reads again", function()
		local w = world()
		best(w, "7", "Ada", 80, 3)
		w.data["HiscoreTop|all"] = { runs = { stored("2", 60, 1, FRI, 1) } }
		w.holdGet["HiscoreEntries:7"] = true
		w.send(7, "all")
		w.leave(7)
		w.holdGet["HiscoreEntries:7"] = nil
		w.release()
		best(w, "7", "Ada", 95, 4)
		w.now += 1
		t.expect(w.ask(7, "all")[5]).toEqual({ score = 95, level = 4 })
		t.expect(w.exactly("get:HiscoreEntries:7")).toBe(2)
	end)

	it("a best that cannot be read again is no best: the stale one is not kept", function()
		local w = world()
		best(w, "7", "Ada", 80, 3)
		w.data["HiscoreTop|all"] = { runs = { stored("7", 80, 3, FRI, 1) } }
		t.expect(w.ask(7, "all")[5]).toEqual({ score = 80, level = 3 })
		w.now += Hiscores.CACHE_TTL
		w.failGet["HiscoreEntries:7"] = true
		local answer = w.ask(7, "all")
		t.expect(answer[4]).toBe(false)
		t.expect(answer[5]).toBe(nil)
	end)

	it("a best that cannot be read is no best, and the board still answers", function()
		local w = world()
		best(w, "7", "Ada", 80, 3)
		w.failGet["HiscoreEntries:7"] = true
		w.data["HiscoreTop|all"] = { runs = { stored("7", 80, 3, FRI, 1) } }
		local answer = w.ask(7, "all")
		t.expect(answer[4]).toBe(false)
		t.expect(#answer[2]).toBe(1)
		t.expect(answer[5]).toBe(nil)
	end)

	-- AC4 (adapter part) ---------------------------------------------------------------------------------------------
	it("Ranks sends the place, or the miss, to a player still in the game", function()
		local storage = node("ReplicatedStorage")
		child(storage, "Folder", "Remotes")
		local players = node("Players")
		local one = child(players, "Player", "One")
		one.UserId = 1
		players.GetPlayerByUserId = function(_: any, id: number): any
			return if id == 1 then one else nil
		end
		local hear: any = nil
		load(
			"src/server/Ranks.luau",
			env({ Players = players, ReplicatedStorage = storage }, {
				["./HiscoreStore"] = {
					listen = function(fn: any)
						hear = fn
					end,
				},
			})
		).start()
		local remote = storage.Remotes:FindFirstChild("Rank")
		hear("1", 1, nil, 10)
		hear("1", 2, 3, nil)
		t.expect(#remote.toClient).toBe(2)
		local missed = remote.toClient[1].args
		t.expect({ missed[1], missed[2], missed[3] } :: { any }).toEqual({ 1, nil, 10 } :: { any })
		local placed = remote.toClient[2].args
		t.expect({ placed[1], placed[2], placed[3] } :: { any }).toEqual({ 2, 3, nil } :: { any })
	end)

	it("FlowView shows a heard miss and a heard place on the game-over overlay", function()
		local storage = node("ReplicatedStorage")
		local remotes = child(storage, "Folder", "Remotes")
		child(remotes, "RemoteEvent", "ToLobby")
		child(remotes, "RemoteEvent", "LobbyStatus")
		local rank = child(remotes, "RemoteEvent", "Rank")
		local localPlayer = node("Player", "LocalPlayer")
		local gui = child(localPlayer, "PlayerGui", "PlayerGui")
		local view = load(
			"src/client/FlowView.luau",
			env({
				ContextActionService = { BindAction = function() end },
				Players = { LocalPlayer = localPlayer },
				ReplicatedStorage = storage,
			}, { [LOGIC .. "Flow"] = Flow })
		)
		view.start()
		local function label(): any
			for _, d in gui:GetDescendants() do
				if d.Name == "Rank" then
					return d
				end
			end
			return nil
		end
		local over = {
			banner = "GAME OVER",
			detail = "SCORE 5   LEVEL 1",
			fade = 0.6,
			flash = false,
			tap = true,
			cursor = true,
		}
		local playing = { fade = 0, flash = false, tap = false, cursor = false }
		view.show(over)
		rank.OnClientEvent:fire(1, nil, 10)
		t.expect(label().Text).toBe("NOT IN THE ALL-TIME TOP 10")
		t.expect(label().Visible).toBe(true)
		view.show(playing)
		t.expect(label().Visible).toBe(false)
		-- heard before its overlay: shown when it opens
		rank.OnClientEvent:fire(2, 4, nil)
		view.show(over)
		t.expect(label().Text).toBe("ALL-TIME #4")
		t.expect(label().Visible).toBe(true)
	end)

	it("LobbyView adds the best line under the all-time panel only", function()
		local storage = node("ReplicatedStorage")
		local remotes = child(storage, "Folder", "Remotes")
		child(remotes, "RemoteEvent", "StartGame")
		child(remotes, "RemoteEvent", "Status")
		local board = child(remotes, "RemoteEvent", "Board")
		local localPlayer = node("Player", "LocalPlayer")
		local gui = child(localPlayer, "PlayerGui", "PlayerGui")
		load(
			"src/lobby/client/LobbyView.luau",
			env(
				{ Players = { LocalPlayer = localPlayer }, ReplicatedStorage = storage },
				{ [LOGIC .. "Lobby"] = Lobby, [LOGIC .. "Travel"] = Travel },
				{ task = { delay = function() end } }
			)
		).start()
		local function rows(): string
			for _, d in gui:GetDescendants() do
				if d.Name == "Rows" then
					return d.Text
				end
			end
			return "(no Rows)"
		end
		local shown = {
			{ rank = 1, name = "Ada", score = 80, level = 3 },
			{ rank = 2, name = "Ada", score = 50, level = 2 },
		}
		board.OnClientEvent:fire("all", shown, 1, false, { score = 80, level = 3 })
		t.expect(rows()).toBe("> 1 Ada 80 3\n2 Ada 50 2\nYOUR BEST 80 3")
		for _, d in gui:GetDescendants() do
			if d.ClassName == "TextButton" and d.Text == Lobby.boardTitle("day") then
				d.Activated:fire()
			end
		end
		board.OnClientEvent:fire("day", shown, nil, false, { score = 80, level = 3 })
		t.expect(rows()).toBe("1 Ada 80 3\n2 Ada 50 2")
	end)
end)
