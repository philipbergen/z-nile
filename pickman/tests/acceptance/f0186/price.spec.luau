--!strict
-- f0186 AC6: wherever pickman shows the price of a play, it shows "5 R$" struck through, on sale for "1 R$" (the
-- charge stays 1 R$: the Developer Product's price). The words are Lobby.PRICE, and Lobby.salePrice() is them as rich
-- text ("<s>5 R$</s> 1 R$ SALE"). The lobby's line under START GAME (f0145's Lobby.payLine) uses it where it showed
-- "1 ROBUX A GAME"; its free, held and closed lines are as they were. The test purchase screen (f0145's TestPurchase,
-- opened by the server for a "play") shows it as rich text; for a "continue" it shows no struck price, and the
-- continue's own price line (Flow.OFFER.price) is as it was (a guess pending the user: the capture names the price of
-- a play). The lobby's pay line is drawn as rich text (PayView).
local Flow = require("@logic/Flow")
local Lobby = require("@logic/Lobby")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local NOW = 1792108800
local SALE = "<s>5 R$</s> 1 R$ SALE"

local gamePlace = place.load()
local lobbyPlace = place.load("lobby.project.json")

local function sourceAt(root: any, path: { string }): string
	local node: any = root
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

-- every text under `root` that has `needle`, with whether its object draws rich text
local function texts(
	root: any,
	needle: string,
	out: { { text: string, rich: boolean } }?
): { { text: string, rich: boolean } }
	local found = out or {}
	for _, c in root.children do
		if type(c.Text) == "string" and string.find(c.Text, needle, 1, true) then
			table.insert(found, { text = c.Text, rich = c.RichText == true })
		end
		texts(c, needle, found)
	end
	return found
end

-- f0145's clients.spec stub world: OfferView (which boots TestPurchase) on the Continue, PayStatus and Purchase remotes
local function offerView(): (any, any)
	local OFFER_VIEW = sourceAt(gamePlace, { "StarterPlayer", "StarterPlayerScripts", "Client", "OfferView" })
	local TEST_PURCHASE = sourceAt(gamePlace, { "ReplicatedStorage", "Shared", "TestPurchase" })
	local enum = enumProxy()
	local remotes: { [string]: any } = {}
	for _, name in { "Continue", "PayStatus", "Purchase" } do
		remotes[name] = { OnClientEvent = signal(), FireServer = function() end }
	end
	local playerGui = instance("PlayerGui")
	local services: { [string]: any } = {
		ContextActionService = { BindAction = function() end },
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
	local loaded: { [string]: any } = {}
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
		new = function(r: number, g: number, b: number): any
			return { r = r, g = g, b = b }
		end,
	}
	env.task = {
		spawn = function(fn: () -> ())
			fn()
		end,
	}
	env.require = function(spec: string): any
		if spec == "@game/ReplicatedStorage/Shared/TestPurchase" then
			if loaded.TestPurchase == nil then
				loaded.TestPurchase =
					luau.load(TEST_PURCHASE, { environment = env, debugName = "TestPurchase" })()
			end
			return loaded.TestPurchase
		end
		local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
		return (require :: any)("@logic/" .. assert(name, spec))
	end
	local view = luau.load(OFFER_VIEW, { environment = env, debugName = "OfferView" })() :: any
	view.start()
	return playerGui, remotes.Purchase
end

return t.spec("f0186 the price of a play shows on sale", function(it)
	it("the price of a play: 5 R$ struck through, on sale for 1 R$", function()
		t.expect(Lobby.PRICE).toEqual({ struck = "5 R$", price = "1 R$", sale = "SALE" })
		t.expect(table.isfrozen(Lobby.PRICE)).toBe(true)
		t.expect(Lobby.salePrice()).toBe(SALE)
	end)

	it("the lobby's line shows that price wherever it showed the price of a play", function()
		t.expect(
			Lobby.payLine(
				{ free = false, nextFree = NOW + 41 * 60 + 5, plays = 0, continues = 0 },
				"live",
				NOW
			)
		)
			.toBe(`A GAME: {SALE}, NEXT FREE GAME IN 42 MIN`)
		t.expect(Lobby.payLine({ free = false, plays = 0, continues = 0 }, "live", NOW))
			.toBe(`A GAME: {SALE}`)
		t.expect(Lobby.payLine({ free = false, plays = 0, continues = 0 }, "test", NOW))
			.toBe(`A GAME: {SALE} (TEST: NOTHING IS CHARGED)`)
		t.expect(Lobby.payLine({ free = false, plays = 0, continues = 0 }, nil, NOW))
			.toBe(`A GAME: {SALE} (TEST: NOTHING IS CHARGED)`)
	end)

	it("the lobby's free, held and closed lines are as they were", function()
		t.expect(Lobby.payLine(nil, "live", NOW)).toBe(nil)
		t.expect(Lobby.payLine({ free = true, plays = 2, continues = 0 }, "live", NOW)).toBe("FREE GAME")
		t.expect(Lobby.payLine({ free = false, plays = 1, continues = 0 }, "live", NOW))
			.toBe("1 GAME YOU BOUGHT")
		t.expect(
			Lobby.payLine({ free = false, nextFree = NOW + 60, plays = 0, continues = 0 }, "closed", NOW)
		)
			.toBe("STORE UNAVAILABLE, NEXT FREE GAME IN 1 MIN")
		t.expect(Lobby.payLine({ free = true, plays = 0, continues = 0 }, "test", NOW))
			.toBe("FREE GAME (TEST: NOTHING IS CHARGED)")
	end)

	it("the continue's price is not a play's: no struck price under the offer's buttons", function()
		t.expect((string.find(Flow.OFFER.price, Lobby.PRICE.struck, 1, true))).toBe(nil)
		t.expect((string.find(Flow.OFFER.price, "<s>", 1, true))).toBe(nil)
		t.expect(Flow.offerPrice({ mode = "live", held = 0 })).toBe(Flow.OFFER.price)
	end)

	it(
		"the test purchase screen shows a play's price struck through, as rich text; a continue's stays plain",
		function()
			local gui, purchase = offerView()
			purchase.OnClientEvent.fire("play")
			local shown = texts(gui, SALE)
			t.expect(#shown >= 1).toBe(true)
			for _, s in shown do
				t.expect(s.rich).toBe(true)
			end
			local other, again = offerView()
			again.OnClientEvent.fire("continue")
			t.expect(#texts(other, Lobby.PRICE.struck)).toBe(0)
		end
	)

	it("the lobby draws its pay line as rich text", function()
		local pay = sourceAt(lobbyPlace, { "StarterPlayer", "StarterPlayerScripts", "Lobby", "PayView" })
		pay = string.gsub(pay, "%-%-[^\n]*", "")
		t.expect(string.find(pay, "RichText%s*=%s*true") ~= nil).toBe(true)
	end)
end)
