--!strict
-- f0145 AC5: the paid-play adapters, run from their real sources on a stub engine (an in-memory DataStore, a
-- MarketplaceService that records prompts and holds ProcessReceipt, players, remotes made at run time). Purchases
-- grants a receipt once and answers PurchaseGranted only after the record is written; an unknown product or a
-- failed write answers NotProcessedYet and grants nothing. The lobby lets a player start when a free start is due
-- or a play is held (the start itself is charged on arrival), and otherwise opens the purchase screen: Roblox's in
-- live mode with the configured product, the test screen in test mode; a grant starts the game at once, and a test
-- confirmation grants only in test mode. The game place charges the start on the player's first Ready, switches the
-- continue offer on for their run, uses a held continue at once, holds the countdown while a purchase screen is
-- open, continues on a grant during the offer, keeps a grant after the offer as a held continue, and ends the offer
-- at the next step on a decline. The stub loader falls back to the real Logic (pickman-test stub-loaders-fall-back).
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Pay = require("@logic/Pay")
local Session = require("@logic/Session")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()
local lobbyPlace = place.load("lobby.project.json")

local function sourceAt(root: any, path: { string }): string
	local node = root
	for _, part in path do
		node = node and node:FindFirstChild(part)
	end
	assert(node, `no {table.concat(path, ".")}`)
	return node.Source
end

local PURCHASES = sourceAt(gamePlace, { "ReplicatedStorage", "Shared", "Purchases" })
local LOBBY_PAID = sourceAt(lobbyPlace, { "ServerScriptService", "Lobby", "Paid" })
local LOBBY_STARTS = sourceAt(lobbyPlace, { "ServerScriptService", "Lobby", "Starts" })
local CONTINUES = sourceAt(gamePlace, { "ServerScriptService", "Server", "Continues" })

local PLAY_ID, CONTINUE_ID = 1001, 1002
local NOW = 1792108800

type Signal = { Connect: (any, (...any) -> ()) -> (), fire: (...any) -> () }
local function signal(): Signal
	local fns: { (...any) -> () } = {}
	return {
		Connect = function(_: any, fn: (...any) -> ())
			table.insert(fns, fn)
		end,
		fire = function(...: any)
			for _, fn in fns do
				fn(...)
			end
		end,
	}
end

local function enumProxy(): any
	return setmetatable({}, {
		__index = function(self: any, group: string): any
			local g = setmetatable({}, {
				__index = function(gs: any, item: string): any
					local v = `{group}.{item}`
					rawset(gs, item, v)
					return v
				end,
			})
			rawset(self, group, g)
			return g
		end,
	})
end

type Sent = { remote: string, player: any, args: { any } }
type World = {
	records: { [string]: any }, -- the store of the world's mode, by user id
	stores: { [string]: { [string]: any } }, -- every store, by name
	passes: { [string]: any }, -- the MemoryStore pass map
	race: ((store: { [string]: any }, key: string) -> ())?, -- another server's write, just before this one's transform
	twice: boolean, -- UpdateAsync calls the transform first with the value it read before the race, then again
	failWrites: boolean,
	failReads: boolean,
	failPassReads: boolean, -- the MemoryStore pass map cannot be read
	failTeleport: boolean, -- TeleportAsync errors
	writes: number, -- UpdateAsync calls
	clock: number, -- os.clock(), moved by the cases
	onWrite: (() -> ())?, -- runs inside the next write, before its transform, as events would while a real write yields
	kicks: { { player: any, message: string } },
	delayed: { { seconds: number, fn: (...any) -> (), args: { any } } },
	elapse: () -> (), -- runs every task.delay callback
	leave: (player: any) -> (),
	reads: number,
	onRead: (() -> ())?, -- runs inside a read, as another press would while a real read yields
	prompts: { { player: any, id: number } },
	teleports: { any },
	sent: { Sent },
	attributes: { [string]: any },
	remote: (name: string) -> any,
	player: (userId: number) -> any,
	receipt: (userId: number, productId: number, purchaseId: string) -> string,
	finished: (userId: number, productId: number, bought: boolean) -> (),
	env: { [string]: any },
	deferred: { () -> () },
	flush: () -> (),
}

