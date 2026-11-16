--!strict
-- f0208 AC3: the play buttons' server (ServerScriptService.Server.Plays), run from its real source on a stub server:
-- a stub Wallet whose reads yield until the case answers, a stub Receipts whose handlers the case calls, a recording
-- TeleportService, an in-memory MemoryStore, players and a clock the case moves. A client only asks. The server reads
-- the player's record and decides: a free start due or a held play teleports at once; a failed read writes the
-- portal's pass and teleports; a busy read reads again; with nothing held it opens the play product, and teleports
-- only on that purchase's grant (a close not bought, or a bought one whose receipt is late, ends it); closed mode
-- sells nothing. PLAY goes to a public server of the title's place from the attributes, ARENA to the shared arena's
-- reserved server, 2 PLAYERS to a waiting line and then, with a second player, both in one teleport to a fresh
-- reserved server. One play per player at a time, Travel's cool-down after a failure, nothing for a player who left,
-- nothing in TeleportData. Receipts is installed here once.
local PaidPlay = require("@arcade/Logic/PaidPlay")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local SOURCE = (built :: any)
	:GetService("ServerScriptService")
	:FindFirstChild("Server")
	:FindFirstChild("Plays").Source

local NOW = 1000000 -- the stub's os.time()
local IDS = {
	PortalPlaceId = 100,
	PickmanPlaceId = 101,
	SnakePlaceId = 102,
	InvadersPlaceId = 103,
	AsteroidsPlaceId = 104,
}

type Signal = { Connect: (any, (...any) -> ()) -> any, fire: (...any) -> (), count: () -> number }

local function standin(): any
	local s: any
	s = setmetatable({}, {
		__index = function(): any
			return s
		end,
		__call = function(): any
			return nil
		end,
	})
	return s
end

