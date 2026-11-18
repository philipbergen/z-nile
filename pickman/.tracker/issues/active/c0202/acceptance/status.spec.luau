--!strict
-- c0202 AC9: what main's paid play landed with after this issue was first designed, kept through the switch
-- (R0118 code review 001 F1 to F3, final review 001 F2, and the user's "Play in Studio only"), on the same stub
-- engine: R0118's tests/place/paid-play-status.spec cases, moved onto the library. The game place tells the mode
-- on every path that lets a player play (no status after a failed claim) and what the player holds after every
-- record it writes or hears; a test confirm whose grant or revive write fails releases the countdown at once; a
-- confirm with no screen open leaves every other hold; a Studio play with nothing to pay with plays.
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
	w.onUpdate = nil :: (() -> ())?
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
						local during = w.onUpdate -- runs once, at the start of the next write (before it is held)
						if during then
							w.onUpdate = nil
							during()
						end
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
		RunService = { Heartbeat = signal() } :: any, -- no IsStudio: not Studio (status.spec's cases set one)
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
	w.service = function(name: string): any -- a stub service, which a case may change
		return assert(services[name], `service {name}`)
	end
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

local function timer(a: any): number
	return Session.frame(a.s, "7").play.timer
end

-- the last PayStatus the player was told: the mode and the status (nil when the record is unknown)
local function lastStatus(a: any): (any, any)
	local told = a.w.sentOn("PayStatus", a.p)
	assert(#told > 0, "nothing told on PayStatus")
	local args = told[#told]
	return args[1], args[2]
end

local function noFree(w: any, store: string, revives: number?)
	w.seed(store, 7, { free = NOW - 60, plays = 1, continues = revives or 0, receipts = {} })
end

-- an arrival with nothing to pay with (the hour's free game used, nothing held, no pass), where teleports fail as in
-- Studio; `isStudio` is RunService.IsStudio, or none at all
local function nothingToPay(isStudio: any): any
	return arrive("test", function(w: any)
		w.seed(TEST_STORE, 7, { free = NOW - 600, plays = 0, continues = 0, receipts = {} })
		w.fail.teleport = true
		if isStudio ~= nil then
			w.service("RunService").IsStudio = isStudio
		end
	end)
end

return t.spec(
	"c0202 what main's paid play landed with, kept on the library (R0118's fixes, the Studio play)",
	function(it)
		it(
			"a live arrival whose claim fails still tells the mode, with no status, before any offer",
			function()
				local a = arrive("live", function(w: any)
					w.fail.update = true
				end)
				t.expect(a.s.members["7"].play.offer).toBe(Game.OFFER_TICKS) -- it plays (G10)
				local mode, status = lastStatus(a)
				t.expect(mode).toBe("live")
				t.expect(status).toBe(nil)
			end
		)

		it("a closed arrival whose claim fails tells closed", function()
			local a = arrive("live", function(w: any)
				w.attributes.ContinueProductId = nil -- live with an id missing: closed ("Refuse paid play")
				w.fail.update = true
			end)
			local mode, status = lastStatus(a)
			t.expect(mode).toBe("closed")
			t.expect(status).toBe(nil)
		end)

		it("a revive receipt heard outside the offer tells the revive held", function()
			local a = arrive("live")
			local before = #a.w.sentOn("PayStatus", a.p)
			t.expect(Session.offering(a.s, "7")).toBe(false)
			t.expect(a.w.receipt(7, REVIVE_ID, "C9")).toBe("ProductPurchaseDecision.PurchaseGranted")
			t.expect(#a.w.sentOn("PayStatus", a.p) > before).toBe(true)
			local mode, status = lastStatus(a)
			t.expect(mode).toBe("live")
			t.expect(status.revives).toBe(1)
		end)

		it("a revive's write that finds none held tells none held", function()
			local a = offer("live", function(w: any)
				w.fail.update = true -- the arrival's claim fails: what the player holds is not known
			end)
			a.w.fail.update = false
			a.w.seed(STORE, 7, { free = NOW, plays = 0, continues = 0, receipts = {} })
			local before, writes = #a.w.sentOn("PayStatus", a.p), a.w.writes
			sendContinue(a, "ask")
			t.expect(a.w.writes > writes).toBe(true) -- the ask wrote: nothing was known
			t.expect(#a.w.prompts).toBe(1) -- none held: the purchase screen
			t.expect(#a.w.sentOn("PayStatus", a.p) > before).toBe(true)
			local _, status = lastStatus(a)
			t.expect(status.revives).toBe(0)
		end)

		it("a revive given back after its write tells the revive held", function()
			local a = offer("live", function(w: any)
				noFree(w, STORE, 1)
			end)
			a.w.hold.update = true
			sendContinue(a, "ask")
			sendContinue(a, "decline") -- the player declines while the revive's write yields
			local before = #a.w.sentOn("PayStatus", a.p)
			a.w.release()
			t.expect(stored(a.w, STORE, 7).revives).toBe(1) -- given back
			t.expect(#a.w.sentOn("PayStatus", a.p) > before).toBe(true) -- told after the give-back, not only on arrival
			local _, status = lastStatus(a)
			t.expect(status.revives).toBe(1)
		end)

		it(
			"test: a confirm whose grant write fails releases the countdown; a later ask opens the screen",
			function()
				local a = offer("test")
				sendContinue(a, "ask")
				t.expect(#a.w.sentOn("TestPurchase", a.p)).toBe(1)
				t.expect(holding(a)).toBe(true)
				a.w.fail.update = true
				local before = timer(a)
				a.w.answer(a.p, "confirm")
				t.expect(holding(a)).toBe(false)
				Session.step(a.s)
				t.expect(timer(a) < before).toBe(true)
				t.expect(Session.offering(a.s, "7")).toBe(true)
				a.w.fail.update = false
				a.w.advance(10)
				sendContinue(a, "ask")
				t.expect(#a.w.sentOn("TestPurchase", a.p)).toBe(2)
				t.expect(holding(a)).toBe(true)
			end
		)

		-- R0118 final review 001 F2
		it(
			"test: a granted confirm whose revive write fails releases the hold at once; an ask uses it",
			function()
				local a = offer("test")
				sendContinue(a, "ask")
				t.expect(holding(a)).toBe(true)
				a.w.onUpdate = function() -- the grant's write goes through; the revive's write after it fails
					a.w.onUpdate = function()
						a.w.fail.update = true
					end
				end
				local before = timer(a)
				a.w.answer(a.p, "confirm")
				a.w.fail.update = false
				t.expect(stored(a.w, TEST_STORE, 7).revives).toBe(1) -- granted, held
				t.expect(holding(a)).toBe(false) -- at once, not after the receipt wait
				Session.step(a.s)
				t.expect(timer(a) < before).toBe(true)
				a.w.advance(10)
				sendContinue(a, "ask")
				t.expect(Session.offering(a.s, "7")).toBe(false)
				t.expect(lives(a)).toBe(Game.CONTINUE_LIVES)
				t.expect(stored(a.w, TEST_STORE, 7).revives).toBe(0)
			end
		)

		it("test: a confirm heard during a revive's write leaves that flight's hold", function()
			local a = offer("test")
			sendContinue(a, "ask") -- none held: the test screen, the countdown held
			t.expect(#a.w.sentOn("TestPurchase", a.p)).toBe(1)
			a.w.onUpdate = function() -- the confirm's grant; the next write is the flight it starts, held
				a.w.onUpdate = function()
					a.w.hold.update = true
				end
			end
			a.w.answer(a.p, "confirm")
			a.w.answer(a.p, "confirm") -- heard during that flight: no screen is open
			t.expect(holding(a)).toBe(true) -- the flight's end decides, not the confirm
			a.w.release()
			t.expect(Session.offering(a.s, "7")).toBe(false) -- the flight continued the run
			t.expect(lives(a)).toBe(Game.CONTINUE_LIVES)
			t.expect(stored(a.w, TEST_STORE, 7).revives).toBe(0) -- one revive bought, one used
		end)

		it("a confirm with no screen open leaves a revive's write holding the countdown", function()
			local a = offer("test", function(w: any)
				noFree(w, TEST_STORE, 1)
			end)
			local during: boolean? = nil
			a.w.onUpdate = function()
				a.w.fail.update = true -- the confirm's own write, if it made one, would fail
				a.w.answer(a.p, "confirm")
				during = holding(a)
				a.w.fail.update = false
			end
			sendContinue(a, "ask")
			t.expect(during).toBe(true)
			t.expect(lives(a)).toBe(Game.CONTINUE_LIVES) -- the flight's revive went on
		end)

		it("a confirm with no screen open leaves a bought revive's receipt awaited", function()
			local a = offer("live", function(w: any)
				noFree(w, STORE)
			end)
			sendContinue(a, "ask")
			a.w.finished(7, REVIVE_ID, true) -- bought, the receipt not here yet
			t.expect(holding(a)).toBe(true)
			a.w.answer(a.p, "confirm")
			t.expect(holding(a)).toBe(true)
			local before = timer(a)
			Session.step(a.s)
			t.expect(timer(a)).toBe(before)
		end)

		-- R0118 code review 001 F2, ruled by the user (2026-11-16): (b) "Play in Studio only", kept in pickman's Continues
		-- (2026-11-17, "Keep it in pickman"). An arrival with nothing to pay with and no pass plays when
		-- RunService:IsStudio() is true; anywhere else (false, an error, or no IsStudio at all, as the stub has) it is sent
		-- back as G10 says.
		it("in Studio an arrival with nothing to pay plays with the offer on and is not sent back", function()
			local a = nothingToPay(function(): boolean
				return true
			end)
			t.expect(Session.isOver(a.s, "7")).toBe(false)
			t.expect(a.s.members["7"].play.offer).toBe(Game.OFFER_TICKS)
			t.expect(#a.w.teleports).toBe(0)
			t.expect(#a.w.kicks).toBe(0)
			t.expect(stored(a.w, TEST_STORE, 7).free).toBe(NOW - 600) -- nothing charged, no free game taken
		end)

		-- design review 002 F1: Studio is read only after the library's arrival, so a Studio play still claims what it holds
		it(
			"in Studio an arrival still claims a free game due or a held play, takes its pass, and is told",
			function()
				local function studio(seed: any?, pass: boolean): any
					return arrive("test", function(w: any)
						if seed then
							w.seed(TEST_STORE, 7, seed)
						end
						if pass then
							w.passes["pickman/7"] = true
						end
						w.service("RunService").IsStudio = function(): boolean
							return true
						end
					end)
				end
				local due = studio(nil, false) -- no record: the free game is due
				t.expect(stored(due.w, TEST_STORE, 7).free).toBe(NOW)
				local _, dueStatus = lastStatus(due)
				t.expect(dueStatus ~= nil and dueStatus.free == false).toBe(true)
				local held = studio({ free = NOW - 600, plays = 2, continues = 0, receipts = {} }, false)
				t.expect(stored(held.w, TEST_STORE, 7).plays).toBe(1)
				local _, heldStatus = lastStatus(held)
				t.expect(heldStatus ~= nil and heldStatus.plays == 1).toBe(true)
				local passed = studio({ free = NOW - 600, plays = 0, continues = 0, receipts = {} }, true)
				t.expect(passed.w.passes["pickman/7"]).toBe(nil) -- taken, as on every arrival
				local _, passStatus = lastStatus(passed)
				t.expect(passStatus ~= nil).toBe(true)
				t.expect(#passed.w.teleports).toBe(0)
			end
		)

		-- design review 002 F3: the tell after a use reads the store when the library forgot the record seen, so it comes
		-- after the hold's release and the decline
		it(
			"a decline during a revive's write whose give-back fails ends the run while the tell's read is under way",
			function()
				local a = offer("live", function(w: any)
					noFree(w, STORE, 1)
				end)
				a.w.hold.update = true
				sendContinue(a, "ask")
				sendContinue(a, "decline") -- noted during the flight
				a.w.onUpdate = function() -- the give-back's write, after the use's, fails: the record seen is forgotten
					a.w.fail.update = true
				end
				a.w.hold.get = true -- the tell's read of the store, which follows, does not come back
				local reads = a.w.reads
				a.w.release()
				t.expect(a.w.reads > reads).toBe(true) -- the tell is reading
				Session.step(a.s)
				t.expect(Session.isOver(a.s, "7")).toBe(true) -- the decline did not wait for it
			end
		)

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
	end
)
