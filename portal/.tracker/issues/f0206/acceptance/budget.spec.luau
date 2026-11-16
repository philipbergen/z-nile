--!strict
-- f0206 AC5: the portal reads every title's boards within Roblox's DataStore budget (the arcade's E3), and answers
-- every player promptly. The portal's real BoardRelay and the arcade's real Boards (f0197), both from the built portal
-- place, run together on a stub server whose DataStoreService counts every read. Runs are written through the arcade's
-- own submit. Flooded (every board of every title every second for five minutes, by 1, 4 and 20 players), the sorted
-- reads stay inside the portal's allowance (BURST, then the larger of RATE a minute per player and FLOOR), which is
-- below the engine's per-server budget of 5 + 2 a player a minute; the standard reads stay inside 60 + 40 a player a
-- minute; no board is read twice inside REFRESH; every player is still answered with the stored rows. At the screen's
-- own cadence (BoardsView's asks, modelled with Board.wants, askDue, parse and learn): a lone player sees every card's
-- board the first time they choose its tab, within WAIT_RETRY; players arriving at every phase of the cache's cycle
-- each see their own best within REFRESH + WAIT_RETRY of their first ask, and never "no best"; a board kept in front
-- shows a new run within two REFRESH periods.
local Board = require("@logic/Board")
local Games = require("@shared/Games")
local HiscoreGames = require("@arcade/HiscoreGames")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local RELAY = (built :: any)
	:GetService("ServerScriptService")
	:FindFirstChild("Server")
	:FindFirstChild("BoardRelay").Source
local ARCADE = (built :: any)
	:GetService("ServerStorage")
	:FindFirstChild("Arcade")
	:FindFirstChild("Boards").Source

local START = 1792152000 -- 2026-10-16 12:00 UTC

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out: { [any]: any } = {}
	for k, x in v :: { [any]: any } do
		out[k] = copy(x)
	end
	return out
end

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

local function world(): any
	local w: any = {
		now = START,
		errors = {},
		fired = {},
		players = {},
		reads = { get = 0, sorted = 0 },
		sortedBy = {}, -- "<store>|<scope>" -> { times }
		stores = {},
	}
	local function spawn(fn: (...any) -> (), ...: any)
		local ok, err = coroutine.resume(coroutine.create(fn), ...)
		if not ok then
			table.insert(w.errors, tostring(err))
		end
	end
	local function signal(): any
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
		}
	end
	local function open(name: string, scope: string?): any
		local id = `{name}|{scope or "global"}`
		local data = w.stores[id]
		if data == nil then
			data = {}
			w.stores[id] = data
		end
		return {
			GetAsync = function(_: any, key: string): any
				w.reads.get += 1
				return copy(data[key])
			end,
			UpdateAsync = function(_: any, key: string, transform: (any) -> any): any
				local value = transform(copy(data[key]))
				if value ~= nil then
					data[key] = copy(value)
				end
				return copy(value)
			end,
			GetSortedAsync = function(_: any, ascending: boolean, size: number): any
				w.reads.sorted += 1
				w.sortedBy[id] = w.sortedBy[id] or {}
				table.insert(w.sortedBy[id], w.now)
				local list = {}
				for key, value in data do
					table.insert(list, { key = key, value = value })
				end
				table.sort(list, function(a, b)
					return if ascending then a.value < b.value else a.value > b.value
				end)
				while #list > size do
					table.remove(list)
				end
				return {
					GetCurrentPage = function(): any
						return list
					end,
				}
			end,
		}
	end
	local remote: any = {
		OnServerEvent = signal(),
		FireClient = function(_: any, player: any, ...: any)
			table.insert(w.fired, table.pack(player, ...))
		end,
	}
	w.remote = remote
	local remotes = {
		WaitForChild = function(_: any, name: string): any
			assert(name == "Boards", name)
			return remote
		end,
	}
	local services: { [string]: any } = {
		DataStoreService = {
			GetDataStore = function(_: any, name: string, scope: string?): any
				return open(name, scope)
			end,
			GetOrderedDataStore = function(_: any, name: string, scope: string?): any
				return open(name, scope)
			end,
			GetRequestBudgetForRequestType = function(): number
				return 1000
			end,
		},
		Players = {
			PlayerRemoving = signal(),
			GetPlayers = function(): { any }
				return table.clone(w.players)
			end,
		},
		ReplicatedStorage = {
			WaitForChild = function(_: any, name: string): any
				assert(name == "Remotes", name)
				return remotes
			end,
		},
	}
	local env: { [string]: any } = {}
	local arcadeBoards: any = nil
	env.game = {
		JobId = "job-1",
		GetService = function(_: any, name: string): any
			return services[name] or standin()
		end,
	}
	env.Enum = setmetatable({}, {
		__index = function(_: any, group: string): any
			return setmetatable({}, {
				__index = function(_: any, item: string): string
					return `{group}.{item}`
				end,
			})
		end,
	})
	env.task = {
		spawn = spawn,
		defer = spawn,
		delay = function() end,
		wait = function()
			return 0
		end,
	}
	env.os = {
		time = function(): number
			return w.now
		end,
		clock = function(): number
			return w.now
		end,
	}
	env.warn = function() end
	env.require = function(spec: string): any
		if spec == "@game/ServerStorage/Arcade/Boards" then
			return arcadeBoards
		end
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
		return standin()
	end
	arcadeBoards = luau.load(ARCADE, { debugName = "Boards", environment = env })()
	w.arcade = arcadeBoards
	w.Relay = luau.load(RELAY, { debugName = "BoardRelay", environment = env })()
	w.Relay.start()

	function w.join(userId: number): any
		local p = { UserId = userId, Name = `p{userId}`, Parent = {} }
		table.insert(w.players, p)
		return p
	end
	-- a finished run, written through the arcade's own submit
	function w.run(title: string, userId: number, score: number, level: number, revives: number)
		local handle = arcadeBoards.open(HiscoreGames[title].prefix)
		handle.submit(tostring(userId), `p{userId}`, score, level, revives, 1)
	end
	function w.ask(p: any, title: string, id: string): any?
		local before = #w.fired
		remote.OnServerEvent.fire(p, title, id)
		local last = nil
		for i = before + 1, #w.fired do
			last = w.fired[i]
		end
		return last
	end
	return w
end

-- every title gets a few runs, written before the asks begin; the read counts then start from zero
local function seeded(): any
	local w = world()
	for _, e in Games.LIST do
		for i = 1, 4 do
			w.run(e.name, 100 + i, 1000 * i, i, i - 1)
		end
	end
	w.reads.get, w.reads.sorted = 0, 0
	w.sortedBy = {}
	return w
end

local function flood(w: any, players: number, seconds: number): { [any]: any }
	local ps = {}
	for i = 1, players do
		table.insert(ps, w.join(i))
	end
	local last: { [any]: any } = {}
	for _ = 1, seconds do
		for _, p in ps do
			for _, e in Games.LIST do
				for _, id in Board.TABS do
					local got = w.ask(p, e.name, id)
					if got ~= nil then
						last[`{p.UserId}|{e.name}|{id}`] = got
					end
				end
			end
		end
		w.now += 1
	end
	return last
end

-- the screen of one player, as BoardsView asks: every card's board on its tab (and a card's all-time board while its
-- best is unknown), each again after REASK, or WAIT_RETRY after a wait or a pending best
type Screen = {
	p: any,
	tab: string,
	asked: { [string]: Board.Asked },
	mine: { [string]: Board.Mine },
	seen: { [string]: number }, -- "<title>|<id>" -> when its first answer that was not a wait came
	knownAt: { [string]: number }, -- title -> when the player's own best on it was first known
	answers: { Board.Answer },
}
local NAMES: { [string]: boolean } = {}
local ORDER: { string } = {}
for _, e in Games.LIST do
	NAMES[e.name] = true
	table.insert(ORDER, e.name)