local function world(attributes: { [string]: any }?): any
	local attrs = attributes or IDS
	local w: any = {
		clock = 0,
		sent = {},
		all = {},
		reads = {},
		asks = {},
		passes = {},
		teleports = {},
		errors = {},
		timers = {},
		attrReads = 0,
		maps = {},
		updates = {},
		modes = {},
		guid = 0,
		players = {},
		offers = {},
		receiptStarts = 0,
		inviteStarts = 0,
		askOpens = true,
		teleportFails = false,
		memoryDown = false,
		races = {},
	}

	local function spawn(fn: (...any) -> (), ...: any)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			table.insert(w.errors, tostring(err))
		end
	end

	local function signal(): Signal
		local fns: { (...any) -> () } = {}
		return {
			Connect = function(_: any, fn: (...any) -> ()): any
				table.insert(fns, fn)
				return { Disconnect = function() end }
			end,
			fire = function(...: any)
				for _, fn in table.clone(fns) do
					spawn(fn, ...)
				end
			end,
			count = function(): number
				return #fns
			end,
		}
	end

	local function later(seconds: number, fn: (...any) -> (), ...: any)
		table.insert(w.timers, { at = w.clock + (seconds or 0), fn = fn, args = table.pack(...) })
	end

	-- moves the clock, running each timer that comes due, in order
	function w.advance(dt: number)
		local target = w.clock + dt
		while true do
			local best, at = nil, math.huge
			for i, timer in w.timers do
				if timer.at <= target and timer.at < at then
					best, at = i, timer.at
				end
			end
			if best == nil then
				break
			end
			local timer = table.remove(w.timers, best)
			w.clock = timer.at
			spawn(timer.fn, table.unpack(timer.args, 1, timer.args.n))
		end
		w.clock = target
	end

	local remote: any = { OnServerEvent = signal(), Name = "Play", ClassName = "RemoteEvent" }
	remote.FireClient = function(_: any, player: any, ...: any)
		table.insert(w.sent, { player = player, args = table.pack(...) })
	end
	remote.FireAllClients = function(_: any, ...: any)
		table.insert(w.all, table.pack(...))
	end
	w.remote = remote
	local remotes: any = {
		Name = "Remotes",
		WaitForChild = function(_: any, name: string): any
			assert(name == "Play", name)
			return remote
		end,
		FindFirstChild = function(_: any, name: string): any
			return if name == "Play" then remote else nil
		end,
	}
	local playersService: any = { PlayerRemoving = signal(), PlayerAdded = signal() }
	playersService.GetPlayers = function(): { any }
		local out = {}
		for _, p in w.players do
			if p.Parent ~= nil then
				table.insert(out, p)
			end
		end
		return out
	end
	playersService.GetPlayerByUserId = function(_: any, id: any): any
		for _, p in w.players do
			if p.Parent ~= nil and p.UserId == id then
				return p
			end
		end
		return nil
	end
	local teleport: any = { TeleportInitFailed = signal() }
	teleport.TeleportAsync = function(_: any, placeId: any, players: any, options: any, ...: any)
		table.insert(w.teleports, {
			place = placeId,
			players = table.clone(players),
			options = options,
			extra = select("#", ...),
		})
		if w.teleportFails then
			error("teleport failed")
		end
		return standin()
	end
	w.teleport = teleport
	local memory: any = {}
	memory.GetHashMap = function(_: any, name: string): any
		local map = w.maps[name]
		if map == nil then
			map = { data = {} }
			map.UpdateAsync = function(_: any, key: string, fn: (any) -> any, expiration: number): any
				if w.memoryDown then
					error("memory store down")
				end
				local race = w.races[key]
				if race ~= nil then
					w.races[key] = nil
					fn(map.data[key]) -- an outdated first call
					map.data[key] = race -- another portal server wrote meanwhile
				end
				local value = fn(map.data[key])
				table.insert(w.updates, { map = name, key = key, expiration = expiration, value = value })
				if value ~= nil then
					map.data[key] = value
				end
				return value
			end
			map.GetAsync = function(_: any, key: string): any
				return map.data[key]
			end
			map.SetAsync = function(_: any, key: string, value: any): boolean
				map.data[key] = value
				return true
			end
			w.maps[name] = map
		end
		return map
	end
	local services: { [string]: any } = {
		Players = playersService,
		ReplicatedStorage = {
			WaitForChild = function(_: any, name: string): any
				assert(name == "Remotes", name)
				return remotes
			end,
			FindFirstChild = function(_: any, name: string): any
				return if name == "Remotes" then remotes else nil
			end,
		},
		ServerScriptService = {
			GetAttribute = function(_: any, name: string): any
				w.attrReads += 1
				return attrs[name]
			end,
		},
		TeleportService = teleport,
		MemoryStoreService = memory,
		HttpService = {
			GenerateGUID = function(): string
				w.guid += 1
				return `guid-{w.guid}`
			end,
		},
		RunService = { Heartbeat = signal() },
	}
	w.services = services

	local wallet: any = standin()
	wallet.read = function(player: any, name: string): (any, any)
		table.insert(w.reads, { player = player, name = name, co = coroutine.running(), done = false })
		return coroutine.yield()
	end
	wallet.mode = function(name: string): string
		return w.modes[name] or "test"
	end
	wallet.pass = function(player: any, name: string): boolean
		table.insert(w.passes, { player = player, name = name, teleports = #w.teleports })
		return true
	end
	local receipts: any = standin()
	receipts.start = function(handlers: any): boolean
		w.receiptStarts += 1
		w.handlers = handlers
		return true
	end
	receipts.ask = function(player: any, name: string, kind: string): boolean
		table.insert(w.asks, { player = player, name = name, kind = kind })
		return w.askOpens
	end
	local invites: any = standin()
	invites.start = function()
		w.inviteStarts += 1
	end
	invites.offer = function(player: any, name: string)
		table.insert(w.offers, { player = player, name = name })
	end

	local env: { [string]: any } = {}
	env.game = {
		GetService = function(_: any, name: string): any
			return services[name] or standin()
		end,
		JobId = "job-here",
		PlaceId = 100,
	}
	env.Instance = {
		new = function(class: string): any
			return { ClassName = class }
		end,
	}
	env.task = {
		spawn = spawn,
		defer = spawn,
		delay = later,
		wait = function(seconds: number?): number
			local co = coroutine.running()
			later(seconds or 0, function()
				local ok, err = coroutine.resume(co, seconds or 0)
				if not ok then
					table.insert(w.errors, tostring(err))
				end
			end)
			return coroutine.yield()
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
	env.require = function(spec: string): any
		local logic = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/(%w+)$")
		if logic then
			return (require :: any)("@logic/" .. logic)
		end
		local shared = string.match(spec, "^@game/ReplicatedStorage/Shared/(%w+)$")
		if shared then
			return (require :: any)("@shared/" .. shared)
		end
		local arcadeLogic = string.match(spec, "^@game/ReplicatedStorage/Arcade/Logic/(%w+)$")
		if arcadeLogic then
			return (require :: any)("@arcade/Logic/" .. arcadeLogic)
		end
		local arcade = string.match(spec, "^@game/ReplicatedStorage/Arcade/(%w+)$")
		if arcade then
			return (require :: any)("@arcade/" .. arcade)
		end
		if spec == "@game/ServerStorage/Arcade/Wallet" then
			return wallet
		elseif spec == "@game/ServerStorage/Arcade/Receipts" then
			return receipts
		elseif spec == "./Invites" then
			return invites
		end
		return standin() -- another server module or a sibling adapter a later issue adds
	end

	local Plays = luau.load(SOURCE, { debugName = "Plays", environment = env })()
	w.Plays = Plays
	spawn(function()
		Plays.start()
	end)

	function w.join(name: string, id: number): any
		local p: any = { Name = name, UserId = id, Parent = playersService }
		table.insert(w.players, p)
		playersService.PlayerAdded.fire(p)
		return p
	end
	function w.leave(p: any)
		p.Parent = nil
		playersService.PlayerRemoving.fire(p)
	end
	function w.press(p: any, ...: any)
		remote.OnServerEvent.fire(p, ...)
	end
	-- the read of `name` for `p` still waiting, answered with the record and reason given
	function w.answer(p: any, name: string, record: any, reason: any)
		for _, r in w.reads do
			if r.player == p and r.name == name and not r.done then
				r.done = true
				local ok, err = coroutine.resume(r.co, record, reason)
				if not ok then
					table.insert(w.errors, tostring(err))
				end
				return
			end
		end
		error(`no read of {name} waiting`)
	end
	function w.waitingReads(p: any): number
		local n = 0
		for _, r in w.reads do
			if r.player == p and not r.done then
				n += 1
			end
		end
		return n
	end
	function w.readCount(p: any): number
		local n = 0
		for _, r in w.reads do
			if r.player == p then
				n += 1
			end
		end
		return n
	end
	-- the last status the server told `p`, or nil
	function w.status(p: any): any
		for i = #w.sent, 1, -1 do
			local m = w.sent[i]
			if m.player == p and m.args[1] == "status" then
				return m.args[2]
			end
		end
		return nil
	end
	function w.phase(p: any): string?
		local s = w.status(p)
		return if s == nil then nil else s.phase
	end
	-- the last status's phase, title and mode, field by field (a later issue may add fields)
	function w.about(p: any): string
		local s = w.status(p)
		return if s == nil then "none" else `{s.phase} {tostring(s.name)} {tostring(s.mode)}`
	end
	-- the i-th teleport call, asserting it was made (so a missing call fails on an assertion)
	function w.call(i: number): any
		t.expect(#w.teleports >= i).toBe(true)
		return w.teleports[i]
	end
	function w.lastAll(): any
		t.expect(#w.all > 0).toBe(true)
		return w.all[#w.all]
	end
	function w.grant(p: any, name: string, kind: string)
		w.handlers.granted(p, name, kind)
	end
	function w.closed(p: any, name: string, kind: string, bought: boolean)
		w.handlers.closed(p, name, kind, bought)
	end
	function w.heartbeat(dt: number)
		w.advance(dt)
		services.RunService.Heartbeat.fire(dt)
	end
	return w
end

local FREE = PaidPlay.record(nil) -- a new player's record: the free start is due
local function held(plays: number): any
	return PaidPlay.record({ free = NOW - 60, plays = plays, continues = 0, receipts = {} })
end
local NONE = held(0) -- the free start was taken a minute ago and nothing is held

local function clean(w: any)
	t.expect(table.concat(w.errors, "\n")).toBe("")
end

return t.spec("f0208 server", function(it)
	it("installs Receipts once, with a grant and a close handler, and Invites once", function()
		local w = world()
		t.expect(w.receiptStarts).toBe(1)
		t.expect(type(w.handlers.granted)).toBe("function")
		t.expect(type(w.handlers.closed)).toBe("function")
		t.expect(w.inviteStarts).toBe(1)
		w.Plays.start()
		t.expect(w.receiptStarts).toBe(1)
		t.expect(w.inviteStarts).toBe(1)
		t.expect(w.remote.OnServerEvent.count()).toBe(1)
		clean(w)
	end)

	it("PLAY with a free start due checks the record, then teleports to the title's place at once", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "invaders", "solo")
		t.expect(w.phase(p)).toBe("checking")
		t.expect(#w.reads).toBe(1)
		t.expect(w.reads[1].name).toBe("invaders")
		t.expect(#w.teleports).toBe(0)
		w.answer(p, "invaders", FREE)
		t.expect(#w.teleports).toBe(1)
		t.expect(w.call(1).place).toBe(103)
		t.expect(w.call(1).players).toEqual({ p })
		t.expect(w.call(1).options.ReservedServerId).toBe(nil)
		t.expect(w.phase(p)).toBe("going")
		t.expect(w.about(p)).toBe("going invaders solo")
		t.expect(#w.asks).toBe(0)
		t.expect(#w.passes).toBe(0)
		clean(w)
	end)

	it("PLAY with a held play teleports at once; nothing is charged here", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "pickman", "solo")
		w.answer(p, "pickman", held(1))
		t.expect(#w.teleports).toBe(1)
		t.expect(w.call(1).place).toBe(101)
		t.expect(#w.asks).toBe(0)
		clean(w)
	end)

	it(
		"the free state is PaidPlay's at os.time(): a free start taken under an hour ago is not due",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.press(p, "play", "pickman", "solo")
			w.answer(p, "pickman", PaidPlay.record({ free = NOW - 3599, plays = 0 }))
			t.expect(#w.teleports).toBe(0)
			t.expect(#w.asks).toBe(1)
			local q = w.join("bob", 2)
			w.press(q, "play", "pickman", "solo")
			w.answer(q, "pickman", PaidPlay.record({ free = NOW - 3600, plays = 0 }))
			t.expect(#w.teleports).toBe(1)
			clean(w)
		end
	)

	it(
		"with nothing held it opens the 1 R$ play product of that title, and teleports on its grant",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.press(p, "play", "snake", "solo")
			w.answer(p, "snake", NONE)
			t.expect(w.asks).toEqual({ { player = p, name = "snake", kind = "play" } })
			t.expect(w.phase(p)).toBe("buying")
			t.expect(#w.teleports).toBe(0)
			w.grant(p, "snake", "play")
			t.expect(#w.teleports).toBe(1)
			t.expect(w.call(1).place).toBe(102)
			t.expect(w.phase(p)).toBe("going")
			clean(w)
		end
	)

	it(
		"a grant of another title, a revive, or one with no purchase open starts nothing; it stays held",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.grant(p, "snake", "play")
			w.press(p, "play", "snake", "solo")
			w.answer(p, "snake", NONE)
			w.grant(p, "invaders", "play")
			w.grant(p, "snake", "revive")
			t.expect(#w.teleports).toBe(0)
			t.expect(w.phase(p)).toBe("buying")
			clean(w)
		end
	)

	it(
		"a purchase screen closed not bought ends the purchase: idle, no teleport, and a later grant starts nothing",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.press(p, "play", "snake", "solo")
			w.answer(p, "snake", NONE)
			w.closed(p, "snake", "play", false)
			t.expect(w.phase(p)).toBe("idle")
			w.grant(p, "snake", "play")
			t.expect(#w.teleports).toBe(0)
			clean(w)
		end
	)

	it(
		"a screen closed bought before its receipt keeps the purchase open; the grant then teleports",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.press(p, "play", "snake", "solo")
			w.answer(p, "snake", NONE)
			w.closed(p, "snake", "play", true)
			t.expect(w.phase(p)).toBe("buying")
			w.advance(29)
			w.grant(p, "snake", "play")
			t.expect(#w.teleports).toBe(1)
			clean(w)
		end
	)

	it("a receipt before the screen's close teleports, and the close changes nothing", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "snake", "solo")
		w.answer(p, "snake", NONE)
		w.grant(p, "snake", "play")
		w.closed(p, "snake", "play", true)
		w.advance(40)
		t.expect(#w.teleports).toBe(1)
		t.expect(w.phase(p)).toBe("going")
		clean(w)
	end)

	it(
		"a bought screen whose receipt is not here within RECEIPT_SECONDS ends the purchase; the late grant is held",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.press(p, "play", "snake", "solo")
			w.answer(p, "snake", NONE)
			w.closed(p, "snake", "play", true)
			w.advance(30)
			t.expect(w.phase(p)).toBe("idle")
			w.grant(p, "snake", "play")
			t.expect(#w.teleports).toBe(0)
			clean(w)
		end
	)

	it("a purchase screen that cannot open ends in failed", function()
		local w = world()
		w.askOpens = false
		local p = w.join("ann", 1)
		w.press(p, "play", "snake", "solo")
		w.answer(p, "snake", NONE)
		t.expect(w.phase(p)).toBe("failed")
		t.expect(#w.teleports).toBe(0)
		clean(w)
	end)

	it("a read that failed writes the portal's pass for that title, then teleports", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "asteroids", "solo")
		w.answer(p, "asteroids", nil, "down")
		t.expect(#w.passes).toBe(1)
		t.expect(w.passes[1].name).toBe("asteroids")
		t.expect(w.passes[1].teleports).toBe(0)
		t.expect(#w.teleports).toBe(1)
		t.expect(#w.asks).toBe(0)
		clean(w)
	end)

	it("a read that failed lets the player go in closed mode too", function()
		local w = world()
		w.modes.asteroids = "closed"
		local p = w.join("ann", 1)
		w.press(p, "play", "asteroids", "solo")
		w.answer(p, "asteroids", nil, "down")
		t.expect(#w.passes).toBe(1)
		t.expect(#w.teleports).toBe(1)
		clean(w)
	end)

	it(
		"in closed mode nothing is sold: store unavailable, no prompt; a free start or a held play still goes",
		function()
			local w = world()
			w.modes.snake = "closed"
			local p = w.join("ann", 1)
			w.press(p, "play", "snake", "solo")
			w.answer(p, "snake", NONE)
			t.expect(w.phase(p)).toBe("closed")
			t.expect(#w.asks).toBe(0)
			t.expect(#w.teleports).toBe(0)
			w.press(p, "play", "snake", "solo")
			w.answer(p, "snake", held(1))
			t.expect(#w.teleports).toBe(1)
			clean(w)
		end
	)

	it("a busy read is read again BUSY_SECONDS later, with no second read meanwhile", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "pickman", "solo")
		w.answer(p, "pickman", nil, "busy")
		t.expect(w.readCount(p)).toBe(1)
		w.advance(0.2)
		t.expect(w.readCount(p)).toBe(1)
		w.advance(0.05)
		t.expect(w.readCount(p)).toBe(2)
		w.answer(p, "pickman", FREE)
		t.expect(#w.teleports).toBe(1)
		clean(w)
	end)

	it("a check still busy after CHECK_SECONDS fails, with no teleport and no pass", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "pickman", "solo")
		for _ = 1, 200 do
			if w.waitingReads(p) == 0 then
				break
			end
			w.answer(p, "pickman", nil, "busy")
			w.advance(0.25)
		end
		t.expect(w.phase(p)).toBe("failed")
		t.expect(#w.teleports).toBe(0)
		t.expect(#w.passes).toBe(0)
		t.expect(w.readCount(p) <= 42).toBe(true)
		t.expect(w.readCount(p) >= 39).toBe(true)
		clean(w)
	end)

	it(
		"the destinations are the place-id attributes, read once; an unpublished title plays nothing",
		function()
			local w = world({ PickmanPlaceId = 555 })
			local reads = w.attrReads
			t.expect(reads).toBe(5)
			local p = w.join("ann", 1)
			w.press(p, "play", "snake", "solo")
			t.expect(#w.reads).toBe(0)
			t.expect(w.status(p)).toBe(nil)
			w.press(p, "play", "pickman", "solo")
			w.answer(p, "pickman", FREE)
			t.expect(w.call(1).place).toBe(555)
			t.expect(w.attrReads).toBe(reads)
			clean(w)
		end
	)

	it(
		"what the client sends is checked: an unknown title or a mode the title lacks plays nothing",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.press(p, "play", "pickman", "arena")
			w.press(p, "play", "snake", "pair")
			w.press(p, "play", "tetris", "solo")
			w.press(p, "play", 103, "solo")
			w.press(p, "start")
			w.press(p)
			t.expect(#w.reads).toBe(0)
			t.expect(#w.teleports).toBe(0)
			clean(w)
		end
	)

	it("one play at a time: a press while checking, buying or going starts nothing more", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "pickman", "solo")
		w.press(p, "play", "pickman", "solo")
		w.press(p, "play", "snake", "solo")
		t.expect(#w.reads).toBe(1)
		w.answer(p, "pickman", NONE)
		w.press(p, "play", "pickman", "solo")
		w.press(p, "play", "snake", "solo")
		t.expect(#w.reads).toBe(1)
		t.expect(#w.asks).toBe(1)
		w.grant(p, "pickman", "play")
		w.press(p, "play", "pickman", "solo")
		w.grant(p, "pickman", "play")
		t.expect(#w.reads).toBe(1)
		t.expect(#w.teleports).toBe(1)
		clean(w)
	end)

	it(
		"a teleport that errors fails; a press during Travel's cool-down does nothing, one after it plays again",
		function()
			local w = world()
			w.teleportFails = true
			local p = w.join("ann", 1)
			w.press(p, "play", "pickman", "solo")
			w.answer(p, "pickman", FREE)
			t.expect(#w.teleports).toBe(1)
			t.expect(w.phase(p)).toBe("failed")
			w.teleportFails = false
			w.advance(2.9)
			w.press(p, "play", "pickman", "solo")
			t.expect(#w.reads).toBe(1)
			w.advance(0.2)
			w.press(p, "play", "pickman", "solo")
			t.expect(#w.reads).toBe(2)
			w.answer(p, "pickman", FREE)
			t.expect(#w.teleports).toBe(2)
			clean(w)
		end
	)

	it("TeleportInitFailed fails the start", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "pickman", "solo")
		w.answer(p, "pickman", FREE)
		w.teleport.TeleportInitFailed.fire(p)
		t.expect(w.phase(p)).toBe("failed")
		w.press(p, "play", "pickman", "solo")
		t.expect(#w.reads).toBe(1)
		clean(w)
	end)

	it("a start that has not left 15 s after the call fails, told once the heartbeat sees it", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "pickman", "solo")
		w.answer(p, "pickman", FREE)
		w.heartbeat(14)
		t.expect(w.phase(p)).toBe("going")
		w.heartbeat(1.5)
		t.expect(w.phase(p)).toBe("failed")
		clean(w)
	end)

	it(
		"a player who leaves during the check, or with a purchase open, is told, asked and sent nothing",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.press(p, "play", "pickman", "solo")
			local told = #w.sent
			w.leave(p)
			w.answer(p, "pickman", FREE)
			t.expect(#w.teleports).toBe(0)
			local q = w.join("bob", 2)
			w.press(q, "play", "pickman", "solo")
			w.answer(q, "pickman", NONE)
			w.leave(q)
			w.grant(q, "pickman", "play")
			t.expect(#w.teleports).toBe(0)
			local r = w.join("cy", 3)
			w.press(r, "play", "pickman", "solo")
			w.leave(r)
			w.answer(r, "pickman", NONE)
			t.expect(#w.asks).toBe(1)
			for i = told + 1, #w.sent do
				t.expect(w.sent[i].player ~= p).toBe(true)
			end
			clean(w)
		end
	)

	it("a press from a player who already left reads nothing", function()
		local w = world()
		local p = w.join("ann", 1)
		w.leave(p)
		w.press(p, "play", "pickman", "solo")
		t.expect(#w.reads).toBe(0)
		clean(w)
	end)

	it("nothing rides in TeleportData: the call takes the place, the players and options only", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "pickman", "solo")
		w.answer(p, "pickman", FREE)
		local call = w.call(1)
		t.expect(call.extra).toBe(0)
		t.expect(call.options.ClassName).toBe("TeleportOptions")
		for key in call.options do
			t.expect(key == "ClassName" or key == "ReservedServerId").toBe(true)
		end
		clean(w)
	end)

	it("statuses go to the player they are about", function()
		local w = world()
		local p = w.join("ann", 1)
		local q = w.join("bob", 2)
		w.press(p, "play", "pickman", "solo")
		w.answer(p, "pickman", FREE)
		t.expect(w.status(q)).toBe(nil)
		for _, m in w.all do
			t.expect(m[1]).toBe("waiting")
		end
		clean(w)
	end)

	it(
		"ARENA joins the shared arena on record: its reserved server, one more sent, kept OPEN_SECONDS",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.press(p, "play", "snake", "arena")
			w.answer(p, "snake", FREE)
			t.expect(#w.teleports).toBe(1)
			t.expect(w.call(1).place).toBe(102)
			local first = w.call(1).options.ReservedServerId
			t.expect(type(first)).toBe("string")
			t.expect(w.updates[1].map).toBe("PortalArenas")
			t.expect(w.updates[1].key).toBe("snake")
			t.expect(w.updates[1].expiration).toBe(600)
			local q = w.join("bob", 2)
			w.press(q, "play", "snake", "arena")
			w.answer(q, "snake", held(1))
			t.expect(w.call(2).options.ReservedServerId).toBe(first)
			t.expect(w.call(2).players).toEqual({ q })
			t.expect(w.maps.PortalArenas.data.snake.count).toBe(2)
			clean(w)
		end
	)

	it("a full or closed arena makes the next ARENA player open a new one", function()
		local w = world()
		w.memoryDown = false
		local map = w.services.MemoryStoreService:GetHashMap("PortalArenas")
		map.data.snake = { id = "full", count = 24, opened = NOW - 10 }
		local p = w.join("ann", 1)
		w.press(p, "play", "snake", "arena")
		w.answer(p, "snake", FREE)
		local id = w.call(1).options.ReservedServerId
		t.expect(id ~= "full" and type(id) == "string").toBe(true)
		map.data.snake = { id = "old", count = 1, opened = NOW - 600 }
		local q = w.join("bob", 2)
		w.press(q, "play", "snake", "arena")
		w.answer(q, "snake", FREE)
		local id2 = w.call(2).options.ReservedServerId
		t.expect(id2 ~= "old" and id2 ~= id).toBe(true)
		clean(w)
	end)

	it(
		"the arena's last transform call decides: another server's arena written meanwhile is joined",
		function()
			local w = world()
			w.races.snake = { id = "theirs", count = 3, opened = NOW - 5 }
			local p = w.join("ann", 1)
			w.press(p, "play", "snake", "arena")
			w.answer(p, "snake", FREE)
			t.expect(w.call(1).options.ReservedServerId).toBe("theirs")
			t.expect(w.maps.PortalArenas.data.snake.count).toBe(4)
			clean(w)
		end
	)

	it("an arena record that cannot be written fails the start; nothing is sent", function()
		local w = world()
		w.memoryDown = true
		local p = w.join("ann", 1)
		w.press(p, "play", "snake", "arena")
		w.answer(p, "snake", FREE)
		t.expect(#w.teleports).toBe(0)
		t.expect(w.phase(p)).toBe("failed")
		clean(w)
	end)

	it("ARENA bought teleports to the arena on its grant", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "snake", "arena")
		w.answer(p, "snake", NONE)
		t.expect(#w.updates).toBe(0)
		w.grant(p, "snake", "play")
		t.expect(#w.teleports).toBe(1)
		t.expect(type(w.call(1).options.ReservedServerId)).toBe("string")
		clean(w)
	end)

	it(
		"2 PLAYERS alone waits on the card, teleports nothing, and every player hears one is waiting",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.press(p, "play", "invaders", "pair")
			w.answer(p, "invaders", FREE)
			t.expect(w.about(p)).toBe("waiting invaders pair")
			t.expect(#w.teleports).toBe(0)
			local m = w.lastAll()
			t.expect(m[1]).toBe("waiting")
			t.expect(m[2].invaders).toBe(1)
			t.expect(m[2].asteroids).toBe(0)
			local q = w.join("bob", 2)
			local hello = w.sent[#w.sent]
			t.expect(hello.player).toBe(q)
			t.expect(hello.args[1]).toBe("waiting")
			t.expect(hello.args[2].invaders).toBe(1)
			clean(w)
		end
	)

	it(
		"a second player's 2 PLAYERS on that title sends both in one teleport to a fresh reserved server",
		function()
			local w = world()
			local p = w.join("ann", 1)
			local q = w.join("bob", 2)
			w.press(p, "play", "invaders", "pair")
			w.answer(p, "invaders", FREE)
			w.press(q, "play", "invaders", "pair")
			t.expect(#w.teleports).toBe(0)
			w.answer(q, "invaders", held(1))
			t.expect(#w.teleports).toBe(1)
			local call = w.call(1)
			t.expect(call.place).toBe(103)
			t.expect(call.players).toEqual({ p, q })
			t.expect(type(call.options.ReservedServerId)).toBe("string")
			t.expect(w.phase(p)).toBe("going")
			t.expect(w.phase(q)).toBe("going")
			t.expect(w.lastAll()[2].invaders).toBe(0)
			local r = w.join("cy", 3)
			local s = w.join("di", 4)
			w.press(r, "play", "invaders", "pair")
			w.answer(r, "invaders", FREE)
			w.press(s, "play", "invaders", "pair")
			w.answer(s, "invaders", FREE)
			t.expect(w.call(2).options.ReservedServerId ~= call.options.ReservedServerId).toBe(true)
			clean(w)
		end
	)

	it("players waiting on different titles are not paired", function()
		local w = world()
		local p = w.join("ann", 1)
		local q = w.join("bob", 2)
		w.press(p, "play", "invaders", "pair")
		w.answer(p, "invaders", FREE)
		w.press(q, "play", "asteroids", "pair")
		w.answer(q, "asteroids", FREE)
		t.expect(#w.teleports).toBe(0)
		t.expect(w.phase(q)).toBe("waiting")
		clean(w)
	end)

	it("a 2 PLAYERS purchase waits on its grant, then joins the line", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "asteroids", "pair")
		w.answer(p, "asteroids", NONE)
		t.expect(w.phase(p)).toBe("buying")
		w.grant(p, "asteroids", "play")
		t.expect(w.phase(p)).toBe("waiting")
		t.expect(#w.teleports).toBe(0)
		clean(w)
	end)

	it("a 2 PLAYERS player whose read failed has their pass written, then waits", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "asteroids", "pair")
		w.answer(p, "asteroids", nil, "down")
		t.expect(#w.passes).toBe(1)
		t.expect(w.phase(p)).toBe("waiting")
		clean(w)
	end)

	it("CANCEL leaves the line: idle, nobody waiting, and the next player waits instead of going", function()
		local w = world()
		local p = w.join("ann", 1)
		local q = w.join("bob", 2)
		w.press(p, "play", "invaders", "pair")
		w.answer(p, "invaders", FREE)
		w.press(p, "cancel")
		t.expect(w.phase(p)).toBe("idle")
		t.expect(w.lastAll()[2].invaders).toBe(0)
		w.press(q, "play", "invaders", "pair")
		w.answer(q, "invaders", FREE)
		t.expect(#w.teleports).toBe(0)
		t.expect(w.phase(q)).toBe("waiting")
		clean(w)
	end)

	it("a waiting player who leaves leaves the line", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "invaders", "pair")
		w.answer(p, "invaders", FREE)
		w.leave(p)
		t.expect(w.lastAll()[2].invaders).toBe(0)
		local q = w.join("bob", 2)
		w.press(q, "play", "invaders", "pair")
		w.answer(q, "invaders", FREE)
		t.expect(#w.teleports).toBe(0)
		clean(w)
	end)

	it("another play while waiting leaves the line first, then checks the new play", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "invaders", "pair")
		w.answer(p, "invaders", FREE)
		w.press(p, "play", "pickman", "solo")
		t.expect(w.lastAll()[2].invaders).toBe(0)
		t.expect(w.phase(p)).toBe("checking")
		w.answer(p, "pickman", FREE)
		t.expect(w.call(1).place).toBe(101)
		clean(w)
	end)

	it("a party teleport that errors fails both; neither is left waiting", function()
		local w = world()
		w.teleportFails = true
		local p = w.join("ann", 1)
		local q = w.join("bob", 2)
		w.press(p, "play", "invaders", "pair")
		w.answer(p, "invaders", FREE)
		w.press(q, "play", "invaders", "pair")
		w.answer(q, "invaders", FREE)
		t.expect(w.phase(p)).toBe("failed")
		t.expect(w.phase(q)).toBe("failed")
		t.expect(w.lastAll()[2].invaders).toBe(0)
		clean(w)
	end)

	it(
		"INVITE while waiting records the invite once per wait and tells the client to prompt each time",
		function()
			local w = world()
			local p = w.join("ann", 1)
			w.press(p, "invite")
			t.expect(#w.offers).toBe(0)
			w.press(p, "play", "invaders", "pair")
			w.answer(p, "invaders", FREE)
			w.press(p, "invite")
			w.press(p, "invite")
			t.expect(w.offers).toEqual({ { player = p, name = "invaders" } })
			local prompts = 0
			for _, m in w.sent do
				if m.player == p and m.args[1] == "invite" then
					prompts += 1
				end
			end
			t.expect(prompts).toBe(2)
			clean(w)
		end
	)

	it("CANCEL or INVITE with no wait does nothing", function()
		local w = world()
		local p = w.join("ann", 1)
		w.press(p, "play", "pickman", "solo")
		w.press(p, "cancel")
		w.press(p, "invite")
		t.expect(w.phase(p)).toBe("checking")
		t.expect(#w.offers).toBe(0)
		clean(w)
	end)
end)
