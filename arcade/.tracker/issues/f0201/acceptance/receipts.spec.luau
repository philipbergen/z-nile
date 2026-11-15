--!strict
-- f0201 AC4: Receipts, run from its real source on the same stub engine. ProcessReceipt grants a known product of
-- any title once, into that title's live record by user id, wherever it is processed, answering PurchaseGranted only
-- after the write; an unknown product or a failed write answers NotProcessedYet. A grant, a test grant and a refund
-- refresh the record this server saw, so a purchase is usable at once. ask prompts Roblox in live mode, opens the
-- test screen in test mode, nothing in closed mode; a test confirm grants into the test store only for a screen this
-- server opened for that player. Fresh grants and closed screens are handed to the place, which hears one client
-- message and never reads join data.
local PaidPlay = require("@logic/PaidPlay")
local Prices = require("@shared/Prices")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local function source(service: string, name: string): string
	local node = (built :: any):GetService(service):FindFirstChild("Arcade"):FindFirstChild(name)
	assert(node, `no {service}.Arcade.{name}`)
	return node.Source
end
local CATALOG = source("ServerStorage", "Catalog")
local WALLET = source("ServerStorage", "Wallet")
local RECEIPTS = source("ServerStorage", "Receipts")

local NOW = 1792108800
-- the four titles' product ids in these worlds
local IDS: { [string]: number } = {
	PlayProductId = 101,
	ContinueProductId = 102,
	SnakePlayProductId = 201,
	SnakeReviveProductId = 202,
	InvadersPlayProductId = 301,
	InvadersReviveProductId = 302,
	AsteroidsPlayProductId = 401,
	AsteroidsReviveProductId = 402,
}

type Signal = { Connect: (any, (...any) -> ()) -> (), fire: (...any) -> () }
type Counted = Signal & { connections: () -> number }
local function signal(): Counted
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
		connections = function(): number
			return #fns
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

export type Handle = { done: boolean, results: { any } }
type Event = { kind: string, player: any, name: string, what: string, bought: boolean? }

