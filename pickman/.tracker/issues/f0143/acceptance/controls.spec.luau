--!strict
-- f0143 AC3 (design review 001 F1, F2, F8): Controls runs from its real source on a stub engine whose clock the case
-- sets (os.clock), so the double tap is judged on scripted times. W twice within Boost.WINDOW sends Forward, Forward,
-- Boost; a slow pair no Boost; a triple tap one Boost; the D-pad's Up folds with the keys (the user, 2026-10-25:
-- "D-pad yes"); a swipe up and a W never pair (one Taps each); two swipes up within the window boost; Left twice
-- never boosts; the left stick's click (ButtonL3, Pad.BUTTONS' "Boost") sends Boost alone. The stub require falls
-- back to the real Logic modules (pickman-test lesson stub-loaders-fall-back), so f0146's Pad and later features'
-- requires load.
local Boost = require("@logic/Boost")
local Pad = require("@logic/Pad")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function source(name: string): string
	local node = game:FindFirstChild("StarterPlayer")
	for _, child in { "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(child)
	end
	assert(node, `no Client.{name} in the game place`)
	return node.Source
end

local function enumProxy(): any
	return setmetatable({}, {
		__index = function(self: any, group: string): any
			local g = setmetatable({}, {
				__index = function(gs: any, item: string): any
					local v = { Name = item, Value = 0, group = group }
					rawset(gs, item, v)
					return v
				end,
			})
			rawset(self, group, g)
			return g
		end,
	})
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

local function anything(): any
	return setmetatable({}, {
		__index = function(_: any, _key: string): any
			return function(): any
				return anything()
			end
		end,
	})
end

local function requirer(spec: string): any
	local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
	if name then
		return (require :: any)("@logic/" .. name)
	end
	if string.match(spec, "^%./[%w_]+$") then
		return anything()
	end
	error(`unexpected require {spec}`)
end

type World = {
	enum: any,
	fired: { any },
	handlers: { { fn: any, codes: { string } } },
	heartbeat: Signal,
	lastChanged: Signal,
	last: { name: string },
	connected: { [string]: boolean },
	sticks: { [string]: { x: number, y: number } },
	press: (key: string, state: string) -> { any },
	swipe: (dx: number, dy: number) -> (),
	now: { t: number },
	env: { [string]: any },
}

local function world(): World
	local enum = enumProxy()
	local fired: { any } = {}
	local remote = {
		FireServer = function(_: any, intent: any)
			table.insert(fired, intent)
		end,
	}
	local remotes = {
		WaitForChild = function(_: any, _name: string): any
			return remote
		end,
	}
	local w: World
	w = {
		enum = enum,
		fired = fired,
		handlers = {},
		heartbeat = signal(),
		lastChanged = signal(),
		last = { name = "Keyboard" },
		connected = {},
		sticks = {},
		-- a key or button event to every handler bound to it; returns their results (a ContextActionResult each)
		press = function(key: string, state: string): { any }
			local out: { any } = {}
			for _, h in w.handlers do
				if table.find(h.codes, key) then
					table.insert(
						out,
						h.fn("action", enum.UserInputState[state], { KeyCode = { Name = key } })
					)
				end
			end
			return out
		end,
		swipe = function(_dx: number, _dy: number) end,
		now = { t = 0 },
		env = {},
	}
	local began, changed, ended = signal(), signal(), signal()
	w.swipe = function(dx: number, dy: number)
		-- one finger in the turn half (the left), a straight line from down to up
		local input = { UserInputType = enum.UserInputType.Touch, Position = { X = 200, Y = 200 } }
		began.fire(input, false)
		input.Position = { X = 200 + dx, Y = 200 + dy }
		changed.fire(input, false)
		ended.fire(input, false)
	end
	local function bind(_: any, _name: string, fn: any, _touch: boolean, ...: any)
		local codes: { string } = {}
		for _, code in { ... } do
			if type(code) == "table" and code.Name then
				table.insert(codes, code.Name)
			end
		end
		table.insert(w.handlers, { fn = fn, codes = codes })
	end
	local services: { [string]: any } = {
		ContextActionService = {
			BindActionAtPriority = function(
				self: any,
				name: string,
				fn: any,
				touch: boolean,
				_p: number,
				...: any
			)
				bind(self, name, fn, touch, ...)
			end,
			BindAction = bind,
		},
		GuiService = {
			GetInsetArea = function(_: any, _which: any): any
				return { Min = { X = 0, Y = 0 }, Max = { X = 800, Y = 400 } }
			end,
		},
		ReplicatedStorage = {
			WaitForChild = function(_: any, _name: string): any
				return remotes
			end,
		},
		RunService = { Heartbeat = w.heartbeat },
		UserInputService = {
			InputBegan = began,
			InputChanged = changed,
			InputEnded = ended,
			WindowFocusReleased = signal(),
			LastInputTypeChanged = w.lastChanged,
			GetLastInputType = function(_: any): any
				return enum.UserInputType[w.last.name]
			end,
			GetGamepadConnected = function(_: any, pad: any): boolean
				return w.connected[pad.Name] == true
			end,
			GetGamepadState = function(_: any, pad: any): { any }
				local stick = w.sticks[pad.Name]
				if stick == nil then
					return {}
				end
				return {
					{ KeyCode = enum.KeyCode.Thumbstick1, Position = { X = stick.x, Y = stick.y, Z = 0 } },
				}
			end,
		},
	}
	w.env = {
		game = {
			GetService = function(_: any, name: string): any
				return services[name] or anything()
			end,
		},
		workspace = { CurrentCamera = { ViewportSize = { X = 800, Y = 400 } } },
		Enum = enum,
		require = requirer,
		os = {
			clock = function(): number
				return w.now.t
			end,
		},
	}
	return w
end

local function boot(w: World, name: string): any
	local module = luau.load(source(name), { environment = w.env, debugName = name })()
	return module
end

local function controls(): World
	local w = world()
	local c = boot(w, "Controls")
	c.keys({
		arrows = function() end,
		aim = function(): any
			return "N"
		end,
	})
	c.start(function() end)
	return w
end

-- presses `key` (Begin, then End) at each scripted time
local function taps(w: World, key: string, times: { number })
	for _, at in times do
		w.now.t = at
		w.press(key, "Begin")
		w.press(key, "End")
	end
end

local function boosts(w: World): number
	local n = 0
	for _, intent in w.fired do
		if intent == Boost.INTENT then
			n += 1
		end
	end
	return n
end

return t.spec("f0143 Controls' boost triggers on a stub engine", function(it)
	it("W twice within the window sends Forward, Forward, Boost; a slow pair sends no Boost", function()
		local w = controls()
		taps(w, "W", { 0, 0.2 })
		t.expect(w.fired).toEqual({ "Forward", "Forward", Boost.INTENT })
		local slow = controls()
		taps(slow, "W", { 0, 0.31 })
		t.expect(slow.fired).toEqual({ "Forward", "Forward" })
	end)

	it("a triple tap boosts once; one W after the cooldown does not boost by itself", function()
		local w = controls()
		taps(w, "W", { 0, 0.1, 0.2 })
		t.expect(boosts(w)).toBe(1)
		taps(w, "W", { 10 })
		t.expect(boosts(w)).toBe(1)
	end)

	it("the D-pad's Up folds with the keys: a double tap of it boosts", function()
		local w = controls()
		taps(w, "DPadUp", { 0, 0.2 })
		t.expect(w.fired).toEqual({ "Forward", "Forward", Boost.INTENT })
	end)

	it("Left twice never boosts; only the forward intent folds", function()
		local w = controls()
		taps(w, "A", { 0, 0.1 })
		taps(w, "D", { 1, 1.1 })
		taps(w, "S", { 2, 2.1 })
		t.expect(boosts(w)).toBe(0)
	end)

	it("two swipes up within the window boost; a swipe up and a W never pair", function()
		local w = controls()
		w.now.t = 0
		w.swipe(0, -120)
		w.now.t = 0.2
		w.swipe(0, -120)
		t.expect(w.fired).toEqual({ "Forward", "Forward", Boost.INTENT })
		local mixed = controls()
		mixed.now.t = 0
		mixed.swipe(0, -120)
		taps(mixed, "W", { 0.1 })
		t.expect(mixed.fired).toEqual({ "Forward", "Forward" })
	end)

	it("the left stick's click (ButtonL3) sends Boost alone, with no Forward, and is sunk", function()
		t.expect(Pad.BUTTONS.ButtonL3).toBe("Boost")
		local w = controls()
		w.now.t = 0
		local r = w.press("ButtonL3", "Begin")
		w.press("ButtonL3", "End")
		t.expect(w.fired).toEqual({ Boost.INTENT })
		t.expect(r[1]).toBe(w.enum.ContextActionResult.Sink)
	end)
end)
