--!strict
-- f0026 AC4: the board and rank remotes are created in code, not in the place files, and the adapters that use
-- them run here on a stub `game` (this spec's own small stub, not tests/lib/fakeengine, which f0061 pins and
-- f0065 extends): Boards answers every request once, also when the read fails, and shares one read between
-- the requests that arrive while it is under way; LobbyView asks again only after a failed answer; Ranks sends
-- only to a player still in the game. The lobby boot path and FlowView's empty FireServer stay as the promoted
-- specs pin them.
local Hiscores = require("@logic/Hiscores")
local LobbyModule = require("@logic/Lobby")
local Travel = require("@logic/Travel")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local Lobby = LobbyModule :: any -- READ_GAP and boardTitle are this raft's additions

local LOGIC = "@game/ReplicatedStorage/Shared/Logic/"
local FRI = 1792108800

local function stripped(path: string): string
	return string.gsub(fs.readFile(path), "%-%-[^\n]*", "")
end

-- A small instance model: Name, ClassName, Parent, children (also by dot index) ----------------------------------------------

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
			table.insert(raws[self].toClient, { player = player, args = { ... } })
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

local unknown: { string } = {} -- modules a loaded adapter asked for that its stub does not serve

local function plainEnv(services: { [string]: any }, modules: { [string]: any }): { [string]: any }
	return {
		game = {
			GetService = function(_: any, name: string): any
				local found = services[name]
				assert(found ~= nil, `stub: game:GetService("{name}") is not modelled`)
				return found
			end,
		},
		require = function(spec: string): any
			local found = modules[spec]
			if found == nil then
				table.insert(unknown, spec)
				return {}
			end
			return found
		end,
		Instance = {
			new = function(className: string): any
				return node(className)
			end,
		},
		Enum = setmetatable({}, {
			__index = function(_: any, group: string): any
				return setmetatable({}, {
					__index = function(_: any, item: string): string
						return `{group}.{item}`
					end,
				})
			end,
		}),
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
end

local function load(path: string, env: { [string]: any }): any
	return luau.load(fs.readFile(path), { environment = env, debugName = path })()
end

local home = node("Players") -- where a player who is still in the game is parented

local function player(userId: number): any
	local p = node("Player", `Player{userId}`)
	p.UserId = userId
	p.Parent = home
	return p
end

-- Boards on a stub DataStoreService -----------------------------------------------------------------------

type BoardsWorld = {
	remote: any,
	now: number,
	mode: string, -- "ok", "error", or "hold" (the read yields until `release`)
	held: { thread },
	reads: { { name: string, scope: string, ascending: boolean, size: number } },
	ordered: { [string]: { [string]: number } },
	companion: { [string]: { [string]: any } },
	openFails: number, -- this many GetOrderedDataStore calls throw first
	failsAt: number?, -- a page size the sorted read rejects
	opens: { string }, -- "<ordered|companion>|<name>|<scope>" per store open, in order
	gets: number, -- companion GetAsync calls
	companionFails: { [string]: boolean }, -- keys whose GetAsync throws
	removing: Signal,
	errors: { string }, -- errors that escaped the request handler (the engine would only log them)
	ask: (p: any, raw: any) -> (),
	answers: (p: any) -> { { any } },
	release: (failure: boolean) -> (),
}

local function boards(): BoardsWorld
	local storage = node("ReplicatedStorage")
	child(storage, "Folder", "Remotes")
	local w: BoardsWorld
	local dataStores = {
		GetOrderedDataStore = function(_: any, name: string, scope: string?): any
			table.insert(w.opens, `ordered|{name}|{scope or "global"}`)
			if w.openFails > 0 then
				w.openFails -= 1
				error("stub: You must publish this place to the web to access DataStore", 0)
			end
			return {
				GetSortedAsync = function(_: any, ascending: boolean, size: number): any
					table.insert(
						w.reads,
						{ name = name, scope = scope or "global", ascending = ascending, size = size }
					)
					if w.mode == "error" or w.failsAt == size then
						error("stub: sorted read failed", 0)
					elseif w.mode == "hold" then
						table.insert(w.held, coroutine.running())
						if coroutine.yield() then
							error("stub: sorted read failed", 0)
						end
					end
					local list: { { key: string, value: number } } = {}
					local held: { [string]: number } = w.ordered[scope or "global"] or {}
					for key, value in held do
						table.insert(list, { key = key, value = value })
					end
					table.sort(list, function(a, b)
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
		end,
		GetDataStore = function(_: any, name: string, scope: string?): any
			table.insert(w.opens, `companion|{name}|{scope or "global"}`)
			return {
				GetAsync = function(_: any, key: string): any
					w.gets += 1
					if w.companionFails[key] then
						error("stub: companion read throttled", 0)
					end
					return (w.companion[scope or "global"] or {})[key]
				end,
			}
		end,
	}
	local removing = signal()
	local env = plainEnv({
		ReplicatedStorage = storage,
		DataStoreService = dataStores,
		Players = { PlayerRemoving = removing },
	}, { [LOGIC .. "Hiscores"] = Hiscores })
	env.os = {
		time = function(): number
			return w.now
		end,
	}
	w = {
		remote = nil,
		now = FRI,
		mode = "ok",
		held = {},
		reads = {},
		ordered = {},
		companion = {},
		openFails = 0,
		failsAt = nil,
		opens = {},
		gets = 0,
		companionFails = {},
		removing = removing,
		errors = {},
		ask = function(p: any, raw: any)
			local ok, err = pcall(function()
				w.remote.OnServerEvent:fire(p, raw)
			end)
			if not ok then
				table.insert(w.errors, tostring(err))
			end
		end,
		answers = function(p: any): { { any } }
			local out: { { any } } = {}
			for _, f in w.remote.toClient do
				if f.player == p then
					table.insert(out, f.args)
				end
			end
			return out
		end,
		release = function(failure: boolean)
			local co = table.remove(w.held, 1) :: thread
			local ok, err = coroutine.resume(co, failure)
			if not ok then
				error(err, 0)
			end
		end,
	}
	load("src/lobby/server/Boards.luau", env).start()
	w.remote = storage.Remotes:FindFirstChild("Board")
	return w
end

local function seed(w: BoardsWorld)
	w.ordered.all = { ["1"] = Hiscores.pack(50, 2), ["2"] = Hiscores.pack(80, 3) }
	w.companion.all = {
		["1"] = { name = "Ada", userId = "1", level = 2, score = 50 },
		["2"] = { name = "Bea", userId = "2", level = 3, score = 80 },
	}
end

-- LobbyView on a stub client --------------------------------------------------------------------------------

type View = {
	remotes: any,
	gui: any,
	clock: { now: number },
	tick: (seconds: number) -> (),
	find: (name: string) -> any,
	button: (text: string) -> any,
	asks: () -> { { any } },
}

local function lobbyView(withBoard: boolean): View
	local storage = node("ReplicatedStorage")
	local remotes = child(storage, "Folder", "Remotes")
	child(remotes, "RemoteEvent", "StartGame")
	child(remotes, "RemoteEvent", "Status")
	if withBoard then
		child(remotes, "RemoteEvent", "Board")
	end
	local localPlayer = node("Player", "LocalPlayer")
	local gui = child(localPlayer, "PlayerGui", "PlayerGui")
	local clock = { now = 0 }
	local timers: { { due: number, fn: (...any) -> (), args: { any } } } = {}
	local env = plainEnv(
		{ Players = { LocalPlayer = localPlayer }, ReplicatedStorage = storage },
		{ [LOGIC .. "Lobby"] = LobbyModule, [LOGIC .. "Travel"] = Travel }
	)
	env.task = {
		delay = function(seconds: number, fn: (...any) -> (), ...: any)
			table.insert(timers, { due = clock.now + seconds, fn = fn, args = { ... } })
		end,
	}
	local v: View = {
		remotes = remotes,
		gui = gui,
		clock = clock,
		tick = function(seconds: number)
			clock.now += seconds
			local due: { { due: number, fn: (...any) -> (), args: { any } } } = {}
			local later: { { due: number, fn: (...any) -> (), args: { any } } } = {}
			for _, timer in timers do
				table.insert(if timer.due <= clock.now + 1e-9 then due else later, timer)
			end
			timers = later
			for _, timer in due do
				timer.fn(table.unpack(timer.args))
			end
		end,
		find = function(name: string): any
			for _, d in gui:GetDescendants() do
				if d.Name == name then
					return d
				end
			end
			return nil
		end,
		button = function(text: string): any
			for _, d in gui:GetDescendants() do
				if d.ClassName == "TextButton" and d.Text == text then
					return d
				end
			end
			return nil
		end,
		asks = function(): { { any } }
			local board = remotes:FindFirstChild("Board")
			return if board then board.toServer else {}
		end,
	}
	load("src/lobby/client/LobbyView.luau", env).start()
	return v
end

local function rowsOf(...: any): { any }
	return { ... }
end

-- Ranks on a stub HiscoreStore ------------------------------------------------------------------------------

type Ranks = {
	remote: any,
	heard: (userId: string, run: number, rank: number) -> (),
	players: { [number]: any },
}

local function ranks(): Ranks
	local storage = node("ReplicatedStorage")
	child(storage, "Folder", "Remotes")
	local playersService = node("Players")
	local r: Ranks = { remote = nil, heard = function() end, players = {} }
	playersService.GetPlayerByUserId = function(_: any, id: number): any
		return r.players[id]
	end
	local env = plainEnv({ Players = playersService, ReplicatedStorage = storage }, {
		["./HiscoreStore"] = {
			listen = function(fn: (string, number, number) -> ())
				r.heard = fn
			end,
		},
	})
	load("src/server/Ranks.luau", env).start()
	r.remote = storage.Remotes:FindFirstChild("Rank")
	for _, id in { 1, 2 } do
		local p = player(id)
		p.Parent = playersService
		r.players[id] = p
	end
	return r
end

return t.spec("f0026 adapter boundaries", function(it)
	it("the place files do not gain a Board or Rank remote", function()
		local lobby = serde.decode("json", fs.readFile("lobby.project.json"))
		local game = serde.decode("json", fs.readFile("default.project.json"))
		t.expect(lobby.tree.ReplicatedStorage.Remotes.Board).toBe(nil)
		t.expect(lobby.tree.ReplicatedStorage.Remotes.StartGame["$className"]).toBe("RemoteEvent")
		t.expect(lobby.tree.ReplicatedStorage.Remotes.Status["$className"]).toBe("RemoteEvent")
		t.expect(game.tree.ReplicatedStorage.Remotes.Rank).toBe(nil)
		t.expect(game.tree.ReplicatedStorage.Remotes.Ready["$className"]).toBe("RemoteEvent")
	end)

	it("Starts never opens a store, the lobby Main boots Boards after it, and Boards only reads", function()
		local starts = stripped("src/lobby/server/Starts.luau")
		t.expect((string.find(starts, "DataStore", 1, true))).toBe(nil)
		t.expect((string.find(starts, "Boards", 1, true))).toBe(nil)
		local main = stripped("src/lobby/server/Main.server.luau")
		local startsAt = string.find(main, "Starts", 1, true)
		local boardsAt = string.find(main, "Boards", 1, true)
		t.expect(startsAt ~= nil and boardsAt ~= nil and startsAt < boardsAt).toBe(true)
		t.expect(fs.isFile("src/lobby/server/Boards.luau")).toBe(true)
		local src = stripped("src/lobby/server/Boards.luau")
		for _, needle in
			{
				"Hiscores.boardId",
				"Hiscores.lookup",
				"Hiscores.cacheKey",
				"Hiscores.storeTarget",
				"GetSortedAsync(false",
			}
		do
			t.expect(string.find(src, needle, 1, true) ~= nil).toBe(true)
		end
		for _, banned in { "SetAsync", "UpdateAsync", "HiscoreStore", "AdvanceToNextPage" } do
			t.expect((string.find(src, banned, 1, true))).toBe(nil)
		end
	end)

	it("Boards creates Board under Remotes and ignores anything but all, day or week", function()
		local w = boards()
		t.expect(w.remote ~= nil).toBe(true)
		t.expect(w.remote.ClassName).toBe("RemoteEvent")
		local p1 = player(1)
		w.ask(p1, 5000)
		w.ask(p1, { score = 99999 })
		w.ask(p1, "ALL")
		t.expect(#w.answers(p1)).toBe(0)
		t.expect(#w.reads).toBe(0)
	end)

	it("a failed read still answers once, with failed = true and the rows it had, or none", function()
		local w = boards()
		local p1, p3 = player(1), player(3)
		w.mode = "error"
		w.ask(p1, "all")
		t.expect(w.answers(p1)).toEqual({ { "all", {}, nil, true } :: { any } })
		t.expect(#w.reads).toBe(2)
		t.expect(w.reads[1].ascending).toBe(false)
		t.expect(w.reads[1].size).toBe(10)
		t.expect(w.reads[2].size).toBe(50)
		t.expect(w.reads[1].name).toBe("Hiscores")
		t.expect(w.reads[1].scope).toBe("all")
		-- inside the key's failure window another player is answered from what there is, without a read
		w.now += Hiscores.READ_GAP
		w.ask(p3, "all")
		t.expect(w.answers(p3)).toEqual({ { "all", {}, nil, true } :: { any } })
		t.expect(#w.reads).toBe(2)
		seed(w)
		w.mode = "ok"
		w.now += Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 1) - Hiscores.READ_GAP
		w.ask(p1, "all")
		local healthy = w.answers(p1)[2]
		t.expect(healthy[1]).toBe("all")
		t.expect(healthy[2]).toEqual({
			{ rank = 1, name = "Bea", score = 80, level = 3 },
			{ rank = 2, name = "Ada", score = 50, level = 2 },
		})
		t.expect(healthy[3]).toBe(2)
		t.expect(healthy[4]).toBe(false)
		local reads = #w.reads
		w.mode = "error"
		w.now += 2
		w.ask(p3, "all")
		t.expect(#w.reads).toBe(reads)
		t.expect(w.answers(p3)[2]).toEqual({ "all", healthy[2], nil, false } :: { any })
		w.now += Hiscores.CACHE_TTL
		w.ask(p1, "all")
		t.expect(#w.answers(p1)).toBe(3)
		t.expect(w.answers(p1)[3]).toEqual({ "all", healthy[2], 2, true } :: { any })
		-- inside that failure window the board the server holds is the answer, never an empty one, and nothing is read
		reads = #w.reads
		w.now += 1
		local p2 = player(2)
		w.ask(p2, "all")
		w.ask(p3, "all")
		w.ask(p1, "all")
		t.expect(#w.reads).toBe(reads)
		t.expect(w.answers(p2)).toEqual({ { "all", healthy[2], 1, true } :: { any } })
		t.expect(w.answers(p3)[3]).toEqual({ "all", healthy[2], nil, true } :: { any })
		t.expect(w.answers(p1)[4]).toEqual({ "all", healthy[2], 2, true } :: { any })
	end)

	it(
		"a request that arrives while the read is under way does not read again, and each gets one answer",
		function()
			local w = boards()
			seed(w)
			local p1, p2 = player(1), player(2)
			local p9 = player(9)
			w.mode = "hold"
			w.ask(p1, "all")
			w.ask(p2, "all")
			w.ask(p9, "all")
			t.expect(#w.reads).toBe(1)
			t.expect(#w.answers(p1)).toBe(0)
			t.expect(#w.answers(p2)).toBe(0)
			w.release(false)
			t.expect(#w.reads).toBe(1)
			t.expect(#w.answers(p1)).toBe(1)
			t.expect(#w.answers(p2)).toBe(1)
			t.expect(#w.answers(p9)).toBe(1)
			t.expect(w.answers(p1)[1][3]).toBe(2)
			t.expect(w.answers(p2)[1][3]).toBe(1)
			t.expect(w.answers(p9)[1][3]).toBe(nil)
			t.expect(w.answers(p2)[1][4]).toBe(false)
			t.expect(#w.answers(p2)[1][2]).toBe(2)
		end
	)

	it(
		"during an outage a client asking every second costs three reads of the board in ten seconds",
		function()
			local w = boards()
			local p1 = player(1)
			w.mode = "error"
			for _ = 0, 10 do
				w.ask(p1, "all")
				w.now += 1
			end
			-- reads at 0, 2 and 6 s (failure waits of 2, 4, then 8 s), each at page sizes 10 and 50
			t.expect(#w.reads).toBe(6)
			t.expect(#w.answers(p1)).toBe(11)
			for _, answer in w.answers(p1) do
				t.expect(answer[4]).toBe(true)
			end
			seed(w)
			w.mode = "ok"
			w.now = FRI + 14
			w.ask(p1, "all")
			t.expect(#w.reads).toBe(7)
			t.expect(w.answers(p1)[12][4]).toBe(false)
		end
	)

	it(
		"an error anywhere in the read, opening the store included, is a failed read and the board is not wedged",
		function()
			local w = boards()
			seed(w)
			w.openFails = 1
			local p1, p2, p9 = player(1), player(2), player(9)
			w.ask(p1, "all")
			t.expect(w.answers(p1)).toEqual({ { "all", {}, nil, true } :: { any } })
			w.now += 1
			w.ask(p2, "all")
			t.expect(w.answers(p2)).toEqual({ { "all", {}, nil, true } :: { any } })
			w.now += Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 1) - 1
			w.ask(p9, "all")
			t.expect(#w.answers(p9)).toBe(1)
			t.expect(w.answers(p9)[1][4]).toBe(false)
			t.expect(#w.answers(p9)[1][2]).toBe(2)
			w.ask(p2, "all")
			t.expect(w.answers(p2)[2][3]).toBe(1)
			t.expect(w.errors).toEqual({})
		end
	)

	it(
		"a companion row that cannot be read fails the read: no short board is answered as healthy or cached",
		function()
			local w = boards()
			seed(w)
			w.companionFails["2"] = true
			local p1 = player(1)
			w.ask(p1, "all")
			t.expect(w.answers(p1)).toEqual({ { "all", {}, nil, true } :: { any } })
			w.companionFails["2"] = nil
			w.now += Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 1)
			w.ask(p1, "all")
			local answer = w.answers(p1)[2]
			t.expect(answer[4]).toBe(false)
			t.expect(#answer[2]).toBe(2)
			t.expect(answer[3]).toBe(2)
			-- a companion that is simply absent is skipped, and the board is healthy
			local v = boards()
			seed(v)
			v.companion.all["2"] = nil
			v.ask(p1, "all")
			t.expect(v.answers(p1)).toEqual({
				{ "all", { { rank = 1, name = "Ada", score = 50, level = 2 } }, 1, false } :: { any },
			})
		end
	)

	it(
		"a waiter who left before the read returned gets no answer, and Boards keeps no per-player state",
		function()
			local w = boards()
			seed(w)
			local p1, p2 = player(1), player(2)
			w.mode = "hold"
			w.ask(p1, "all")
			w.ask(p2, "all")
			p2.Parent = nil
			w.removing:fire(p2)
			w.release(false)
			t.expect(#w.answers(p1)).toBe(1)
			t.expect(#w.answers(p2)).toBe(0)
			-- nothing is keyed by player, so nothing can outlive a visitor
			local src = stripped("src/lobby/server/Boards.luau")
			t.expect((string.find(src, "lastFetch", 1, true))).toBe(nil)
			t.expect((string.find(src, "%[%s*player%s*%]%s*="))).toBe(nil)
		end
	)

	it("one player asking all and then day in the same second gets both boards, healthy", function()
		local w = boards()
		seed(w)
		w.ordered["day:2026-10-16"] = { ["2"] = Hiscores.pack(80, 3) }
		w.companion["day:2026-10-16"] = { ["2"] = { name = "Bea", userId = "2", level = 3, score = 80 } }
		local p2 = player(2)
		w.ask(p2, "all")
		w.ask(p2, "day")
		t.expect(#w.reads).toBe(2)
		t.expect(w.answers(p2)[1][4]).toBe(false)
		t.expect(w.answers(p2)[2]).toEqual({
			"day",
			{ { rank = 1, name = "Bea", score = 80, level = 3 } },
			1,
			false,
		} :: { any })
		t.expect(table.find(w.opens, "companion|HiscoreEntries|day:2026-10-16") ~= nil).toBe(true)
		t.expect(table.find(w.opens, "ordered|Hiscores|day:2026-10-16") ~= nil).toBe(true)
	end)

	it(
		"Boards opens the ordered and the companion store under their own names and the board's scope",
		function()
			local w = boards()
			seed(w)
			w.ask(player(1), "all")
			local companions, ordereds = 0, 0
			for _, open in w.opens do
				if string.sub(open, 1, 9) == "companion" then
					companions += 1
					t.expect(open).toBe("companion|HiscoreEntries|all")
				else
					ordereds += 1
					t.expect(open).toBe("ordered|Hiscores|all")
				end
			end
			t.expect(companions >= 1).toBe(true)
			t.expect(ordereds >= 1).toBe(true)
			local name, scope = Hiscores.storeTarget("companion", Hiscores.board("all", FRI), true)
			t.expect(`companion|{name}|{scope}`).toBe("companion|HiscoreEntries|all")
		end
	)

	it("a page of 50 after the size-10 fallback is cut to the top N before any companion is read", function()
		local w = boards()
		w.ordered.all = {}
		w.companion.all = {}
		for i = 1, 30 do
			local id = tostring(100 + i)
			w.ordered.all[id] = Hiscores.pack(1000 - i, 1)
			w.companion.all[id] = { name = `P{i}`, userId = id, level = 1, score = 1000 - i }
		end
		w.failsAt = 10
		local p1 = player(1)
		w.ask(p1, "all")
		t.expect(#w.reads).toBe(2)
		t.expect(w.reads[2].size).toBe(50)
		t.expect(w.gets <= Hiscores.N).toBe(true)
		local answer = w.answers(p1)[1]
		t.expect(answer[4]).toBe(false)
		t.expect(#answer[2]).toBe(Hiscores.N)
		t.expect(answer[2][1].score).toBe(999)
	end)

	it("a healthy empty board is an answer, not a failure", function()
		local w = boards()
		local p1 = player(1)
		w.ask(p1, "day")
		t.expect(w.answers(p1)).toEqual({ { "day", {}, nil, false } :: { any } })
		t.expect(w.reads[1].scope).toBe("day:2026-10-16")
	end)

	it(
		"the lobby screen asks for all once at start and draws the answer, marking the rank it was sent",
		function()
			local v = lobbyView(true)
			t.expect(v.asks()).toEqual({ { "all" } })
			t.expect(v.find("Title").Text).toBe("HISCORES")
			t.expect(v.find("Rows").Text).toBe("No scores yet")
			v.remotes.Board.OnClientEvent:fire(
				"all",
				rowsOf(
					{ rank = 1, name = "Bea", score = 80, level = 3 },
					{ rank = 2, name = "Ada", score = 50, level = 2 }
				),
				2,
				false
			)
			t.expect(v.find("Rows").Text).toBe("1 Bea 80 3\n> 2 Ada 50 2")
			v.tick(10)
			t.expect(#v.asks()).toBe(1)
			t.expect(#v.remotes.StartGame.toServer).toBe(0)
		end
	)

	it(
		"failed answers in a row ask again after 1, 2 and 4 s, then stop, and a healthy answer starts over",
		function()
			local v = lobbyView(true)
			local board = v.remotes.Board
			for n, wait in { 1, 2, 4 } do
				board.OnClientEvent:fire("all", {}, nil, true)
				v.tick(wait - 0.5)
				t.expect(#v.asks()).toBe(n)
				v.tick(0.5)
				t.expect(#v.asks()).toBe(n + 1)
			end
			board.OnClientEvent:fire("all", {}, nil, true)
			v.tick(60)
			t.expect(#v.asks()).toBe(4)
			board.OnClientEvent:fire("all", {}, nil, false)
			board.OnClientEvent:fire("all", {}, nil, true)
			v.tick(Lobby.READ_GAP)
			t.expect(#v.asks()).toBe(5)
		end
	)

	it(
		"a tap starts the failure count over, so a failed answer after the retries stopped is retried",
		function()
			local v = lobbyView(true)
			local board = v.remotes.Board
			for _, wait in { 1, 2, 4 } do
				board.OnClientEvent:fire("all", {}, nil, true)
				v.tick(wait)
			end
			board.OnClientEvent:fire("all", {}, nil, true)
			v.tick(60)
			t.expect(#v.asks()).toBe(4)
			v.button(Lobby.boardTitle("day")).Activated:fire()
			board.OnClientEvent:fire("day", {}, nil, true)
			v.tick(Lobby.READ_GAP)
			t.expect(#v.asks()).toBe(6)
			t.expect(v.asks()[6]).toEqual({ "day" })
		end
	)

	it("a failed day or week answer asks again for that board", function()
		local v = lobbyView(true)
		v.button(Lobby.boardTitle("day")).Activated:fire()
		v.remotes.Board.OnClientEvent:fire("day", {}, nil, true)
		v.tick(Lobby.READ_GAP)
		t.expect(v.asks()).toEqual({ { "all" }, { "day" }, { "day" } })
		v.button(Lobby.boardTitle("week")).Activated:fire()
		v.remotes.Board.OnClientEvent:fire("week", {}, nil, true)
		v.tick(10)
		t.expect(v.asks()[5]).toEqual({ "week" })
	end)

	it("a retry or a late answer for a board the player left neither asks nor draws", function()
		local v = lobbyView(true)
		local board = v.remotes.Board
		board.OnClientEvent:fire("all", {}, nil, true)
		v.button(Lobby.boardTitle("day")).Activated:fire()
		v.tick(Lobby.READ_GAP)
		t.expect(v.asks()).toEqual({ { "all" }, { "day" } })
		board.OnClientEvent:fire("day", rowsOf({ rank = 1, name = "Cy", score = 5, level = 1 }), nil, false)
		t.expect(v.find("Title").Text).toBe("TODAY")
		v.button(Lobby.boardTitle("week")).Activated:fire()
		board.OnClientEvent:fire("week", rowsOf({ rank = 1, name = "Di", score = 9, level = 2 }), nil, false)
		-- TODAY's answer arrives after THIS WEEK's, and after a failed one for all: neither is drawn
		board.OnClientEvent:fire("day", rowsOf({ rank = 1, name = "Old", score = 1, level = 1 }), nil, false)
		board.OnClientEvent:fire("all", {}, nil, true)
		t.expect(v.find("Title").Text).toBe("THIS WEEK")
		t.expect(v.find("Rows").Text).toBe("1 Di 9 2")
		v.tick(10)
		t.expect(#v.asks()).toBe(3)
	end)

	it("a failed answer asks for all once more after READ_GAP, and a healthy one never does", function()
		local v = lobbyView(true)
		v.remotes.Board.OnClientEvent:fire("all", {}, nil, true)
		t.expect(v.find("Rows").Text).toBe("No scores yet")
		t.expect(#v.asks()).toBe(1)
		v.tick(Lobby.READ_GAP / 2)
		t.expect(#v.asks()).toBe(1)
		v.tick(Lobby.READ_GAP / 2)
		t.expect(v.asks()).toEqual({ { "all" }, { "all" } })
		v.tick(10)
		t.expect(#v.asks()).toBe(2)
		v.remotes.Board.OnClientEvent:fire("all", {}, nil, false)
		v.tick(10)
		t.expect(#v.asks()).toBe(2)
	end)

	it("all, day and week are buttons of at least the touch size that ask for only their board", function()
		local v = lobbyView(true)
		local all = v.button(Lobby.boardTitle("all"))
		local today = v.button(Lobby.boardTitle("day"))
		local week = v.button(Lobby.boardTitle("week"))
		t.expect(all ~= nil and today ~= nil and week ~= nil).toBe(true)
		t.expect(all.Size.Y.Offset >= Lobby.BUTTON_MIN_PX).toBe(true)
		t.expect(today.Size.Y.Offset >= Lobby.BUTTON_MIN_PX).toBe(true)
		t.expect(week.Size.Y.Offset >= Lobby.BUTTON_MIN_PX).toBe(true)
		today.Activated:fire()
		v.remotes.Board.OnClientEvent:fire(
			"day",
			rowsOf({ rank = 1, name = "Cy", score = 5, level = 1 }),
			nil,
			false
		)
		t.expect(v.find("Title").Text).toBe("TODAY")
		t.expect(v.find("Rows").Text).toBe("1 Cy 5 1")
		week.Activated:fire()
		all.Activated:fire()
		t.expect(v.asks()).toEqual({ { "all" }, { "day" }, { "week" }, { "all" } })
		v.find("Start").Activated:fire()
		t.expect(v.remotes.StartGame.toServer).toEqual({ {} })
	end)

	it(
		"the lobby screen requires only Lobby and Travel, the modules f0061's fake engine serves it",
		function()
			table.clear(unknown)
			lobbyView(true)
			lobbyView(false)
			t.expect(unknown).toEqual({})
		end
	)

	it("without a Board remote the lobby asks nothing and keeps the empty panel", function()
		local v = lobbyView(false)
		t.expect(#v.asks()).toBe(0)
		t.expect(v.find("Rows").Text).toBe("No scores yet")
		local view = stripped("src/lobby/client/LobbyView.luau")
		t.expect(string.find(view, 'FindFirstChild("Board")', 1, true) ~= nil).toBe(true)
		t.expect((string.find(view, 'WaitForChild("Board")', 1, true))).toBe(nil)
	end)

	it("FlowView keeps an empty FireServer and hears Rank without waiting for it", function()
		local view = stripped("src/client/FlowView.luau")
		local calls = 0
		for call in string.gmatch(view, ":FireServer%b()") do
			calls += 1
			t.expect(call).toBe(":FireServer()")
		end
		t.expect(calls >= 1).toBe(true)
		t.expect(string.find(view, 'FindFirstChild("Rank")', 1, true) ~= nil).toBe(true)
		t.expect((string.find(view, 'WaitForChild("Rank")', 1, true))).toBe(nil)
		t.expect(string.find(view, "OnClientEvent", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, "Flow.follow", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, "Flow.hearRank", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, "Flow.shownRank", 1, true) ~= nil).toBe(true)
		t.expect(string.find(view, 'banner == "GAME OVER"', 1, true) ~= nil).toBe(true)
		local main = stripped("src/client/Main.client.luau")
		t.expect((string.find(main, "Rank", 1, true))).toBe(nil)
		t.expect(string.find(main, "Flow.overlay", 1, true) ~= nil).toBe(true)
	end)

	it("Ranks creates Rank in code and sends a rank only to a player still in the game", function()
		local r = ranks()
		t.expect(r.remote ~= nil).toBe(true)
		t.expect(r.remote.ClassName).toBe("RemoteEvent")
		r.heard("1", 1, 3)
		t.expect(#r.remote.toClient).toBe(1)
		t.expect(r.remote.toClient[1].player).toBe(r.players[1])
		t.expect(r.remote.toClient[1].args).toEqual({ 1, 3 })
		r.players[1].Parent = nil
		r.heard("1", 2, 4)
		r.heard("99", 1, 1)
		t.expect(#r.remote.toClient).toBe(1)
		r.heard("2", 1, 7)
		t.expect(r.remote.toClient[2].player).toBe(r.players[2])
		t.expect(#r.remote.OnServerEvent.fns).toBe(0)
		local src = stripped("src/server/Ranks.luau")
		t.expect((string.find(src, "OnServerEvent", 1, true))).toBe(nil)
		t.expect((string.find(src, "FireServer", 1, true))).toBe(nil)
	end)

	it("the game server starts Ranks before Sessions", function()
		local main = stripped("src/server/Main.server.luau")
		local ranksAt = string.find(main, 'Ranks["%)]*%.start%(')
		local sessionsAt = string.find(main, 'Sessions["%)]*%.start%(')
		t.expect(ranksAt ~= nil and sessionsAt ~= nil and ranksAt < sessionsAt).toBe(true)
	end)
end)
