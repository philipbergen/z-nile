--!strict
-- R0058 code review 001 F3 and F4: Pads and Sticks run from their real sources on a small stub engine. Sticks' fold
-- over the left stick starts afresh only when the driving controller changes, so another controller's first push the
-- same way still turns; a read of nothing (a dropout) keeps it, so the same pad returning still pushed sends no second
-- turn (review 002 F1); a reconnect at rest sends nothing. Pads counts a pad's button press (InputBegan) as a full press, but a non-stick InputChanged (a trigger's
-- travel) as nothing, so it never takes over.
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
					local v = { Name = item }
					rawset(gs, item, v)
					return v
				end,
			})
			rawset(self, group, g)
			return g
		end,
	})
end

type World = {
	fired: { any },
	connected: { [string]: boolean },
	sticks: { [string]: { x: number, y: number } },
	changed: (pad: string, key: string, x: number, y: number, z: number?) -> (),
	pressed: (pad: string, key: string) -> (),
	beat: () -> (),
	pads: any,
}

local function world(): World
	local enum = enumProxy()
	local fired: { any } = {}
	local began, changed, heartbeat = signal(), signal(), signal()
	local w: World
	w = {
		fired = fired,
		connected = {},
		sticks = {},
		changed = function(pad: string, key: string, x: number, y: number, z: number?)
			changed.fire({
				UserInputType = enum.UserInputType[pad],
				KeyCode = enum.KeyCode[key],
				Position = { X = x, Y = y, Z = z or 0 },
			}, false)
		end,
		pressed = function(pad: string, key: string)
			began.fire({
				UserInputType = enum.UserInputType[pad],
				KeyCode = enum.KeyCode[key],
				Position = { X = 0, Y = 0, Z = 0 },
			}, false)
		end,
		beat = function()
			heartbeat.fire(1 / 60)
		end,
		pads = nil,
	}
	local intent = {
		FireServer = function(_: any, x: any)
			table.insert(fired, x)
		end,
	}
	local services: { [string]: any } = {
		ReplicatedStorage = {
			WaitForChild = function(_: any, _name: string): any
				return {
					WaitForChild = function(_: any, _n: string): any
						return intent
					end,
				}
			end,
		},
		RunService = { Heartbeat = heartbeat },
		UserInputService = {
			InputBegan = began,
			InputChanged = changed,
			GetGamepadConnected = function(_: any, pad: any): boolean
				return w.connected[pad.Name] == true
			end,
			GetGamepadState = function(_: any, pad: any): { any }
				local s = w.sticks[pad.Name]
				if s == nil then
					return {}
				end
				return { { KeyCode = enum.KeyCode.Thumbstick1, Position = { X = s.x, Y = s.y, Z = 0 } } }
			end,
		},
	}
	local env = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], name)
			end,
		},
		Enum = enum,
		require = function(spec: string): any
			local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
			return (require :: any)("@logic/" .. assert(name, spec))
		end,
	}
	local pads = luau.load(source("Pads"), { environment = env, debugName = "Pads" })() :: any
	pads.start()
	local sticks = luau.load(source("Sticks"), { environment = env, debugName = "Sticks" })() :: any
	sticks.start(pads.stick)
	w.pads = pads
	return w
end

return t.spec("Sticks and Pads across a change of controller", function(it)
	it(
		"after a disconnect mid-push, the other pad taking over resets the fold: its first push the same way turns",
		function()
			local w = world()
			w.connected.Gamepad1 = true
			w.changed("Gamepad1", "Thumbstick1", -0.9, 0)
			w.sticks.Gamepad1 = { x = -0.9, y = 0 }
			w.beat()
			t.expect(w.fired).toEqual({ "Left" })
			w.connected.Gamepad1 = false
			w.beat() -- reads nothing
			w.connected.Gamepad2 = true
			w.changed("Gamepad2", "Thumbstick1", -0.9, 0)
			w.sticks.Gamepad2 = { x = -0.9, y = 0 }
			w.beat()
			t.expect(w.fired).toEqual({ "Left", "Left" })
		end
	)

	it(
		"two connected pads: Gamepad1 still held left, Gamepad2's stick takes over pushed left, and turns",
		function()
			local w = world()
			w.connected.Gamepad1, w.connected.Gamepad2 = true, true
			w.changed("Gamepad1", "Thumbstick1", -0.9, 0)
			w.sticks.Gamepad1 = { x = -0.9, y = 0 }
			w.beat()
			t.expect(w.fired).toEqual({ "Left" })
			w.changed("Gamepad2", "Thumbstick1", -0.45, 0) -- takes over past STEER_OFF, below STEER_ON
			w.sticks.Gamepad2 = { x = -0.45, y = 0 }
			w.beat()
			t.expect(w.fired).toEqual({ "Left" }) -- a fresh fold engages only at STEER_ON
			w.sticks.Gamepad2 = { x = -0.9, y = 0 }
			w.beat()
			t.expect(w.fired).toEqual({ "Left", "Left" })
		end
	)

	it(
		"the same pad dropping mid-push and returning still pushed sends nothing more: one push, one turn",
		function()
			local w = world()
			w.connected.Gamepad1 = true
			w.changed("Gamepad1", "Thumbstick1", -0.9, 0)
			w.sticks.Gamepad1 = { x = -0.9, y = 0 }
			w.beat()
			w.connected.Gamepad1 = false
			w.beat()
			w.connected.Gamepad1 = true
			w.beat()
			t.expect(w.fired).toEqual({ "Left" })
		end
	)

	it("the same pad dropping mid-push, returning released, then pushed the same way, turns again", function()
		local w = world()
		w.connected.Gamepad1 = true
		w.changed("Gamepad1", "Thumbstick1", -0.9, 0)
		w.sticks.Gamepad1 = { x = -0.9, y = 0 }
		w.beat()
		w.connected.Gamepad1 = false
		w.beat()
		w.connected.Gamepad1 = true
		w.sticks.Gamepad1 = { x = 0, y = 0 }
		w.beat()
		w.sticks.Gamepad1 = { x = -0.9, y = 0 }
		w.beat()
		t.expect(w.fired).toEqual({ "Left", "Left" })
	end)

	it("a reconnect of the same pad at rest sends nothing", function()
		local w = world()
		w.connected.Gamepad1 = true
		w.changed("Gamepad1", "Thumbstick1", 0, 0.9)
		w.sticks.Gamepad1 = { x = 0, y = 0.9 }
		w.beat()
		w.connected.Gamepad1 = false
		w.beat()
		w.connected.Gamepad1 = true
		w.sticks.Gamepad1 = { x = 0, y = 0 }
		w.beat()
		w.beat()
		t.expect(w.fired).toEqual({ "Forward" })
	end)

	it("a trigger's travel (a non-stick InputChanged) never takes over; its press does", function()
		local w = world()
		w.connected.Gamepad1, w.connected.Gamepad2 = true, true
		w.changed("Gamepad1", "Thumbstick1", 0, 0.9)
		w.sticks.Gamepad1 = { x = 0, y = 0.9 }
		w.sticks.Gamepad2 = { x = 0.9, y = 0 }
		w.changed("Gamepad2", "ButtonR2", 0, 0, 1)
		local _, _, from = w.pads.stick("Thumbstick1")
		t.expect(from).toBe("Gamepad1")
		w.pressed("Gamepad2", "ButtonR2")
		local _, _, now = w.pads.stick("Thumbstick1")
		t.expect(now).toBe("Gamepad2")
	end)
end)
