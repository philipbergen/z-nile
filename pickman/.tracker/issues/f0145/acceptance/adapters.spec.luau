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
	records: { [string]: any }, -- the PaidPlay store, by user id
	failWrites: boolean,
	failReads: boolean,
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
				assert(name == Pay.STORE, name)
				return {
					UpdateAsync = function(_: any, key: string, fn: (any) -> any): any
						if w.failWrites then
							error("store down", 0)
						end
						local nextValue = fn(w.records[key])
						if nextValue ~= nil then
							w.records[key] = nextValue
						end
						return nextValue
					end,
					GetAsync = function(_: any, key: string): any
						if w.failReads then
							error("store down", 0)
						end
						return w.records[key]
					end,
				}
			end,
		},
		MarketplaceService = marketplace,
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
				return 0
			end,
		},
		task = {
			defer = function(fn: () -> ())
				table.insert(w.deferred, fn)
			end,
			spawn = function(fn: () -> ())
				fn()
			end,
		},
	}
	w = {
		records = {},
		failWrites = false,
		failReads = false,
		prompts = {},
		teleports = {},
		sent = {},
		attributes = {
			PaidPlay = mode,
			PlayProductId = PLAY_ID,
			ContinueProductId = CONTINUE_ID,
			GamePlaceId = 777,
		},
		remote = function(name: string): any
			return assert(remotes[name], `no remote {name}`)
		end,
		player = function(userId: number): any
			local p = { UserId = userId, Parent = {}, Name = `P{userId}` }
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

-- the game place with one player whose run is in the continue offer
local function arena(mode: string?, ticks: number?): Arena
	local w = world(mode)
	local p = w.player(7)
	local s = Session.new(Maze.parse({ "#######", "#..P..#", "#######" }, "corridor"), 1, Session.GAME_CONFIG)
	Session.join(s, "7")
	local continues = luau.load(CONTINUES, { environment = w.env, debugName = "Continues" })() :: any
	continues.start(function(player: any): Session.Session?
		return if player == p then s else nil
	end)
	w.remote("Ready").OnServerEvent.fire(p)
	w.flush()
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

	it("a test confirmation grants a play and starts at once, in test mode only", function()
		local test = lobby("test")
		test.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
		local p = test.player(7)
		test.remote("Purchase").OnServerEvent.fire(p, "confirm")
		t.expect(Pay.record(test.records["7"]).plays).toBe(1)
		t.expect(#test.teleports).toBe(1)
		local live = lobby("live")
		live.records["7"] = { free = NOW - 60, plays = 0, continues = 0, receipts = {} }
		local q = live.player(7)
		live.remote("Purchase").OnServerEvent.fire(q, "confirm")
		t.expect(Pay.record(live.records["7"]).plays).toBe(0)
		t.expect(#live.teleports).toBe(0)
	end)

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

	it("a continue asked with one held is used at once: three new lives", function()
		local a = arena("live", 50)
		a.w.records["7"].continues = 1
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
end)
