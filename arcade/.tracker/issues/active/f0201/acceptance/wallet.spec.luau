--!strict
-- f0201 AC3: Wallet, run from its real source on a stub engine (in-memory DataStores whose calls can yield,
-- a MemoryStore pass map, players, a clock). The arrival claims the free start due, else a held play, once per join,
-- in one UpdateAsync whose transform's last call decides, writing f0145's record shape; a failed or slow claim plays;
-- the portal's pass (per title, written only after a read that answered down) is taken on every arrival within
-- WAIT_SECONDS; join data is never read. Revives are used once and counted for the run (less a refund, dropped
-- KEEP_SECONDS after a leave), bounded per player and title; reads are per title, busy, cached, time-limited and
-- held down for RETRY_SECONDS after a failure. A test store that cannot be opened has a stand-in; a live one has
-- none. Calls for a player who left claim nothing.
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
local LIVE, TEST = "PaidPlay", "PaidPlayTest" -- Pickman's stores

-- the portal's read of a title failing, as before it writes a pass
local function downRead(w: any, p: any, name: string)
	w.fail.get = true
	w.run(w.wallet().read, p, name)
	w.fail.get = false
end

-- a player's Pickman record in a store, read back as PaidPlay reads it
local function rec(w: any, storeName: string, userId: number): PaidPlay.Record
	return PaidPlay.record(w.record(storeName, userId))
end