end

local function screen(w: any, userId: number): Screen
	return { p = w.join(userId), tab = "all", asked = {}, mine = {}, seen = {}, knownAt = {}, answers = {} }
end

local function tick(w: any, s: Screen)
	for _, want in Board.wants(s.tab, ORDER, s.mine) do
		local key = `{want.name}|{want.id}`
		if Board.askDue(s.asked[key], w.now) then
			s.asked[key] = { at = w.now, wait = false }
			local before = #w.fired
			w.remote.OnServerEvent.fire(s.p, want.name, want.id)
			for i = before + 1, #w.fired do
				local f = w.fired[i]
				if f[1] == s.p then
					local a = Board.parse(NAMES, table.unpack(f, 2, f.n))
					if a ~= nil then
						table.insert(s.answers, a)
						s.mine[a.name] = Board.learn(s.mine[a.name], a)
						if s.mine[a.name].known and s.knownAt[a.name] == nil then
							s.knownAt[a.name] = w.now
						end
						local k = `{a.name}|{a.id}`
						if s.asked[k] ~= nil then
							s.asked[k].wait = a.status == "wait" or a.pending
						end
						if a.status ~= "wait" and s.seen[k] == nil then
							s.seen[k] = w.now
						end
					end
				end
			end
		end
	end
end

