--!strict
-- f0146 AC3 (design reviews 001 F1, F2 and 002 F1 to F3): Controls, Pads and Sticks run from their real sources on
-- a stub engine. Controls: each pad button does what its key does (R2 fires where the player aims, each D-pad
-- direction turns, R3 recentres) and is sunk, except Pad.CONTINUE (ButtonA), which jumps (Hop.INTENT) and is passed
-- on, so FlowView's binding hears it at game over. Pads, the one tracker Sticks and Camera read: the most recently
-- used controller drives, judged from its inputs (a button, or a stick past STEER_OFF), so a stick alone takes over,
-- an idle pad's drift never does, a key keeps it, and a disconnected one reads nothing. Sticks: every Heartbeat it
-- folds the driving controller's Thumbstick1 through Pad.steer (stick up is Forward, never inverted) and hands what
-- it emits to Controls.turn, the keys' own path to the server. The stub require falls back to the real Logic
-- modules (pickman-test lesson stub-loaders-fall-back).
local Blaster = require("@logic/Blaster")
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
	looks: { [string]: { x: number, y: number } },
	input: (pad: string, key: string, x: number, y: number, began: boolean) -> (),
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
	local began, changed = signal(), signal()
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
		looks = {},
		input = function() end,
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
	-- an input from a controller: a button press (began) or a stick's move (InputChanged), as Roblox reports them
	w.input = function(pad: string, key: string, x: number, y: number, isBegin: boolean)
		local obj = {
			UserInputType = enum.UserInputType[pad],
			KeyCode = enum.KeyCode[key],
			Position = { X = x, Y = y, Z = 0 },
		}
		if isBegin then
			began.fire(obj, false)
		else
			changed.fire(obj, false)
		end
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
				local out = {}
				local stick, look = w.sticks[pad.Name], w.looks[pad.Name]
				if stick then
					table.insert(
						out,
						{ KeyCode = enum.KeyCode.Thumbstick1, Position = { X = stick.x, Y = stick.y, Z = 0 } }
					)
				end
				if look then
					table.insert(
						out,
						{ KeyCode = enum.KeyCode.Thumbstick2, Position = { X = look.x, Y = look.y, Z = 0 } }
					)
				end
				return out
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

-- Controls booted and started, with a snap counter; Pads booted and started
local function boot3(w: World): (any, any, { snaps: number })
	local snaps = { snaps = 0 }
	local controls = boot(w, "Controls")
	controls.keys({
		arrows = function() end,
		aim = function(): any
			return "N"
		end,
	})
	controls.start(function()
		snaps.snaps += 1
	end)
	local pads = boot(w, "Pads")
	pads.start()
	return controls, pads, snaps
end

local function beat(w: World, pad: string, x: number, y: number)
	w.sticks[pad] = { x = x, y = y }
	w.heartbeat.fire(1 / 60)
end

return t.spec("f0146 Controls, Pads and Sticks on a stub engine", function(it)
	it(
		"each pad button does what its key does and is sunk; ButtonA jumps and is passed on to FlowView",
		function()
			local w = world()
			local _, _, snaps = boot3(w)
			local function adds(key: string): ({ any }, any)
				local before = #w.fired
				local r = w.press(key, "Begin")
				w.press(key, "End")
				t.expect(#r).toBe(1)
				local added = {}
				for i = before + 1, #w.fired do
					table.insert(added, w.fired[i])
				end
				return added, r[1]
			end
			local a, pass = adds("ButtonA")
			t.expect(a).toEqual({ Hop.INTENT })
			t.expect(pass).toBe(w.enum.ContextActionResult.Pass)
			local sink = w.enum.ContextActionResult.Sink
			local expected: { { any } } = {
				{ "ButtonR2", { Blaster.intent("N") } },
				{ "DPadUp", { "Forward" } },
				{ "DPadDown", { "Back" } },
				{ "DPadLeft", { "Left" } },
				{ "DPadRight", { "Right" } },
				{ "W", { "Forward" } },
				{ "Space", { Hop.INTENT } },
			}
			for _, row in expected do
				local added, result = adds(row[1])
				t.expect(added).toEqual(row[2])
				t.expect(result).toBe(sink)
			end
			local r3, result = adds("ButtonR3")
			t.expect(r3).toEqual({})
			t.expect(result).toBe(sink)
			t.expect(snaps.snaps).toBe(1)
		end
	)

	it(
		"Sticks folds the driving controller's left stick into Controls.turn: up Forward, down Back, right Right",
		function()
			local w = world()
			local controls, pads = boot3(w)
			local sticks = boot(w, "Sticks")
			w.connected.Gamepad1 = true
			sticks.start(pads.stick, controls.turn)
			w.input("Gamepad1", "Thumbstick1", 0, 0.9, false) -- the stick alone takes over
			beat(w, "Gamepad1", 0, 0.9)
			beat(w, "Gamepad1", 0, 0.9) -- held: nothing more
			beat(w, "Gamepad1", 0, 0)
			beat(w, "Gamepad1", 0, -0.9)
			beat(w, "Gamepad1", 0, 0)
			beat(w, "Gamepad1", 0.9, 0)
			t.expect(w.fired).toEqual({ "Forward", "Back", "Right" })
		end
	)

	it(
		"Pads: a used controller takes over, an idle pad's drift never does, a key keeps it, a disconnected one reads nothing",
		function()
			local w = world()
			local controls, pads = boot3(w)
			local sticks = boot(w, "Sticks")
			w.connected.Gamepad1, w.connected.Gamepad2 = true, true
			sticks.start(pads.stick, controls.turn)
			t.expect(pads.stick("Thumbstick1")).toBe(nil) -- none drives yet
			w.input("Gamepad1", "Thumbstick1", -0.9, 0, false)
			beat(w, "Gamepad1", -0.9, 0)
			t.expect(w.fired).toEqual({ "Left" })
			-- Gamepad2's stick drifts below STEER_OFF: Gamepad1 still drives
			w.input("Gamepad2", "Thumbstick1", 0.1, 0.1, false)
			w.sticks.Gamepad2 = { x = 0.9, y = 0 }
			beat(w, "Gamepad1", -0.9, 0)
			t.expect(w.fired).toEqual({ "Left" })
			-- a button on Gamepad2: it drives now, sticks and look alike
			w.input("Gamepad2", "ButtonX", 0, 0, true)
			w.looks.Gamepad1 = { x = 0.5, y = 0 }
			w.looks.Gamepad2 = { x = 0, y = 0.7 }
			w.heartbeat.fire(1 / 60)
			t.expect(w.fired).toEqual({ "Left", "Right" })
			local lx, ly = pads.stick("Thumbstick2")
			t.expect(lx).toBe(0)
			t.expect(ly).toBe(0.7)
			-- a key keeps the controller that drives
			w.input("Keyboard", "W", 0, 0, true)
			local kx = pads.stick("Thumbstick2")
			t.expect(kx).toBe(0)
			-- disconnected: nothing read, nothing sent
			w.connected.Gamepad2 = false
			t.expect(pads.stick("Thumbstick2")).toBe(nil)
			beat(w, "Gamepad2", 0, -0.9)
			t.expect(#w.fired).toBe(2)
		end
	)
end)
