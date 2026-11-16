--!strict
-- f0206 AC4: the portal's server adapter (ServerScriptService.Server.BoardRelay), run from its real source on a stub
-- server with a stand-in for the arcade's Boards (f0197). At start it opens every card's title through the arcade by
-- the title's HiscoreGames prefix and serves each on a relay of its own (never the client's remote). A client asks on
-- ReplicatedStorage.Remotes.Boards with (title, board id); Board.plan decides: a refresh or a forward goes to that
-- title's arcade boards as (player, id), and the arcade's answer comes back to the asker as (title, id, rows, rank,
-- status, best) and is held; any other ask is answered from the held rows. The engine's budget is read for standard
-- and sorted reads before each ask. A player who left hears nothing, and a player who rejoins starts afresh.
local Games = require("@shared/Games")
local HiscoreGames = require("@arcade/HiscoreGames")
local Hiscores = require("@arcade/Logic/Hiscores")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local SOURCE = (built :: any)
	:GetService("ServerScriptService")
	:FindFirstChild("Server")
	:FindFirstChild("BoardRelay").Source

local NOON = 1792152000 -- 2026-10-16 12:00 UTC

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

local function rows(...: string): { any }
	local out = {}
	for i, name in { ... } do
		table.insert(out, { rank = i, name = name, score = 1000 - i, level = 2, revives = i - 1 })
	end
	return out
end

local function world(options: { failOpen: string?, budgetFails: boolean? }?): any
	local opts: any = options or {}
	local w: any = {
		now = NOON,
		errors = {},
		fired = {},
		opened = {},
		served = {},
		forwards = {},
		budgetKinds = {},
		budget = { StandardRead = 1000, OrderedList = 1000 },
		players = {},
		warnings = 0,
	}

	local function spawn(fn: (...any) -> (), ...: any)
		local ok, err = coroutine.resume(coroutine.create(fn), ...)
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

	local remote: any = {
		Name = "Boards",
		ClassName = "RemoteEvent",
		OnServerEvent = signal(),
		FireClient = function(_: any, player: any, ...: any)
			table.insert(w.fired, table.pack(player, ...))
		end,
		FireAllClients = function(_: any)
			table.insert(w.errors, "FireAllClients")
		end,
	}
	w.remote = remote
	local remotes: any = {
		WaitForChild = function(_: any, name: string): any
			assert(name == "Boards", name)
			return remote
		end,
	}
	remotes.FindFirstChild = remotes.WaitForChild
	local removing = signal()
	w.removing = removing

	-- the arcade's Boards, as the relay uses it: open(prefix).serve(remote-like); its handler records each forward
	local FakeBoards = {
		open = function(prefix: string): any
			table.insert(w.opened, prefix)
			if opts.failOpen == prefix then
				error("stub: bad prefix", 0)
			end
			return {
				serve = function(relay: any)
					w.served[prefix] = relay
					relay.OnServerEvent:Connect(function(player: any, id: any)
						table.insert(w.forwards, { prefix = prefix, player = player, id = id })
					end)
				end,
			}
		end,
	}

	local services: { [string]: any } = {
		ReplicatedStorage = {
			WaitForChild = function(_: any, name: string): any
				assert(name == "Remotes", name)
				return remotes
			end,
			FindFirstChild = function(_: any, name: string): any
				return if name == "Remotes" then remotes else nil
			end,
		},
		Players = {
			PlayerRemoving = removing,
			PlayerAdded = signal(),
			GetPlayers = function(): { any }
				return table.clone(w.players)
			end,
		},
		DataStoreService = {
			GetRequestBudgetForRequestType = function(_: any, kind: any): number
				table.insert(w.budgetKinds, tostring(kind))
				if opts.budgetFails then
					error("stub: budget query failed", 0)
				end
				local item = string.match(tostring(kind), "%.(%w+)$") or ""
				return w.budget[item] or 0
			end,
		},
	}
	local env: { [string]: any } = {
		game = {
			GetService = function(_: any, name: string): any
				return services[name] or standin()
			end,
		},
		Enum = setmetatable({}, {
			__index = function(_: any, group: string): any
				return setmetatable({}, {
					__index = function(_: any, item: string): string
						return `{group}.{item}`
					end,
				})
			end,
		}),
		task = {
			spawn = spawn,
			defer = spawn,
			delay = function() end,
			wait = function()
				return 0
			end,
		},
		os = {
			time = function(): number
				return w.now
			end,
			clock = function(): number
				return w.now
			end,
		},
		warn = function()
			w.warnings += 1
		end,
		require = function(spec: string): any
			local logic = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/(%w+)$")
			if logic then
				return (require :: any)("@logic/" .. logic)
			end
			local shared = string.match(spec, "^@game/ReplicatedStorage/Shared/(%w+)$")
			if shared then
				return (require :: any)("@shared/" .. shared)
			end
			if spec == "@game/ServerStorage/Arcade/Boards" then
				return FakeBoards
			end
			local arcadeLogic = string.match(spec, "^@game/ReplicatedStorage/Arcade/Logic/(%w+)$")
			if arcadeLogic then
				return (require :: any)("@arcade/Logic/" .. arcadeLogic)
			end
			local arcade = string.match(spec, "^@game/ReplicatedStorage/Arcade/(%w+)$")
			if arcade then
				return (require :: any)("@arcade/" .. arcade)
			end
			return standin() -- a module a later issue adds
		end,
	}
	w.Relay = luau.load(SOURCE, { debugName = "BoardRelay", environment = env })()

	function w.join(userId: number): any
		local p = { UserId = userId, Name = `p{userId}`, Parent = {} }
		table.insert(w.players, p)
		return p
	end
	function w.leave(p: any)
		p.Parent = nil
		local i = table.find(w.players, p)
		if i then
			table.remove(w.players, i)
		end
		removing.fire(p)
	end
	-- a client's ask: returns what the remote fired to clients meanwhile
	function w.ask(p: any, ...: any): { any }
		local before = #w.fired
		remote.OnServerEvent.fire(p, ...)
		local out = {}
		for i = before + 1, #w.fired do
			table.insert(out, w.fired[i])
		end
		return out
	end
	-- the arcade answers one forwarded ask on its relay: (player, id, rows, rank, failed, best)
	function w.reply(
		prefix: string,
		p: any,
		id: string,
		rs: { any },
		rank: number?,
		failed: boolean,
		best: any
	): { any }
		local before = #w.fired
		local relay = w.served[prefix]
		assert(relay ~= nil, `no relay for {prefix}`)
		relay:FireClient(p, id, rs, rank, failed, best)
		local out = {}
		for i = before + 1, #w.fired do
			table.insert(out, w.fired[i])
		end
		return out
	end
	function w.forwarded(): number
		return #w.forwards
	end
	-- start's own error, if any, is the case's to judge: the engine would log it and boot nothing after it
	local ok, err = pcall(w.Relay.start)
	w.startError = if ok then nil else tostring(err)
	return w