return t.spec("f0201 Wallet on a stub engine", function(it)
	it("a first arrival is free, recorded in test mode's own store; live mode writes the live one", function()
		local w = world(nil)
		local p = w.player(7)
		local h = w.run(w.wallet().arrive, p, "pickman")
		t.expect(h.done).toBe(true)
		t.expect(h.results[1]).toBe("play")
		t.expect(h.results[2]).toBe("free")
		t.expect(rec(w, TEST, 7).free).toBe(NOW)
		t.expect(w.record(LIVE, 7)).toBe(nil)
		local lw = world("live")
		local lp = lw.player(7)
		local lh = lw.run(lw.wallet().arrive, lp, "pickman")
		t.expect(lh.results[2]).toBe("free")
		t.expect(rec(lw, LIVE, 7).free).toBe(NOW)
		t.expect(lw.record(TEST, 7)).toBe(nil)
	end)

	it("each title keeps its own record: a free start in one leaves another's due", function()
		local w = world(nil)
		local p = w.player(7)
		w.run(w.wallet().arrive, p, "snake")
		t.expect(rec(w, "SnakePaidPlayTest", 7).free).toBe(NOW)
		t.expect(w.record(TEST, 7)).toBe(nil)
		local h = w.run(w.wallet().arrive, p, "pickman")
		t.expect(h.results[2]).toBe("free")
		t.expect(rec(w, TEST, 7).free).toBe(NOW)
		t.expect(w.writes).toBe(2)
	end)

	it(
		"within the hour a held play is used; with none the arrival is buy, goes back and writes nothing",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 60, plays = 1 })
			local p = w.player(7)
			local h = w.run(w.wallet().arrive, p, "pickman")
			t.expect(h.results[1]).toBe("play")
			t.expect(h.results[2]).toBe("credit")
			t.expect(rec(w, TEST, 7).plays).toBe(0)
			local w2 = world(nil)
			w2.seed(TEST, 8, { free = NOW - 60 })
			local before = w2.record(TEST, 8)
			local h2 = w2.run(w2.wallet().arrive, w2.player(8), "pickman")
			t.expect(h2.results[1]).toBe("back")
			t.expect(h2.results[2]).toBe("buy")
			t.expect(w2.record(TEST, 8)).toBe(before)
		end
	)

	it(
		"the arrival is charged once per join: a later call answers the same; a new join claims again",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 60, plays = 2 })
			local p = w.player(7)
			w.run(w.wallet().arrive, p, "pickman")
			local h = w.run(w.wallet().arrive, p, "pickman")
			t.expect(h.results[2]).toBe("credit")
			t.expect(w.writes).toBe(1)
			t.expect(rec(w, TEST, 7).plays).toBe(1)
			w.leave(p)
			local again = w.player(7)
			w.run(w.wallet().arrive, again, "pickman")
			t.expect(w.writes).toBe(2)
			t.expect(rec(w, TEST, 7).plays).toBe(0)
		end
	)

	it("a second arrival during the first's write waits for it: one write, the same answer", function()
		local w = world(nil)
		local p = w.player(7)
		w.hold.update = true
		local first = w.run(w.wallet().arrive, p, "pickman")
		local second = w.run(w.wallet().arrive, p, "pickman")
		t.expect(first.done).toBe(false)
		t.expect(second.done).toBe(false)
		t.expect(w.writes).toBe(1)
		w.release()
		t.expect(first.done).toBe(true)
		t.expect(second.done).toBe(true)
		t.expect(first.results[2]).toBe("free")
		t.expect(second.results[1]).toBe("play")
		t.expect(second.results[2]).toBe("free")
		t.expect(w.writes).toBe(1)
	end)

	it(
		"an arrival whose write fails plays and charges nothing; one not back within WAIT_SECONDS plays",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 60, plays = 1 })
			w.fail.update = true
			local h = w.run(w.wallet().arrive, w.player(7), "pickman")
			t.expect(h.results[1]).toBe("play")
			t.expect(h.results[2]).toBe(nil)
			t.expect(rec(w, TEST, 7).plays).toBe(1)
			local w2 = world(nil)
			local p2 = w2.player(8)
			w2.seed(TEST, 8, { free = NOW - 60 })
			w2.hold.update = true
			local h2 = w2.run(w2.wallet().arrive, p2, "pickman")
			t.expect(h2.done).toBe(false)
			t.expect(w2.wallet().WAIT_SECONDS).toBe(5)
			w2.elapse()
			t.expect(h2.done).toBe(true)
			t.expect(h2.results[1]).toBe("play")
			t.expect(h2.results[2]).toBe(nil)
			w2.release() -- the late write ends; its answer changes nothing
			t.expect((w2.run(w2.wallet().arrive, p2, "pickman")).results[2]).toBe(nil)
		end
	)

	it("a live DataStore that cannot be opened: the arrival plays, a read is down, nothing throws", function()
		local w = world("live")
		w.fail.open = true
		local p = w.player(7)
		local ok, h = pcall(w.run, w.wallet().arrive, p, "pickman")
		t.expect(ok).toBe(true)
		t.expect(h.results[1]).toBe("play")
		t.expect(h.results[2]).toBe(nil)
		local okRead, r = pcall(w.run, w.wallet().read, w.player(8), "pickman")
		t.expect(okRead).toBe(true)
		t.expect(r.results[1]).toBe(nil)
		t.expect(r.results[2]).toBe("down")
		local okUse, u = pcall(w.run, w.wallet().useRevive, w.player(9), "pickman")
		t.expect(okUse).toBe(true)
		t.expect(u.results[1]).toBe(nil)
		t.expect(#w.opened > 0).toBe(true)
	end)

	it(
		"the portal's pass lets a buy arrival play, and is taken on every arrival, whatever its start",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 60 })
			local p = w.player(7)
			downRead(w, p, "pickman")
			t.expect(w.run(w.wallet().pass, p, "pickman").results[1]).toBe(true)
			t.expect(w.passes["pickman/7"]).toBe(true)
			local h = w.run(w.wallet().arrive, p, "pickman")
			t.expect(h.results[1]).toBe("play")
			t.expect(h.results[2]).toBe("buy")
			t.expect(w.passes["pickman/7"]).toBe(nil)
			local w2 = world(nil)
			local p2 = w2.player(8)
			downRead(w2, p2, "pickman")
			w2.run(w2.wallet().pass, p2, "pickman")
			w2.run(w2.wallet().arrive, p2, "pickman") -- free: the pass is taken all the same
			t.expect(w2.passes["pickman/8"]).toBe(nil)
			w2.leave(p2)
			local back = w2.run(w2.wallet().arrive, w2.player(8), "pickman")
			t.expect(back.results[1]).toBe("back")
		end
	)

	it("a pass is the title's own: another title's pass does not let a buy arrival play", function()
		local w = world(nil)
		w.seed(TEST, 7, { free = NOW - 60 })
		local p = w.player(7)
		downRead(w, p, "snake")
		w.run(w.wallet().pass, p, "snake")
		t.expect(w.run(w.wallet().arrive, p, "pickman").results[1]).toBe("back")
		t.expect(w.passes["snake/7"]).toBe(true)
	end)

	it(
		"a buy arrival whose pass map cannot be read plays (the user, 2026-10-31: 'Let all of them play')",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 60 })
			w.fail.passGet = true
			local h = w.run(w.wallet().arrive, w.player(7), "pickman")
			t.expect(h.results[1]).toBe("play")
			t.expect(h.results[2]).toBe("buy")
		end
	)

	it("TeleportData is never trusted: a join claiming a paid play is a buy arrival", function()
		local w = world(nil)
		w.seed(TEST, 7, { free = NOW - 60 })
		local p = w.player(7, { plays = 9, paid = true, start = "credit" })
		local h = w.run(w.wallet().arrive, p, "pickman")
		t.expect(h.results[1]).toBe("back")
		t.expect(h.results[2]).toBe("buy")
	end)

	it(
		"the transform decides: another server's free start just before this write makes this one use a held play",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { plays = 1 })
			w.race = function(store: { [string]: any }, key: string)
				store[key] = { free = NOW - 10, plays = 1 }
			end
			local h = w.run(w.wallet().arrive, w.player(7), "pickman")
			t.expect(h.results[2]).toBe("credit")
			local r = rec(w, TEST, 7)
			t.expect(r.free).toBe(NOW - 10)
			t.expect(r.plays).toBe(0)
		end
	)

	it("the transform's last call decides: a first call on an outdated value does not count", function()
		local w = world(nil)
		w.seed(TEST, 7, { plays = 1 })
		w.twice = true
		w.race = function(store: { [string]: any }, key: string)
			store[key] = { free = NOW - 10 }
		end
		local h = w.run(w.wallet().arrive, w.player(7), "pickman")
		t.expect(h.results[1]).toBe("back")
		t.expect(h.results[2]).toBe("buy")
	end)

	it(
		"a held revive is used once and counted for the run; with none held known, no write is made",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 7200, continues = 1 })
			local p = w.player(7)
			local wallet = w.wallet()
			w.run(wallet.arrive, p, "pickman")
			t.expect(wallet.revives(p, "pickman")).toBe(0)
			local writes = w.writes
			t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
			t.expect(w.writes).toBe(writes + 1)
			t.expect(rec(w, TEST, 7).revives).toBe(0)
			t.expect(wallet.revives(p, "pickman")).toBe(1)
			w.clock += 30
			t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(false)
			t.expect(w.writes).toBe(writes + 1)
			t.expect(wallet.revives(p, "pickman")).toBe(1)
		end
	)

	it(
		"one revive write per player and title at a time: a use during a use's write answers nil, one write",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { continues = 2 })
			local p = w.player(7)
			local wallet = w.wallet()
			w.hold.update = true
			local first = w.run(wallet.useRevive, p, "pickman")
			local second = w.run(wallet.useRevive, p, "pickman")
			t.expect(second.done).toBe(true)
			t.expect(second.results[1]).toBe(nil)
			w.clock += 30 -- a write slower than USE_SECONDS: still one at a time
			local third = w.run(wallet.useRevive, p, "pickman")
			t.expect(third.results[1]).toBe(nil)
			t.expect(w.writes).toBe(1)
			w.release()
			t.expect(first.results[1]).toBe(true)
			t.expect(rec(w, TEST, 7).revives).toBe(1)
			t.expect(wallet.revives(p, "pickman")).toBe(1)
		end
	)

	it("revive writes are bounded over time: none within USE_SECONDS of the last; one after it", function()
		local w = world(nil)
		w.seed(TEST, 7, { continues = 3 })
		local p = w.player(7)
		local wallet = w.wallet()
		t.expect(wallet.USE_SECONDS).toBe(6)
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
		w.clock += 5.9
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(nil)
		t.expect(w.writes).toBe(1)
		w.clock += 0.2
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
		t.expect(w.writes).toBe(2)
		t.expect(wallet.revives(p, "pickman")).toBe(2)
	end)

	it("a revive use whose store fails answers nil and counts nothing", function()
		local w = world(nil)
		w.seed(TEST, 7, { continues = 1 })
		local p = w.player(7)
		w.fail.update = true
		t.expect(w.run(w.wallet().useRevive, p, "pickman").results[1]).toBe(nil)
		t.expect(w.wallet().revives(p, "pickman")).toBe(0)
	end)

	it(
		"the run's revive count is kept after the player leaves, and starts again at their next arrival",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 7200, continues = 2 })
			local p = w.player(7)
			local wallet = w.wallet()
			w.run(wallet.arrive, p, "pickman")
			w.run(wallet.useRevive, p, "pickman")
			w.leave(p)
			t.expect(wallet.revives(p, "pickman")).toBe(1)
			local again = w.player(7)
			t.expect(wallet.revives(again, "pickman")).toBe(1)
			w.run(wallet.arrive, again, "pickman")
			t.expect(wallet.revives(again, "pickman")).toBe(0)
			t.expect(wallet.revives(again, "snake")).toBe(0)
		end
	)

	it("a refund is one more credit of its kind, outside the receipts", function()
		local w = world(nil)
		w.seed(TEST, 7, { receipts = { "a" } })
		local p = w.player(7)
		t.expect(w.run(w.wallet().refund, p, "pickman", "revive").results[1]).toBe(true)
		t.expect(w.run(w.wallet().refund, p, "pickman", "revive").results[1]).toBe(true)
		local r = rec(w, TEST, 7)
		t.expect(r.revives).toBe(2)
		t.expect(r.receipts).toEqual({ "a" })
	end)

	it(
		"a read reads the mode's store; within READ_SECONDS of the last record seen it answers from it",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { plays = 2 })
			local p = w.player(7)
			local wallet = w.wallet()
			t.expect(wallet.READ_SECONDS).toBe(60)
			local r = w.run(wallet.read, p, "pickman")
			t.expect(r.results[1].plays).toBe(2)
			t.expect(w.reads).toBe(1)
			w.clock += 59.9
			t.expect(w.run(wallet.read, p, "pickman").results[1].plays).toBe(2)
			t.expect(w.reads).toBe(1)
			w.clock += 0.2
			w.run(wallet.read, p, "pickman")
			t.expect(w.reads).toBe(2)
		end
	)

	it("a read during a read for the same player is busy: one read, and the second answers nil", function()
		local w = world(nil)
		local p = w.player(7)
		local wallet = w.wallet()
		w.hold.get = true
		local first = w.run(wallet.read, p, "pickman")
		local second = w.run(wallet.read, p, "pickman")
		t.expect(second.done).toBe(true)
		t.expect(second.results[1]).toBe(nil)
		t.expect(second.results[2]).toBe("busy")
		t.expect(w.reads).toBe(1)
		w.release()
		t.expect(first.done).toBe(true)
		t.expect(first.results[1].plays).toBe(0)
	end)

	it("a read not back within WAIT_SECONDS is down, and stays busy until it ends", function()
		local w = world(nil)
		local p = w.player(7)
		local wallet = w.wallet()
		w.hold.get = true
		local first = w.run(wallet.read, p, "pickman")
		w.elapse()
		t.expect(first.done).toBe(true)
		t.expect(first.results[2]).toBe("down")
		t.expect(w.run(wallet.read, p, "pickman").results[2]).toBe("busy")
		t.expect(w.reads).toBe(1)
		w.release() -- the late end starts the retry span: down with no store call for RETRY_SECONDS
		t.expect(w.run(wallet.read, p, "pickman").results[2]).toBe("down")
		t.expect(w.reads).toBe(1)
		w.advance(6.1)
		t.expect(w.run(wallet.read, p, "pickman").results[1].plays).toBe(0)
		t.expect(w.reads).toBe(2)
	end)

	it("a read that ends after the player left keeps nothing: their next join reads again", function()
		local w = world(nil)
		w.seed(TEST, 7, { plays = 1 })
		local p = w.player(7)
		local wallet = w.wallet()
		w.hold.get = true
		w.run(wallet.read, p, "pickman")
		w.leave(p)
		w.release()
		local again = w.player(7)
		w.seed(TEST, 7, { plays = 3 })
		t.expect(w.run(wallet.read, again, "pickman").results[1].plays).toBe(3)
		t.expect(w.reads).toBe(2)
	end)

	it(
		"a read whose store fails is down, and reads stay down with no store call for RETRY_SECONDS",
		function()
			local w = world(nil)
			local p = w.player(7)
			local wallet = w.wallet()
			t.expect(wallet.RETRY_SECONDS).toBe(6)
			w.fail.get = true
			local r = w.run(wallet.read, p, "pickman")
			t.expect(r.results[1]).toBe(nil)
			t.expect(r.results[2]).toBe("down")
			t.expect(w.reads).toBe(1)
			w.fail.get = false
			w.advance(5.9)
			t.expect(w.run(wallet.read, p, "pickman").results[2]).toBe("down")
			t.expect(w.reads).toBe(1)
			w.advance(0.2)
			t.expect(w.run(wallet.read, p, "pickman").results[1].plays).toBe(0)
			t.expect(w.reads).toBe(2)
		end
	)

	it("a title not in the catalog is an error, not a silent free start", function()
		local w = world(nil)
		local p = w.player(7)
		t.expect(function()
			w.wallet().arrive(p, "tetris")
		end).toThrow("no title")
		t.expect(function()
			w.wallet().useRevive(p, "Pickman")
		end).toThrow("no title")
	end)

	it("the mode is read once from ServerScriptService: PaidPlay and each title's two ids", function()
		local w = world("live", { SnakeReviveProductId = 0 })
		t.expect(w.wallet().mode("pickman")).toBe("live")
		t.expect(w.wallet().mode("snake")).toBe("closed")
		w.attributes.PaidPlay = nil
		w.attributes.SnakeReviveProductId = 202
		t.expect(w.wallet().mode("pickman")).toBe("live")
		t.expect(w.wallet().mode("snake")).toBe("closed")
		t.expect(world(nil).wallet().mode("pickman")).toBe("test")
	end)

	it(
		"a record Wallet writes is f0145's shape: free, plays, continues and receipts, nothing else",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 7200, plays = 1, continues = 2, receipts = { "a" } })
			local p = w.player(7)
			w.run(w.wallet().arrive, p, "pickman")
			w.run(w.wallet().useRevive, p, "pickman")
			local raw = w.record(TEST, 7)
			local keys = {}
			for k in raw do
				table.insert(keys, k)
			end
			table.sort(keys)
			t.expect(keys).toEqual({ "continues", "free", "plays", "receipts" })
			t.expect(raw.continues).toBe(1)
			t.expect(raw.plays).toBe(1)
			t.expect(raw.free).toBe(NOW)
		end
	)

	it(
		"each title has its own read: two titles read within READ_SECONDS each answer their own record",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { plays = 2 })
			w.seed("SnakePaidPlayTest", 7, { free = NOW - 60 })
			local p = w.player(7)
			local wallet = w.wallet()
			t.expect(w.run(wallet.read, p, "pickman").results[1].plays).toBe(2)
			local snake = w.run(wallet.read, p, "snake").results[1]
			t.expect(snake.plays).toBe(0)
			t.expect(snake.free).toBe(NOW - 60)
			t.expect(w.reads).toBe(2)
		end
	)

	it("a read of one title under way leaves another title's read free", function()
		local w = world(nil)
		w.seed(TEST, 7, { plays = 1 })
		local p = w.player(7)
		local wallet = w.wallet()
		w.hold.get = true
		local snake = w.run(wallet.read, p, "snake")
		local pickman = w.run(wallet.read, p, "pickman")
		t.expect(snake.done).toBe(false)
		t.expect(pickman.results[1].plays).toBe(1)
		w.release()
		t.expect(snake.done).toBe(true)
	end)

	it("a revive used in one title does not start another title's USE_SECONDS", function()
		local w = world(nil)
		w.seed(TEST, 7, { continues = 1 })
		w.seed("SnakePaidPlayTest", 7, { continues = 1 })
		local p = w.player(7)
		local wallet = w.wallet()
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
		t.expect(w.run(wallet.useRevive, p, "snake").results[1]).toBe(true)
		t.expect(wallet.revives(p, "pickman")).toBe(1)
		t.expect(wallet.revives(p, "snake")).toBe(1)
	end)

	it(
		"a pass read not back within WAIT_SECONDS counts as a pass; its late answer still removes the entry",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 60 })
			local p = w.player(7)
			w.passes["pickman/7"] = true -- the portal's pass
			w.hold.pass = true
			local h = w.run(w.wallet().arrive, p, "pickman")
			t.expect(h.done).toBe(false)
			w.elapse()
			t.expect(h.done).toBe(true)
			t.expect(h.results[1]).toBe("play")
			t.expect(h.results[2]).toBe("buy")
			w.release()
			t.expect(w.passes["pickman/7"]).toBe(nil)
			w.leave(p)
			t.expect(w.run(w.wallet().arrive, w.player(7), "pickman").results[1]).toBe("back")
		end
	)

	it("a slow pass read with no pass there still plays, and the arrival ends within its limit", function()
		local w = world(nil)
		w.seed(TEST, 7, { free = NOW - 60 })
		w.hold.pass = true
		local h = w.run(w.wallet().arrive, w.player(7), "pickman")
		w.elapse()
		t.expect(h.results[1]).toBe("play")
	end)

	it(
		"in test mode a test store that cannot be opened has a stand-in: arrivals, test purchases and revives work",
		function()
			local w = world(nil)
			w.fail.open = true
			local p = w.player(7)
			local r = w.start()
			local wallet = w.wallet()
			local h = w.run(wallet.arrive, p, "pickman")
			t.expect(h.results[1]).toBe("play")
			t.expect(h.results[2]).toBe("free")
			t.expect(r.ask(p, "pickman", "revive")).toBe(true)
			w.run(w.answer, p, "confirm")
			t.expect(w.events[1].bought).toBe(true)
			t.expect(w.events[2].kind).toBe("granted")
			t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
			t.expect(wallet.revives(p, "pickman")).toBe(1)
			w.leave(p)
			local again = w.player(7)
			t.expect(w.run(wallet.arrive, again, "pickman").results[1]).toBe("back") -- the stand-in kept the free start
		end
	)

	it(
		"in live mode an unopenable store has no stand-in: a receipt is not processed and the arrival claims nothing",
		function()
			local w = world("live")
			w.fail.open = true
			w.player(7)
			w.start()
			t.expect(w.run(w.receipt, 7, 101, "live-1").results[1])
				.toBe("ProductPurchaseDecision.NotProcessedYet")
			local h = w.run(w.wallet().arrive, w.player(8), "pickman")
			t.expect(h.results[1]).toBe("play")
			t.expect(h.results[2]).toBe(nil)
		end
	)

	it("a pass is written only after a read that answered down, once per such answer", function()
		local w = world(nil)
		local p = w.player(7)
		local wallet = w.wallet()
		t.expect(w.run(wallet.pass, p, "pickman").results[1]).toBe(false)
		w.run(wallet.read, p, "pickman") -- a good read
		t.expect(w.run(wallet.pass, p, "pickman").results[1]).toBe(false)
		t.expect(w.passes["pickman/7"]).toBe(nil)
		local q = w.player(8)
		w.hold.get = true
		w.run(wallet.read, q, "pickman")
		t.expect(w.run(wallet.read, q, "pickman").results[2]).toBe("busy")
		t.expect(w.run(wallet.pass, q, "pickman").results[1]).toBe(false)
		w.release()
		local d = w.player(9)
		w.fail.get = true
		t.expect(w.run(wallet.read, d, "pickman").results[2]).toBe("down")
		t.expect(w.run(wallet.pass, d, "pickman").results[1]).toBe(true)
		t.expect(w.passes["pickman/9"]).toBe(true)
		w.passes["pickman/9"] = nil
		t.expect(w.run(wallet.pass, d, "pickman").results[1]).toBe(false)
		t.expect(w.run(wallet.read, d, "pickman").results[2]).toBe("down") -- within RETRY_SECONDS, no store call
		t.expect(w.run(wallet.pass, d, "pickman").results[1]).toBe(true)
		t.expect(w.run(wallet.pass, d, "snake").results[1]).toBe(false)
	end)

	it(
		"a written revive refund takes one off the run's count, never below 0; a failed one or a play refund does not",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 7200, continues = 1 })
			local p = w.player(7)
			local wallet = w.wallet()
			w.run(wallet.arrive, p, "pickman")
			w.run(wallet.useRevive, p, "pickman")
			t.expect(wallet.revives(p, "pickman")).toBe(1)
			w.fail.update = true
			t.expect(w.run(wallet.refund, p, "pickman", "revive").results[1]).toBe(false)
			t.expect(wallet.revives(p, "pickman")).toBe(1)
			w.fail.update = false
			t.expect(w.run(wallet.refund, p, "pickman", "play").results[1]).toBe(true)
			t.expect(wallet.revives(p, "pickman")).toBe(1)
			t.expect(w.run(wallet.refund, p, "pickman", "revive").results[1]).toBe(true)
			t.expect(wallet.revives(p, "pickman")).toBe(0)
			t.expect(rec(w, TEST, 7).revives).toBe(1)
			t.expect(w.run(wallet.refund, p, "pickman", "revive").results[1]).toBe(true)
			t.expect(wallet.revives(p, "pickman")).toBe(0)
		end
	)

	it(
		"calls for a player who already left claim, read, use and pass nothing; a refund is still written",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { continues = 1 })
			local p = w.player(7)
			local wallet = w.wallet()
			w.leave(p)
			local a = w.run(wallet.arrive, p, "pickman")
			t.expect(a.results[1]).toBe("back")
			t.expect(a.results[2]).toBe(nil)
			t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(nil)
			local r = w.run(wallet.read, p, "pickman")
			t.expect(r.results[1]).toBe(nil)
			t.expect(r.results[2]).toBe("down")
			t.expect(w.run(wallet.pass, p, "pickman").results[1]).toBe(false)
			t.expect(w.writes).toBe(0)
			t.expect(w.reads).toBe(0)
			t.expect(w.passReads).toBe(0)
			t.expect(w.run(wallet.refund, p, "pickman", "revive").results[1]).toBe(true)
			t.expect(rec(w, TEST, 7).revives).toBe(2)
		end
	)

	it(
		"a departed run's count is dropped KEEP_SECONDS after the leave, and a later leave restarts that span",
		function()
			local w = world(nil)
			w.seed(TEST, 7, { free = NOW - 7200, continues = 3 })
			local wallet = w.wallet()
			t.expect(wallet.KEEP_SECONDS).toBe(600)
			local p = w.player(7)
			w.run(wallet.arrive, p, "pickman")
			w.run(wallet.useRevive, p, "pickman")
			w.leave(p) -- t = 0
			w.advance(100)
			t.expect(wallet.revives(p, "pickman")).toBe(1) -- kept for the departed run's submit
			local again = w.player(7)
			w.run(wallet.arrive, again, "pickman")
			w.run(wallet.useRevive, again, "pickman")
			w.advance(400)
			w.leave(again) -- t = 500
			w.advance(101) -- t = 601: the first leave's span is over, but this run left at 500
			t.expect(wallet.revives(again, "pickman")).toBe(1)
			w.advance(500) -- t = 1101
			t.expect(wallet.revives(again, "pickman")).toBe(0)
		end
	)

	it("nothing a teleport carries is read: no Wallet call reads the join data", function()
		local w = world(nil)
		w.seed(TEST, 7, { free = NOW - 60, continues = 1 })
		local p = w.player(7, { plays = 9, paid = true })
		local wallet = w.wallet()
		w.run(wallet.arrive, p, "pickman")
		w.run(wallet.read, p, "snake")
		w.run(wallet.useRevive, p, "pickman")
		w.run(wallet.refund, p, "pickman", "play")
		w.run(wallet.pass, p, "pickman")
		w.run(wallet.revives, p, "pickman")
		t.expect(w.joinReads).toBe(0)
	end)
end)
