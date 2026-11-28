--!strict
-- Wallet's record seen and its pass, against overlapping store calls (R0110 code review 001, F1 to F3), run from the
-- built place's real source on a small stub engine. Unlike the acceptance stub, a held GetAsync answers the value
-- the store held when the request was served, and a write can be held after it was applied, so an answer can come
-- back after a newer write: the record seen must follow the store, never the order answers arrive in. The pass is
-- written only after a read that answered down (never after a busy or a good answer), and at most once per
-- RETRY_SECONDS per player and title however often a client asks.
local PaidPlay = require("@logic/PaidPlay")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local function source(name: string): string
	local node = (built :: any):GetService("ServerStorage"):FindFirstChild("Arcade"):FindFirstChild(name)
	assert(node, `no ServerStorage.Arcade.{name}`)
	return node.Source
end
local CATALOG = source("Catalog")
local WALLET = source("Wallet")

local NOW = 1792108800
local LIVE = "PaidPlay"
local TEST = "PaidPlayTest"
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

local function resume(co: thread, ...: any)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		error(debug.traceback(co, tostring(err)), 0)
	end
end

-- A server on a stub engine. `w.hold.get` holds the next GetAsync after it read its value; `w.hold.before` holds the
-- next UpdateAsync before it reads; `w.hold.after` holds the next one after it wrote; `w.hold.pass` holds the next
-- pass read. `w.release()` resumes the oldest held call. Delays run on `w.advance(seconds)`.
local function world(mode: any?): any
	local w: any = {}
	local players: { any } = {}
	w.stores = {} :: { [string]: { [string]: any } }
	w.passes = {} :: { [string]: any }
	w.held = {} :: { thread }
	w.hold = { get = false, before = false, after = false, pass = false }
	w.fail = { get = false }
	w.writes, w.reads, w.passWrites = 0, 0, 0
	w.clock = 0
	w.delayed = {} :: { { due: number, fn: () -> () } }
	w.attributes = { PaidPlay = mode }
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
	local services: { [string]: any } = {
		DataStoreService = {
			GetDataStore = function(_: any, name: string): any
				local values = storeOf(name)
				return {
					UpdateAsync = function(_: any, key: string, fn: (any) -> any): any
						w.writes += 1
						hold("before")
						local value = fn(values[key])
						if value ~= nil then
							values[key] = value
						end
						hold("after")
						return value
					end,
					GetAsync = function(_: any, key: string): any
						w.reads += 1
						if w.fail.get then
							error("store down", 0)
						end
						local value = values[key] -- as the store held it when the request was served
						hold("get")
						return value
					end,
				}
			end,
		},
		MemoryStoreService = {
			GetHashMap = function(_: any, _name: string): any
				return {
					SetAsync = function(_: any, key: string, value: any, _ttl: number)
						w.passWrites += 1
						w.passes[key] = value
					end,
					GetAsync = function(_: any, key: string): any
						hold("pass")
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
				return "guid"
			end,
		},
		Players = {
			PlayerRemoving = {
				Connect = function(_: any, _fn: (any) -> ()) end, -- no player leaves in these cases
			},
			GetPlayerByUserId = function(_: any, id: number): any
				for _, p in players do
					if p.UserId == id then
						return p
					end
				end
				return nil
			end,
		},
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
	env.require = function(spec: string): any
		if spec == "./Catalog" then
			return load("Catalog", CATALOG)
		elseif spec == "@game/ReplicatedStorage/Arcade/Logic/PaidPlay" then
			return PaidPlay
		end
		error(`stub: no module for require("{spec}")`, 0)
	end
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
			resume(if type(fn) == "thread" then fn else coroutine.create(fn), ...)
		end,
		delay = function(seconds: number, fn: () -> ())
			table.insert(w.delayed, { due = w.clock + seconds, fn = fn })
		end,
	}
	w.run = function(fn: (...any) -> ...any, ...: any): any
		local h: any = { done = false, results = {} }
		local args = table.pack(...)
		resume(coroutine.create(function()
			h.results = table.pack(fn(table.unpack(args, 1, args.n)))
			h.done = true
		end))
		return h
	end
	w.release = function()
		local co = table.remove(w.held, 1)
		assert(co, "nothing held")
		resume(co)
	end
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
	w.player = function(userId: number): any
		local p: any = { UserId = userId, Parent = {}, Name = `P{userId}` }
		table.insert(players, p)
		return p
	end
	w.wallet = function(): any
		return load("Wallet", WALLET)
	end
	w.seed = function(storeName: string, userId: number, value: any)
		storeOf(storeName)[tostring(userId)] = value
	end
	w.record = function(storeName: string, userId: number): any
		return storeOf(storeName)[tostring(userId)]
	end
	return w
end

return t.spec("Wallet: the record seen follows the store; the pass is bounded", function(it)
	it("a read served before a revive grant and answered after it does not hide the revive", function()
		local w = world("live")
		w.seed(LIVE, 7, { free = NOW - 60, plays = 0, continues = 0 })
		local p = w.player(7)
		local wallet = w.wallet()
		w.hold.get = true
		local read = w.run(wallet.read, p, "pickman")
		t.expect(read.done).toBe(false)
		t.expect(w.run(wallet.grant, 7, "pickman", "revive", "r1").results[1]).toBe(true)
		w.release()
		t.expect(read.done).toBe(true)
		t.expect(read.results[1].revives).toBe(0) -- the answer is the read's own, as served
		local writes = w.writes
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
		t.expect(w.writes).toBe(writes + 1)
		t.expect(w.record(LIVE, 7).continues).toBe(0)
	end)

	it("a revive granted while the arrival waits on its pass read is usable at once", function()
		local w = world("live")
		w.seed(LIVE, 7, { free = NOW - 60, plays = 1, continues = 0 })
		local p = w.player(7)
		local wallet = w.wallet()
		w.hold.pass = true
		local arrival = w.run(wallet.arrive, p, "pickman")
		t.expect(arrival.done).toBe(false)
		t.expect(w.record(LIVE, 7).plays).toBe(0) -- the claim is written; the pass read is held
		t.expect(w.run(wallet.grant, 7, "pickman", "revive", "r1").results[2]).toBe(true)
		w.release()
		t.expect(arrival.results[1]).toBe("play")
		t.expect(arrival.results[2]).toBe("credit")
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
		t.expect(w.record(LIVE, 7).continues).toBe(0)
	end)

	it("two writes answered out of the order they were applied leave no stale record seen", function()
		local w = world("live")
		w.seed(LIVE, 7, { free = NOW - 60, plays = 0, continues = 1 })
		local p = w.player(7)
		local wallet = w.wallet()
		w.run(wallet.arrive, p, "pickman") -- the record seen holds one revive
		w.hold.after = true
		local use = w.run(wallet.useRevive, p, "pickman") -- applied 1 -> 0, its answer held
		t.expect(w.record(LIVE, 7).continues).toBe(0)
		t.expect(w.run(wallet.grant, 7, "pickman", "revive", "r1").results[1]).toBe(true) -- applied 0 -> 1, answered
		w.release()
		t.expect(use.results[1]).toBe(true)
		w.advance(wallet.USE_SECONDS)
		local writes = w.writes
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
		t.expect(w.writes).toBe(writes + 1)
		t.expect(w.record(LIVE, 7).continues).toBe(0)
	end)

	it("with nothing overlapping, a revive none is known to hold makes no write", function()
		local w = world("live")
		w.seed(LIVE, 7, { free = NOW - 60, plays = 1, continues = 0 })
		local p = w.player(7)
		local wallet = w.wallet()
		w.run(wallet.arrive, p, "pickman")
		local writes = w.writes
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(false)
		t.expect(w.writes).toBe(writes)
		w.run(wallet.grant, 7, "pickman", "revive", "r1")
		t.expect(w.run(wallet.useRevive, p, "pickman").results[1]).toBe(true)
	end)

	it("after a down answer, a busy answer takes the pass away", function()
		local w = world(nil)
		local p = w.player(7)
		local wallet = w.wallet()
		w.fail.get = true
		t.expect(w.run(wallet.read, p, "pickman").results[2]).toBe("down")
		w.fail.get = false
		w.advance(wallet.RETRY_SECONDS)
		w.hold.get = true
		w.run(wallet.read, p, "pickman")
		t.expect(w.run(wallet.read, p, "pickman").results[2]).toBe("busy")
		t.expect(w.run(wallet.pass, p, "pickman").results[1]).toBe(false)
		t.expect(w.passWrites).toBe(0)
		w.release()
	end)

	it("after a down answer, a good answer from the record seen takes the pass away", function()
		local w = world(nil)
		local p = w.player(7)
		local wallet = w.wallet()
		w.fail.get = true
		t.expect(w.run(wallet.read, p, "pickman").results[2]).toBe("down")
		w.fail.get = false
		w.advance(wallet.RETRY_SECONDS)
		t.expect(w.run(wallet.refund, p, "pickman", "play").results[1]).toBe(true)
		local reads = w.reads
		local r = w.run(wallet.read, p, "pickman").results
		t.expect(r[1].plays).toBe(1)
		t.expect(w.reads).toBe(reads) -- answered from the record seen
		t.expect(w.run(wallet.pass, p, "pickman").results[1]).toBe(false)
		t.expect(w.passWrites).toBe(0)
	end)

	it("during an outage a client asking again and again writes its pass once per RETRY_SECONDS", function()
		local w = world(nil)
		local p = w.player(7)
		local wallet = w.wallet()
		w.fail.get = true
		for _ = 1, 50 do
			t.expect(w.run(wallet.read, p, "pickman").results[2]).toBe("down")
			t.expect(w.run(wallet.pass, p, "pickman").results[1]).toBe(true)
		end
		t.expect(w.reads).toBe(1)
		t.expect(w.passWrites).toBe(1)
		t.expect(w.passes["pickman/7"]).toBe(true)
		w.advance(wallet.RETRY_SECONDS)
		t.expect(w.run(wallet.read, p, "pickman").results[2]).toBe("down")
		t.expect(w.run(wallet.pass, p, "pickman").results[1]).toBe(true)
		t.expect(w.passWrites).toBe(2)
		t.expect(w.reads).toBe(2)
		-- another title's pass is its own
		t.expect(w.run(wallet.read, p, "snake").results[2]).toBe("down")
		t.expect(w.run(wallet.pass, p, "snake").results[1]).toBe(true)
		t.expect(w.passWrites).toBe(3)
		t.expect(w.record(TEST, 7)).toBe(nil)
	end)

	it("d0405: a busy answer while a read is late keeps the pass allowance", function()
		local w = world(nil)
		local p = w.player(7)
		local wallet = w.wallet()
		w.hold.get = true
		local first = w.run(wallet.read, p, "pickman")
		w.advance(wallet.WAIT_SECONDS)
		t.expect(first.done).toBe(true)
		t.expect(first.results[2]).toBe("down")
		t.expect(w.run(wallet.read, p, "pickman").results[2]).toBe("busy")
		t.expect(w.run(wallet.pass, p, "pickman").results[1]).toBe(true)
		t.expect(w.passWrites).toBe(1)
		t.expect(w.passes["pickman/7"]).toBe(true)
		w.release()
	end)
end)
