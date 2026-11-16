--!strict
-- c0202 AC2: Pickman's continue offer on the library's revives (Wallet.useRevive, Wallet.refund, Receipts.ask),
-- on the same stub engine: a revive held is used at once; none held opens Pickman's revive product (Roblox's
-- screen live, the library's test screen in test mode) and holds the countdown; a receipt continues; a closed
-- screen releases; a closed server sells nothing; a decline or a leave during the write gives the revive back;
-- one write in flight; a revive bought within the library's USE_SECONDS of a use is used when the span ends.
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
						hold("get")
						if w.fail.get then
							error("store down", 0)
						end
						return held[key]
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

-- runs a session's member to its last life's end: the offer when it is on, else the game over
local function lose(s: Session.Session)
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
end

-- the game place with user 7 in the continue offer
local function offer(mode: any?, setup: ((any) -> ())?): any
	local a = arrive(mode, setup)
	lose(a.s)
	return a
end

local function sendContinue(a: any, what: string)
	resume(coroutine.create(function()
		a.w.remote("Continue").OnServerEvent.fire(a.p, what)
	end))
end

local function lives(a: any): number
	return Session.frame(a.s, "7").play.lives
end

local function holding(a: any): boolean
	return Session.holding(a.s, "7")
end

local function noFree(w: any, continues: number?)
	w.seed(STORE, 7, { free = NOW - 60, plays = 1, continues = continues or 0, receipts = {} })
end

