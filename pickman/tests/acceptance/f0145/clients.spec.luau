--!strict
-- f0145 AC5 (every input; the user's rule, 2026-10-25: "We support keyboard, cosole, and touch for every feature"):
-- the offer and the test purchase screen take keys and controller buttons as well as taps. OfferView and TestPurchase
-- run from their real sources on a stub engine. While the offer is up (Flow's overlay says so), Return, KeypadEnter
-- or ButtonA ask for a continue and Backspace or ButtonB decline, on the key going down, and the key is sunk; at any
-- other time the keys pass on untouched (so FlowView's Return still returns to the lobby at the game over). The
-- CONTINUE and END GAME buttons show only during the offer and send the same answers. The test purchase screen,
-- opened by the server, takes BUY and CANCEL from the same keys while it is open, and passes them on otherwise.
local Flow = require("@logic/Flow")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()

local function sourceAt(path: { string }): string
	local node: any = gamePlace
	for _, part in path do
		node = node and node:FindFirstChild(part)
	end
	assert(node, `no {table.concat(path, ".")}`)
	return node.Source
end

local OFFER_VIEW = sourceAt({ "StarterPlayer", "StarterPlayerScripts", "Client", "OfferView" })
local TEST_PURCHASE = sourceAt({ "ReplicatedStorage", "Shared", "TestPurchase" })

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

-- a stub instance: plain fields, children by Name, an Activated signal for buttons
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

type World = {
	enum: any,
	sent: { { remote: string, args: { any } } },
	key: (name: string, state: string) -> { any },
	gui: any,
	remote: (name: string) -> any,
	env: { [string]: any },
}

local function world(): World
	local enum = enumProxy()
	local sent: { { remote: string, args: { any } } } = {}
	local bound: { { fn: any, codes: { string } } } = {}
	local remotes: { [string]: any } = {}
	for _, name in { "Continue", "PayStatus", "Purchase" } do
		remotes[name] = {
			OnClientEvent = signal(),
			FireServer = function(_: any, ...: any)
				table.insert(sent, { remote = name, args = { ... } })
			end,
		}
	end
	local playerGui = instance("PlayerGui")
	local w: World
	w = {
		enum = enum,
		sent = sent,
		gui = playerGui,
		remote = function(name: string): any
			return remotes[name]
		end,
		key = function(name: string, state: string): { any }
			local out = {}
			for _, b in bound do
				if table.find(b.codes, name) then
					table.insert(
						out,
						b.fn("action", enum.UserInputState[state], { KeyCode = { Name = name } })
					)
				end
			end
			return out
		end,
		env = {},
	}
	local services: { [string]: any } = {
		ContextActionService = {
			BindAction = function(_: any, _name: string, fn: any, _touch: boolean, ...: any)
				local codes = {}
				for _, c in { ... } do
					table.insert(codes, c.Name)
				end
				table.insert(bound, { fn = fn, codes = codes })
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
	local loaded: { [string]: any } = {}
	w.env = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], name)
			end,
		},
		Enum = enum,
		Instance = { new = instance },
		UDim2 = {
			fromScale = function(x: number, y: number): any
				return { x = x, y = y }
			end,
			new = function(...: any): any
				return { ... }
			end,
		},
		Vector2 = {
			new = function(x: number, y: number): any
				return { x = x, y = y }
			end,
		},
		Color3 = {
			fromRGB = function(r: number, g: number, b: number): any
				return { r = r, g = g, b = b }
			end,
			new = function(r: number, g: number, b: number): any
				return { r = r, g = g, b = b }
			end,
		},
		task = {
			spawn = function(fn: () -> ())
				fn()
			end,
		},
		require = function(spec: string): any
			if spec == "@game/ReplicatedStorage/Shared/TestPurchase" then
				if loaded.TestPurchase == nil then
					loaded.TestPurchase =
						luau.load(TEST_PURCHASE, { environment = w.env, debugName = "TestPurchase" })()
				end
				return loaded.TestPurchase
			end
			local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
			return (require :: any)("@logic/" .. assert(name, spec))
		end,
	}
	return w
end

local function offerView(): (World, any)
	local w = world()
	local view = luau.load(OFFER_VIEW, { environment = w.env, debugName = "OfferView" })() :: any
	view.start()
	return w, view
end

local function continues(w: World): { any }
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

return t.spec("f0145 the offer and the test screen by key, button and tap", function(it)
	it(
		"while the offer is up, Return, KeypadEnter and ButtonA ask, Backspace and ButtonB decline, on the press",
		function()
			local w, view = offerView()
			view.show(OFFER)
			for _, name in Flow.OFFER_KEYS.ask do
				local before = #continues(w)
				local r = w.key(name, "Begin")
				t.expect(r[1]).toBe(w.enum.ContextActionResult.Sink)
				t.expect(continues(w)[before + 1]).toBe("ask")
				w.key(name, "End")
				t.expect(#continues(w)).toBe(before + 1) -- nothing on the release
			end
			for _, name in Flow.OFFER_KEYS.decline do
				local before = #continues(w)
				w.key(name, "Begin")
				t.expect(continues(w)[before + 1]).toBe("decline")
			end
		end
	)

	it("outside the offer the keys pass on and send nothing", function()
		local w, view = offerView()
		view.show(PLAY)
		for _, name in { "Return", "ButtonA", "Backspace", "ButtonB" } do
			local r = w.key(name, "Begin")
			t.expect(r[1]).toBe(w.enum.ContextActionResult.Pass)
		end
		t.expect(#continues(w)).toBe(0)
	end)

	it("CONTINUE and END GAME show only during the offer and send ask and decline", function()
		local w, view = offerView()
		local buttons = find(w.gui, "Buttons")
		view.show(PLAY)
		t.expect(buttons.Visible).toBe(false)
		view.show(OFFER)
		t.expect(buttons.Visible).toBe(true)
		find(w.gui, "Continue").Activated.fire()
		find(w.gui, "Decline").Activated.fire()
		t.expect(continues(w)).toEqual({ "ask", "decline" })
	end)

	it(
		"the test screen, opened by the server, buys on Return or ButtonA and cancels on Backspace or ButtonB",
		function()
			local w = offerView()
			local purchase = w.remote("Purchase")
			local function answers(): { any }
				local out = {}
				for _, s in w.sent do
					if s.remote == "Purchase" then
						table.insert(out, s.args[1])
					end
				end
				return out
			end
			t.expect(w.key("Return", "Begin")[2]).toBe(w.enum.ContextActionResult.Pass) -- closed: passes on
			purchase.OnClientEvent.fire("continue")
			t.expect(w.key("ButtonA", "Begin")[2]).toBe(w.enum.ContextActionResult.Sink)
			t.expect(answers()).toEqual({ "confirm" })
			t.expect(w.key("Return", "Begin")[2]).toBe(w.enum.ContextActionResult.Pass) -- closed again
			purchase.OnClientEvent.fire("play")
			w.key("Backspace", "Begin")
			t.expect(answers()).toEqual({ "confirm", "cancel" })
			purchase.OnClientEvent.fire("continue")
			find(w.gui, "BUY").Activated.fire()
			t.expect(answers()).toEqual({ "confirm", "cancel", "confirm" })
		end
	)
end)
