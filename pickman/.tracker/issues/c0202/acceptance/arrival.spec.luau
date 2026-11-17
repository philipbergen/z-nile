--!strict
-- c0202 AC1: Pickman's game place on the arcade library's paid play (Wallet, Receipts), run from the real
-- sources of both on a stub engine whose stores the portal's server can share. The arrival takes what the player
-- holds whoever sold it: the free start due, a play bought on the portal or in the lobby, or the library's pass
-- (pickman/<user id>); anything else is refused and sent back to LobbyPlaceId, kicked when that fails. A claim
-- that fails plays. The place installs the library's Receipts once.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local PaidPlay = require("@arcade/Logic/PaidPlay")
local Prices = require("@arcade/Prices")
local Session = require("@logic/Session")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()

local function sourceAt(root: any, path: { string }): string
	local node = root
	for _, part in path do
		node = node and node:FindFirstChild(part)
	end
	assert(node, `no {table.concat(path, ".")}`)
	return node.Source
end

-- the library as each place builds it (ServerStorage.Arcade), and pickman's adapters from their places
local CATALOG = sourceAt(gamePlace, { "ServerStorage", "Arcade", "Catalog" })
local WALLET = sourceAt(gamePlace, { "ServerStorage", "Arcade", "Wallet" })
local RECEIPTS = sourceAt(gamePlace, { "ServerStorage", "Arcade", "Receipts" })
local CONTINUES = sourceAt(gamePlace, { "ServerScriptService", "Server", "Continues" })

local NOW = 1792108800
local STORE, TEST_STORE = "PaidPlay", "PaidPlayTest" -- Pickman's records (f0145's names, f0201's catalog)
local PLAY_ID, REVIVE_ID = 101, 102 -- Pickman's two products (PlayProductId, ContinueProductId)
local GAME_PLACE, LOBBY_PLACE = 777, 555
local IDS: { [string]: number } = {
	PlayProductId = PLAY_ID,
	ContinueProductId = REVIVE_ID,
	SnakePlayProductId = 201,
	SnakeReviveProductId = 202,
	InvadersPlayProductId = 301,
	InvadersReviveProductId = 302,
	AsteroidsPlayProductId = 401,
	AsteroidsReviveProductId = 402,
}

