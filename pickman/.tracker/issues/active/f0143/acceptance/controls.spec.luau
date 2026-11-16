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
	padInput: (pad: string, key: string, x: number, y: number) -> (),
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
		padInput = function() end,
		now = { t = 0 },
		env = {},
	}
	local began, changed, ended = signal(), signal(), signal()
	-- a controller's stick moved, as Roblox reports it (Pads tracks the driving controller from these)
	w.padInput = function(pad: string, key: string, x: number, y: number)
		changed.fire({
			UserInputType = enum.UserInputType[pad],
			KeyCode = enum.KeyCode[key],
			Position = { X = x, Y = y, Z = 0 },
		}, false)
	end
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

-- presses `key` (Begin, then End) at each scripted time; every intent goes out on the press, none on the release
-- (design review 002 F2)
local function taps(w: World, key: string, times: { number })
	for _, at in times do
		w.now.t = at
		local before = #w.fired
		w.press(key, "Begin")
		local pressed = #w.fired
		t.expect(pressed > before).toBe(true)
		w.press(key, "End")
		t.expect(#w.fired).toBe(pressed)
	end
end

-- Pads and Sticks booted on the same stub, Gamepad1 connected and driving
local function sticks(w: World)
	local pads = boot(w, "Pads")
	pads.start()
	boot(w, "Sticks").start(pads.stick)
	w.connected.Gamepad1 = true
	w.padInput("Gamepad1", "Thumbstick1", 0, 0.9)
end

-- the left stick at (x, y) on the heartbeat at scripted time `at`
local function push(w: World, at: number, x: number, y: number)
	w.now.t = at
	w.sticks.Gamepad1 = { x = x, y = y }
	w.heartbeat.fire(1 / 60)
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
		t.expect(w.fired).toEqual({ Boost.INTENT }) -- on the press (design review 002 F2)
		w.press("ButtonL3", "End")
		t.expect(w.fired).toEqual({ Boost.INTENT }) -- nothing on the release
		t.expect(r[1]).toBe(w.enum.ContextActionResult.Sink)
	end)

	it("a quick double push of the left stick up boosts (its own Taps); a slow one does not", function()
		local w = world()
		sticks(w)
		push(w, 0, 0, 0.9)
		push(w, 0.1, 0, 0)
		push(w, 0.2, 0, 0.9)
		t.expect(w.fired).toEqual({ "Forward", "Forward", Boost.INTENT })
		local slow = world()
		sticks(slow)
		push(slow, 0, 0, 0.9)
		push(slow, 0.1, 0, 0)
		push(slow, 0.31, 0, 0.9)
		t.expect(slow.fired).toEqual({ "Forward", "Forward" })
	end)

	it("a stick held up is one push; a tilt between STEER_OFF and STEER_ON from rest is none", function()
		local w = world()
		sticks(w)
		for i = 0, 20 do
			push(w, i * 0.02, 0, 0.9)
		end
		t.expect(w.fired).toEqual({ "Forward" })
		local wobble = world()
		sticks(wobble)
		push(wobble, 0, 0, 0)
		for i = 1, 10 do
			push(wobble, i * 0.02, 0, if i % 2 == 0 then 0.45 else 0.55)
		end
		t.expect(wobble.fired).toEqual({})
	end)

	it(
		"every Forward the stick emits is a push, a turn into up included; the stick and W never pair",
		function()
			local w = world()
			sticks(w)
			push(w, 0, -0.9, 0) -- Left
			push(w, 0.05, math.cos(math.rad(100)) * 0.9, math.sin(math.rad(100)) * 0.9) -- rotated into up: Forward
			push(w, 0.1, 0, 0)
			push(w, 0.2, 0, 0.9)
			t.expect(w.fired).toEqual({ "Left", "Forward", "Forward", Boost.INTENT })
			local mixed = world()
			local c = boot(mixed, "Controls")
			c.keys({
				arrows = function() end,
				aim = function(): any
					return "N"
				end,
			})
			c.start(function() end)
			sticks(mixed)
			push(mixed, 0, 0, 0.9)
			taps(mixed, "W", { 0.1 })
			t.expect(mixed.fired).toEqual({ "Forward", "Forward" })
		end
	)
end)
