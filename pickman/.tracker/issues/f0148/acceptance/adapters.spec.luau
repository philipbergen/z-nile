--!strict
-- f0148 AC4: the server adapters, their real source on a stub engine with a stub DataStore. The lobby's Bests puts each
-- player's stored best on the player (Best.ATTRIBUTE) and stores the level they chose; the game place's Bests claims
-- each arriving player's start once (level 1 when the store fails or does not answer within Bests.WAIT) and raises the
-- stored best when a run reaches a new level; Sessions makes each session with the start Sessions.starts gives and
-- hands every step's events to its listeners. Server authority: the start a run plays is the store's, never the
-- client's (the client's request only reaches the lobby's choice, which Best.choose bounds by the stored best).
local Best = require("@logic/Best")
local Session = require("@logic/Session")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local lobby = place.load("lobby.project.json")
local gamePlace = place.load()

local function sourceOf(root: any, path: { string }): string
	local node: any = root
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	assert(node, `{table.concat(path, ".")} in the built place`)
	return node.Source
end

type Signal = { fns: { (...any) -> () }, Connect: (any, (...any) -> ()) -> any, fire: (Signal, ...any) -> () }
local function signal(): Signal
	local s: Signal
	s = {
		fns = {},
		Connect = function(_: any, fn: (...any) -> ()): any
			table.insert(s.fns, fn)
			return { Disconnect = function() end }
		end,
		fire = function(_: Signal, ...: any)
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

-- a DataStore stand-in: one table per store name; `mode` "ok", "fail" (every call errors), "hang" (calls never
-- return) or "failwrite" (UpdateAsync runs the transform, then fails to write it)
type Stores = { data: { [string]: { [string]: any } }, names: { string }, mode: string, writes: number }
local function stores(): (any, Stores)
	local st: Stores = { data = {}, names = {}, mode = "ok", writes = 0 }
	local service = {
		GetDataStore = function(_: any, name: string): any
			table.insert(st.names, name)
			st.data[name] = st.data[name] or {}
			local d = st.data[name]
			local function gate()
				if st.mode == "fail" then
					error("stub DataStore failure", 0)
				elseif st.mode == "hang" then
					coroutine.yield()
					error("stub DataStore never answered", 0)
				end
			end
			return {
				GetAsync = function(_: any, key: string): any
					gate()
					return d[key]
				end,
				UpdateAsync = function(_: any, key: string, fn: (any) -> any): any
					gate()
					local v = fn(d[key])
					if st.mode == "failwrite" then
						error("stub DataStore write failure", 0)
					end
					d[key] = v
					st.writes += 1
					return v
				end,
			}
		end,
	}
	return service, st
end

local function player(id: number, playersService: any): any
	local attributes: { [string]: any } = {}
	return {
		UserId = id,
		Name = `p{id}`,
		DisplayName = `p{id}`,
		Parent = playersService,
		SetAttribute = function(_: any, n: string, v: any)
			attributes[n] = v
		end,
		GetAttribute = function(_: any, n: string): any
			return attributes[n]
		end,
	}
end

type Engine = { env: { [string]: any }, players: any, clock: { now: number }, stores: Stores }
local function engine(extra: { [string]: any }?): Engine
	local service, st = stores()
	local playersService: any = { PlayerAdded = signal(), PlayerRemoving = signal(), list = {} }
	playersService.GetPlayers = function(): { any }
		return playersService.list
	end
	local clock = { now = 0 }
	local services: { [string]: any } = { DataStoreService = service, Players = playersService }
	for k, v in (extra or {}) :: { [string]: any } do
		services[k] = v
	end
	local env: { [string]: any } = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], `the adapter asks for {name}`)
			end,
		},
		require = function(path: string): any
			local feature = string.match(path, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
			assert(feature, `the adapter requires {path}`)
			return (require :: any)("@logic/" .. feature)
		end,
		task = {
			spawn = function(fn: (...any) -> (), ...: any)
				local ok, err = coroutine.resume(coroutine.create(fn), ...)
				if not ok then
					error(err, 0)
				end
			end,
			wait = function(seconds: number?): number
				local dt = seconds or 0.03
				clock.now += dt
				return dt
			end,
		},
	}
	return { env = env, players = playersService, clock = clock, stores = st }
