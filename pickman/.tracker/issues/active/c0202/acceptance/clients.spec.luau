--!strict
-- c0202 AC5: what the player sees is as it was, on the library's words and screen. The lobby's line under START GAME
-- (Lobby.payLine) and the price of a play (Lobby.salePrice) read the library's Prices table, which the adapter passes
-- in, and say exactly what f0186 had them say; Lobby keeps no price table of its own. OfferView (from its real source,
-- on a stub client) reads what the player holds from the library's status (`revives`), boots the library's test
-- screen, keeps its keys (Return, KeypadEnter, ButtonA ask; Backspace, ButtonB decline; passed on outside the offer)
-- and does nothing on a tap of its buttons while the library's screen is open over them. PayView draws the line from
-- the library's status and Prices, as rich text, and boots the library's screen.
local Flow = require("@logic/Flow")
local Lobby = require("@logic/Lobby")
local PaidPlay = require("@arcade/Logic/PaidPlay")
local Prices = require("@arcade/Prices")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()
local lobbyPlace = place.load("lobby.project.json")

local NOW = 1792108800
local SALE = "<s>5 R$</s> 1 R$ SALE"

local function sourceAt(root: any, path: { string }): string
	local node = root
	for _, part in path do
		node = node and node:FindFirstChild(part)
	end
	assert(node, `no {table.concat(path, ".")}`)
	return node.Source
end

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
					local v = { Name = item, group = group }
					rawset(gs, item, v)
					return v
				end,
			})
			rawset(self, group, g)
			return g
		end,
	})
end

local function instance(class: string): any
	local children: { any } = {}
	local self: any = { ClassName = class, Activated = signal(), children = children }
	setmetatable(self, {
		__newindex = function(tbl: any, key: string, value: any)
			if key == "Parent" and value ~= nil then
				table.insert(value.children, tbl)
			end
			rawset(tbl, key, value)
		end,
	})
	return self
end

local function find(root: any, name: string): any
	for _, c in root.children do
		if c.Name == name then
			return c
		end
		local deeper = find(c, name)
		if deeper then
			return deeper
		end
	end
	return nil
end