return t.spec("c0202 Pickman's continue offer on the arcade's revives", function(it)
	it("a revive held is used at once: three new lives, and the record holds one less", function()
		local a = offer("live", function(w: any)
			noFree(w, 2)
		end)
		t.expect(Session.offering(a.s, "7")).toBe(true)
		sendContinue(a, "ask")
		t.expect(Session.offering(a.s, "7")).toBe(false)
		t.expect(lives(a)).toBe(Game.CONTINUE_LIVES)
		t.expect(stored(a.w, STORE, 7).revives).toBe(1)
		t.expect(#a.w.prompts).toBe(0)
		local told = a.w.sentOn("PayStatus", a.p)
		t.expect(told[#told][2].revives).toBe(1)
	end)

	it(
		"with none held, live mode holds the countdown and prompts Pickman's revive product; a receipt continues",
		function()
			local a = offer("live", noFree)
			local writes = a.w.writes
			sendContinue(a, "ask")
			t.expect(a.w.writes).toBe(writes) -- none known held: no write
			t.expect(#a.w.prompts).toBe(1)
			t.expect(a.w.prompts[1].id).toBe(REVIVE_ID)
			t.expect(holding(a)).toBe(true)
			sendContinue(a, "ask") -- an ask while the screen is open is dropped
			t.expect(#a.w.prompts).toBe(1)
			local timer = Session.frame(a.s, "7").play.timer
			for _ = 1, 20 do
				Session.step(a.s)
			end
			t.expect(Session.frame(a.s, "7").play.timer).toBe(timer)
			t.expect(a.w.receipt(7, REVIVE_ID, "C1")).toBe("ProductPurchaseDecision.PurchaseGranted")
			t.expect(Session.offering(a.s, "7")).toBe(false)
			t.expect(lives(a)).toBe(Game.CONTINUE_LIVES)
			local r = stored(a.w, STORE, 7)
			t.expect(r.revives).toBe(0)
			t.expect(r.receipts).toEqual({ "C1" })
		end
	)

	it(
		"Roblox's screen closed without buying lets the countdown run; closed bought, it waits for the receipt",
		function()
			local a = offer("live", noFree)
			sendContinue(a, "ask")
			a.w.finished(7, REVIVE_ID, false)
			t.expect(holding(a)).toBe(false)
			local b = offer("live", noFree)
			sendContinue(b, "ask")
			b.w.finished(7, REVIVE_ID, true)
			t.expect(holding(b)).toBe(true)
			for _ = 1, Game.RECEIPT_WAIT_TICKS - 1 do
				Session.step(b.s)
			end
			t.expect(b.w.receipt(7, REVIVE_ID, "C2")).toBe("ProductPurchaseDecision.PurchaseGranted")
			t.expect(lives(b)).toBe(Game.CONTINUE_LIVES)
			-- another title's product closing changes nothing
			local c = offer("live", noFree)
			sendContinue(c, "ask")
			c.w.finished(7, 202, false)
			t.expect(holding(c)).toBe(true)
		end
	)

	it(
		"with none held, test mode opens the library's test screen for Pickman's revive; BUY continues, CANCEL releases",
		function()
			local a = offer("test", noFree)
			sendContinue(a, "ask")
			t.expect(#a.w.prompts).toBe(0)
			t.expect(a.w.sentOn("TestPurchase", a.p)).toEqual({
				{ "open", PaidPlay.testLines("PICKMAN", "revive", Prices) :: any },
			})
			a.w.answer(a.p, "confirm")
			t.expect(lives(a)).toBe(Game.CONTINUE_LIVES)
			t.expect(stored(a.w, TEST_STORE, 7).revives).toBe(0)
			t.expect(a.w.record(STORE, 7).continues).toBe(0) -- the live record is untouched
			local b = offer("test", noFree)
			sendContinue(b, "ask")
			b.w.answer(b.p, "cancel")
			t.expect(holding(b)).toBe(false)
			t.expect(Session.offering(b.s, "7")).toBe(true)
		end
	)

	it("a closed server sells no revive and holds nothing; a revive held is still used", function()
		local a = offer("live", function(w: any)
			noFree(w)
			w.attributes.ContinueProductId = nil
		end)
		sendContinue(a, "ask")
		t.expect(#a.w.prompts).toBe(0)
		t.expect(#a.w.sentOn("TestPurchase", a.p)).toBe(0)
		t.expect(holding(a)).toBe(false)
		local b = offer("live", function(w: any)
			noFree(w, 1)
			w.attributes.PlayProductId = 0
		end)
		sendContinue(b, "ask")
		t.expect(lives(b)).toBe(Game.CONTINUE_LIVES)
	end)

	it("a decline during a revive's write gives the revive back and ends the run at the next step", function()
		local a = offer("live", function(w: any)
			noFree(w, 1)
		end)
		a.w.hold.update = true
		sendContinue(a, "ask")
		t.expect(holding(a)).toBe(true) -- judged at the ask
		sendContinue(a, "decline")
		a.w.release()
		t.expect(stored(a.w, STORE, 7).revives).toBe(1) -- used, then given back
		Session.step(a.s)
		t.expect(Session.isOver(a.s, "7")).toBe(true)
	end)

	it("a second ask while a revive's write is under way is dropped: one write, one continue", function()
		local a = offer("live", function(w: any)
			noFree(w, 2)
		end)
		local writes = a.w.writes
		a.w.hold.update = true
		sendContinue(a, "ask")
		for _ = 1, 20 do
			sendContinue(a, "ask")
		end
		a.w.release()
		t.expect(a.w.writes - writes).toBe(1)
		t.expect(stored(a.w, STORE, 7).revives).toBe(1)
		t.expect(#a.w.prompts).toBe(0)
		t.expect(lives(a)).toBe(Game.CONTINUE_LIVES)
	end)

	it(
		"a revive bought just after a use that found none is used once the library's span allows it",
		function()
			-- the arrival's claim failed, so nothing was known: the first ask writes (and finds none), then the purchase
			local a = offer("live", function(w: any)
				w.fail.update = true
			end)
			sendContinue(a, "ask") -- the write fails: nothing known, the product is offered
			t.expect(#a.w.prompts).toBe(1)
			a.w.fail.update = false
			a.w.finished(7, REVIVE_ID, true)
			a.w.advance(1)
			t.expect(a.w.receipt(7, REVIVE_ID, "C3")).toBe("ProductPurchaseDecision.PurchaseGranted")
			t.expect(Session.offering(a.s, "7")).toBe(true) -- within the span after the last use's write
			a.w.advance(a.w.wallet().USE_SECONDS)
			t.expect(Session.offering(a.s, "7")).toBe(false)
			t.expect(lives(a)).toBe(Game.CONTINUE_LIVES)
			t.expect(stored(a.w, STORE, 7).revives).toBe(0)
		end
	)

	it("a play bought during the offer is held for a later game and revives nothing", function()
		local a = offer("live", function(w: any)
			noFree(w, 1)
		end)
		t.expect(a.w.receipt(7, PLAY_ID, "P5")).toBe("ProductPurchaseDecision.PurchaseGranted")
		t.expect(Session.offering(a.s, "7")).toBe(true)
		local r = stored(a.w, STORE, 7)
		t.expect(r.plays).toBe(1)
		t.expect(r.revives).toBe(1)
	end)

	it("a revive granted after its offer ended is held for the next one", function()
		local a = offer("live", noFree)
		sendContinue(a, "decline")
		Session.step(a.s)
		t.expect(a.w.receipt(7, REVIVE_ID, "C9")).toBe("ProductPurchaseDecision.PurchaseGranted")
		t.expect(stored(a.w, STORE, 7).revives).toBe(1)
	end)

	it("a player who leaves during a revive's write keeps the revive and the run ends", function()
		local a = offer("live", function(w: any)
			noFree(w, 1)
		end)
		a.w.hold.update = true
		sendContinue(a, "ask")
		a.w.leave(a.p)
		a.w.release()
		t.expect(stored(a.w, STORE, 7).revives).toBe(1)
		for _ = 1, 3 do
			Session.step(a.s)
		end
		t.expect(Session.isOver(a.s, "7")).toBe(true)
	end)
end)
