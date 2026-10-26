--!strict
-- f0146 AC3 (design review 001 F1, F2): Controls and Sticks run from their real sources on a stub engine. Controls:
-- a pad button goes down its key's path and is sunk, except Pad.CONTINUE (ButtonA), which jumps (Hop.INTENT) and is
-- passed on, so FlowView's binding hears it at game over; keys are sunk as before. Sticks: every Heartbeat it folds
-- the most recently used controller's Thumbstick1 through Pad.steer (stick up is Forward, never inverted) and sends
-- what it emits; another controller used takes over; a disconnected one sends nothing. The stub require falls back
-- to the real Logic modules (pickman-test lesson stub-loaders-fall-back).
local Hop = require("@logic/Hop")
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
		env = {},
	}
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
			InputBegan = signal(),
			InputChanged = signal(),
			InputEnded = signal(),
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
				return 0
			end,
		},
	}
	return w
end

local function boot(w: World, name: string): any
	local module = luau.load(source(name), { environment = w.env, debugName = name })()
	return module
end

local function use(w: World, pad: string)
	w.last.name = pad
	w.lastChanged.fire(w.enum.UserInputType[pad])
end

return t.spec("f0146 Controls and Sticks on a stub engine", function(it)
	it("ButtonA jumps and is passed on to FlowView; other pad buttons and the keys are sunk", function()
		local w = world()
		local controls = boot(w, "Controls")
		controls.keys({
			arrows = function() end,
			aim = function(): any
				return "N"
			end,
		})
		controls.start(function() end)
		local a = w.press("ButtonA", "Begin")
		t.expect(#a).toBe(1)
		t.expect(a[1]).toBe(w.enum.ContextActionResult.Pass)
		t.expect(w.fired).toEqual({ Hop.INTENT })
		for _, key in { "ButtonR2", "DPadUp", "ButtonR3", "W", "Space" } do
			local r = w.press(key, "Begin")
			t.expect(#r).toBe(1)
			t.expect(r[1]).toBe(w.enum.ContextActionResult.Sink)
		end
		t.expect(w.fired[#w.fired - 1]).toBe("Forward") -- W
		t.expect(table.find(w.fired, "Forward") ~= nil).toBe(true) -- the D-pad's Up goes the way of W
	end)

	it(
		"Sticks folds the most recent controller's left stick: up is Forward, down Back, right Right, never inverted",
		function()
			local w = world()
			local sticks = boot(w, "Sticks")
			w.connected.Gamepad1 = true
			use(w, "Gamepad1")
			sticks.start()
			w.sticks.Gamepad1 = { x = 0, y = 0.9 }
			w.heartbeat.fire(1 / 60)
			w.heartbeat.fire(1 / 60) -- held: nothing more
			w.sticks.Gamepad1 = { x = 0, y = 0 }
			w.heartbeat.fire(1 / 60)
			w.sticks.Gamepad1 = { x = 0, y = -0.9 }
			w.heartbeat.fire(1 / 60)
			w.sticks.Gamepad1 = { x = 0, y = 0 }
			w.heartbeat.fire(1 / 60)
			w.sticks.Gamepad1 = { x = 0.9, y = 0 }
			w.heartbeat.fire(1 / 60)
			t.expect(w.fired).toEqual({ "Forward", "Back", "Right" })
		end
	)

	it("another controller used takes the stick over; a disconnected one sends nothing", function()
		local w = world()
		local sticks = boot(w, "Sticks")
		w.connected.Gamepad1, w.connected.Gamepad2 = true, true
		use(w, "Gamepad1")
		sticks.start()
		w.sticks.Gamepad1 = { x = -0.9, y = 0 }
		w.sticks.Gamepad2 = { x = 0.9, y = 0 }
		w.heartbeat.fire(1 / 60)
		t.expect(w.fired).toEqual({ "Left" })
		use(w, "Gamepad2")
		w.heartbeat.fire(1 / 60)
		t.expect(w.fired).toEqual({ "Left", "Right" })
		use(w, "Keyboard") -- a key keeps the controller that drives
		w.sticks.Gamepad2 = { x = 0, y = 0.9 }
		w.heartbeat.fire(1 / 60)
		t.expect(w.fired).toEqual({ "Left", "Right", "Forward" })
		w.connected.Gamepad2 = false
		w.sticks.Gamepad2 = { x = 0, y = -0.9 }
		w.heartbeat.fire(1 / 60)
		t.expect(#w.fired).toBe(3)
	end)
end)
