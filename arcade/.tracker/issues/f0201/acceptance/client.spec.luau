--!strict
-- f0201 AC5: the test purchase screen (ReplicatedStorage.Arcade.TestPurchase), run from its real source on a stub
-- client. The server opens it with its lines; it shows them with BUY and CANCEL, centred in the middle half of the
-- screen inside the safe insets; BUY (a tap, Return, KeypadEnter or ButtonA) sends "confirm" and CANCEL (a tap,
-- Backspace or ButtonB) sends "cancel", on the press, and closes it. Its keys are bound above the place's own only
-- while it is open, so outside it they pass on and send nothing. A malformed open shows nothing it cannot print.
local PaidPlay = require("@logic/PaidPlay")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local SOURCE = (built :: any):GetService("ReplicatedStorage"):FindFirstChild("Arcade"):FindFirstChild("TestPurchase").Source

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
					local v = setmetatable({ Name = item, group = group }, {
						__tostring = function(): string
							return `{group}.{item}`
						end,
					})
					rawset(gs, item, v)
					return v
				end,
			})
			rawset(self, group, g)
			return g
		end,
	})
end

local function node(className: string): any
	local n: any = { ClassName = className, children = {}, destroyed = false }
	if className == "TextButton" then
		n.Activated = signal()
	end
	return setmetatable(n, {
		__newindex = function(self: any, key: string, value: any)
			if key == "Parent" then
				local old = rawget(self, "_parent")
				if old then
					local i = table.find(old.children, self)
					if i then
						table.remove(old.children, i)
					end
				end
				rawset(self, "_parent", value)
				if value then
					table.insert(value.children, self)
				end
			else
				rawset(self, key, value)
			end
		end,
		__index = function(self: any, key: string): any
			if key == "Parent" then
				return rawget(self, "_parent")
			elseif key == "Destroy" then
				return function(me: any)
					me.Parent = nil
					me.destroyed = true
				end
			elseif key == "FindFirstChild" then
				return function(me: any, name: string): any
					for _, c in me.children do
						if c.Name == name then
							return c
						end
					end
					return nil
				end
			end
			return nil
		end,
	})
end

local function client(): any
	local c: any = { sent = {}, binds = {}, unbinds = 0 }
	local enum = enumProxy()
	local remote: any = { OnClientEvent = signal() }
	remote.FireServer = function(_: any, ...: any)
		table.insert(c.sent, { ... })
	end
	local folder: any = {
		WaitForChild = function(_: any, name: string): any
			assert(name == "TestPurchase", name)
			return remote
		end,
	}
	local playerGui = node("PlayerGui")
	local bound: any = nil
	local services: { [string]: any } = {
		ContextActionService = {
			BindActionAtPriority = function(_: any, name: string, fn: any, touch: boolean, priority: number, ...: any)
				bound = { name = name, fn = fn, touch = touch, priority = priority, keys = { ... } }
				table.insert(c.binds, bound)
			end,
			UnbindAction = function(_: any, name: string)
				if bound and bound.name == name then
					bound = nil
				end
				c.unbinds += 1
			end,
		},
		Players = {
			LocalPlayer = {
				WaitForChild = function(_: any, name: string): any
					assert(name == "PlayerGui", name)
					return playerGui
				end,
			},
		},
		ReplicatedStorage = {
			WaitForChild = function(_: any, name: string): any
				assert(name == "ArcadePaidPlay", name)
				return folder
			end,
		},
	}
	local env: { [string]: any } = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], `service {name}`)
			end,
		},
		Enum = enum,
		require = function(spec: string): any
			assert(spec == "./Logic/PaidPlay", spec)
			return PaidPlay
		end,
		Instance = {
			new = function(className: string): any
				return node(className)
			end,
		},
		UDim2 = {
			fromScale = function(x: number, y: number): any
				return { X = x, Y = y }
			end,
		},
	}
	c.module = luau.load(SOURCE, { environment = env, debugName = "TestPurchase" })()
	c.enum = enum
	c.gui = playerGui
	c.open = function(...: any)
		remote.OnClientEvent.fire(...)
	end
	-- a key going down or up: the bound action takes it when it lists the key, else it passes on ("passed")
	c.key = function(name: string, phase: string): any
		local code = enum.KeyCode[name]
		if bound and table.find(bound.keys, code) then
			return bound.fn(bound.name, enum.UserInputState[phase], { KeyCode = code })
		end
		return "passed"
	end
	c.screen = function(): any
		return playerGui:FindFirstChild("ArcadeTestPurchase")
	end
	c.bound = function(): any
		return bound
	end
	return c
end

local LINES = { "SNAKE: 1 GAME", "5 R$ 1 R$ SALE", "TEST PURCHASE: NOTHING IS CHARGED" }

local function texts(screen: any): { string }
	local out = {}
	for _, ch in screen:FindFirstChild("Panel").children do
		if ch.ClassName == "TextLabel" then
			table.insert(out, ch.Text)
		end
	end
	return out
end