type Signal = { Connect: (any, (...any) -> ()) -> (), fire: (...any) -> () }
local function signal(): Signal
	local fns: { (...any) -> () } = {}
	return {
		Connect = function(_: any, fn: (...any) -> ())
			table.insert(fns, fn)
		end,
		fire = function(...: any)
			for _, fn in table.clone(fns) do
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

local function resume(co: thread, ...: any)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		error(debug.traceback(co, tostring(err)), 0)
	end
end

-- A server on a stub engine. `shared` (another world) shares its DataStores and its MemoryStore pass map, as two
-- servers of one experience do: the portal and Pickman's game place, say. In-memory DataStores whose calls can be
-- held (they yield until w.release()), a MemoryStore pass map, players, Marketplace prompts and ProcessReceipt, a
-- Remotes folder whose remotes the adapters make at run time, a TeleportService that records teleports, and a task
-- library whose spawned threads run at once and whose delays run on w.advance(seconds) (those due) or w.elapse() (all).
local function world(mode: any?, shared: any?): any
	local w: any = {}
	local enum = enumProxy()
	local players: { any } = {}
	local added, removing = signal(), signal()
	local finished = signal()
	local initFailed = signal()
	local guid = 0
	w.stores = if shared then shared.stores else {} :: { [string]: { [string]: any } }
	w.passes = if shared then shared.passes else {} :: { [string]: any }
	w.held = {} :: { thread }
	w.hold = { update = false, get = false }
	w.fail = { update = false, get = false, passGet = false, teleport = false }
	w.writes, w.reads = 0, 0
	w.clock = 0
	w.now = NOW
	w.prompts = {} :: { { player: any, id: number } }
	w.sent = {} :: { { remote: string, player: any, args: { any } } }
	w.teleports = {} :: { { destination: number, player: any } }
	w.kicks = {} :: { { player: any, message: string } }
	w.delayed = {} :: { { due: number, fn: (...any) -> (), args: { any } } }
	w.receiptSetters = 0 -- how many times ProcessReceipt was assigned
	w.attributes = { PaidPlay = mode, GamePlaceId = GAME_PLACE, LobbyPlaceId = LOBBY_PLACE }
	for k, v in IDS do
		w.attributes[k] = v
	end

	local function storeOf(name: string): { [string]: any }
		local s = w.stores[name]
		if s == nil then
			s = {}
			w.stores[name] = s
		end
		return s
	end
	local function hold(which: string)
		if w.hold[which] then
			w.hold[which] = false
			table.insert(w.held, coroutine.running())
			coroutine.yield()
		end
	end

	-- instances: a Name, children by name, a Parent that files them under it
	local function node(class: string): any
		local children: { [string]: any } = {}
		local n: any = { ClassName = class, children = children }
		n.FindFirstChild = function(_: any, name: string): any
			return children[name]
		end
		n.WaitForChild = function(_: any, name: string): any
			return assert(children[name], `no child {name}`)
		end
		if class == "RemoteEvent" then
			n.OnServerEvent = signal()
			n.FireClient = function(self: any, player: any, ...: any)
				table.insert(w.sent, { remote = self.Name, player = player, args = { ... } })
			end
			n.FireAllClients = function() end
		end
		return setmetatable({}, {
			__index = n,
			__newindex = function(self: any, key: string, value: any)
				if key == "Parent" then
					value.children[n.Name] = self
				end
				n[key] = value
			end,
		})
	end
	local replicated = node("ReplicatedStorage")
	local remotes = node("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = replicated
	for _, name in { "StartGame", "Status", "Ready", "Intent", "Snapshot", "ToLobby", "LobbyStatus" } do
		local r = node("RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end

	local marketplace: any = setmetatable({
		PromptProductPurchase = function(_: any, player: any, id: number)
			table.insert(w.prompts, { player = player, id = id })
		end,
		PromptProductPurchaseFinished = finished,
	}, {
		__newindex = function(self: any, key: string, value: any)
			if key == "ProcessReceipt" then
				w.receiptSetters += 1
			end
			rawset(self, key, value)
		end,
	})
	local services: { [string]: any } = {
		DataStoreService = {
			GetDataStore = function(_: any, name: string): any
				local held = storeOf(name)
				return {
					UpdateAsync = function(_: any, key: string, fn: (any) -> any): any
						w.writes += 1
						hold("update")
						if w.fail.update then
							error("store down", 0)
						end
						local value = fn(held[key])
						if value ~= nil then
							held[key] = value
						end
						return value
					end,
					GetAsync = function(_: any, key: string): any
						w.reads += 1
						local value = held[key] -- what the store held when the read began: a held read returns it
						hold("get")
						if w.fail.get then
							error("store down", 0)
						end
						return value
					end,
				}
			end,
		},
		MemoryStoreService = {
			GetHashMap = function(_: any, name: string): any
				assert(name == "PaidPlayPass", name)
				return {
					SetAsync = function(_: any, key: string, value: any, _ttl: number)
						w.passes[key] = value
					end,
					GetAsync = function(_: any, key: string): any
						if w.fail.passGet then
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
			GenerateGUID = function(_: any, _braces: boolean?): string
				guid += 1
				return `guid{guid}`
			end,
		},
		MarketplaceService = marketplace,
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
		ReplicatedStorage = replicated,
		ServerScriptService = {
			GetAttribute = function(_: any, name: string): any
				return w.attributes[name]
			end,
		},
		TeleportService = {
			TeleportAsync = function(_: any, destination: number, list: { any })
				table.insert(w.teleports, { destination = destination, player = list[1] })
				if w.fail.teleport then
					error("teleport failed", 0)
				end
			end,
			TeleportInitFailed = initFailed,
		},
		RunService = { Heartbeat = signal() },
	}
	local loaded: { [string]: any } = {}
	local env: { [string]: any } = {}
	local function load(name: string, src: string): any
		if loaded[name] == nil then
			loaded[name] = luau.load(src, { environment = env, debugName = name })()
		end
		return loaded[name]
	end
	env.game = {
		GetService = function(_: any, name: string): any
			return assert(services[name], `service {name}`)
		end,
	}
	env.Enum = enum
	env.require = function(spec: string): any
		if spec == "./Catalog" then
			return load("Catalog", CATALOG)
		elseif spec == "./Wallet" or spec == "@game/ServerStorage/Arcade/Wallet" then
			return load("Wallet", WALLET)
		elseif spec == "@game/ServerStorage/Arcade/Receipts" then
			return load("Receipts", RECEIPTS)
		elseif spec == "@game/ReplicatedStorage/Arcade/Logic/PaidPlay" then
			return PaidPlay
		elseif spec == "@game/ReplicatedStorage/Arcade/Prices" then
			return Prices
		end
		local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
		if name then
			return (require :: any)("@logic/" .. name)
		end
		error(`stub: no module for require("{spec}")`, 0)
	end
	env.Instance = {
		new = function(class: string): any
			assert(class == "Folder" or class == "RemoteEvent", class)
			return node(class)
		end,
	}
	env.os = {
		time = function(): number
			return w.now
		end,
		clock = function(): number
			return w.clock
		end,
	}
	env.task = {
		spawn = function(fn: any, ...: any)
			if type(fn) == "thread" then
				resume(fn, ...)
			else
				resume(coroutine.create(fn), ...)
			end
		end,
		delay = function(seconds: number, fn: (...any) -> (), ...: any)
			table.insert(w.delayed, { due = w.clock + seconds, fn = fn, args = { ... } })
		end,
		defer = function(fn: any, ...: any)
			env.task.spawn(fn, ...)
		end,
		wait = function(seconds: number?): number
			local co = coroutine.running()
			table.insert(w.delayed, {
				due = w.clock + (seconds or 0),
				fn = function()
					resume(co, seconds or 0)
				end,
				args = {},
			})
			return coroutine.yield()
		end,
	}
	-- resumes the oldest held store call
	w.release = function()
		local co = table.remove(w.held, 1)
		assert(co, "nothing held")
		resume(co)
	end
	-- moves the clock and runs the delays due by then
	w.advance = function(seconds: number)
		w.clock += seconds
		local due: { any }, later: { any } = {}, {}
		for _, d in w.delayed do
			table.insert(if d.due <= w.clock then due else later, d)
		end
		w.delayed = later
		for _, d in due do
			resume(coroutine.create(d.fn), table.unpack(d.args))
		end
	end
	w.player = function(userId: number): any
		local p: any = { UserId = userId, Parent = {}, Name = `P{userId}` }
		p.Kick = function(_: any, message: string)
			table.insert(w.kicks, { player = p, message = message })
			w.leave(p)
		end
		table.insert(players, p)
		resume(coroutine.create(function()
			added.fire(p)
		end))
		return p
	end
	w.leave = function(p: any)
		p.Parent = nil
		local i = table.find(players, p)
		if i then
			table.remove(players, i)
		end
		removing.fire(p)
	end
	w.removing = removing
	w.wallet = function(): any
		return load("Wallet", WALLET)
	end
	w.receipts = function(): any
		return load("Receipts", RECEIPTS)
	end
	w.load = function(name: string, src: string): any
		return load(name, src)
	end
	w.receipt = function(userId: number, productId: number, purchaseId: string): any
		return marketplace.ProcessReceipt({
			PlayerId = userId,
			ProductId = productId,
			PurchaseId = purchaseId,
		})
	end
	w.finished = function(userId: number, productId: number, bought: boolean)
		finished.fire(userId, productId, bought)
	end
	w.initFailed = function(p: any)
		initFailed.fire(p)
	end
	w.remote = function(name: string): any
		local r = remotes:FindFirstChild(name)
		if r == nil then
			local folder = replicated:FindFirstChild("ArcadePaidPlay")
			r = folder and folder:FindFirstChild(name)
		end
		return assert(r, `no remote {name}`)
	end
	-- the library's test screen's answer, as the client sends it
	w.answer = function(p: any, what: any)
		w.remote("TestPurchase").OnServerEvent.fire(p, what)
	end
	w.sentOn = function(remote: string, p: any): { { any } }
		local out = {}
		for _, s in w.sent do
			if s.remote == remote and s.player == p then
				table.insert(out, s.args)
			end
		end
		return out
	end
	w.record = function(storeName: string, userId: number): any
		return storeOf(storeName)[tostring(userId)]
	end
	w.seed = function(storeName: string, userId: number, value: any)
		storeOf(storeName)[tostring(userId)] = value
	end
	return w
end

-- the record as stored, read the library's way
local function stored(w: any, storeName: string, userId: number): PaidPlay.Record
	return PaidPlay.record(w.record(storeName, userId))
end

-- the game place with one player (user 7) whose session exists; `setup` runs before the place boots
local function arrive(mode: any?, setup: ((any) -> ())?, shared: any?): any
	local w = world(mode, shared)
	local p = w.player(7)
	local s = Session.new(Maze.parse({ "#######", "#..P..#", "#######" }, "corridor"), 1, Session.GAME_CONFIG)
	Session.join(s, "7")
	if setup then
		setup(w) -- before the place boots: the attributes are read once, at Receipts.start
	end
	local continues = w.load("Continues", CONTINUES)
	local arrived = continues.start(function(player: any): Session.Session?
		return if player == p and p.Parent ~= nil then s else nil
	end)
	-- as Sessions does: a departing player's run ends its offer (f0145's Session.depart)
	w.removing:Connect(function(player: any)
		if player == p then
			Session.depart(s, "7")
		end
	end)
	arrived(p, s)
	return { w = w, s = s, p = p, arrived = arrived, continues = continues }
end

-- a second server of the experience (the portal) on the same stores, with the library's Receipts installed
local function portal(shared: any?, mode: any?): any
	local w = world(mode or "live", shared)
	w.receipts().start({})
	return w
end

local function played(a: any): boolean
	return a.s.members["7"].play.offer == Game.OFFER_TICKS and not Session.isOver(a.s, "7")
end

return t.spec("c0202 Pickman's game place takes the arcade's entitlement on arrival", function(it)
	it(
		"a player who took the free game on the portal plays at once: the arrival claims it in Pickman's record",
		function()
			local a = arrive("live")
			t.expect(played(a)).toBe(true)
			t.expect(stored(a.w, STORE, 7).free).toBe(NOW)
			t.expect(a.w.record(TEST_STORE, 7)).toBe(nil)
			t.expect(#a.w.teleports).toBe(0)
		end
	)

	it(
		"a game bought on the portal's Pickman card plays at once: its receipt is the held play, used once",
		function()
			local shop = portal()
			shop.seed(STORE, 7, { free = NOW - 60, plays = 0, continues = 0, receipts = {} })
			shop.player(7)
			t.expect(shop.receipt(7, PLAY_ID, "P1")).toBe("ProductPurchaseDecision.PurchaseGranted")
			t.expect(stored(shop, STORE, 7).plays).toBe(1)
			local a = arrive("live", nil, shop)
			t.expect(played(a)).toBe(true)
			local r = stored(a.w, STORE, 7)
			t.expect(r.plays).toBe(0)
			t.expect(r.free).toBe(NOW - 60) -- not a free start: the hour has not passed
			t.expect(r.receipts).toEqual({ "P1" })
			-- a second call for the same arrival charges nothing more
			a.w.seed(STORE, 7, { free = NOW - 60, plays = 1, continues = 0, receipts = { "P1" } })
			a.arrived(a.p, a.s)
			t.expect(stored(a.w, STORE, 7).plays).toBe(1)
			t.expect(#a.w.sentOn("PayStatus", a.p)).toBe(1) -- one arrival, told once
		end
	)

	it("the portal's pass lets a player with nothing to pay with play that one game, once", function()
		local shop = portal()
		shop.seed(STORE, 7, { free = NOW - 60, plays = 0, continues = 0, receipts = {} })
		local buyer = shop.player(7)
		shop.fail.get = true
		local record, problem = shop.wallet().read(buyer, "pickman")
		t.expect(record).toBe(nil)
		t.expect(problem).toBe("down")
		t.expect(shop.wallet().pass(buyer, "pickman")).toBe(true)
		t.expect(shop.passes["pickman/7"]).toBe(true)
		local a = arrive("live", nil, shop)
		t.expect(played(a)).toBe(true)
		t.expect(a.w.passes["pickman/7"]).toBe(nil) -- taken
		t.expect(#a.w.teleports).toBe(0)
		local again = arrive("live", nil, shop) -- the next join has no pass left
		t.expect(Session.isOver(again.s, "7")).toBe(true)
		t.expect(#again.w.teleports).toBe(1)
	end)

	it(
		"with nothing to pay with and no pass the run is refused and the player sent back to the start place",
		function()
			local a = arrive("live", function(w: any)
				w.seed(STORE, 7, { free = NOW - 60, plays = 0, continues = 0, receipts = {} })
				w.passes["7"] = true -- f0145's pass key is not the library's
			end)
			t.expect(Session.isOver(a.s, "7")).toBe(true)
			t.expect(a.s.members["7"].play.offer).toBe(0)
			t.expect(#a.w.teleports).toBe(1)
			t.expect(a.w.teleports[1].destination).toBe(LOBBY_PLACE)
			t.expect(a.w.passes["7"]).toBe(true)
			t.expect(#a.w.kicks).toBe(0)
			a.w.advance(10)
			t.expect(#a.w.kicks).toBe(1) -- still here after BACK_SECONDS
			t.expect(a.w.kicks[1].message).toBe("Start a game from the lobby.")
		end
	)

	it("a player sent back whose teleport errors, has no start place, or fails to start is kicked", function()
		local function nothing(w: any)
			w.seed(STORE, 7, { free = NOW - 60, plays = 0, continues = 0, receipts = {} })
		end
		local errs = arrive("live", function(w: any)
			nothing(w)
			w.fail.teleport = true
		end)
		t.expect(#errs.w.kicks).toBe(1)
		local unset = arrive("live", function(w: any)
			nothing(w)
			w.attributes.LobbyPlaceId = 0
		end)
		t.expect(#unset.w.teleports).toBe(0)
		t.expect(#unset.w.kicks).toBe(1)
		local init = arrive("live", nothing)
		t.expect(#init.w.kicks).toBe(0)
		init.w.initFailed(init.p)
		t.expect(#init.w.kicks).toBe(1)
		-- a paying player whose own teleport fails is never kicked
		local paying = arrive("live")
		paying.w.initFailed(paying.p)
		t.expect(#paying.w.kicks).toBe(0)
	end)

	it("an arrival whose claim fails plays, with the offer on, and charges nothing", function()
		local a = arrive("live", function(w: any)
			w.fail.update = true
		end)
		t.expect(played(a)).toBe(true)
		t.expect(a.w.record(STORE, 7)).toBe(nil)
		t.expect(#a.w.teleports).toBe(0)
		t.expect(a.w.reads).toBe(0) -- nothing is known, so nothing is told: no read to tell it
		t.expect(#a.w.sentOn("PayStatus", a.p)).toBe(0)
	end)

	it("a player who leaves during the claim is neither sent back, teleported nor kicked", function()
		local a = arrive("live", function(w: any)
			w.seed(STORE, 7, { free = NOW - 60, plays = 0, continues = 0, receipts = {} })
			w.hold.update = true
		end)
		a.w.leave(a.p)
		a.w.release()
		a.w.advance(30)
		t.expect(#a.w.teleports).toBe(0)
		t.expect(#a.w.kicks).toBe(0)
	end)

	it("in test mode the arrival claims in Pickman's test store; a live record is untouched", function()
		local a = arrive("test", function(w: any)
			w.seed(STORE, 7, { free = NOW - 60, plays = 3, continues = 0, receipts = {} })
		end)
		t.expect(played(a)).toBe(true)
		t.expect(stored(a.w, TEST_STORE, 7).free).toBe(NOW)
		t.expect(stored(a.w, STORE, 7).plays).toBe(3)
	end)

	it("the arrival tells the player what they hold on PayStatus, in the library's status", function()
		local a = arrive("live", function(w: any)
			w.seed(STORE, 7, { free = NOW - 60, plays = 2, continues = 4, receipts = {} })
		end)
		local told = a.w.sentOn("PayStatus", a.p)
		t.expect(#told).toBe(1)
		t.expect(told[1][1]).toBe("live")
		t.expect(told[1][2]).toEqual(PaidPlay.status(stored(a.w, STORE, 7), NOW))
		t.expect(told[1][2].revives).toBe(4)
		t.expect(told[1][2].plays).toBe(1)
	end)

	it(
		"the game place installs the library's receipts: any title's receipt is granted into its own record",
		function()
			local a = arrive("live")
			t.expect(a.w.receiptSetters).toBe(1)
			t.expect(a.w.receipt(7, 201, "S1")).toBe("ProductPurchaseDecision.PurchaseGranted")
			t.expect(stored(a.w, "SnakePaidPlay", 7).plays).toBe(1)
			t.expect(a.w.receipt(7, PLAY_ID, "P9")).toBe("ProductPurchaseDecision.PurchaseGranted")
			t.expect(stored(a.w, STORE, 7).plays).toBe(1) -- a play bought for later is held, not started
			t.expect(a.w.receipt(7, 999, "X1")).toBe("ProductPurchaseDecision.NotProcessedYet")
		end
	)
end)
