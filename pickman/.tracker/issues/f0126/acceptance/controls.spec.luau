--!strict
-- f0126 AC12 (every input, user 2026-10-25: "We support keyboard, cosole, and touch for every feature"): Controls,
-- run from its real source on a stub engine, sends View.PICK_INTENT for F on the keyboard, for Y / triangle
-- (ButtonY) on a controller, and for a finger going down on the PICK button (Touch.buttons' pick rectangle, handed in
-- through f0110's buttons hook); and HudView draws the PICK button there, gold, captioned PICK, on touch screens only.
-- The stub require falls back to the real Logic modules (pickman-test lesson stub-loaders-fall-back).
local Hud = require("@logic/Hud")
local Session = require("@logic/Session")
local Touch = require("@logic/Touch")
local View = require("@logic/View")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function script(name: string): any
	local node = game:FindFirstChild("StarterPlayer")
	for _, child in { "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(child)
	end
	t.expect(node ~= nil).toBe(true)
	return node
end

type Rect = { x: number, y: number, w: number, h: number }

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

-- a stand-in for a sibling module or service the cases do not look at
local function anything(): any
	return setmetatable({}, {
		__index = function(_: any, _key: string): any
			return function(): any
				return anything()
			end
		end,
	})
end

local function requirer(): (string) -> any
	return function(spec: string): any
		local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
		if name then
			return (require :: any)("@logic/" .. name)
		end
		if string.match(spec, "^%./[%w_]+$") then
			return anything()
		end
		error(`unexpected require {spec}`)
	end
end

type World = {
	fired: { any },
	bound: { string },
	began: Signal,
	changed: Signal,
	ended: Signal,
	touch: (x: number, y: number) -> (),
	drag: (x0: number, y0: number, x1: number, y1: number) -> (),
	press: (key: string, state: string) -> (),
}

local PICK: Rect = { x = 520, y = 300, w = 70, h = 70 }
local FIRE: Rect = { x = 600, y = 300, w = 70, h = 70 }
local HOP: Rect = { x = 700, y = 300, w = 70, h = 70 }
local SNAP: Rect = { x = 420, y = 350, w = 44, h = 44 }

local function controls(withPick: boolean): World
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
	local handler: any = nil
	local bound: { string } = {}
	local world: World
	world = {
		fired = fired,
		bound = bound,
		began = signal(),
		changed = signal(),
		ended = signal(),
		touch = function(x: number, y: number)
			local input = { UserInputType = enum.UserInputType.Touch, Position = { X = x, Y = y } }
			world.began.fire(input, false)
			world.ended.fire(input, false)
		end,
		drag = function(x0: number, y0: number, x1: number, y1: number)
			local input = { UserInputType = enum.UserInputType.Touch, Position = { X = x0, Y = y0 } }
			world.began.fire(input, false)
			input.Position = { X = x1, Y = y1 }
			world.changed.fire(input, false)
			world.ended.fire(input, false)
		end,
		press = function(key: string, state: string)
			handler("PickmanControls", enum.UserInputState[state], { KeyCode = { Name = key } })
		end,
	}
	local services: { [string]: any } = {
		ContextActionService = {
			BindActionAtPriority = function(
				_: any,
				_name: string,
				h: any,
				_touch: boolean,
				_p: number,
				...: any
			)
				handler = h
				for _, code in { ... } do
					table.insert(bound, code.Name)
				end
			end,
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
		UserInputService = {
			InputBegan = world.began,
			InputChanged = world.changed,
			InputEnded = world.ended,
			WindowFocusReleased = signal(),
		},
	}
	local env = {
		game = {
			GetService = function(_: any, name: string): any
				return services[name] or anything()
			end,
		},
		workspace = { CurrentCamera = { ViewportSize = { X = 800, Y = 400 } } },
		Enum = enum,
		require = requirer(),
	}
	local Controls = luau.load(script("Controls").Source, { environment = env, debugName = "Controls" })()
	local buttons = { snap = SNAP, fire = FIRE, hop = HOP, pick = if withPick then PICK else nil }
	(Controls.start :: any)(
		function() end,
		function(_dx: number, _dy: number) end,
		nil,
		function(_: boolean) end,
		function(): any
			return buttons
		end
	)
	return world
end

local function count(list: { any }, value: any): number
	local n = 0
	for _, v in list do
		if v == value then
			n += 1
		end
	end
	return n
end

type Inst = { [string]: any }

local function instance(class: string): Inst
	local children: { Inst } = {}
	local props: { [string]: any } = { ClassName = class }
	local self: Inst
	self = setmetatable({}, {
		__index = function(_: any, key: string): any
			if key == "GetChildren" then
				return function(): { Inst }
					return table.clone(children)
				end
			elseif key == "ClearAllChildren" then
				return function()
					table.clear(children)
				end
			elseif key == "FindFirstChild" then
				return function(_: any, name: string): Inst?
					for _, c in children do
						if c.Name == name then
							return c
						end
					end
					return nil
				end
			elseif key == "IsA" then
				return function(_: any, c: string): boolean
					return props.ClassName == c
				end
			elseif key == "WaitForChild" then
				return function(_: any, _name: string): Inst
					return instance("PlayerGui")
				end
			elseif key == "children" then
				return children
			end
			return props[key]
		end,
		__newindex = function(_: any, key: string, value: any)
			if key == "Parent" then
				if value == props.Parent then
					return
				end
				if props.Parent then
					local i = table.find(props.Parent.children, self)
					if i then
						table.remove(props.Parent.children, i)
					end
				end
				if value ~= nil then
					table.insert(value.children, self)
				end
			end
			props[key] = value
		end,
	}) :: any
	return self
end

type Core = { left: number, top: number, right: number, bottom: number }
type HudWorld = {
	made: { [string]: Inst },
	render: () -> (),
	layout: () -> Hud.Layout,
	screen: (number, number, Core) -> (),
}

local function hudView(touch: boolean, core: Core?): HudWorld
	local rendered: { () -> () } = {}
	local made: { [string]: Inst } = {}
	local c: Core = core or { left = 0, top = 0, right = 0, bottom = 0 }
	local area = { Min = { X = 0, Y = 0 }, Max = { X = 844, Y = 390 } }
	local safe = { Min = { X = c.left, Y = c.top }, Max = { X = 844 - c.right, Y = 390 - c.bottom } }
	local viewport = { X = 844, Y = 390 }
	local services: { [string]: any } = {
		GuiService = {
			GetInsetArea = function(_: any, which: any): any
				return if which.Name == "CoreUISafeInsets" then safe else area
			end,
		},
		Players = { LocalPlayer = instance("Player") },
		RunService = {
			BindToRenderStep = function(_: any, _name: string, _priority: number, fn: () -> ())
				table.insert(rendered, fn)
			end,
		},
		UserInputService = { TouchEnabled = touch },
	}
	local env = {
		game = {
			GetService = function(_: any, name: string): any
				return services[name] or anything()
			end,
		},
		workspace = { CurrentCamera = { ViewportSize = viewport } },
		Enum = enumProxy(),
		Instance = {
			new = function(class: string): Inst
				local i = instance(class)
				local mt = getmetatable(i :: any)
				local set = mt.__newindex
				mt.__newindex = function(s: any, key: string, value: any)
					set(s, key, value)
					if key == "Name" then
						made[value] = i
					end
				end
				return i
			end,
		},
		UDim2 = {
			fromOffset = function(x: number, y: number): any
				return { x = x, y = y }
			end,
			fromScale = function(x: number, y: number): any
				return { sx = x, sy = y }
			end,
		},
		UDim = {
			new = function(s: number, o: number): any
				return { s = s, o = o }
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
		},
		require = requirer(),
	}
	local hud = luau.load(script("HudView").Source, { environment = env, debugName = "HudView" })()
	hud.start()
	hud.show(
		{ phase = "playing", level = 1, score = 0, lives = 3, timer = 0, frightened = 0 } :: Session.PlayFrame
	)
	return {
		made = made,
		render = function()
			for _, fn in rendered do
				fn()
			end
		end,
		layout = function(): Hud.Layout
			return Hud.layout(viewport.X, viewport.Y, Hud.safeInset(area, safe))
		end,
		screen = function(w: number, h: number, nc: Core)
			viewport.X, viewport.Y = w, h
			area.Max = { X = w, Y = h }
			safe.Min = { X = nc.left, Y = nc.top }
			safe.Max = { X = w - nc.right, Y = h - nc.bottom }
		end,
	}
end

local function texts(f: Inst): { string }
	local out: { string } = {}
	for _, c in f:GetChildren() do
		if c.ClassName == "TextLabel" and c.Text then
			table.insert(out, c.Text)
		end
	end
	return out
end

return t.spec("f0126 the pick on every input", function(it)
	it("the keyboard's F and the controller's Y are bound to the pick", function()
		t.expect(View.action("F")).toBe("Pick")
		t.expect(View.PICK_INTENT).toBe("Pick")
		-- Y is a row of f0146's controller map (Pad.BUTTONS), which Controls binds beside View.KEYS
		local Pad = (require :: any)("@logic/Pad")
		t.expect(Pad.action("ButtonY")).toBe("Pick")
		local w = controls(true)
		t.expect(table.find(w.bound, "F") ~= nil).toBe(true)
		t.expect(table.find(w.bound, "ButtonY") ~= nil).toBe(true)
	end)

	it("F and Y going down each send the pick once; going up sends nothing", function()
		for _, key in { "F", "ButtonY" } do
			local w = controls(true)
			w.press(key, "Begin")
			t.expect(count(w.fired, View.PICK_INTENT)).toBe(1) -- on the press, before the release
			w.press(key, "End")
			t.expect(count(w.fired, View.PICK_INTENT)).toBe(1) -- the release adds nothing
			t.expect(#w.fired).toBe(1)
		end
	end)

	it("a finger going down on the PICK button sends the pick, once a tap", function()
		local w = controls(true)
		w.touch(PICK.x + 10, PICK.y + 10)
		w.touch(PICK.x + PICK.w - 1, PICK.y + PICK.h - 1)
		t.expect(count(w.fired, View.PICK_INTENT)).toBe(2)
	end)

	it("FIRE, JUMP and the rest of the screen never send the pick", function()
		local w = controls(true)
		w.touch(FIRE.x + 10, FIRE.y + 10)
		w.touch(HOP.x + 10, HOP.y + 10)
		w.touch(100, 100)
		w.touch(PICK.x - 5, PICK.y + 10)
		w.drag(700, 100, 760, 130) -- a look drag on the right half
		w.drag(100, 200, 100, 100) -- a swipe on the left half turns
		t.expect(count(w.fired, View.PICK_INTENT)).toBe(0)
		t.expect(#w.fired >= 1).toBe(true) -- the swipe did send its turn
	end)

	it("without a pick rectangle in the buttons, that place is the look half as before", function()
		local w = controls(false)
		w.touch(PICK.x + 10, PICK.y + 10)
		t.expect(count(w.fired, View.PICK_INTENT)).toBe(0)
	end)

	it(
		"HudView draws the PICK button at Touch.buttons' pick rectangle, gold, captioned PICK, on touch only",
		function()
			for _, touch in { true, false } do
				local world = hudView(touch)
				world.render()
				local l = world.layout()
				local f = world.made.Pick
				t.expect(f ~= nil).toBe(true)
				local want: Rect = (Touch :: any).buttons(l).pick
				t.expect({ x = f.Position.x, y = f.Position.y, w = f.Size.x, h = f.Size.y }).toEqual(want)
				t.expect(f.BackgroundColor3).toEqual({ r = 255, g = 191, b = 0 })
				t.expect(f.Visible).toBe(touch)
				local found = false
				for _, c in f:GetChildren() do
					for _, text in texts(c) do
						found = found or text == "PICK"
					end
					found = found or c.Text == "PICK"
				end
				t.expect(found).toBe(true)
				t.expect(f.Active).toBe(false) -- drawn only: the touch is the fold's
			end
		end
	)

	it("HudView places the PICK button by the layout's inset, and again when the screen turns", function()
		local world = hudView(true, { left = 47, top = 0, right = 0, bottom = 21 })
		world.render()
		local function placed(): Rect
			local f = world.made.Pick
			return { x = f.Position.x, y = f.Position.y, w = f.Size.x, h = f.Size.y }
		end
		t.expect(placed()).toEqual((Touch :: any).buttons(world.layout()).pick)
		local turns: { { w: number, h: number, core: Core } } = {
			{ w = 390, h = 844, core = { left = 0, top = 47, right = 0, bottom = 34 } },
			{ w = 844, h = 390, core = { left = 0, top = 0, right = 47, bottom = 21 } },
		}
		for _, s in turns do
			world.screen(s.w, s.h, s.core)
			world.render()
			t.expect(placed()).toEqual((Touch :: any).buttons(world.layout()).pick)
		end
	end)
end)