end

local function load(e: Engine, source: string, name: string): any
	return luau.load(source, { debugName = name, environment = e.env })()
end

local LOBBY_BESTS = { "ServerScriptService", "Lobby", "Bests" }
local GAME_BESTS = { "ServerScriptService", "Server", "Bests" }
local SESSIONS = { "ServerScriptService", "Server", "Sessions" }

return t.spec("f0148 the server adapters", function(it)
	-- the lobby -------------------------------------------------------------------------------------------------------

	it("the lobby puts each arriving player's stored best on the player, and a fresh player's 1", function()
		local e = engine()
		e.stores.data[Best.STORE] = { ["21"] = { best = 4, next = 2 } }
		local mod = load(e, sourceOf(lobby, LOBBY_BESTS), "Bests")
		mod.start()
		t.expect(e.stores.names[1]).toBe(Best.STORE)
		local a, b = player(21, e.players), player(22, e.players)
		e.players.PlayerAdded:fire(a)
		e.players.PlayerAdded:fire(b)
		t.expect(a:GetAttribute(Best.ATTRIBUTE)).toBe(4)
		t.expect(b:GetAttribute(Best.ATTRIBUTE)).toBe(1)
	end)

	it("the lobby reads players already in when it starts, and sets nothing when the store fails", function()
		local e = engine()
		e.stores.data[Best.STORE] = { ["23"] = { best = 3 } }
		local early = player(23, e.players)
		table.insert(e.players.list, early)
		local mod = load(e, sourceOf(lobby, LOBBY_BESTS), "Bests")
		mod.start()
		t.expect(early:GetAttribute(Best.ATTRIBUTE)).toBe(3)
		e.stores.mode = "fail"
		local late = player(24, e.players)
		e.players.PlayerAdded:fire(late)
		t.expect(late:GetAttribute(Best.ATTRIBUTE)).toBe(nil)
	end)

	it(
		"the lobby stores the chosen level, bounded by the stored best; a failing store is no error",
		function()
			local e = engine()
			e.stores.data[Best.STORE] = { ["25"] = { best = 4 } }
			local mod = load(e, sourceOf(lobby, LOBBY_BESTS), "Bests")
			mod.start()
			local p = player(25, e.players)
			mod.choose(p, 2)
			t.expect(e.stores.data[Best.STORE]["25"]).toEqual({ best = 4, next = 2 })
			mod.choose(p, 9) -- more than the best: the best
			t.expect(e.stores.data[Best.STORE]["25"]).toEqual({ best = 4, next = 4 })
			mod.choose(p, "3") -- not a number: the best
			t.expect(e.stores.data[Best.STORE]["25"]).toEqual({ best = 4, next = 4 })
			e.stores.mode = "fail"
			mod.choose(p, 1)
			t.expect(e.stores.data[Best.STORE]["25"]).toEqual({ best = 4, next = 4 })
		end
	)

	-- the game place --------------------------------------------------------------------------------------------------

	it("the game place claims each arriving player's chosen start once and clears it", function()
		local e = engine()
		e.stores.data[Best.STORE] = { ["31"] = { best = 5, next = 3 }, ["32"] = { best = 2, next = 9 } }
		local mod = load(e, sourceOf(gamePlace, GAME_BESTS), "Bests")
		mod.start()
		local a, b, c = player(31, e.players), player(32, e.players), player(33, e.players)
		for _, p in { a, b, c } do
			e.players.PlayerAdded:fire(p)
		end
		t.expect(mod.startOf(a)).toBe(3)
		t.expect(e.stores.data[Best.STORE]["31"]).toEqual({ best = 5 })
		t.expect(mod.startOf(b)).toBe(1) -- a choice over the best is never played
		t.expect(mod.startOf(c)).toBe(1) -- nothing stored
	end)

	it(
		"a failing store starts the run on level 1; one that never answers does after Bests.WAIT seconds",
		function()
			local e = engine()
			e.stores.data[Best.STORE] = { ["34"] = { best = 5, next = 4 } }
			local mod = load(e, sourceOf(gamePlace, GAME_BESTS), "Bests")
			mod.start()
			e.stores.mode = "fail"
			local p = player(34, e.players)
			e.players.PlayerAdded:fire(p)
			t.expect(mod.startOf(p)).toBe(1)
			-- a claim whose write fails was not taken: the stored choice stays, and this run starts on level 1
			e.stores.mode = "failwrite"
			local w = player(36, e.players)
			e.stores.data[Best.STORE]["36"] = { best = 5, next = 4 }
			e.players.PlayerAdded:fire(w)
			t.expect(mod.startOf(w)).toBe(1)
			e.stores.mode = "hang"
			local q = player(35, e.players)
			e.players.PlayerAdded:fire(q)
			local before = e.clock.now
			t.expect(mod.startOf(q)).toBe(1)
			t.expect(e.clock.now - before >= mod.WAIT).toBe(true)
			t.expect(e.clock.now - before < mod.WAIT + 1).toBe(true)
			t.expect(mod.WAIT).toBe(10)
		end
	)

	it(
		"a run reaching a new level raises its player's stored best; a death or a lower level changes nothing",
		function()
			local e = engine()
			e.stores.data[Best.STORE] = { ["41"] = { best = 3 } }
			local mod = load(e, sourceOf(gamePlace, GAME_BESTS), "Bests")
			mod.start()
			mod.reached({ { kind = "Ready", reason = "level", level = 4, player = "41" } })
			t.expect(e.stores.data[Best.STORE]["41"]).toEqual({ best = 4 })
			local writes = e.stores.writes
			mod.reached({
				{ kind = "Ready", reason = "respawn", level = 9, player = "41" },
				{ kind = "Ready", reason = "again", level = 9, player = "41" },
				{ kind = "LevelCleared", level = 9, player = "41" },
			} :: { any })
			t.expect(e.stores.writes).toBe(writes)
			mod.reached({ { kind = "Ready", reason = "level", level = 2, player = "41" } })
			t.expect(e.stores.data[Best.STORE]["41"]).toEqual({ best = 4 })
			mod.reached({ { kind = "Ready", reason = "level", level = 2, player = "42" } })
			t.expect(e.stores.data[Best.STORE]["42"]).toEqual({ best = 2 })
		end
	)

	-- Sessions ---------------------------------------------------------------------------------------------------------

	local function world(): any
		local heartbeat = signal()
		local remotes: { [string]: any } = {}
		local snapshots = 0
		for _, name in { "Ready", "Intent", "Snapshot", "ToLobby", "LobbyStatus" } do
			remotes[name] = {
				Name = name,
				OnServerEvent = signal(),
				FireClient = function()
					snapshots += 1
				end,
			}
		end
		local e = engine({
			ReplicatedStorage = {
				WaitForChild = function(_: any, n: string): any
					assert(n == "Remotes", n)
					return {
						WaitForChild = function(_: any, r: string): any
							return assert(remotes[r], r)
						end,
					}
				end,
			},
			RunService = { Heartbeat = heartbeat },
		})
		local mod = load(e, sourceOf(gamePlace, SESSIONS), "Sessions")
		return { e = e, mod = mod, heartbeat = heartbeat, remotes = remotes }
	end

	it(
		"Sessions makes each session on the level Sessions.starts gives, and on level 1 without one",
		function()
			for _, case in { { start = 4 :: number?, want = 4 }, { start = nil :: number?, want = 1 } } do
				local w = world()
				local asked: { any } = {}
				if case.start then
					w.mod.starts(function(p: any): number
						table.insert(asked, p)
						return case.start :: number
					end)
				end
				local level: number? = nil
				w.mod.start({
					ready = function(s: any, p: any)
						level = Session.frame(s, tostring(p.UserId)).play.level
					end,
					step = function(): boolean
						return false
					end,
				})
				local p = player(51, w.e.players)
				w.remotes.Ready.OnServerEvent:fire(p)
				t.expect(level).toBe(case.want)
				t.expect(#asked).toBe(if case.start then 1 else 0)
			end
		end
	)

	it(
		"Sessions hands every step's events to each listener, the run's own Ready with its starting level included",
		function()
			local w = world()
			w.mod.starts(function(): number
				return 3
			end)
			local heard: { any } = {}
			w.mod.listen(function(events: { any })
				for _, ev in events do
					table.insert(heard, ev)
				end
			end)
			w.mod.start(nil)
			local p = player(53, w.e.players)
			w.remotes.Ready.OnServerEvent:fire(p)
			for _ = 1, 70 do
				w.heartbeat:fire(1 / Session.STEP_RATE)
			end
			local playing = nil
			for _, ev in heard do
				if ev.kind == "Playing" then
					playing = ev
				end
			end
			t.expect(playing ~= nil and playing.level == 3).toBe(true)
		end
	)

	it("a second Ready while the first waits for the start makes no second session", function()
		local w = world()
		local waiting: { thread } = {}
		local calls = 0
		w.mod.starts(function(): number
			calls += 1
			table.insert(waiting, coroutine.running())
			coroutine.yield()
			return 2
		end)
		local made = 0
		w.mod.start({
			ready = function()
				made += 1
			end,
			step = function(): boolean
				return false
			end,
		})
		local p = player(54, w.e.players)
		w.remotes.Ready.OnServerEvent:fire(p)
		w.remotes.Ready.OnServerEvent:fire(p)
		for _, co in waiting do
			coroutine.resume(co)
		end
		t.expect(calls >= 1).toBe(true)
		t.expect(made).toBe(1)
	end)

	-- the wiring ------------------------------------------------------------------------------------------------------

	-- the source without comments
	local function code(root: any, path: { string }): string
		return (string.gsub(sourceOf(root, path), "%-%-[^\n]*", ""))
	end
	local function order(src: string, patterns: { string }): boolean
		local at = 0
		for _, pat in patterns do
			local found = string.find(src, pat, at + 1)
			if found == nil then
				return false
			end
			at = found
		end
		return true
	end

	it(
		"each place's Main hands the hooks over: the store adapter starts first, then the hooks, then what uses them",
		function()
			local lobbyMain = code(lobby, { "ServerScriptService", "Lobby", "Main" })
			t.expect(
				order(
					lobbyMain,
					{ "Bests%.start%(%)", "Starts%.choosing%(%s*Bests%.choose%s*%)", "Starts%.start%(%)" }
				)
			).toBe(true)
			local gameMain = code(gamePlace, { "ServerScriptService", "Server", "Main" })
			t.expect(order(gameMain, {
				"Bests%.start%(%)",
				"Sessions%.starts%(%s*Bests%.startOf%s*%)",
				"Sessions%.listen%(%s*Bests%.reached%s*%)",
				"Sessions%.start%(",
			})).toBe(true)
			local clientMain = code(lobby, { "StarterPlayer", "StarterPlayerScripts", "Lobby", "Main" })
			t.expect(order(clientMain, {
				'LobbyView"%)%.start%(%)',
				'LobbyPicker"%)%.new%(%)',
				"%.usePicker%(%s*picker%s*%)",
				"picker%.attach%(%)",
			})).toBe(true)
		end
	)
end)