return t.spec("f0201 the test purchase screen", function(it)
	it("opened by the server it shows the lines with BUY and CANCEL; nothing shows before", function()
		local c = client()
		c.module.start()
		t.expect(c.screen()).toBe(nil)
		c.open("open", LINES)
		local s = c.screen()
		t.expect(s ~= nil).toBe(true)
		t.expect(texts(s)).toEqual(LINES)
		local panel = s:FindFirstChild("Panel")
		t.expect(panel:FindFirstChild("BUY").Text).toBe("BUY")
		t.expect(panel:FindFirstChild("CANCEL").Text).toBe("CANCEL")
	end)

	it("a tap on BUY sends confirm and closes; a tap on CANCEL sends cancel and closes", function()
		local c = client()
		c.module.start()
		c.open("open", LINES)
		c.screen():FindFirstChild("Panel"):FindFirstChild("BUY").Activated.fire()
		t.expect(c.sent).toEqual({ { "confirm" } })
		t.expect(c.screen()).toBe(nil)
		t.expect(c.bound()).toBe(nil)
		c.open("open", LINES)
		c.screen():FindFirstChild("Panel"):FindFirstChild("CANCEL").Activated.fire()
		t.expect(c.sent).toEqual({ { "confirm" }, { "cancel" } })
		t.expect(c.screen()).toBe(nil)
	end)

	it("while it is open Return, KeypadEnter and ButtonA buy on the press; the release adds nothing", function()
		for _, k in { "Return", "KeypadEnter", "ButtonA" } do
			local c = client()
			c.module.start()
			c.open("open", LINES)
			local sunk = c.key(k, "Begin")
			t.expect(tostring(sunk)).toBe("ContextActionResult.Sink")
			t.expect(c.sent).toEqual({ { "confirm" } })
			t.expect(c.screen()).toBe(nil)
			c.key(k, "End")
			t.expect(c.sent).toEqual({ { "confirm" } })
		end
	end)

	it("while it is open Backspace and ButtonB cancel on the press; the release adds nothing", function()
		for _, k in { "Backspace", "ButtonB" } do
			local c = client()
			c.module.start()
			c.open("open", LINES)
			c.key(k, "Begin")
			t.expect(c.sent).toEqual({ { "cancel" } })
			c.key(k, "End")
			t.expect(c.sent).toEqual({ { "cancel" } })
		end
	end)

	it("its keys are bound only while it is open, above the place's own: outside it they pass on and send nothing", function()
		local c = client()
		c.module.start()
		t.expect(c.key("Return", "Begin")).toBe("passed")
		t.expect(#c.binds).toBe(0)
		c.open("open", LINES)
		local b = c.bound()
		t.expect(b.priority).toBe(3000)
		t.expect(b.priority > 2000).toBe(true) -- Enum.ContextActionPriority.High
		t.expect(b.touch).toBe(false)
		local names = {}
		for _, code in b.keys do
			table.insert(names, code.Name)
		end
		table.sort(names)
		t.expect(names).toEqual({ "Backspace", "ButtonA", "ButtonB", "KeypadEnter", "Return" })
		c.key("Return", "Begin")
		t.expect(c.key("Return", "Begin")).toBe("passed")
		t.expect(c.key("ButtonB", "Begin")).toBe("passed")
		t.expect(c.sent).toEqual({ { "confirm" } })
	end)

	it("centred in the middle half, inside the safe insets, above the place's screens, kept across respawns", function()
		local c = client()
		c.module.start()
		c.open("open", LINES)
		local s = c.screen()
		t.expect(tostring(s.ScreenInsets)).toBe("ScreenInsets.CoreUISafeInsets")
		t.expect(s.ResetOnSpawn).toBe(false)
		t.expect(s.DisplayOrder >= 1000).toBe(true)
		local panel = s:FindFirstChild("Panel")
		t.expect(panel.Position).toEqual({ X = 0.25, Y = 0.25 })
		t.expect(panel.Size).toEqual({ X = 0.5, Y = 0.5 })
	end)

	it("a second open replaces the first: one screen, one binding", function()
		local c = client()
		c.module.start()
		c.open("open", LINES)
		c.open("open", { "PICKMAN: 1 GAME" })
		local screens = 0
		for _, ch in c.gui.children do
			if ch.Name == "ArcadeTestPurchase" then
				screens += 1
			end
		end
		t.expect(screens).toBe(1)
		t.expect(texts(c.screen())).toEqual({ "PICKMAN: 1 GAME" })
	end)

	it("a malformed open shows nothing; lines that are not text are dropped", function()
		local c = client()
		c.module.start()
		c.open("open", "SNAKE")
		c.open("close", LINES)
		t.expect(c.screen()).toBe(nil)
		c.open("open", { "A", 5 :: any, "B" })
		t.expect(texts(c.screen())).toEqual({ "A", "B" })
	end)

	it("started twice it listens once: one open, one screen", function()
		local c = client()
		c.module.start()
		c.module.start()
		c.open("open", LINES)
		t.expect(#c.binds).toBe(1)
	end)
end)