local function world(mode: string?): World
	local enum = enumProxy()
	local w: World
	local remotes: { [string]: any } = {}
	local players: { any } = {}
	local added, removing = signal(), signal()
	local finishedSignal = signal()
	local guid = 0
	local function makeRemote(name: string): any
		local r = {
			Name = name,
			OnServerEvent = signal(),
			OnClientEvent = signal(),
			FireClient = function(_: any, player: any, ...: any)
				table.insert(w.sent, { remote = name, player = player, args = { ... } })
			end,
		}
		remotes[name] = r
		return r
	end
	makeRemote("Ready")
	makeRemote("StartGame")
	makeRemote("Status")
	local remotesFolder = {
		FindFirstChild = function(_: any, name: string): any
			return remotes[name]
		end,
		WaitForChild = function(_: any, name: string): any
			return assert(remotes[name], `no remote {name}`)
		end,
	}
	local marketplace = {
		PromptProductPurchase = function(_: any, player: any, id: number)
			table.insert(w.prompts, { player = player, id = id })
		end,
		PromptProductPurchaseFinished = finishedSignal,
		ProcessReceipt = nil :: any,
	}
	local services: { [string]: any } = {
		DataStoreService = {
			GetDataStore = function(_: any, name: string): any
				assert(name == Pay.STORE or name == Pay.TEST_STORE, name)
				local held = w.stores[name]
				return {
					UpdateAsync = function(_: any, key: string, fn: (any) -> any): any
						w.writes += 1
						local during = w.onWrite
						if during then
							w.onWrite = nil
							during()
						end
						if w.failWrites then
							error("store down", 0)
						end
						local stale = held[key]
						local race = w.race
						if race then
							w.race = nil
							race(held, key)
						end
						if w.twice then
							fn(stale) -- a first call on an outdated value: its answer must not count
						end
						local nextValue = fn(held[key])
						if nextValue ~= nil then
							held[key] = nextValue
						end
						return nextValue
					end,
					GetAsync = function(_: any, key: string): any
						w.reads += 1
						local hook = w.onRead
						if hook then
							w.onRead = nil
							hook()
						end
						if w.failReads then
							error("store down", 0)
						end
						return held[key]
					end,
				}
			end,
		},
		MarketplaceService = marketplace,
		MemoryStoreService = {
			GetHashMap = function(_: any, name: string): any
				assert(name == "PaidPlayPass", name)
				return {
					SetAsync = function(_: any, key: string, value: any, _ttl: number)
						w.passes[key] = value
					end,
					GetAsync = function(_: any, key: string): any
						if w.failPassReads then
							error("memory store down", 0)
						end
						return w.passes[key]
					end,
					RemoveAsync = function(_: any, key: string)
						w.passes[key] = nil
					end,
				}
			end,
		},
		HttpService = {
			GenerateGUID = function(): string
				guid += 1
				return `guid{guid}`
			end,
		},
		Players = {
			PlayerAdded = added,
			PlayerRemoving = removing,
			GetPlayers = function(): { any }
				return table.clone(players)
			end,
			GetPlayerByUserId = function(_: any, id: number): any
				for _, p in players do
					if p.UserId == id then
						return p
					end
				end
				return nil
			end,
		},
		ReplicatedStorage = {
			WaitForChild = function(_: any, name: string): any
				assert(name == "Remotes", name)
				return remotesFolder
			end,
		},
		ServerScriptService = {
			GetAttribute = function(_: any, name: string): any
				return w.attributes[name]
			end,
		},
		TeleportService = {
			TeleportAsync = function(_: any, destination: number, list: { any })
				table.insert(w.teleports, { destination = destination, player = list[1] })
				if w.failTeleport then
					error("teleport failed", 0)
				end
			end,
			TeleportInitFailed = signal(),
		},
		RunService = { Heartbeat = signal() },
	}
	local loaded: { [string]: any } = {}
	local env: { [string]: any }
	local function requirer(spec: string): any
		if spec == "@game/ReplicatedStorage/Shared/Purchases" then
			if loaded.Purchases == nil then
				loaded.Purchases = luau.load(PURCHASES, { environment = env, debugName = "Purchases" })()
			end
			return loaded.Purchases
		end
		local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
			or string.match(spec, "^%./Logic/([%w_]+)$")
		return (require :: any)("@logic/" .. assert(name, spec))
	end
	env = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], `service {name}`)
			end,
		},
		Enum = enum,
		require = requirer,
		Instance = {
			new = function(class: string): any
				assert(class == "RemoteEvent", class)
				local made: any = nil
				return setmetatable({}, {
					__newindex = function(_: any, key: string, value: any)
						if key == "Name" then
							made = makeRemote(value)
						end
					end,
					__index = function(_: any, key: string): any
						return made and made[key]
					end,
				})
			end,
		},
		os = {
			time = function(): number
				return NOW
			end,
			clock = function(): number
				return w.clock
			end,
		},
		task = {
			defer = function(fn: () -> ())
				table.insert(w.deferred, fn)
			end,
			spawn = function(fn: () -> ())
				fn()
			end,
			delay = function(seconds: number, fn: (...any) -> (), ...: any)
				table.insert(w.delayed, { seconds = seconds, fn = fn, args = { ... } })
			end,
		},
	}
	w = {
		records = {},
		stores = { [Pay.STORE] = {}, [Pay.TEST_STORE] = {} },
		passes = {},
		race = nil,
		twice = false,
		failWrites = false,
		failReads = false,
		failPassReads = false,
		failTeleport = false,
		writes = 0,
		clock = 0,
		onWrite = nil,
		kicks = {},
		delayed = {},
		elapse = function()
			local list = w.delayed
			w.delayed = {}
			for _, d in list do
				d.fn(table.unpack(d.args))
			end
		end,
		leave = function(player: any)
			player.Parent = nil
			local i = table.find(players, player)
			if i then
				table.remove(players, i)
			end
			removing.fire(player)
		end,
		reads = 0,
		onRead = nil,
		prompts = {},
		teleports = {},
		sent = {},
		attributes = {
			PaidPlay = mode,
			PlayProductId = PLAY_ID,
			ContinueProductId = CONTINUE_ID,
			GamePlaceId = 777,
			LobbyPlaceId = 555,
		},
		remote = function(name: string): any
			return assert(remotes[name], `no remote {name}`)
		end,
		player = function(userId: number): any
			local p: any = { UserId = userId, Parent = {}, Name = `P{userId}` }
			p.Kick = function(_: any, message: string)
				table.insert(w.kicks, { player = p, message = message })
				w.leave(p)
			end
			table.insert(players, p)
			added.fire(p)
			return p
		end,
		receipt = function(userId: number, productId: number, purchaseId: string): string
			return marketplace.ProcessReceipt({
				PlayerId = userId,
				ProductId = productId,
				PurchaseId = purchaseId,
			})
		end,
		finished = function(userId: number, productId: number, bought: boolean)
			finishedSignal.fire(userId, productId, bought)
		end,
		env = env,
		deferred = {},
		flush = function()
			local list = w.deferred
			w.deferred = {}
			for _, fn in list do
				fn()
			end
		end,
	}
	w.records = w.stores[Pay.store(Pay.mode(mode, { play = PLAY_ID, continue = CONTINUE_ID }))]

	return w
