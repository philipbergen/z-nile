--!strict
-- f0205 AC4: the portal's server adapter (ServerScriptService.Server.Cards), run from its real source on a stub
-- server. It reads which games are published once, from the place-id attributes through the arcade's Places; on a
-- player's ask it answers that player at once (published, and the free state it knows), then reads each published
-- game's record through the arcade's Wallet (never an unpublished one, never twice at once) and answers again as each
-- read comes back, with PaidPlay's status at os.time(): free when due, the sale when not due or when the read failed.
-- What the client sends is ignored, no place id leaves the server, and a player who left hears nothing more.
local Card = require("@logic/Card")
local Games = require("@shared/Games")
local PaidPlay = require("@arcade/Logic/PaidPlay")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local SOURCE = (built :: any)
	:GetService("ServerScriptService")
	:FindFirstChild("Server")
	:FindFirstChild("Cards").Source

local NOW = 1000000 -- the stub's os.time()

type Signal = { Connect: (any, (...any) -> ()) -> any, fire: (...any) -> () }

-- a stand-in that accepts any use: every field is a callable stand-in too (an adapter's later additions keep working)
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

local function world(attributes: { [string]: any }): any
	local w: any = { sent = {}, reads = {}, errors = {}, players = {}, timers = {}, clock = 5 }

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
		}
	end

	local remote: any = { OnServerEvent = signal(), Name = "Cards", ClassName = "RemoteEvent" }
	remote.FireClient = function(_: any, player: any, ...: any)
		table.insert(w.sent, { player = player, args = table.pack(...) })
	end
	remote.FireAllClients = function()
		table.insert(w.errors, "FireAllClients: every answer is one player's")
	end
	w.remote = remote
	local remotes: any = {
		Name = "Remotes",
		WaitForChild = function(_: any, name: string): any
			assert(name == "Cards", name)
			return remote
		end,
		FindFirstChild = function(_: any, name: string): any
			return if name == "Cards" then remote else nil
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
				return attributes[name]
			end,
		},
	}

	local wallet: any = standin()
	-- the Wallet's bounds as this stub gives them: numbers no other module holds, so the waits must come from here
	wallet.WAIT_SECONDS = 7
	wallet.RETRY_SECONDS = 11
	wallet.READ_SECONDS = 50
	wallet.read = function(player: any, name: string): (any, any)
		table.insert(w.reads, { player = player, name = name, co = coroutine.running(), done = false })
		return coroutine.yield()
	end
	w.wallet = wallet

	local env: { [string]: any } = {}
	env.game = {
		GetService = function(_: any, name: string): any
			return services[name] or standin()
		end,
	}
	env.task = {
		spawn = spawn,
		defer = spawn,
		delay = function(seconds: number, fn: (...any) -> (), ...: any)
			table.insert(
				w.timers,
				{ at = w.clock + seconds, fn = fn, args = table.pack(...), wait = seconds }
			)
		end,
		wait = function()
			return 0
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
		end
		return standin() -- another server module or a sibling adapter a later issue adds
	end

	local Cards = luau.load(SOURCE, { debugName = "Cards", environment = env })()
	w.Cards = Cards

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
	function w.ask(p: any, ...: any)
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
	-- the waits of the timers set and not yet run, in the order set
	function w.pending(): { number }
		local out = {}
		for _, tm in w.timers do
			if not tm.ran then
				table.insert(out, tm.wait)
			end
		end
		return out
	end
	-- moves the stub's clock on by `seconds`, running every timer that comes due, in the order they come due
	function w.advance(seconds: number)
		local stop = w.clock + seconds
		while true do
			local due: any = nil
			for _, tm in w.timers do
				if not tm.ran and tm.at <= stop and (due == nil or tm.at < due.at) then
					due = tm
				end
			end
			if due == nil then
				break
			end
			due.ran = true
			w.clock = due.at
			spawn(due.fn, table.unpack(due.args, 1, due.args.n))
		end
		w.clock = stop
	end
	function w.readsOf(p: any): { string }
		local out = {}
		for _, r in w.reads do
			if r.player == p then
				table.insert(out, r.name)
			end
		end
		return out
	end
	function w.sentTo(p: any): { any }
		local out = {}
		for _, s in w.sent do
			if s.player == p then
				table.insert(out, s.args[1])
			end
		end
		return out
	end
	-- the last answer `p` got, and the first: each must be there (a missing one fails on an assertion)
	function w.last(p: any): any
		local all = w.sentTo(p)
		t.expect(#all > 0).toBe(true)
		return all[#all]
	end
	function w.first(p: any): any
		local all = w.sentTo(p)
		t.expect(#all > 0).toBe(true)
		return all[1]
	end
	return w
end

local ALL = { PickmanPlaceId = 101, SnakePlaceId = 102, InvadersPlaceId = 103, AsteroidsPlaceId = 104 }

local function started(attributes: { [string]: any }?): any
	local w = world(attributes or ALL)
	w.Cards.start()
	return w
end

local function fresh(): any
	return PaidPlay.record(nil) -- a player who never played: a free start is due
end

local function playedAt(instant: number): any
	return PaidPlay.record({ free = instant, plays = 0, continues = 0, receipts = {} })
end

return t.spec("f0205 server", function(it)
	it("an ask is answered at once, to that player, before any read comes back", function()
		local w = started()
		local p = w.join("p", 1)
		w.ask(p)
		local first = w.first(p)
		t.expect(first ~= nil).toBe(true)
		for _, e in Games.LIST do
			t.expect(first[e.name].published).toBe(true)
			t.expect(first[e.name].free).toBe(nil)
		end
		t.expect(#w.errors).toBe(0)
	end)

	it("which games are published comes from the place-id attributes, read through Places", function()
		local w = started({
			PickmanPlaceId = 101,
			SnakePlaceId = 0,
			InvadersPlaceId = "203",
			AsteroidsPlaceId = 1.5,
		})
		local p = w.join("p", 1)
		w.ask(p)
		local s = Card.parse(w.first(p), Games.LIST)
		t.expect(s.pickman.published).toBe(true)
		t.expect(s.snake.published).toBe(false)
		t.expect(s.invaders.published).toBe(true)
		t.expect(s.asteroids.published).toBe(false)
	end)

	it("with no place-id attribute at all, every card is coming soon and nothing is read", function()
		local w = started({})
		local p = w.join("p", 1)
		w.ask(p)
		local s = w.first(p)
		for _, e in Games.LIST do
			t.expect(s[e.name].published).toBe(false)
		end
		t.expect(#w.reads).toBe(0)
	end)

	it("the attributes are read once, at start: a later change does not count", function()
		local attrs = { PickmanPlaceId = 101 }
		local w = started(attrs)
		attrs.SnakePlaceId = 102 :: any
		local p = w.join("p", 1)
		w.ask(p)
		t.expect(w.first(p).snake.published).toBe(false)
	end)

	it(
		"an ask reads each published game's record through the Wallet, by player and name, and no other",
		function()
			local w = started({ PickmanPlaceId = 101, InvadersPlaceId = 103 })
			local p = w.join("p", 1)
			w.ask(p)
			t.expect(table.concat(w.readsOf(p), " ")).toBe("pickman invaders")
			for _, r in w.reads do
				t.expect(r.player).toBe(p)
			end
		end
	)

	it("a record whose free start is due shows FREE GAME READY when its read comes back", function()
		local w = started()
		local p = w.join("p", 1)
		w.ask(p)
		w.answer(p, "snake", fresh())
		local s = w.last(p)
		t.expect(s.snake.free).toBe(true)
		t.expect(s.pickman.free).toBe(nil)
		t.expect(
			Card.badge(Card.parse(s, Games.LIST).snake, { struck = "a", price = "b", sale = "c" }, Card.WORDS).kind
		).toBe("free")
	end)

	it("each read is answered as it comes back: one more answer per read", function()
		local w = started()
		local p = w.join("p", 1)
		w.ask(p)
		t.expect(#w.sentTo(p)).toBe(1)
		w.answer(p, "invaders", fresh())
		t.expect(#w.sentTo(p)).toBe(2)
		w.answer(p, "pickman", playedAt(NOW - 10))
		t.expect(#w.sentTo(p)).toBe(3)
		local s = w.last(p)
		t.expect(s.invaders.free).toBe(true)
		t.expect(s.pickman.free).toBe(false)
		t.expect(s.snake.free).toBe(nil)
	end)

	it(
		"the free state is PaidPlay's status at os.time(): due a full hour after the last free start",
		function()
			local w = started()
			local p = w.join("p", 1)
			w.ask(p)
			w.answer(p, "pickman", playedAt(NOW - PaidPlay.FREE_SECONDS))
			w.answer(p, "snake", playedAt(NOW - PaidPlay.FREE_SECONDS + 1))
			local s = w.last(p)
			t.expect(s.pickman.free).toBe(true)
			t.expect(s.snake.free).toBe(false)
		end
	)

	it("a read that failed shows the sale, never a free game", function()
		local w = started()
		local p = w.join("p", 1)
		w.ask(p)
		w.answer(p, "pickman", nil, "down")
		local s = w.last(p)
		t.expect(s.pickman.free).toBe(false)
		t.expect(#w.errors).toBe(0)
	end)

	it("a busy read (another read of the record under way) keeps what was known", function()
		local w = started({ PickmanPlaceId = 101, SnakePlaceId = 102 })
		local p = w.join("p", 1)
		w.ask(p)
		w.answer(p, "pickman", fresh())
		w.answer(p, "snake", nil, "busy") -- nothing known yet: still nothing
		t.expect(w.last(p).snake.free).toBe(nil)
		w.advance(1)
		w.ask(p)
		w.answer(p, "pickman", nil, "busy") -- known free: still free
		t.expect(w.last(p).pickman.free).toBe(true)
	end)

	it("a busy read is read again once, after the Wallet's WAIT_SECONDS, and not before", function()
		local w = started({ PickmanPlaceId = 101 })
		local p = w.join("p", 1)
		w.ask(p)
		w.answer(p, "pickman", nil, "busy")
		t.expect(table.concat(w.pending(), " ")).toBe("7")
		w.advance(6.5)
		t.expect(#w.readsOf(p)).toBe(1)
		w.advance(0.5)
		t.expect(#w.readsOf(p)).toBe(2)
		w.answer(p, "pickman", fresh())
		t.expect(w.last(p).pickman.free).toBe(true)
		t.expect(#w.pending()).toBe(0)
	end)

	it("a second busy read in a row is a failure: the sale, then the down back-off", function()
		local w = started({ PickmanPlaceId = 101 })
		local p = w.join("p", 1)
		w.ask(p)
		w.answer(p, "pickman", fresh())
		w.advance(1)
		w.ask(p)
		w.answer(p, "pickman", nil, "busy")
		w.advance(7)
		w.answer(p, "pickman", nil, "busy")
		t.expect(w.last(p).pickman.free).toBe(false)
		t.expect(table.concat(w.pending(), " ")).toBe("11")
	end)

	it(
		"a failed read is read again after RETRY_SECONDS, doubling up to READ_SECONDS, while it fails",
		function()
			local w = started({ PickmanPlaceId = 101 })
			local p = w.join("p", 1)
			w.ask(p)
			local waits = {}
			for _ = 1, 5 do
				w.answer(p, "pickman", nil, "down")
				local pend = w.pending()
				t.expect(#pend).toBe(1)
				table.insert(waits, pend[1])
				w.advance(pend[1] - 0.25)
				t.expect(#w.pending()).toBe(1) -- not before its time
				w.advance(0.25)
			end
			t.expect(table.concat(waits, " ")).toBe("11 22 44 50 50")
			w.answer(p, "pickman", fresh())
			t.expect(w.last(p).pickman.free).toBe(true)
			t.expect(#w.pending()).toBe(0)
		end
	)

	it("one retry at a time per game: an ask's read that comes back replaces the retry waiting", function()
		local w = started({ PickmanPlaceId = 101 })
		local p = w.join("p", 1)
		w.ask(p)
		w.answer(p, "pickman", nil, "down")
		w.advance(2)
		w.ask(p)
		w.answer(p, "pickman", fresh())
		w.advance(60)
		t.expect(#w.readsOf(p)).toBe(2) -- the old retry read nothing
	end)

	it("a player who leaves stops the retries, and a retry's answer goes to the asker only", function()
		local w = started({ PickmanPlaceId = 101 })
		local a, b = w.join("a", 1), w.join("b", 2)
		w.ask(a)
		w.answer(a, "pickman", nil, "down")
		w.advance(11)
		t.expect(#w.readsOf(a)).toBe(2)
		w.answer(a, "pickman", fresh())
		t.expect(#w.sentTo(b)).toBe(0)
		w.ask(b)
		w.answer(b, "pickman", nil, "down")
		w.leave(b)
		w.advance(200)
		t.expect(#w.readsOf(b)).toBe(1)
		t.expect(#w.errors).toBe(0)
	end)

	it(
		"asks closer than ASK_GAP are answered together: a burst gets one answer at once and one at its end",
		function()
			local w = started({ PickmanPlaceId = 101 })
			local p = w.join("p", 1)
			w.ask(p)
			w.answer(p, "pickman", fresh())
			local before = #w.sentTo(p)
			for _ = 1, 10 do
				w.advance(0.05)
				w.ask(p)
			end
			t.expect(#w.sentTo(p)).toBe(before)
			t.expect(#w.readsOf(p)).toBe(1)
			w.advance(1)
			t.expect(#w.sentTo(p)).toBe(before + 1)
			t.expect(#w.readsOf(p)).toBe(2)
		end
	)

	it(
		"an ask while a game's read is under way starts no second read of it, and is answered at once",
		function()
			local w = started({ PickmanPlaceId = 101, SnakePlaceId = 102 })
			local p = w.join("p", 1)
			w.ask(p)
			w.answer(p, "pickman", fresh())
			w.advance(1)
			w.ask(p)
			t.expect(table.concat(w.readsOf(p), " ")).toBe("pickman snake pickman")
			t.expect(#w.sentTo(p)).toBe(3)
			t.expect(w.last(p).pickman.free).toBe(true) -- what it knew, until the new read comes back
		end
	)

	it("an ask after the reads came back reads again, and the new answer replaces the old", function()
		local w = started({ PickmanPlaceId = 101 })
		local p = w.join("p", 1)
		w.ask(p)
		w.answer(p, "pickman", fresh())
		w.advance(1)
		w.ask(p)
		t.expect(#w.readsOf(p)).toBe(2)
		w.answer(p, "pickman", playedAt(NOW))
		t.expect(w.last(p).pickman.free).toBe(false)
	end)

	it("answers go to the player who asked, and each player has their own reads and free states", function()
		local w = started({ PickmanPlaceId = 101 })
		local a, b = w.join("a", 1), w.join("b", 2)
		w.ask(a)
		t.expect(#w.sentTo(b)).toBe(0)
		w.ask(b)
		t.expect(#w.readsOf(a)).toBe(1)
		t.expect(#w.readsOf(b)).toBe(1)
		w.answer(b, "pickman", fresh())
		w.answer(a, "pickman", playedAt(NOW))
		t.expect(w.last(b).pickman.free).toBe(true)
		t.expect(w.last(a).pickman.free).toBe(false)
		for _, s in w.sent do
			t.expect(s.player == a or s.player == b).toBe(true)
		end
	end)

	it(
		"a player who leaves while a read is under way hears nothing more, and a rejoin starts afresh",
		function()
			local w = started({ PickmanPlaceId = 101 })
			local p = w.join("p", 1)
			w.ask(p)
			w.leave(p)
			w.answer(p, "pickman", fresh())
			t.expect(#w.sentTo(p)).toBe(1)
			local again = w.join("p", 1)
			w.ask(again)
			t.expect(w.first(again).pickman.free).toBe(nil)
			t.expect(#w.readsOf(again)).toBe(1)
			t.expect(#w.errors).toBe(0)
		end
	)

	it("an ask from a player who already left reads nothing and answers nothing", function()
		local w = started()
		local p = w.join("p", 1)
		w.leave(p)
		w.ask(p)
		t.expect(#w.reads).toBe(0)
		t.expect(#w.sent).toBe(0)
	end)

	it("what the client sends with its ask is ignored", function()
		local w = started({ PickmanPlaceId = 101 })
		local p = w.join("p", 1)
		w.ask(p, { snake = { published = true, free = true } }, "snake", 999)
		local s = w.first(p)
		t.expect(s.snake.published).toBe(false)
		t.expect(s.pickman.published).toBe(true)
		t.expect(table.concat(w.readsOf(p), " ")).toBe("pickman")
	end)

	it("no place id leaves the server: nothing in any answer is an id", function()
		local w = started({ PickmanPlaceId = 70001, SnakePlaceId = 70002, InvadersPlaceId = 70003 })
		local p = w.join("p", 1)
		w.ask(p)
		w.answer(p, "pickman", fresh())
		local function scan(v: any)
			if type(v) == "table" then
				for k, x in v do
					scan(k)
					scan(x)
				end
			elseif type(v) == "number" or type(v) == "string" then
				t.expect(tostring(v) == "70001" or tostring(v) == "70002" or tostring(v) == "70003")
					.toBe(false)
			end
		end
		for _, s in w.sent do
			for i = 1, s.args.n do
				scan(s.args[i])
			end
		end
	end)

	it("start is once per server: a second start adds no second answer", function()
		local w = started({ PickmanPlaceId = 101 })
		w.Cards.start()
		local p = w.join("p", 1)
		w.ask(p)
		t.expect(#w.sentTo(p)).toBe(1)
		t.expect(#w.readsOf(p)).toBe(1)
	end)
end)