local function noRepeatInsideRefresh(w: any)
	for key, times in w.sortedBy do
		for i = 2, #times do
			if times[i] - times[i - 1] < Board.REFRESH then
				error(`{key} read at {times[i - 1] - START} and {times[i] - START}`)
			end
		end
	end
end

return t.spec("f0206 budget", function(it)
	for _, n in { 1, 4, 20 } do
		it(
			`{n} player(s) asking every board every second for five minutes stay inside the read budgets`,
			function()
				local w = seeded()
				flood(w, n, 300)
				t.expect(#w.errors).toBe(0)
				-- sorted reads: the allowance, below the engine's 5 + 2 a player a minute
				t.expect(w.reads.sorted <= Board.BURST + math.max(Board.RATE * n, Board.FLOOR) * 5 + 1e-9)
					.toBe(true)
				t.expect(w.reads.sorted <= (5 + 2 * n) * 5).toBe(true)
				t.expect(w.reads.sorted > 0).toBe(true)
				-- and the allowance grows with the players: a busy server reads its boards more often than FLOOR allows
				if Board.RATE * n >= 4 * Board.FLOOR then
					t.expect(w.reads.sorted > Board.BURST + Board.FLOOR * 5).toBe(true)
				end
				-- standard reads: inside 60 + 40 a player a minute, leaving the wallet's four a minute per player (f0205)
				t.expect(w.reads.get <= (60 + 36 * n) * 5).toBe(true)
				-- no board's sorted page is read twice inside REFRESH
				for key, times in w.sortedBy do
					for i = 2, #times do
						if times[i] - times[i - 1] < Board.REFRESH then
							error(`{key} read at {times[i - 1] - START} and {times[i] - START}`)
						end
					end
				end
			end
		)
	end

	it("every player is still answered with the stored rows and their revives", function()
		local w = seeded()
		local last = flood(w, 4, 120)
		for userId = 1, 4 do
			for _, e in Games.LIST do
				local got = last[`{userId}|{e.name}|all`]
				t.expect(got ~= nil).toBe(true)
				t.expect(got[2]).toBe(e.name)
				t.expect(got[6]).toBe("ok")
				t.expect(#got[4]).toBe(4)
				t.expect(got[4][1].score).toBe(4000)
				t.expect(got[4][1].revives).toBe(3)
			end
		end
	end)

	for _, n in { 1, 2 } do
		it(
			`{n} player(s) choosing each tab in turn see every card's board the first time they choose it`,
			function()
				local w = seeded()
				local screens = {}
				for i = 1, n do
					table.insert(screens, screen(w, i))
				end
				-- ALL-TIME at the screen's open, TODAY five seconds later, THIS WEEK five more, then back
				local plan = { [0] = "all", [5] = "day", [10] = "week", [40] = "all", [70] = "day" }
				local chosen: { [string]: number } = {}
				for s = 0, 120 do
					local tab = plan[s]
					if tab ~= nil then
						for _, sc in screens do
							sc.tab = tab
						end
						if chosen[tab] == nil then
							chosen[tab] = w.now
						end
					end
					for _, sc in screens do
						tick(w, sc)
					end
					w.now += 1
				end
				t.expect(#w.errors).toBe(0)
				for _, sc in screens do
					for tab, at in chosen do
						for _, name in ORDER do
							local seen = sc.seen[`{name}|{tab}`]
							local label = `{name} {tab}`
							t.expect(seen ~= nil and label).toBe(label)
							t.expect((seen :: number) - at <= Board.WAIT_RETRY and label).toBe(label)
						end
					end
				end
				-- both budgets, over these two minutes
				t.expect(w.reads.sorted <= Board.BURST + math.max(Board.RATE * n, Board.FLOOR) * 2 + 1e-9)
					.toBe(true)
				t.expect(w.reads.sorted <= (5 + 2 * n) * 2 + Board.BURST).toBe(true)
				t.expect(w.reads.get <= (60 + 36 * n) * 2).toBe(true)
				noRepeatInsideRefresh(w)
			end
		)
	end

	it(
		"players arriving at every phase of the cache's cycle each see their own best within REFRESH + WAIT_RETRY",
		function()
			local w = seeded()
			-- each player has a run on every title, at a score of their own
			for userId = 1, 8 do
				for _, e in Games.LIST do
					w.run(e.name, userId, 50 + userId, 1, userId % 3)
				end
			end
			w.reads.get, w.reads.sorted = 0, 0
			w.sortedBy = {}
			local screens: { Screen } = {}
			local joined: { [any]: number } = {}
			for s = 0, 240 do
				-- a player joins every 4 s for 32 s: every phase of a 30 s refresh cycle
				if s % 4 == 0 and #screens < 8 then
					local sc = screen(w, #screens + 1)
					table.insert(screens, sc)
					joined[sc] = w.now
				end
				for _, sc in screens do
					tick(w, sc)
				end
				w.now += 1
			end
			t.expect(#w.errors).toBe(0)
			for i, sc in screens do
				for _, name in ORDER do
					for _, a in sc.answers do
						if a.name == name and a.status ~= "wait" then
							-- never "no best": the player has a run on every title
							t.expect(a.pending or a.best ~= nil).toBe(true)
							if a.best ~= nil then
								t.expect((a.best :: Board.Best).score).toBe(50 + i)
							end
						end
					end
					local at = sc.knownAt[name]
					local label = `player {i} {name}`
					t.expect(at ~= nil and label).toBe(label)
					t.expect((at :: number) - joined[sc] <= Board.REFRESH + Board.WAIT_RETRY and label)
						.toBe(label)
				end
			end
			noRepeatInsideRefresh(w)
		end
	)

	it("a player keeping one board in front sees a new run on it within two REFRESH periods", function()
		local w = seeded()
		local p = w.join(1)
		local seen: number? = nil
		local wrote = START + 300
		while w.now < START + 600 do
			if w.now == wrote then
				w.run("snake", 999, 50000, 9, 2)
			end
			if (w.now - START) % Board.REASK == 0 then
				local got = w.ask(p, "snake", "day")
				if seen == nil and w.now >= wrote and got ~= nil then
					for _, r in got[4] do
						if r.score == 50000 then
							seen = w.now
						end
					end
				end
			end
			w.now += 1
		end
		t.expect(seen ~= nil).toBe(true)
		t.expect((seen :: number) - wrote <= 2 * Board.REFRESH).toBe(true)
	end)
end)