end

local function sentOn(w: World, remote: string, player: any): { { any } }
	local out = {}
	for _, s in w.sent do
		if s.remote == remote and s.player == player then
			table.insert(out, s.args)
		end
	end
	return out
end

local function lobby(mode: string?): World
	local w = world(mode)
	local paid = luau.load(LOBBY_PAID, { environment = w.env, debugName = "Paid" })() :: any
	local starts = luau.load(LOBBY_STARTS, { environment = w.env, debugName = "Starts" })() :: any
	paid.start(starts.start(paid.allow))
	return w
end

local function press(w: World, p: any)
	w.remote("StartGame").OnServerEvent.fire(p)
end

type Arena = { w: World, s: Session.Session, p: any }

-- the game place with one player who has just arrived (their first Ready)
local function arrive(mode: string?, setup: ((World) -> ())?): Arena
	local w = world(mode)
	local p = w.player(7)
	local s = Session.new(Maze.parse({ "#######", "#..P..#", "#######" }, "corridor"), 1, Session.GAME_CONFIG)
	Session.join(s, "7")
	local continues = luau.load(CONTINUES, { environment = w.env, debugName = "Continues" })() :: any
	continues.start(function(player: any): Session.Session?
		return if player == p and p.Parent ~= nil then s else nil
	end)
	-- as Sessions does: a departing player's run is parked and ends its offer (f0145 Session.depart)
	w.env.game:GetService("Players").PlayerRemoving:Connect(function(player: any)
		if player == p then
			Session.depart(s, "7")
		end
	end)
	if setup then
		setup(w)
	end
	w.remote("Ready").OnServerEvent.fire(p)
	w.flush()
	return { w = w, s = s, p = p }
end

-- the game place with one player whose run is in the continue offer
local function arena(mode: string?, ticks: number?, setup: ((World) -> ())?): Arena
	local a = arrive(mode, setup)
	local w, s, p = a.w, a.s, a.p
	if ticks then
		Session.allowOffer(s, "7", ticks)
	end
	for _ = 1, 3 do
		for _ = 1, 400 do
			if Session.frame(s, "7").play.phase == "playing" then
				break
			end
			Session.step(s)
		end
		Session.kill(s, "7")
		Session.step(s)
	end
	for _ = 1, 400 do
		if Session.offering(s, "7") or Session.isOver(s, "7") then
			break
		end
		Session.step(s)
	end
	return { w = w, s = s, p = p }
end