-- a client: OfferView or PayView from its source, the library's TestPurchase a fake whose openness the case sets
local function client(root: any, path: { string }): any
	local enum = enumProxy()
	local w: any = { sent = {}, bound = {}, open = false, started = 0, enum = enum }
	local remotes: { [string]: any } = {}
	for _, name in { "Continue", "PayStatus" } do
		remotes[name] = {
			OnClientEvent = signal(),
			FireServer = function(_: any, ...: any)
				table.insert(w.sent, { remote = name, args = { ... } })
			end,
		}
	end
	local playerGui = instance("PlayerGui")
	w.gui = playerGui
	w.remote = function(name: string): any
		return remotes[name]
	end
	w.key = function(name: string, state: string): { any }
		local out = {}
		for _, b in w.bound do
			if table.find(b.codes, name) then
				table.insert(out, b.fn("action", enum.UserInputState[state], { KeyCode = { Name = name } }))
			end
		end
		return out
	end
	local fakeScreen = {
		start = function()
			w.started += 1
		end,
		isOpen = function(): boolean
			return w.open
		end,
	}
	local services: { [string]: any } = {
		ContextActionService = {
			BindAction = function(_: any, _name: string, fn: any, _touch: boolean, ...: any)
				local codes = {}
				for _, c in { ... } do
					table.insert(codes, c.Name)
				end
				table.insert(w.bound, { fn = fn, codes = codes })
			end,
		},
		Players = {
			LocalPlayer = {
				WaitForChild = function(_: any, _n: string): any
					return playerGui
				end,
			},
		},
		ReplicatedStorage = {
			WaitForChild = function(_: any, _n: string): any
				return {
					WaitForChild = function(_: any, name: string): any
						return assert(remotes[name], name)
					end,
				}
			end,
		},
	}
	local env: { [string]: any } = {}
	env.game = {
		GetService = function(_: any, name: string): any
			return assert(services[name], name)
		end,
	}
	env.Enum = enum
	env.Instance = { new = instance }
	env.UDim2 = {
		fromScale = function(x: number, y: number): any
			return { x = x, y = y }
		end,
		new = function(...: any): any
			return { ... }
		end,
	}
	env.Vector2 = {
		new = function(x: number, y: number): any
			return { x = x, y = y }
		end,
	}
	env.Color3 = {
		fromRGB = function(r: number, g: number, b: number): any
			return { r = r, g = g, b = b }
		end,
	}
	env.os = {
		time = function(): number
			return NOW
		end,
	}
	env.task = {
		spawn = function(fn: () -> ())
			local co = coroutine.create(fn)
			local ok, err = coroutine.resume(co)
			assert(ok, err)
		end,
		wait = function(): number
			return coroutine.yield()
		end,
	}
	env.require = function(spec: string): any
		if spec == "@game/ReplicatedStorage/Arcade/TestPurchase" then
			return fakeScreen
		elseif spec == "@game/ReplicatedStorage/Arcade/Prices" then
			return Prices
		end
		local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
		return (require :: any)("@logic/" .. assert(name, `stub: no module for {spec}`))
	end
	local view = luau.load(sourceAt(root, path), { environment = env, debugName = path[#path] })() :: any
	view.start()
	w.view = view
	return w
end

local function offerView(): any
	return client(gamePlace, { "StarterPlayer", "StarterPlayerScripts", "Client", "OfferView" })
end

local function continues(w: any): { any }
	local out = {}
	for _, s in w.sent do
		if s.remote == "Continue" then
			table.insert(out, s.args[1])
		end
	end
	return out
end

local OFFER = { offer = true, fade = 0, flash = false, tap = false, cursor = true }
local PLAY = { fade = 0, flash = false, tap = false, cursor = false }

local function status(free: boolean, plays: number, revives: number, nextFree: number?): PaidPlay.Status
	return { free = free, plays = plays, revives = revives, nextFree = nextFree }
end

return t.spec("c0202 the screens on the arcade's words and test screen", function(it)
	it("the price of a play is the library's Prices as rich text, and Lobby keeps no price table", function()
		t.expect(Lobby.salePrice(Prices)).toBe(SALE)
		t.expect(Lobby.salePrice({ struck = "9 R$", price = "2 R$", sale = "NOW" }))
			.toBe("<s>9 R$</s> 2 R$ NOW")
		t.expect((Lobby :: any).PRICE).toBe(nil)
	end)

	it("the lobby's line from the library's status says what it said before", function()
		local function line(s: PaidPlay.Status?, mode: string?): string?
			return Lobby.payLine(s, mode, NOW, Prices)
		end
		t.expect(line(nil, "live")).toBe(nil)
		t.expect(line(status(true, 2, 0), "live")).toBe("FREE GAME")
		t.expect(line(status(false, 1, 3), "live")).toBe("1 GAME YOU BOUGHT")
		t.expect(line(status(false, 2, 0), "live")).toBe("2 GAMES YOU BOUGHT")
		t.expect(line(status(false, 0, 1, NOW + 41 * 60 + 5), "live"))
			.toBe(`A GAME: {SALE}, NEXT FREE GAME IN 42 MIN`)
		t.expect(line(status(false, 0, 0), "test")).toBe(`A GAME: {SALE} (TEST: NOTHING IS CHARGED)`)
		t.expect(line(status(false, 0, 0), nil)).toBe(`A GAME: {SALE} (TEST: NOTHING IS CHARGED)`)
		t.expect(line(status(false, 0, 0, NOW + 60), "closed"))
			.toBe("STORE UNAVAILABLE, NEXT FREE GAME IN 1 MIN")
		t.expect(line(status(true, 0, 0), "test")).toBe("FREE GAME (TEST: NOTHING IS CHARGED)")
		-- the line for the library's own status of a record
		local r = PaidPlay.record({ free = NOW - 60, plays = 0, continues = 0, receipts = {} })
		t.expect(line(PaidPlay.status(r, NOW), "live")).toBe(`A GAME: {SALE}, NEXT FREE GAME IN 59 MIN`)
	end)

	it("the offer's price line reads the revives held from the library's status", function()
		local w = offerView()
		local price = find(w.gui, "Price")
		w.view.show(OFFER)
		w.remote("PayStatus").OnClientEvent.fire("live", status(false, 0, 1))
		w.view.show(OFFER)
		t.expect(price.Text).toBe(Flow.offerPrice({ mode = "live", held = 1 }))
		t.expect(price.Text).toBe(Flow.OFFER.held)
		w.remote("PayStatus").OnClientEvent.fire("test", status(false, 3, 0))
		w.view.show(OFFER)
		t.expect(price.Text).toBe(Flow.OFFER.test)
		w.remote("PayStatus").OnClientEvent.fire("live", { free = false, plays = 0, continues = 2 }) -- not the library's
		w.view.show(OFFER)
		t.expect(price.Text).toBe(Flow.OFFER.price)
	end)

	it("OfferView boots the library's test screen, once", function()
		local w = offerView()
		t.expect(w.started).toBe(1)
	end)

	it("the offer's keys ask and decline on the press during the offer, and pass on outside it", function()
		local w = offerView()
		w.view.show(OFFER)
		for _, name in Flow.OFFER_KEYS.ask do
			local r = w.key(name, "Begin")
			t.expect(r[1]).toBe(w.enum.ContextActionResult.Sink)
			w.key(name, "End")
		end
		for _, name in Flow.OFFER_KEYS.decline do
			w.key(name, "Begin")
		end
		t.expect(continues(w)).toEqual({ "ask", "ask", "ask", "decline", "decline" })
		w.view.show(PLAY)
		for _, name in { "Return", "ButtonA", "Backspace", "ButtonB" } do
			t.expect(w.key(name, "Begin")[1]).toBe(w.enum.ContextActionResult.Pass)
		end
		t.expect(#continues(w)).toBe(5)
	end)

	it(
		"CONTINUE and END GAME send ask and decline, and do nothing while the library's screen is open",
		function()
			local w = offerView()
			w.view.show(OFFER)
			w.open = true
			find(w.gui, "Continue").Activated.fire()
			find(w.gui, "Decline").Activated.fire()
			t.expect(#continues(w)).toBe(0)
			w.open = false
			find(w.gui, "Continue").Activated.fire()
			find(w.gui, "Decline").Activated.fire()
			t.expect(continues(w)).toEqual({ "ask", "decline" })
			w.view.show(PLAY)
			find(w.gui, "Continue").Activated.fire()
			t.expect(#continues(w)).toBe(2)
		end
	)

	it(
		"PayView draws the line from the library's status and Prices, as rich text, and boots the library's screen",
		function()
			local w = client(lobbyPlace, { "StarterPlayer", "StarterPlayerScripts", "Lobby", "PayView" })
			t.expect(w.started).toBe(1)
			local label = find(find(w.gui, "PayLine"), "PayLine") -- the line inside its screen of the same name
			t.expect(label.ClassName).toBe("TextLabel")
			t.expect(label.RichText).toBe(true)
			w.remote("PayStatus").OnClientEvent.fire("live", status(false, 0, 0, NOW + 30 * 60))
			t.expect(label.Text).toBe(`A GAME: {SALE}, NEXT FREE GAME IN 30 MIN`)
			w.remote("PayStatus").OnClientEvent.fire("live", status(true, 0, 0))
			t.expect(label.Text).toBe("FREE GAME")
		end
	)
end)
