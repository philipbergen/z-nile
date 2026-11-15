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
-- once and whose delays run on w.elapse(). A store call can be held: it yields until w.release() resumes it.
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
	w.delayed = {} :: { () -> () }
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
		delay = function(_seconds: number, fn: () -> ())
			table.insert(w.delayed, fn)
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
	w.elapse = function()
		local list = w.delayed
		w.delayed = {}
		for _, fn in list do
			resume(coroutine.create(fn))
		end
	end
	w.player = function(userId: number, joinData: any?): any
		local p: any = { UserId = userId, Parent = {}, Name = `P{userId}` }
		p.GetJoinData = function(): any
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
				table.insert(w.events, { kind = "closed", player = player, name = name, what = kind, bought = bought })
			end,
		})
		return r
	end
	w.receipt = function(userId: any, productId: any, purchaseId: any): any
		return marketplace.ProcessReceipt({ PlayerId = userId, ProductId = productId, PurchaseId = purchaseId })
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