return t.spec("f0145 the paid-play adapters on a stub engine", function(it)
	it("a receipt is granted once: PurchaseGranted both times, one play held", function()
		local w = lobby("live")
		w.player(7)
		t.expect(w.receipt(7, PLAY_ID, "R1")).toBe("ProductPurchaseDecision.PurchaseGranted")
		t.expect(w.receipt(7, PLAY_ID, "R1")).toBe("ProductPurchaseDecision.PurchaseGranted")
		t.expect(Pay.record(w.records["7"]).plays).toBe(1) -- held: the lobby never spends one, the arrival does
		t.expect(#Pay.record(w.records["7"]).receipts).toBe(1)
		t.expect(#w.teleports).toBe(1)
	end)

	it("a retried receipt already granted grants, starts and asks for nothing more", function()
		local w = lobby("live")
		w.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = { "R1" } }
		w.player(7)
		t.expect(w.receipt(7, PLAY_ID, "R1")).toBe("ProductPurchaseDecision.PurchaseGranted")
		t.expect(Pay.record(w.records["7"]).plays).toBe(0)
		t.expect(#w.prompts).toBe(0)
		t.expect(#w.teleports).toBe(0)
	end)

	it("an unknown product, or a write that fails, answers NotProcessedYet and grants nothing", function()
		local w = lobby("live")
		w.player(7)
		t.expect(w.receipt(7, 999, "R1")).toBe("ProductPurchaseDecision.NotProcessedYet")
		t.expect(w.records["7"]).toBe(nil)
		w.failWrites = true
		t.expect(w.receipt(7, PLAY_ID, "R2")).toBe("ProductPurchaseDecision.NotProcessedYet")
		t.expect(#w.teleports).toBe(0)
	end)

	it("in the lobby a free start due goes at once; the lobby charges nothing (the arrival does)", function()
		local w = lobby("test")
		local p = w.player(7)
		press(w, p)
		t.expect(#w.teleports).toBe(1)
		t.expect(w.teleports[1].destination).toBe(777)
		t.expect(Pay.record(w.records["7"]).free).toBe(nil)
		local told = sentOn(w, "PayStatus", p)
		t.expect(told[#told][1]).toBe("test")
		t.expect(told[#told][2].free).toBe(true)
	end)

	it(
		"with no free start and none held: live mode prompts the play product; test mode opens the test screen",
		function()
			local live = lobby("live")
			live.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
			local p = live.player(7)
			press(live, p)
			t.expect(#live.teleports).toBe(0)
			t.expect(#live.prompts).toBe(1)
			t.expect(live.prompts[1].id).toBe(PLAY_ID)
			t.expect(#sentOn(live, "Purchase", p)).toBe(0)
			local test = lobby(nil)
			test.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
			local q = test.player(7)
			press(test, q)
			t.expect(#test.prompts).toBe(0)
			t.expect(sentOn(test, "Purchase", q)).toEqual({ { "play" } })
		end
	)

	it(
		"a test confirmation grants a play and starts at once, for a screen this server opened, in test mode only",
		function()
			local test = lobby("test")
			test.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
			local p = test.player(7)
			press(test, p) -- opens the test screen
			test.remote("Purchase").OnServerEvent.fire(p, "confirm")
			t.expect(Pay.record(test.records["7"]).plays).toBe(1)
			t.expect(#test.teleports).toBe(1)
			local live = lobby("live")
			live.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
			local q = live.player(7)
			press(live, q) -- Roblox's screen, not the test one
			live.remote("Purchase").OnServerEvent.fire(q, "confirm")
			t.expect(Pay.record(live.records["7"]).plays).toBe(0)
			t.expect(#live.teleports).toBe(0)
		end
	)

	it(
		"a confirm with no test screen open, or after a cancel, grants nothing (lobby and play place)",
		function()
			local w = lobby("test")
			w.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
			local p = w.player(7)
			for _ = 1, 5 do
				w.remote("Purchase").OnServerEvent.fire(p, "confirm")
			end
			t.expect(Pay.record(w.records["7"]).plays).toBe(0)
			press(w, p)
			w.remote("Purchase").OnServerEvent.fire(p, "cancel")
			w.remote("Purchase").OnServerEvent.fire(p, "confirm")
			t.expect(Pay.record(w.records["7"]).plays).toBe(0)
			t.expect(#w.teleports).toBe(0)
			local a = arena("test", 50)
			for _ = 1, 5 do
				a.w.remote("Purchase").OnServerEvent.fire(a.p, "confirm")
			end
			t.expect(Pay.record(a.w.records["7"]).continues).toBe(0)
			t.expect(Session.offering(a.s, "7")).toBe(true)
		end
	)

	it("test credits live in their own store: a live read never sees them", function()
		local w = lobby("test")
		w.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
		local p = w.player(7)
		press(w, p)
		w.remote("Purchase").OnServerEvent.fire(p, "confirm")
		t.expect(Pay.record(w.stores[Pay.TEST_STORE]["7"]).plays).toBe(1)
		t.expect(w.stores[Pay.STORE]["7"]).toBe(nil)
	end)

	it(
		"a second press while the lobby's read is under way is dropped: one read, one teleport, no prompt",
		function()
			local w = lobby("live")
			local p = w.player(7)
			local before = w.reads
			w.onRead = function()
				press(w, p)
			end
			press(w, p)
			t.expect(w.reads - before).toBe(1)
			t.expect(#w.teleports).toBe(1)
			t.expect(#w.prompts).toBe(0)
		end
	)

	it("a held play starts; a store that cannot be read lets the player start", function()
		local w = lobby("live")
		w.records["7"] = { free = NOW - 60, plays = 1, continues = 0, receipts = {} }
		press(w, w.player(7))
		t.expect(#w.teleports).toBe(1)
		local down = lobby("live")
		down.failReads = true
		press(down, down.player(8))
		t.expect(#down.teleports).toBe(1)
	end)

	it("in the game place the start is charged on the first Ready only, and the run's offer is on", function()
		local a = arena("live")
		local r = Pay.record(a.w.records["7"])
		t.expect(r.free).toBe(NOW)
		a.w.records["7"].plays = 1 -- a second Ready would use it if it charged again
		a.w.remote("Ready").OnServerEvent.fire(a.p)
		t.expect(Pay.record(a.w.records["7"]).free).toBe(NOW)
		t.expect(Pay.record(a.w.records["7"]).plays).toBe(1)
		t.expect(Session.offering(a.s, "7")).toBe(true)
		t.expect(a.s.members["7"].play.offer).toBe(Game.OFFER_TICKS)
	end)

	it("an arrival whose store write fails still plays, with the offer on, and charges nothing", function()
		local w = world("live")
		w.failWrites = true
		local p = w.player(9)
		local s9 =
			Session.new(Maze.parse({ "#######", "#..P..#", "#######" }, "corridor"), 1, Session.GAME_CONFIG)
		Session.join(s9, "9")
		local continues = luau.load(CONTINUES, { environment = w.env, debugName = "Continues" })() :: any
		continues.start(function(player: any): Session.Session?
			return if player == p then s9 else nil
		end)
		w.remote("Ready").OnServerEvent.fire(p)
		w.flush()
		t.expect(w.records["9"]).toBe(nil)
		t.expect(s9.members["9"].play.offer).toBe(Game.OFFER_TICKS)
	end)

	it("a continue asked with one held is used at once: three new lives", function()
		local a = arena("live", 50, function(w: World)
			w.records["7"] = { free = nil, plays = 0, continues = 1, receipts = {} }
		end)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(Session.offering(a.s, "7")).toBe(false)
		t.expect(Session.frame(a.s, "7").play.lives).toBe(Game.CONTINUE_LIVES)
		t.expect(Pay.record(a.w.records["7"]).continues).toBe(0)
		t.expect(#a.w.prompts).toBe(0)
	end)

	it(
		"with none held, live mode holds the countdown and prompts; a receipt continues; a closed screen releases",
		function()
			local a = arena("live", 50)
			a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
			t.expect(#a.w.prompts).toBe(1)
			t.expect(a.w.prompts[1].id).toBe(CONTINUE_ID)
			local timer = Session.frame(a.s, "7").play.timer
			for _ = 1, 20 do
				Session.step(a.s)
			end
			t.expect(Session.frame(a.s, "7").play.timer).toBe(timer) -- held while the screen is open
			a.w.finished(7, CONTINUE_ID, false)
			Session.step(a.s)
			t.expect(Session.frame(a.s, "7").play.timer < timer).toBe(true)
			t.expect(a.w.receipt(7, CONTINUE_ID, "C1")).toBe("ProductPurchaseDecision.PurchaseGranted")
			t.expect(Session.offering(a.s, "7")).toBe(false)
			t.expect(Session.frame(a.s, "7").play.lives).toBe(Game.CONTINUE_LIVES)
		end
	)

	it(
		"with none held, test mode opens the test screen; a confirm continues, a cancel releases the countdown",
		function()
			local a = arena("test", 50)
			a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
			t.expect(sentOn(a.w, "Purchase", a.p)).toEqual({ { "continue" } })
			t.expect(#a.w.prompts).toBe(0)
			a.w.remote("Purchase").OnServerEvent.fire(a.p, "confirm")
			t.expect(Session.offering(a.s, "7")).toBe(false)
			t.expect(Session.frame(a.s, "7").play.lives).toBe(Game.CONTINUE_LIVES)
			local b = arena("test", 50)
			b.w.remote("Continue").OnServerEvent.fire(b.p, "ask")
			local timer = Session.frame(b.s, "7").play.timer
			b.w.remote("Purchase").OnServerEvent.fire(b.p, "cancel")
			Session.step(b.s)
			t.expect(Session.frame(b.s, "7").play.timer < timer).toBe(true)
			t.expect(Session.offering(b.s, "7")).toBe(true)
		end
	)

	it("a decline ends the offer at the next step; an ask outside the offer does nothing", function()
		local a = arena("live", 50)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "decline")
		Session.step(a.s)
		t.expect(Session.isOver(a.s, "7")).toBe(true)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(#a.w.prompts).toBe(0)
	end)

	it("a continue granted after its offer ended is held for the next one", function()
		local a = arena("live", 50)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "decline")
		Session.step(a.s)
		t.expect(a.w.receipt(7, CONTINUE_ID, "C9")).toBe("ProductPurchaseDecision.PurchaseGranted")
		t.expect(Pay.record(a.w.records["7"]).continues).toBe(1)
	end)

	it("in live mode a confirm during the offer grants nothing and does not continue", function()
		local a = arena("live", 50)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		a.w.remote("Purchase").OnServerEvent.fire(a.p, "confirm")
		t.expect(Pay.record(a.w.records["7"]).continues).toBe(0)
		t.expect(Session.offering(a.s, "7")).toBe(true)
	end)

	it(
		"a live server with a product id missing refuses paid play: free and held still work, nothing is sold",
		function()
			-- decided with the user, 2026-10-26: "Refuse paid play"
			local a = arena("live", 50, function(w: World)
				w.attributes.ContinueProductId = nil
			end)
			a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
			t.expect(#a.w.prompts).toBe(0)
			t.expect(#sentOn(a.w, "Purchase", a.p)).toBe(0)
			t.expect(a.s.members["7"].play.held).toBe(false) -- the countdown runs on
			a.w.remote("Purchase").OnServerEvent.fire(a.p, "confirm")
			t.expect(Pay.record(a.w.records["7"]).continues).toBe(0)
			t.expect(a.w.records).toBe(a.w.stores[Pay.STORE]) -- the live records, not the test ones
			local b = arena("live", 50, function(w: World)
				w.records["7"] = { free = nil, plays = 0, continues = 1, receipts = {} }
				w.attributes.PlayProductId = 0
			end)
			b.w.remote("Continue").OnServerEvent.fire(b.p, "ask")
			t.expect(Session.offering(b.s, "7")).toBe(false) -- a held continue is still used
			local l = lobby("live")
			l.attributes.PlayProductId = nil
			l.stores[Pay.STORE]["8"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
			local q = l.player(8)
			press(l, q)
			t.expect(#l.prompts).toBe(0)
			t.expect(#sentOn(l, "Purchase", q)).toBe(0)
			t.expect(#l.teleports).toBe(0)
			local said = sentOn(l, "PayStatus", q)
			t.expect(said[#said][1]).toBe("closed")
			l.stores[Pay.STORE]["9"] = { free = nil, plays = 0, continues = 0, receipts = {} }
			press(l, l.player(9)) -- a free game still starts
			t.expect(#l.teleports).toBe(1)
		end
	)

	it(
		"a receipt another server granted during this write counts once and is not handed on as fresh",
		function()
			local w = lobby("live")
			w.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
			w.player(7)
			w.race = function(held: { [string]: any }, key: string)
				held[key] = { free = NOW - 60, plays = 1, continues = 0, receipts = { "R1" } }
			end
			w.twice = true
			t.expect(w.receipt(7, PLAY_ID, "R1")).toBe("ProductPurchaseDecision.PurchaseGranted")
			t.expect(Pay.record(w.records["7"]).plays).toBe(1)
			t.expect(#w.teleports).toBe(0) -- the other server's grant started (or will start) the game, not this one
		end
	)

	it("an arrival racing another server's free start uses a held play, not a second free start", function()
		local a = arena("live", nil, function(w: World)
			w.records["7"] = { free = nil, plays = 1, continues = 0, receipts = {} }
			w.race = function(held: { [string]: any }, key: string)
				held[key] = { free = NOW, plays = 1, continues = 0, receipts = {} }
			end
			w.twice = true
		end)
		local r = Pay.record(a.w.records["7"])
		t.expect(r.free).toBe(NOW)
		t.expect(r.plays).toBe(0)
		t.expect(#a.w.teleports).toBe(0)
	end)

	it(
		"a buy arrival is refused at once (over, nothing submitted) and sent back; a failed write plays",
		function()
			local a = arrive("live", function(w: World)
				w.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
			end)
			t.expect(Session.frame(a.s, "7").play.score).toBe(0)
			t.expect(#a.w.teleports).toBe(1)
			t.expect(a.w.teleports[1].destination).toBe(555)
			t.expect(Session.isOver(a.s, "7")).toBe(true)
			for _ = 1, 100 do
				for _, e in Session.step(a.s) do
					t.expect(e.kind ~= "GameOver").toBe(true)
				end
			end
			t.expect(#a.w.kicks).toBe(0)
			local b = arrive("live", function(w: World)
				w.failWrites = true
			end)
			t.expect(#b.w.teleports).toBe(0)
			t.expect(Session.isOver(b.s, "7")).toBe(false)
			t.expect(b.s.members["7"].play.offer).toBe(Game.OFFER_TICKS)
		end
	)

	it(
		"a player sent back whose teleport errors, fails to start, has no lobby, or does not leave in time is kicked",
		function()
			local function buyer(setup: ((World) -> ())?): Arena
				return arena("live", nil, function(w: World)
					w.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
					if setup then
						setup(w)
					end
				end)
			end
			local a = buyer(function(w: World)
				w.failTeleport = true
			end)
			t.expect(#a.w.kicks).toBe(1)
			t.expect(a.w.kicks[1].message).toBe("Start a game from the lobby.")
			local b = buyer(function(w: World)
				w.attributes.LobbyPlaceId = nil
			end)
			t.expect(#b.w.teleports).toBe(0)
			t.expect(#b.w.kicks).toBe(1)
			local c = buyer()
			t.expect(#c.w.kicks).toBe(0)
			c.w.env.game
				:GetService("TeleportService").TeleportInitFailed
				.fire(c.p, "Enum.TeleportResult.Failure", "x")
			t.expect(#c.w.kicks).toBe(1)
			local d = buyer()
			t.expect(#d.w.delayed).toBe(1)
			t.expect(d.w.delayed[1].seconds).toBe(10)
			d.w.elapse()
			t.expect(#d.w.kicks).toBe(1)
			local e = buyer()
			e.w.leave(e.p) -- the teleport took them: nobody is kicked later
			e.w.elapse()
			t.expect(#e.w.kicks).toBe(0)
			local f = arena("live") -- a paying player is never kicked
			f.w.env.game
				:GetService("TeleportService").TeleportInitFailed
				.fire(f.p, "Enum.TeleportResult.Failure", "x")
			f.w.elapse()
			t.expect(#f.w.kicks).toBe(0)
		end
	)

	it(
		"the lobby's pass is taken on every arrival: after a free arrival, a later buy arrival is sent back",
		function()
			local a = arena("live", nil, function(w: World)
				w.records["7"] = { free = nil, plays = 0, continues = 0, receipts = {} }
				w.passes["7"] = true
			end)
			t.expect(a.w.passes["7"]).toBe(nil)
			t.expect(#a.w.teleports).toBe(0)
			local b = arena("live", nil, function(w: World)
				w.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
			end)
			t.expect(#b.w.teleports).toBe(1)
		end
	)

	it('a buy arrival whose pass map cannot be read plays (the user, 2026-10-26: "Let them play")', function()
		local a = arena("live", nil, function(w: World)
			w.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
			w.failPassReads = true
		end)
		t.expect(#a.w.teleports).toBe(0)
		t.expect(Session.isOver(a.s, "7")).toBe(false)
		t.expect(a.s.members["7"].play.offer).toBe(Game.OFFER_TICKS)
	end)

	it(
		"a player the lobby let in on a failed read plays that one game free (the user, 2026-10-26)",
		function()
			local a = arena("live", nil, function(w: World)
				w.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
				w.passes["7"] = true -- the lobby's pass
			end)
			t.expect(#a.w.teleports).toBe(0)
			t.expect(a.s.members["7"].play.offer).toBe(Game.OFFER_TICKS)
			t.expect(a.w.passes["7"]).toBe(nil) -- taken once
			local l = lobby("live")
			l.failReads = true
			local p = l.player(8)
			press(l, p)
			t.expect(l.passes["8"]).toBe(true)
		end
	)

	it("a screen closed bought before its receipt holds the offer until the receipt continues it", function()
		local a = arena("live", 3)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		a.w.finished(7, CONTINUE_ID, true)
		for _ = 1, 5 do
			Session.step(a.s)
		end
		t.expect(Session.offering(a.s, "7")).toBe(true)
		t.expect(a.w.receipt(7, CONTINUE_ID, "C1")).toBe("ProductPurchaseDecision.PurchaseGranted")
		t.expect(Session.offering(a.s, "7")).toBe(false)
		t.expect(Session.frame(a.s, "7").play.lives).toBe(Game.CONTINUE_LIVES)
	end)

	it(
		"bought with no receipt, the countdown runs again after RECEIPT_WAIT_TICKS; not bought, at once",
		function()
			local a = arena("live", 3)
			a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
			a.w.finished(7, CONTINUE_ID, true)
			for _ = 1, Game.RECEIPT_WAIT_TICKS - 1 do
				Session.step(a.s)
			end
			t.expect(Session.frame(a.s, "7").play.timer).toBe(3)
			for _ = 1, 4 do
				Session.step(a.s)
			end
			t.expect(Session.isOver(a.s, "7")).toBe(true)
			local b = arena("live", 3)
			b.w.remote("Continue").OnServerEvent.fire(b.p, "ask")
			b.w.finished(7, CONTINUE_ID, false)
			for _ = 1, 3 do
				Session.step(b.s)
			end
			t.expect(Session.isOver(b.s, "7")).toBe(true)
		end
	)

	it(
		"a second ask while a continue's write is in flight is dropped: two held, one spent, one continue",
		function()
			local a = arena("live", 50, function(w: World)
				w.records["7"] = { free = nil, plays = 0, continues = 2, receipts = {} }
			end)
			a.w.onWrite = function()
				a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
			end
			a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
			t.expect(Pay.record(a.w.records["7"]).continues).toBe(1)
			t.expect(Session.frame(a.s, "7").play.lives).toBe(Game.CONTINUE_LIVES)
			t.expect(a.w.writes).toBe(1 + 1) -- the arrival's and this continue's
			t.expect(#a.w.prompts).toBe(0)
		end
	)

	it("twenty asks during a continue's write make one write and no prompt", function()
		local a = arena("live", 50, function(w: World)
			w.records["7"] = { free = nil, plays = 0, continues = 1, receipts = {} }
		end)
		local before = a.w.writes
		a.w.onWrite = function()
			for _ = 1, 20 do
				a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
			end
		end
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(a.w.writes - before).toBe(1)
		t.expect(#a.w.prompts).toBe(0)
		t.expect(Session.frame(a.s, "7").play.lives).toBe(Game.CONTINUE_LIVES)
	end)

	it("a decline during a continue's write keeps the continue held and ends the run", function()
		local a = arena("live", 50, function(w: World)
			w.records["7"] = { free = nil, plays = 0, continues = 1, receipts = {} }
		end)
		a.w.onWrite = function()
			a.w.remote("Continue").OnServerEvent.fire(a.p, "decline")
		end
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(Pay.record(a.w.records["7"]).continues).toBe(1)
		Session.step(a.s)
		t.expect(Session.isOver(a.s, "7")).toBe(true)
	end)

	it(
		"a leave during a receipt's continue write keeps the continue held and ends the run within LEAVE_STEPS",
		function()
			local a = arena("live", 50)
			a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
			a.w.onWrite = function()
				-- the receipt's own write runs first; the leave comes during the continue's write that follows
				a.w.onWrite = function()
					a.w.leave(a.p)
				end
			end
			t.expect(a.w.receipt(7, CONTINUE_ID, "C9")).toBe("ProductPurchaseDecision.PurchaseGranted")
			t.expect(Pay.record(a.w.records["7"]).continues).toBe(1)
			t.expect(Session.frame(a.s, "7").play.lives).toBe(0)
			for _ = 1, 45 do
				Session.step(a.s)
			end
			t.expect(Session.isOver(a.s, "7")).toBe(true)
		end
	)

	it(
		"asks one after another, each after its screen closed, make no write while none is known to be held",
		function()
			-- design review 003 F1: back-to-back asks, live and test
			for _, mode in { "live", "test" } do
				local a = arena(mode, 50)
				local before = a.w.writes
				for _ = 1, 20 do
					a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
					if mode == "live" then
						a.w.finished(7, CONTINUE_ID, false)
					else
						a.w.remote("Purchase").OnServerEvent.fire(a.p, "cancel")
					end
				end
				t.expect(a.w.writes - before).toBe(0)
				t.expect(Session.offering(a.s, "7")).toBe(true)
			end
		end
	)

	it("asks while a purchase screen is open are dropped: one prompt, no write", function()
		local a = arena("live", 50)
		local before = a.w.writes
		for _ = 1, 20 do
			a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		end
		t.expect(#a.w.prompts).toBe(1)
		t.expect(a.w.writes - before).toBe(0)
	end)

	it("when what is held is not known, asks cost at most one write per ASK_SECONDS", function()
		local a = arena("live", 50, function(w: World)
			w.failWrites = true -- the arrival's write fails: nothing is known
		end)
		-- the store keeps failing, so nothing becomes known: only the bound limits the writes
		local before = a.w.writes
		for _ = 1, 20 do
			a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
			a.w.finished(7, CONTINUE_ID, false)
		end
		t.expect(a.w.writes - before).toBe(1)
		a.w.clock += 2
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(a.w.writes - before).toBe(2) -- a new window, a new write
	end)

	it("lobby presses one after another make one read; a press after PRESS_SECONDS reads again", function()
		local l = lobby("live")
		l.records["8"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
		local q = l.player(8)
		local before = l.reads
		for _ = 1, 20 do
			press(l, q)
			l.remote("Purchase").OnServerEvent.fire(q, "cancel")
		end
		t.expect(l.reads - before).toBe(1)
		t.expect(#l.teleports).toBe(0)
		l.clock += 2
		press(l, q)
		t.expect(l.reads - before).toBe(2)
	end)

	it("an ask in time is judged at the ask: the countdown is held while the continue is written", function()
		-- design review 003 F2: the offer has 3 steps left, the write lasts 4
		local a = arena("live", 3, function(w: World)
			w.records["7"] = { free = nil, plays = 0, continues = 1, receipts = {} }
		end)
		a.w.onWrite = function()
			for _ = 1, 4 do
				Session.step(a.s)
			end
		end
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(Session.isOver(a.s, "7")).toBe(false)
		t.expect(Session.frame(a.s, "7").play.lives).toBe(Game.CONTINUE_LIVES)
		t.expect(Pay.record(a.w.records["7"]).continues).toBe(0)
	end)

	it("a flight that finds nothing leaves a hold it did not set: a receipt awaited stays awaited", function()
		local a = arena("live", 50)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		a.w.finished(7, CONTINUE_ID, true) -- bought: the receipt is awaited
		local function zero(held: { [string]: any }, key: string)
			-- the continue was taken meanwhile (the same record used elsewhere)
			local r = Pay.record(held[key])
			r.continues = 0
			held[key] = r
		end
		a.w.onWrite = function() -- the grant's own write
			a.w.onWrite = function() -- the continue's write that follows it
				a.w.race = zero
			end
		end
		t.expect(a.w.receipt(7, CONTINUE_ID, "C5")).toBe("ProductPurchaseDecision.PurchaseGranted")
		t.expect(Session.offering(a.s, "7")).toBe(true)
		t.expect(Session.holding(a.s, "7")).toBe(true)
		t.expect(a.s.members["7"].play.waiting > 0).toBe(true)
	end)

	it(
		"a player who leaves during the arrival's write is neither sent back, teleported nor kicked",
		function()
			local a = arrive("live", function(w: World)
				w.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
				w.onWrite = function()
					w.leave(w.env.game:GetService("Players"):GetPlayers()[1])
				end
			end)
			t.expect(#a.w.teleports).toBe(0)
			t.expect(#a.w.kicks).toBe(0)
			t.expect(#a.w.delayed).toBe(0)
		end
	)
end)