end

return t.spec("f0206 server", function(it)
	it(
		"opens every card's title by its HiscoreGames prefix, once, and serves each on a relay of its own",
		function()
			local w = world()
			local want = {}
			for _, e in Games.LIST do
				table.insert(want, HiscoreGames[e.name].prefix)
			end
			t.expect(table.concat(w.opened, ",")).toBe(table.concat(want, ","))
			for _, prefix in want do
				local relay = w.served[prefix]
				t.expect(relay ~= nil).toBe(true)
				t.expect(relay ~= w.remote).toBe(true)
				t.expect(type(relay.FireClient)).toBe("function")
				t.expect(type(relay.OnServerEvent.Connect)).toBe("function")
			end
			t.expect(w.remote.OnServerEvent.count()).toBe(1)
			t.expect(#w.errors).toBe(0)
		end
	)

	it("every card's title has its boards in HiscoreGames, with its progress figure named", function()
		for _, e in Games.LIST do
			local h = HiscoreGames[e.name]
			t.expect(h ~= nil).toBe(true)
			t.expect(type(h.prefix)).toBe("string")
			t.expect(type(h.progress) == "string" and #h.progress > 0).toBe(true)
		end
	end)

	it(
		"a first ask goes to that title's arcade boards as (player, id), and nothing is answered yet",
		function()
			local w = world()
			local p = w.join(1)
			local out = w.ask(p, "snake", "day")
			t.expect(#out).toBe(0)
			t.expect(w.forwarded()).toBe(1)
			t.expect(w.forwards[1].prefix).toBe(HiscoreGames.snake.prefix)
			t.expect(w.forwards[1].player).toBe(p)
			t.expect(w.forwards[1].id).toBe("day")
		end
	)

	it("the arcade's answer reaches the asker as (title, id, rows, rank, ok, best)", function()
		local w = world()
		local p = w.join(1)
		w.ask(p, "pickman", "all")
		local best = { score = 999, level = 2, revives = 0 }
		local out = w.reply("", p, "all", rows("Ada", "p1"), 2, false, best)
		t.expect(#out).toBe(1)
		local f = out[1]
		t.expect(f[1]).toBe(p)
		t.expect(f[2]).toBe("pickman")
		t.expect(f[3]).toBe("all")
		t.expect(#f[4]).toBe(2)
		t.expect(f[4][1].name).toBe("Ada")
		t.expect(f[5]).toBe(2)
		t.expect(f[6]).toBe("ok")
		t.expect(f[7]).toBe(best)
	end)

	it("a failed arcade answer reaches the asker as failed, with the rows the arcade held", function()
		local w = world()
		local p = w.join(1)
		w.ask(p, "invaders", "week")
		local out = w.reply(HiscoreGames.invaders.prefix, p, "week", rows("Old"), nil, true, nil)
		t.expect(#out).toBe(1)
		t.expect(out[1][6]).toBe("failed")
		t.expect(#out[1][4]).toBe(1)
		t.expect(out[1][4][1].name).toBe("Old")
	end)

	it(
		"another player's ask inside the arcade's cache time is forwarded too, and hears their own rank",
		function()
			local w = world()
			local a, b = w.join(1), w.join(2)
			w.ask(a, "pickman", "day")
			w.reply("", a, "day", rows("x", "y"), 1, false, nil)
			w.now += 5
			local out = w.ask(b, "pickman", "day")
			t.expect(#out).toBe(0)
			t.expect(w.forwarded()).toBe(2)
			out = w.reply("", b, "day", rows("x", "y"), 2, false, nil)
			t.expect(#out).toBe(1)
			t.expect(out[1][1]).toBe(b)
			t.expect(out[1][5]).toBe(2)
		end
	)

	it(
		"after the cache time and before REFRESH an ask is answered from the held rows, not forwarded",
		function()
			local w = world()
			local a, b, c = w.join(1), w.join(2), w.join(3)
			w.ask(a, "pickman", "day")
			w.reply("", a, "day", rows("x", "y"), 1, false, nil)
			w.now += 3
			w.ask(b, "pickman", "day")
			w.reply("", b, "day", rows("x", "y"), 2, false, nil)
			w.now += 17 -- 20 s after the refresh
			local before = w.forwarded()
			local out = w.ask(b, "pickman", "day")
			t.expect(w.forwarded()).toBe(before)
			t.expect(#out).toBe(1)
			t.expect(out[1][2]).toBe("pickman")
			t.expect(out[1][3]).toBe("day")
			t.expect(#out[1][4]).toBe(2)
			t.expect(out[1][4][2].name).toBe("y")
			t.expect(out[1][5]).toBe(2) -- b's rank, heard since the refresh
			t.expect(out[1][6]).toBe("ok")
			local other = w.ask(c, "pickman", "day")
			t.expect(#other).toBe(1)
			t.expect(other[1][5]).toBe(nil) -- c never heard a rank
			t.expect(#other[1][4]).toBe(2)
		end
	)

	it("REFRESH after the last refresh, an ask is forwarded again", function()
		local w = world()
		local a = w.join(1)
		w.ask(a, "snake", "week")
		w.reply(HiscoreGames.snake.prefix, a, "week", rows("x"), nil, false, nil)
		w.now += 29
		w.ask(a, "snake", "week")
		t.expect(w.forwarded()).toBe(1)
		w.now += 1
		w.ask(a, "snake", "week")
		t.expect(w.forwarded()).toBe(2)
	end)

	it("reads the engine's budget for standard and sorted reads on each ask", function()
		local w = world()
		local a = w.join(1)
		w.ask(a, "pickman", "all")
		local kinds = table.concat(w.budgetKinds, " ")
		t.expect(string.find(kinds, "DataStoreRequestType.StandardRead", 1, true) ~= nil).toBe(true)
		t.expect(string.find(kinds, "DataStoreRequestType.OrderedList", 1, true) ~= nil).toBe(true)
	end)

	it(
		"with the engine's budget below its reserve, a first ask is answered wait and nothing is read",
		function()
			local w = world()
			w.budget.OrderedList = 2
			local a = w.join(1)
			local out = w.ask(a, "pickman", "day")
			t.expect(w.forwarded()).toBe(0)
			t.expect(#out).toBe(1)
			t.expect(out[1][6]).toBe("wait")
			t.expect(#out[1][4]).toBe(0)
			w.budget.OrderedList = 100
			w.ask(a, "pickman", "day")
			t.expect(w.forwarded()).toBe(1)
		end
	)

	it("a budget that cannot be read reads nothing: the ask is answered wait", function()
		local w = world({ budgetFails = true })
		local a = w.join(1)
		local out = w.ask(a, "pickman", "all")
		t.expect(#w.errors).toBe(0)
		t.expect(w.forwarded()).toBe(0)
		t.expect(#out).toBe(1)
		t.expect(out[1][6]).toBe("wait")
	end)

	it("the best goes with all-time answers only, and a held answer carries the best last heard", function()
		local w = world()
		local a = w.join(1)
		w.ask(a, "pickman", "day")
		local day = w.reply("", a, "day", rows("x"), nil, false, { score = 1, level = 1, revives = 0 })
		t.expect(#day).toBe(1)
		t.expect(day[1][7]).toBe(nil)
		w.ask(a, "pickman", "all")
		local best = { score = 5, level = 3, revives = 1 }
		w.reply("", a, "all", rows("x"), nil, false, best)
		w.now += 20
		local held = w.ask(a, "pickman", "all")
		t.expect(#held).toBe(1)
		t.expect(held[1][7]).toBe(best)
		local heldDay = w.ask(a, "pickman", "day")
		t.expect(#heldDay).toBe(1)
		t.expect(heldDay[1][7]).toBe(nil)
	end)

	it("a title it does not serve, a board id that is none, or a player who left: nothing at all", function()
		local w = world()
		local a = w.join(1)
		for _, args in
			{
				{ "lobby" :: any, "all" },
				{ 5 :: any, "all" },
				{ "pickman" :: any, "month" },
				{ "pickman" :: any, false },
				{ false :: any, false },
			} :: { any }
		do
			local out = w.ask(a, args[1], args[2])
			t.expect(#out).toBe(0)
		end
		w.leave(a)
		local out = w.ask(a, "pickman", "all")
		t.expect(#out).toBe(0)
		t.expect(w.forwarded()).toBe(0)
		t.expect(#w.errors).toBe(0)
	end)

	it("an answer for a player who left is not sent, but its rows are held for the next asker", function()
		local w = world()
		local a, b = w.join(1), w.join(2)
		w.ask(a, "pickman", "week")
		w.leave(a)
		local out = w.reply("", a, "week", rows("kept"), nil, false, nil)
		t.expect(#out).toBe(0)
		w.now += 20
		local held = w.ask(b, "pickman", "week")
		t.expect(#held).toBe(1)
		t.expect(#held[1][4]).toBe(1)
		t.expect(held[1][4][1].name).toBe("kept")
		t.expect(held[1][6]).toBe("ok")
	end)

	it(
		"an all-time ask inside BEST_GAP whose best the arcade would read again is answered, not forwarded",
		function()
			local w = world()
			local a, q = w.join(1), w.join(2)
			w.ask(a, "pickman", "all") -- a refresh: the arcade reads a's best
			w.reply("", a, "all", rows("x"), nil, false, nil)
			w.now += 30
			w.ask(q, "pickman", "all") -- the next refresh, q's
			t.expect(w.forwarded()).toBe(2)
			w.now += 1
			local out = w.ask(a, "pickman", "all") -- 31 s after a's best was read: inside BEST_GAP
			t.expect(w.forwarded()).toBe(2)
			t.expect(#out).toBe(1)
		end
	)

	it("a player who leaves and joins again starts afresh", function()
		local w = world()
		local a, q = w.join(1), w.join(2)
		w.ask(a, "pickman", "all")
		w.reply("", a, "all", rows("x"), nil, false, nil)
		w.now += 30
		w.ask(q, "pickman", "all")
		w.now += 1
		w.leave(a)
		local again = w.join(1) -- a new Player object with the same user id
		w.ask(again, "pickman", "all")
		t.expect(w.forwarded()).toBe(3)
		t.expect(w.forwards[3].player).toBe(again)
	end)

	it(
		"a new day is a new board: its first ask refreshes, though yesterday's was read seconds ago",
		function()
			local w = world()
			w.now = 1792195200 - 5 -- five seconds before 2026-10-17 00:00 UTC
			local a = w.join(1)
			w.ask(a, "pickman", "day")
			w.reply("", a, "day", rows("yesterday"), nil, false, nil)
			w.now += 10
			t.expect(Hiscores.cacheKey("day", w.now) ~= Hiscores.cacheKey("day", w.now - 10)).toBe(true)
			w.ask(a, "pickman", "day")
			t.expect(w.forwarded()).toBe(2)
		end
	)

	it("a title whose boards cannot be opened is left out with a warning; the others are served", function()
		local w = world({ failOpen = HiscoreGames.invaders.prefix })
		t.expect(w.startError).toBe(nil)
		t.expect(w.warnings).toBe(1)
		local a = w.join(1)
		t.expect(#w.ask(a, "invaders", "all")).toBe(0)
		t.expect(w.forwarded()).toBe(0)
		w.ask(a, "asteroids", "all")
		t.expect(w.forwarded()).toBe(1)
		t.expect(#w.errors).toBe(0)
	end)

	it("answers go to the asker alone, never to every client", function()
		local w = world()
		local a, b = w.join(1), w.join(2)
		w.ask(a, "pickman", "day")
		local out = w.reply("", a, "day", rows("x"), nil, false, nil)
		t.expect(#out).toBe(1)
		t.expect(out[1][1]).toBe(a)
		t.expect(#w.errors).toBe(0)
		local _ = b
	end)

	it("start is once per server: a second start opens and listens to nothing more", function()
		local w = world()
		local opened = #w.opened
		w.Relay.start()
		t.expect(#w.opened).toBe(opened)
		t.expect(w.remote.OnServerEvent.count()).toBe(1)
	end)
end)