-- A server on a stub engine: in-memory DataStores (one table per store name), a MemoryStore pass map, players,
-- Marketplace prompts and ProcessReceipt, remotes made at run time, and a task library whose spawned threads run at
-- once, whose delays and waits run on w.elapse() (all) or w.advance(seconds) (those due by then), and whose defer runs at
-- once. A store call can be held: it yields until w.release() resumes it. Spies count what must never happen.
local function world(mode: any?, attrs: { [string]: any }?): any
	local w: any = {}
	local enum = enumProxy()
	local players: { any } = {}
	local removing = signal()
	local finished = signal()
	local guid = 0
	local remotes: { [string]: any } = {}
	local folders: { [string]: any } = {}
	w.stores = {} :: { [string]: { [string]: any } }
	w.passes = {} :: { [string]: any }
	w.held = {} :: { thread }
	w.hold = { update = false, get = false, pass = false }
	w.fail = { update = false, get = false, open = false, passGet = false }
	w.writes, w.reads, w.passReads = 0, 0, 0
	w.race = nil :: ((store: { [string]: any }, key: string) -> ())?
	w.twice = false
	w.clock = 0
	w.prompts = {} :: { { player: any, id: number } }
	w.sent = {} :: { { player: any, args: { any } } }
	w.events = {} :: { Event }
	w.delayed = {} :: { { due: number, fn: () -> () } }
	w.joinReads = 0 -- GetJoinData calls: what a teleport carries is never read
	w.opened = {} :: { string }
	w.attributes = { PaidPlay = mode }
	for k, v in IDS do
		w.attributes[k] = v
	end
	local extra: { [string]: any } = attrs or {}
	for k, v in extra do
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

	local marketplace: any = {
		PromptProductPurchase = function(_: any, player: any, id: number)
			table.insert(w.prompts, { player = player, id = id })
		end,
		PromptProductPurchaseFinished = finished,
		ProcessReceipt = nil,
	}
	local function makeRemote(name: string): any
		local r: any = { Name = name, ClassName = "RemoteEvent", OnServerEvent = signal() }
		r.FireClient = function(_: any, player: any, ...: any)
			table.insert(w.sent, { player = player, args = { ... } })
		end
		remotes[name] = r
		return r
	end
	local replicated: any = {
		FindFirstChild = function(_: any, name: string): any
			return folders[name]
		end,
	}
	local services: { [string]: any } = {
		DataStoreService = {
			GetDataStore = function(_: any, name: string): any
				table.insert(w.opened, name)
				if w.fail.open then
					error("DataStores unreachable", 0)
				end
				local held = storeOf(name)
				return {
					UpdateAsync = function(_: any, key: string, fn: (any) -> any): any
						w.writes += 1
						hold("update")
						if w.fail.update then
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
					SetAsync = function(_: any, key: string, value: any, ttl: number)
						assert(ttl == 300, `ttl {ttl}`)
						w.passes[key] = value
					end,
					GetAsync = function(_: any, key: string): any
						w.passReads += 1
						hold("pass")
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
			GenerateGUID = function(_: any, _braces: boolean): string
				guid += 1
				return `guid{guid}`
			end,
		},
		MarketplaceService = marketplace,
		Players = {
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
		elseif spec == "./Wallet" then
			return load("Wallet", WALLET)
		elseif spec == "@game/ReplicatedStorage/Arcade/Logic/PaidPlay" then
			return PaidPlay
		elseif spec == "@game/ReplicatedStorage/Arcade/Prices" then
			return Prices
		end
		error(`stub: no module for require("{spec}")`, 0)
	end
	env.Instance = {
		new = function(class: string): any
			local made: any = nil
			local props: { [string]: any } = {}
			return setmetatable({}, {
				__newindex = function(_: any, key: string, value: any)
					props[key] = value
					if key == "Parent" then
						if class == "Folder" then
							made = { Name = props.Name, ClassName = "Folder" }
							local children: { [string]: any } = {}
							made.FindFirstChild = function(_: any, n: string): any
								return children[n]
							end
							made.children = children
							folders[props.Name] = made
						elseif class == "RemoteEvent" then
							made = makeRemote(props.Name)
							value.children[props.Name] = made
						else
							error(`stub: Instance.new("{class}")`, 0)
						end
					end
				end,
				__index = function(_: any, key: string): any
					if made then
						return made[key]
					end
					return props[key]
				end,
			})
		end,
	}
	env.os = {
		time = function(): number
			return NOW
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
		delay = function(seconds: number, fn: () -> ())
			table.insert(w.delayed, { due = w.clock + seconds, fn = fn })
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
			})
			return coroutine.yield()
		end,
	}

	-- runs an adapter call as an engine event would: in its own thread, which a held store call suspends
	w.run = function(fn: (...any) -> ...any, ...: any): Handle
		local h: Handle = { done = false, results = {} }
		local args = table.pack(...)
		resume(coroutine.create(function()
			h.results = table.pack(fn(table.unpack(args, 1, args.n)))
			h.done = true
		end))
		return h
	end
	-- resumes the oldest held store call
	w.release = function()
		local co = table.remove(w.held, 1)
		assert(co, "nothing held")
		resume(co)
	end
	-- runs every delay and wait, due or not
	w.elapse = function()
		local list = w.delayed
		w.delayed = {}
		for _, d in list do
			resume(coroutine.create(d.fn))
		end
	end
	-- moves the clock and runs the delays and waits due by then
	w.advance = function(seconds: number)
		w.clock += seconds
		local due: { any }, later: { any } = {}, {}
		for _, d in w.delayed do
			table.insert(if d.due <= w.clock then due else later, d)
		end
		w.delayed = later
		for _, d in due do
			resume(coroutine.create(d.fn))
		end
	end
	w.player = function(userId: number, joinData: any?): any
		local p: any = { UserId = userId, Parent = {}, Name = `P{userId}` }
		p.GetJoinData = function(): any
			w.joinReads += 1
			return { TeleportData = joinData }
		end
		table.insert(players, p)
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
	w.wallet = function(): any
		return load("Wallet", WALLET)
	end
	w.receipts = function(): any
		return load("Receipts", RECEIPTS)
	end
	-- Receipts started with handlers that record what the place hears
	w.start = function(): any
		local r = w.receipts()
		r.start({
			granted = function(player: any, name: string, kind: string)
				table.insert(w.events, { kind = "granted", player = player, name = name, what = kind })
			end,
			closed = function(player: any, name: string, kind: string, bought: boolean)
				table.insert(
					w.events,
					{ kind = "closed", player = player, name = name, what = kind, bought = bought }
				)
			end,
		})
		return r
	end
	w.receipt = function(userId: any, productId: any, purchaseId: any): any
		return marketplace.ProcessReceipt({
			PlayerId = userId,
			ProductId = productId,
			PurchaseId = purchaseId,
		})
	end
	w.finished = function(userId: number, productId: number, bought: boolean)
		finished.fire(userId, productId, bought)
	end
	w.answer = function(p: any, what: any)
		local r = remotes.TestPurchase
		assert(r, "no TestPurchase remote")
		r.OnServerEvent.fire(p, what)
	end
	w.remote = function(name: string): any
		return remotes[name]
	end
	w.folder = function(name: string): any
		return folders[name]
	end
	w.marketplace = marketplace
	w.record = function(storeName: string, userId: number): any
		return storeOf(storeName)[tostring(userId)]
	end
	w.seed = function(storeName: string, userId: number, value: any)
		storeOf(storeName)[tostring(userId)] = value
	end
	return w
end
local GRANTED = "ProductPurchaseDecision.PurchaseGranted" -- the stub's Enum values are their own names
local NOT_YET = "ProductPurchaseDecision.NotProcessedYet"

local function rec(w: any, storeName: string, userId: number): PaidPlay.Record
	return PaidPlay.record(w.record(storeName, userId))
end

local function eventsOf(w: any, kind: string): { any }
	local out = {}
	for _, e in w.events do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

return t.spec("f0201 Receipts on a stub engine", function(it)
	it(
		"a receipt is granted once: PurchaseGranted both times, one credit, and the place hears one grant",
		function()
			local w = world("live")
			local p = w.player(7)
			w.start()
			t.expect(w.run(w.receipt, 7, 202, "buy-1").results[1]).toBe(GRANTED)
			t.expect(w.run(w.receipt, 7, 202, "buy-1").results[1]).toBe(GRANTED)
			t.expect(rec(w, "SnakePaidPlay", 7).revives).toBe(1)
			t.expect(rec(w, "SnakePaidPlay", 7).receipts).toEqual({ "buy-1" })
			local g = eventsOf(w, "granted")
			t.expect(#g).toBe(1)
			t.expect(g[1].player).toBe(p)
			t.expect(g[1].name).toBe("snake")
			t.expect(g[1].what).toBe("revive")
		end
	)

	it("every title's receipt is granted in any place, into its own record, by user id", function()
		local w = world("live")
		w.player(7)
		w.start()
		local cases: { { id: number, store: string, field: string } } = {
			{ id = 101, store = "PaidPlay", field = "plays" },
			{ id = 302, store = "InvadersPaidPlay", field = "revives" },
			{ id = 401, store = "AsteroidsPaidPlay", field = "plays" },
		}
		for _, case in cases do
			t.expect(w.run(w.receipt, 7, case.id, `r{case.id}`).results[1]).toBe(GRANTED)
			t.expect((rec(w, case.store, 7) :: any)[case.field]).toBe(1)
		end
	end)

	it("a buyer not on this server is granted all the same, and nothing is handed to the place", function()
		local w = world("live")
		w.start()
		t.expect(w.run(w.receipt, 9, 201, "away-1").results[1]).toBe(GRANTED)
		t.expect(rec(w, "SnakePaidPlay", 9).plays).toBe(1)
		t.expect(#eventsOf(w, "granted")).toBe(0)
	end)

	it(
		"an unknown product, a missing purchase id or a failed write answers NotProcessedYet and grants nothing",
		function()
			local w = world("live")
			w.player(7)
			w.start()
			t.expect(w.run(w.receipt, 7, 999, "x-1").results[1]).toBe(NOT_YET)
			t.expect(w.run(w.receipt, 7, 101, "").results[1]).toBe(NOT_YET)
			t.expect(w.run(w.receipt, 7, 101, nil).results[1]).toBe(NOT_YET)
			t.expect(w.run(w.receipt, "7", 101, "x-2").results[1]).toBe(NOT_YET)
			w.fail.update = true
			t.expect(w.run(w.receipt, 7, 101, "x-3").results[1]).toBe(NOT_YET)
			w.fail.update = false
			t.expect(w.record("PaidPlay", 7)).toBe(nil)
			t.expect(#eventsOf(w, "granted")).toBe(0)
			t.expect(w.run(w.receipt, 7, 101, "x-3").results[1]).toBe(GRANTED)
			t.expect(rec(w, "PaidPlay", 7).plays).toBe(1)
		end
	)

	it("PurchaseGranted is answered only after the write: a held write holds the answer", function()
		local w = world("live")
		w.player(7)
		w.start()
		w.hold.update = true
		local h = w.run(w.receipt, 7, 101, "slow-1")
		t.expect(h.done).toBe(false)
		t.expect(w.record("PaidPlay", 7)).toBe(nil)
		w.release()
		t.expect(h.results[1]).toBe(GRANTED)
		t.expect(rec(w, "PaidPlay", 7).plays).toBe(1)
	end)

	it(
		"a receipt another server granted during this write counts once and is not handed on as new",
		function()
			local w = world("live")
			w.player(7)
			w.start()
			w.race = function(store: { [string]: any }, key: string)
				store[key] = { plays = 1, revives = 0, receipts = { "dup-1" } }
			end
			t.expect(w.run(w.receipt, 7, 101, "dup-1").results[1]).toBe(GRANTED)
			t.expect(rec(w, "PaidPlay", 7).plays).toBe(1)
			t.expect(#eventsOf(w, "granted")).toBe(0)
		end
	)

	it("the transform's last call decides whether the grant is new", function()
		local w = world("live")
		w.player(7)
		w.start()
		w.twice = true
		w.race = function(store: { [string]: any }, key: string)
			store[key] = { plays = 1, receipts = { "dup-2" } }
		end
		w.run(w.receipt, 7, 101, "dup-2")
		t.expect(rec(w, "PaidPlay", 7).plays).toBe(1)
		t.expect(#eventsOf(w, "granted")).toBe(0)
	end)

	it(
		"a real receipt in test mode is kept in the live record, and not handed to a place that reads the test one",
		function()
			local w = world(nil)
			w.player(7)
			w.start()
			t.expect(w.run(w.receipt, 7, 102, "real-1").results[1]).toBe(GRANTED)
			t.expect(rec(w, "PaidPlay", 7).revives).toBe(1)
			t.expect(w.record("PaidPlayTest", 7)).toBe(nil)
			t.expect(#eventsOf(w, "granted")).toBe(0)
		end
	)

	it("a closed title's receipt is still granted: it was charged", function()
		local w = world("live", { ContinueProductId = "bad" })
		w.player(7)
		w.start()
		t.expect(w.wallet().mode("pickman")).toBe("closed")
		t.expect(w.run(w.receipt, 7, 101, "c-1").results[1]).toBe(GRANTED)
		t.expect(rec(w, "PaidPlay", 7).plays).toBe(1)
		t.expect(#eventsOf(w, "granted")).toBe(1)
	end)

	it("ask in live mode prompts the title's own product; nothing else opens", function()
		local w = world("live")
		local p = w.player(7)
		local r = w.start()
		t.expect(r.ask(p, "snake", "play")).toBe(true)
		t.expect(r.ask(p, "pickman", "revive")).toBe(true)
		t.expect(#w.prompts).toBe(2)
		t.expect(w.prompts[1].player).toBe(p)
		t.expect(w.prompts[1].id).toBe(201)
		t.expect(w.prompts[2].id).toBe(102)
		t.expect(#w.sent).toBe(0)
	end)

	it("ask in closed mode opens nothing and answers false", function()
		local w = world("live", { SnakePlayProductId = 0 })
		local p = w.player(7)
		local r = w.start()
		t.expect(r.ask(p, "snake", "revive")).toBe(false)
		t.expect(#w.prompts).toBe(0)
		t.expect(#w.sent).toBe(0)
	end)

	it("ask in test mode opens the test screen with its lines and never prompts Roblox", function()
		local w = world(nil)
		local p = w.player(7)
		local r = w.start()
		t.expect(r.ask(p, "invaders", "revive")).toBe(true)
		t.expect(#w.prompts).toBe(0)
		t.expect(#w.sent).toBe(1)
		t.expect(w.sent[1].player).toBe(p)
		local expected: { any } = {
			"open",
			{ "INVADERS: REVIVE: 3 NEW LIVES", "5 R$ 1 R$ SALE", "TEST PURCHASE: NOTHING IS CHARGED" },
		}
		t.expect(w.sent[1].args).toEqual(expected)
		t.expect(w.folder("ArcadePaidPlay")).toBeTruthy()
		t.expect(w.remote("TestPurchase")).toBeTruthy()
	end)

	it(
		"a test confirm grants into the test store under a test id; the screen closes bought, then the place hears it",
		function()
			local w = world(nil)
			local p = w.player(7)
			local r = w.start()
			r.ask(p, "snake", "play")
			w.run(w.answer, p, "confirm")
			local tr = rec(w, "SnakePaidPlayTest", 7)
			t.expect(tr.plays).toBe(1)
			t.expect(string.match(tr.receipts[1], "^test:") ~= nil).toBe(true)
			t.expect(w.record("SnakePaidPlay", 7)).toBe(nil)
			t.expect(#w.events).toBe(2)
			t.expect(w.events[1])
				.toEqual({ kind = "closed", player = p, name = "snake", what = "play", bought = true })
			t.expect(w.events[2]).toEqual({ kind = "granted", player = p, name = "snake", what = "play" })
		end
	)

	it("each test confirm is its own purchase: two screens bought, two credits", function()
		local w = world(nil)
		local p = w.player(7)
		local r = w.start()
		r.ask(p, "pickman", "revive")
		w.run(w.answer, p, "confirm")
		r.ask(p, "pickman", "revive")
		w.run(w.answer, p, "confirm")
		t.expect(rec(w, "PaidPlayTest", 7).revives).toBe(2)
	end)

	it("a test confirm whose write fails closes the screen not bought and grants nothing", function()
		local w = world(nil)
		local p = w.player(7)
		local r = w.start()
		r.ask(p, "pickman", "play")
		w.fail.update = true
		w.run(w.answer, p, "confirm")
		t.expect(#eventsOf(w, "granted")).toBe(0)
		t.expect(eventsOf(w, "closed")[1].bought).toBe(false)
	end)

	it(
		"a cancel closes the screen not bought; a confirm after it, or with no screen open, grants nothing",
		function()
			local w = world(nil)
			local p = w.player(7)
			local r = w.start()
			w.run(w.answer, p, "confirm")
			t.expect(#w.events).toBe(0)
			r.ask(p, "pickman", "play")
			w.run(w.answer, p, "cancel")
			w.run(w.answer, p, "confirm")
			t.expect(w.record("PaidPlayTest", 7)).toBe(nil)
			t.expect(#w.events).toBe(1)
			t.expect(w.events[1])
				.toEqual({ kind = "closed", player = p, name = "pickman", what = "play", bought = false })
		end
	)

	it("an answer that is neither confirm nor cancel is ignored and the screen stays open", function()
		local w = world(nil)
		local p = w.player(7)
		local r = w.start()
		r.ask(p, "pickman", "play")
		w.run(w.answer, p, "grant")
		w.run(w.answer, p, { "confirm" })
		t.expect(#w.events).toBe(0)
		w.run(w.answer, p, "confirm")
		t.expect(rec(w, "PaidPlayTest", 7).plays).toBe(1)
	end)

	it(
		"one test screen per player at a time: a second ask opens nothing; another player's confirm grants nothing",
		function()
			local w = world(nil)
			local p = w.player(7)
			local q = w.player(8)
			local r = w.start()
			t.expect(r.ask(p, "pickman", "play")).toBe(true)
			t.expect(r.ask(p, "snake", "revive")).toBe(false)
			t.expect(#w.sent).toBe(1)
			w.run(w.answer, q, "confirm")
			t.expect(w.record("PaidPlayTest", 8)).toBe(nil)
			t.expect(#w.events).toBe(0)
		end
	)

	it("a confirm in live mode grants nothing: no test screen is ever open there", function()
		local w = world("live")
		local p = w.player(7)
		local r = w.start()
		r.ask(p, "pickman", "play")
		w.run(w.answer, p, "confirm")
		t.expect(w.record("PaidPlay", 7)).toBe(nil)
		t.expect(w.record("PaidPlayTest", 7)).toBe(nil)
		t.expect(#w.events).toBe(0)
	end)

	it("a player who leaves with a test screen open: their next join's confirm grants nothing", function()
		local w = world(nil)
		local p = w.player(7)
		local r = w.start()
		r.ask(p, "pickman", "play")
		w.leave(p)
		local again = w.player(7)
		w.run(w.answer, again, "confirm")
		t.expect(w.record("PaidPlayTest", 7)).toBe(nil)
	end)

	it("a grant whose player left during its write is not handed to the place", function()
		local w = world(nil)
		local p = w.player(7)
		local r = w.start()
		r.ask(p, "pickman", "revive")
		w.hold.update = true
		w.run(w.answer, p, "confirm")
		w.leave(p)
		w.release()
		t.expect(rec(w, "PaidPlayTest", 7).revives).toBe(1)
		t.expect(#w.events).toBe(0)
	end)

	it("Roblox's purchase screen closing tells the place, bought or not, for a known product only", function()
		local w = world("live")
		local p = w.player(7)
		w.start()
		w.finished(7, 202, false)
		w.finished(7, 101, true)
		w.finished(7, 999, true)
		w.finished(8, 101, true)
		t.expect(#w.events).toBe(2)
		t.expect(w.events[1])
			.toEqual({ kind = "closed", player = p, name = "snake", what = "revive", bought = false })
		t.expect(w.events[2])
			.toEqual({ kind = "closed", player = p, name = "pickman", what = "play", bought = true })
		t.expect(w.record("PaidPlay", 7)).toBe(nil) -- a closed screen grants nothing
	end)

	it(
		"Receipts starts once per server: the second start does nothing; ask before start is an error",
		function()
			local w = world("live")
			local p = w.player(7)
			local r = w.receipts()
			t.expect(function()
				r.ask(p, "pickman", "play")
			end).toThrow("start")
			t.expect(r.start({})).toBe(true)
			local handler = w.marketplace.ProcessReceipt
			t.expect(type(handler)).toBe("function")
			t.expect(r.start({})).toBe(false)
			t.expect(w.marketplace.ProcessReceipt).toBe(handler)
			t.expect(function()
				r.ask(p, "tetris", "play")
			end).toThrow("no title")
		end
	)

	it("a revive bought on this server is usable at once: the grant refreshes the record seen", function()
		local w = world("live")
		w.seed("PaidPlay", 7, { free = NOW - 7200 })
		local p = w.player(7)
		w.start()
		local wallet = w.wallet()
		w.run(wallet.arrive, p, "pickman")
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(false)
		local writes = w.writes
		t.expect(w.run(w.receipt, 7, 102, "rv-1").results[1]).toBe(GRANTED)
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
		t.expect(w.writes).toBe(writes + 2)
		t.expect(wallet.revives(p, "pickman")).toBe(1)
	end)

	it("a test revive bought is usable at once: the test grant refreshes the record seen", function()
		local w = world(nil)
		local p = w.player(7)
		local r = w.start()
		local wallet = w.wallet()
		w.run(wallet.arrive, p, "pickman")
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(false)
		r.ask(p, "pickman", "revive")
		w.run(w.answer, p, "confirm")
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
	end)

	it("a revive given back is usable again: the refund refreshes the record seen", function()
		local w = world(nil)
		w.seed("PaidPlayTest", 7, { free = NOW - 7200, continues = 1 })
		local p = w.player(7)
		local wallet = w.wallet()
		w.run(wallet.arrive, p, "pickman")
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
		w.run(wallet.refund, p, "pickman", "revive")
		w.advance(7)
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
	end)

	it("a play bought shows in the next read at once, with no new store read", function()
		local w = world("live")
		local p = w.player(7)
		w.start()
		local wallet = w.wallet()
		t.expect(w.run(wallet.read, p, "snake").results[1].plays).toBe(0)
		w.run(w.receipt, 7, 201, "pl-1")
		t.expect(w.run(wallet.read, p, "snake").results[1].plays).toBe(1)
		t.expect(w.reads).toBe(1)
	end)

	it(
		"in test mode a real receipt leaves the record seen alone: the next read still shows the test record",
		function()
			local w = world(nil)
			w.seed("PaidPlayTest", 7, { plays = 2 })
			local p = w.player(7)
			w.start()
			local wallet = w.wallet()
			t.expect(w.run(wallet.read, p, "pickman").results[1].plays).toBe(2)
			w.run(w.receipt, 7, 101, "real-2")
			t.expect(w.run(wallet.read, p, "pickman").results[1].plays).toBe(2)
			t.expect(rec(w, "PaidPlay", 7).plays).toBe(1)
		end
	)

	it(
		"the place's adapters hear one client message: one connection to the test screen's answer, no invoke",
		function()
			local w = world(nil)
			w.player(7)
			w.start()
			local remote = w.remote("TestPurchase")
			t.expect(remote.OnServerEvent.connections()).toBe(1)
			t.expect(rawget(remote, "OnServerInvoke")).toBe(nil)
			t.expect(w.folder("ArcadePaidPlay").children.TestPurchase).toBe(remote)
		end
	)

	it("nothing a teleport carries is read: no Receipts path reads the join data", function()
		local w = world(nil)
		local p = w.player(7, { plays = 9, paid = true })
		local r = w.start()
		r.ask(p, "pickman", "play")
		w.run(w.answer, p, "confirm")
		w.run(w.receipt, 7, 101, "j-1")
		w.finished(7, 101, true)
		local lw = world("live")
		local lp = lw.player(7, { paid = true })
		local lr = lw.start()
		lr.ask(lp, "snake", "revive")
		lw.run(lw.receipt, 7, 202, "j-2")
		t.expect(w.joinReads + lw.joinReads).toBe(0)
	end)
end)
