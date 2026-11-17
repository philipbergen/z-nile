--!strict
-- R0118 code review 001 F1 and F3: what the game place tells the client on PayStatus, and the test confirm whose
-- write fails. Continues tells the mode on every path that lets a player play (no status when the record is
-- unknown), so a live client never keeps its "nothing is charged" default, and tells again after every record it
-- writes or hears. A test confirm that took the open screen but wrote nothing releases the hold its ask set, and a
-- confirm with no screen open leaves any other hold. And code review 001 F2, as the user ruled it (2026-11-16, "Play in
-- Studio only"): a Studio arrival with nothing to pay with plays; anywhere else it is sent back. The stub engine below is f0145 adapters.spec's (a sequestered
-- spec, which cannot be shared or edited): its real sources run on an in-memory store, and Logic loads as itself.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Pay = require("@logic/Pay")
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

local PURCHASES = sourceAt(gamePlace, { "ReplicatedStorage", "Shared", "Purchases" })
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

type Arena = { w: World, s: Session.Session, p: any, arrived: (any, Session.Session) -> () }

-- the game place with one player who has just arrived (Sessions.made has told Continues of their new session)
local function arrive(mode: string?, setup: ((World) -> ())?): Arena
	local w = world(mode)
	local p = w.player(7)
	local s = Session.new(Maze.parse({ "#######", "#..P..#", "#######" }, "corridor"), 1, Session.GAME_CONFIG)
	Session.join(s, "7")
	local continues = luau.load(CONTINUES, { environment = w.env, debugName = "Continues" })() :: any
	-- what Main hands to Sessions.made (f0148): the arrival, told each new session once it exists
	local arrived = continues.start(function(player: any): Session.Session?
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
	arrived(p, s) -- as Sessions.made tells it, once the player's session exists
	w.flush()
	return { w = w, s = s, p = p, arrived = arrived }
end

-- the game place with one player whose run is in the continue offer
local function arena(mode: string?, ticks: number?, setup: ((World) -> ())?): Arena
	local a = arrive(mode, setup)
	local w, s, p, arrived = a.w, a.s, a.p, a.arrived
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
	return { w = w, s = s, p = p, arrived = arrived }
end

-- the last PayStatus the player was told: the mode and the status (nil when the record is unknown)
local function lastStatus(w: World, p: any): (any, any)
	local told = sentOn(w, "PayStatus", p)
	assert(#told > 0, "nothing told on PayStatus")
	local args = told[#told]
	return args[1], args[2]
end

return t.spec("f0145 what the game place tells on PayStatus (R0118 code review 001)", function(it)
	it("a live arrival whose write fails still tells the mode, with no status, before any offer", function()
		local a = arrive("live", function(w: World)
			w.failWrites = true
		end)
		t.expect(a.s.members["7"].play.offer).toBe(Game.OFFER_TICKS) -- it plays (G10)
		local mode, status = lastStatus(a.w, a.p)
		t.expect(mode).toBe("live")
		t.expect(status).toBe(nil)
	end)

	it("a closed arrival whose write fails tells closed", function()
		local a = arrive("live", function(w: World)
			w.attributes.ContinueProductId = nil -- live with an id missing: closed ("Refuse paid play")
			w.failWrites = true
		end)
		local mode, status = lastStatus(a.w, a.p)
		t.expect(mode).toBe("closed")
		t.expect(status).toBe(nil)
	end)

	it("a continue receipt heard outside the offer tells the continue held", function()
		local a = arrive("live")
		local before = #sentOn(a.w, "PayStatus", a.p)
		t.expect(Session.offering(a.s, "7")).toBe(false)
		t.expect(a.w.receipt(7, CONTINUE_ID, "C9")).toBe("ProductPurchaseDecision.PurchaseGranted")
		t.expect(#sentOn(a.w, "PayStatus", a.p) > before).toBe(true)
		local mode, status = lastStatus(a.w, a.p)
		t.expect(mode).toBe("live")
		t.expect(status.continues).toBe(1)
	end)

	it("a continue's write that finds none held tells none held", function()
		local a = arena("live", 50, function(w: World)
			w.failWrites = true -- the arrival's write fails: what the player holds is not known
		end)
		a.w.failWrites = false
		a.w.records["7"] = { free = NOW, plays = 0, continues = 0, receipts = {} }
		local before = #sentOn(a.w, "PayStatus", a.p)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(a.w.writes > 1).toBe(true) -- the ask wrote: nothing was known
		t.expect(#a.w.prompts).toBe(1) -- none held: the purchase screen
		t.expect(#sentOn(a.w, "PayStatus", a.p) > before).toBe(true)
		local _, status = lastStatus(a.w, a.p)
		t.expect(status.continues).toBe(0)
	end)

	it("a continue given back after its write tells the continue held", function()
		local a = arena("live", 50, function(w: World)
			w.records["7"] = { free = nil, plays = 0, continues = 1, receipts = {} }
		end)
		a.w.onWrite = function() -- the player declines while the continue's write yields
			a.w.remote("Continue").OnServerEvent.fire(a.p, "decline")
		end
		local before = #sentOn(a.w, "PayStatus", a.p)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(Pay.record(a.w.records["7"]).continues).toBe(1) -- given back
		t.expect(#sentOn(a.w, "PayStatus", a.p) > before).toBe(true) -- told after the give-back, not only on arrival
		local _, status = lastStatus(a.w, a.p)
		t.expect(status.continues).toBe(1)
	end)

	it("test: a confirm whose write fails releases the countdown; a later ask opens the screen", function()
		local a = arena("test", 50)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(#sentOn(a.w, "Purchase", a.p)).toBe(1)
		t.expect(Session.holding(a.s, "7")).toBe(true)
		a.w.failWrites = true
		local timer = Session.frame(a.s, "7").play.timer
		a.w.remote("Purchase").OnServerEvent.fire(a.p, "confirm")
		t.expect(Session.holding(a.s, "7")).toBe(false)
		Session.step(a.s)
		t.expect(Session.frame(a.s, "7").play.timer < timer).toBe(true)
		t.expect(Session.offering(a.s, "7")).toBe(true)
		a.w.failWrites = false
		a.w.clock += 10
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(#sentOn(a.w, "Purchase", a.p)).toBe(2)
		t.expect(Session.holding(a.s, "7")).toBe(true)
	end)

	-- R0118 final review 001 F2
	it("test: a granted confirm whose continue write fails releases the hold; an ask uses it", function()
		local a = arena("test", 50)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(Session.holding(a.s, "7")).toBe(true)
		a.w.onWrite = function() -- the grant's write goes through; the continue's write after it fails
			a.w.onWrite = function()
				a.w.failWrites = true
			end
		end
		local timer = Session.frame(a.s, "7").play.timer
		a.w.remote("Purchase").OnServerEvent.fire(a.p, "confirm")
		a.w.failWrites = false
		t.expect(Pay.record(a.w.records["7"]).continues).toBe(1) -- granted, held
		t.expect(Session.holding(a.s, "7")).toBe(false)
		Session.step(a.s)
		t.expect(Session.frame(a.s, "7").play.timer < timer).toBe(true)
		a.w.clock += 10
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(Session.offering(a.s, "7")).toBe(false)
		t.expect(Session.frame(a.s, "7").play.lives).toBe(Game.CONTINUE_LIVES)
		t.expect(Pay.record(a.w.records["7"]).continues).toBe(0)
	end)

	it("test: a confirm heard during a continue's write leaves that flight's hold", function()
		local a = arena("test", 50)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask") -- none known held: the test screen, the countdown held
		t.expect(#sentOn(a.w, "Purchase", a.p)).toBe(1)
		local during: boolean? = nil
		a.w.onWrite = function() -- the receipt's grant write; the next write is the flight it starts
			a.w.onWrite = function() -- inside that flight, the screen's confirm is heard
				a.w.remote("Purchase").OnServerEvent.fire(a.p, "confirm")
				during = Session.holding(a.s, "7")
			end
		end
		t.expect(a.w.receipt(7, CONTINUE_ID, "C1")).toBe("ProductPurchaseDecision.PurchaseGranted")
		t.expect(during).toBe(true) -- "busy": the flight's end decides, not the confirm
		t.expect(Session.offering(a.s, "7")).toBe(false) -- the flight continued the run
		t.expect(Session.frame(a.s, "7").play.lives).toBe(Game.CONTINUE_LIVES)
		t.expect(Pay.record(a.w.records["7"]).continues).toBe(1) -- the confirm's continue stays held (G9)
	end)

	it("a confirm with no screen open leaves a continue's write holding the countdown", function()
		local a = arena("test", 50, function(w: World)
			w.records["7"] = { free = nil, plays = 0, continues = 1, receipts = {} }
		end)
		local during: boolean? = nil
		a.w.onWrite = function()
			a.w.failWrites = true -- the confirm's own write, if it made one, would fail
			a.w.remote("Purchase").OnServerEvent.fire(a.p, "confirm")
			during = Session.holding(a.s, "7")
			a.w.failWrites = false
		end
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		t.expect(during).toBe(true)
		t.expect(Session.frame(a.s, "7").play.lives).toBe(Game.CONTINUE_LIVES) -- the flight's continue went on
	end)

	it("a confirm with no screen open leaves a bought continue's receipt awaited", function()
		local a = arena("live", 50)
		a.w.remote("Continue").OnServerEvent.fire(a.p, "ask")
		a.w.finished(7, CONTINUE_ID, true) -- bought, the receipt not here yet
		t.expect(Session.holding(a.s, "7")).toBe(true)
		a.w.remote("Purchase").OnServerEvent.fire(a.p, "confirm")
		t.expect(Session.holding(a.s, "7")).toBe(true)
		local timer = Session.frame(a.s, "7").play.timer
		Session.step(a.s)
		t.expect(Session.frame(a.s, "7").play.timer).toBe(timer)
	end)

	-- R0118 code review 001 F2, ruled by the user (2026-11-16): (b) "Play in Studio only". An arrival with nothing to
	-- pay with and no lobby pass plays when RunService:IsStudio() is true; anywhere else (false, an error, or no
	-- IsStudio at all, as adapters.spec's stub has) it is sent back as G10 says.
	local function nothingToPay(isStudio: any): Arena
		return arrive("test", function(w: World)
			w.records["7"] = { free = NOW - 600, plays = 0, continues = 0, receipts = {} } -- the hour's free game used
			w.failTeleport = true -- Studio cannot teleport
			if isStudio ~= nil then
				w.env.game:GetService("RunService").IsStudio = isStudio
			end
		end)
	end

	it("in Studio an arrival with nothing to pay plays with the offer on and is not sent back", function()
		local a = nothingToPay(function(): boolean
			return true
		end)
		t.expect(Session.isOver(a.s, "7")).toBe(false)
		t.expect(a.s.members["7"].play.offer).toBe(Game.OFFER_TICKS)
		t.expect(#a.w.teleports).toBe(0)
		t.expect(#a.w.kicks).toBe(0)
		t.expect(Pay.record(a.w.records["7"]).free).toBe(NOW - 600) -- nothing charged, no free game taken
	end)

	it("outside Studio an arrival with nothing to pay with is still sent back (G10)", function()
		local a = nothingToPay(function(): boolean
			return false
		end)
		t.expect(Session.isOver(a.s, "7")).toBe(true)
		t.expect(#a.w.teleports).toBe(1)
		t.expect(#a.w.kicks).toBe(1) -- its teleport failed
	end)

	it("with no IsStudio, or one that errors, the arrival is sent back as outside Studio", function()
		local erroring = function(): boolean
			error("not here", 0)
		end
		local variants: { any } = { "absent", erroring } -- no IsStudio on the stub, or one that errors
		for _, isStudio in variants do
			local a = nothingToPay(if isStudio == "absent" then nil else isStudio)
			t.expect(Session.isOver(a.s, "7")).toBe(true)
			t.expect(#a.w.teleports).toBe(1)
			t.expect(#a.w.kicks).toBe(1)
		end
	end)
end)
