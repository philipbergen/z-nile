--!strict
-- f0395 AC2: the test purchase screen (ReplicatedStorage.Arcade.TestPurchase) renders its lines as rich text, so a
-- play's struck price shows struck on every screen that opens it (the portal's play screen, f0208, and every game's
-- revive screen included). Run from its real source on a stub client: every line label has RichText on and shows
-- the line exactly as the server sent it (the client neither strips nor escapes the markup); BUY and CANCEL are as
-- f0201 made them.
local PaidPlay = require("@logic/PaidPlay")
local Prices = require("@shared/Prices")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

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

-- a stub client running TestPurchase's real source; its source is read here, not at the file's top
local SOURCE: string? = nil
local function client(): any
	if SOURCE == nil then
		SOURCE = (place.load() :: any)
			:GetService("ReplicatedStorage")
			:FindFirstChild("Arcade")
			:FindFirstChild("TestPurchase").Source
	end
	local source = SOURCE :: string
	local c: any = { sent = {} }
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
	local services: { [string]: any } = {
		ContextActionService = {
			BindActionAtPriority = function() end,
			UnbindAction = function() end,
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
		Enum = enumProxy(),
		require = function(spec: string): any
			assert(spec == "./Logic/PaidPlay", spec)
			return PaidPlay
		end,
		Instance = {
			new = function(className: string): any
				return node(className)
			end,
		},
		task = {
			spawn = function(fn: any, ...: any)
				local co = if type(fn) == "thread" then fn else coroutine.create(fn)
				local ok, err = coroutine.resume(co, ...)
				assert(ok, err)
			end,
		},
		UDim2 = {
			fromScale = function(x: number, y: number): any
				return { X = x, Y = y }
			end,
		},
	}
	c.module = luau.load(source, { environment = env, debugName = "TestPurchase" })()
	c.open = function(...: any)
		remote.OnClientEvent.fire(...)
	end
	c.screen = function(): any
		return playerGui:FindFirstChild("ArcadeTestPurchase")
	end
	return c
end

-- the panel's line labels, in order: their text and whether they render rich text
local function labels(screen: any): { { text: string, rich: boolean } }
	local out = {}
	for _, ch in screen:FindFirstChild("Panel").children do
		if ch.ClassName == "TextLabel" then
			table.insert(out, { text = ch.Text, rich = ch.RichText == true })
		end
	end
	return out
end

local function shown(lines: { string }): { { text: string, rich: boolean } }
	local out = {}
	for _, line in lines do
		table.insert(out, { text = line, rich = true })
	end
	return out
end

return t.spec("f0395 the test screen renders its lines as rich text", function(it)
	it(
		"a play's lines: every line label is rich text and shows the line as sent, the struck price marked",
		function()
			local c = client()
			c.module.start()
			local lines = PaidPlay.testLines("SNAKE", "play", Prices)
			c.open("open", lines)
			local got = labels(c.screen())
			t.expect(got).toEqual(shown(lines))
			t.expect(got[2].text).toBe("<s>5 R$</s> 1 R$ SALE")
			local panel = c.screen():FindFirstChild("Panel")
			t.expect(panel:FindFirstChild("BUY").Text).toBe("BUY")
			t.expect(panel:FindFirstChild("CANCEL").Text).toBe("CANCEL")
		end
	)

	it(
		"a revive's lines and escaped text: every line label is rich text, the entities kept as sent",
		function()
			local c = client()
			c.module.start()
			local lines = PaidPlay.testLines("PICKMAN", "revive", Prices)
			c.open("open", lines)
			t.expect(labels(c.screen())).toEqual(shown(lines))
			local odd = {
				"A&lt;B&gt;&amp;C: 1 GAME",
				"<s>&lt;5&gt;</s> &amp;1 SALE",
				"TEST PURCHASE: NOTHING IS CHARGED",
			}
			c.open("open", odd)
			t.expect(labels(c.screen())).toEqual(shown(odd))
		end
	)
end)
