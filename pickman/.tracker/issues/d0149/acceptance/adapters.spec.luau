--!strict
-- d0149 AC3: the adapters, run from their real source on a stub engine (as f0126's controls.spec does; the stub
-- require falls back to the real Logic modules, pickman-test lesson stub-loaders-fall-back). Controls feeds every
-- touch through Touch's fold against the controls HudView reports and applies what it emits: the steer circle's
-- turns as intents (a pull up also folds f0143's touch taps, so two quick pulls up boost), the look circle's point
-- through Controls.keys' `point` and its tap's hop, FIRE's aimed shot and PICK's pick; the knobs go to the hook it
-- is given. Camera keeps the point in its arrows, so it looks and aims by it. HudView draws the two circles, their
-- knobs, FIRE and PICK where Touch.buttons puts them, on touch screens only, and no snap control or JUMP. Main
-- wires them.
local Blaster = require("@logic/Blaster")
-- f0143's, which lands before this issue: reached by a built name, so the spec type-checks and its requires
-- resolve on a tree without it
local Boost: any = (require :: any)("@logic/" .. "Boost")
local Hop = require("@logic/Hop")
local Hud = require("@logic/Hud")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local Touch: any = require("@logic/Touch")
local View: any = require("@logic/View")
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

-- the controls the cases hand Controls: a layout's own, so they are where HudView would report them
local LAYOUT = Hud.layout(844, 390)
local PLACED = Touch.buttons(LAYOUT)

type World = {
	fired: { any },
	points: { any }, -- every value Controls.keys' point was called with ("nil" for nil)
	knobs: { any },
	held: { boolean },
	clock: { now: number },
	down: (id: number, x: number, y: number) -> (),
	move: (id: number, x: number, y: number) -> (),
	up: (id: number, x: number, y: number) -> (),
	focusLost: () -> (),
	frame: () -> (), -- runs every task.delay callback due by the clock now
	fireTimers: () -> (), -- runs every pending task.delay callback, due or not (a timer that fires early)
	relayout: (b: any) -> (), -- what the buttons hook returns from now on (a turn, the top bar)
}

local function controls(aim: Maze.Heading?): World
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
	local began, changed, ended, focus = signal(), signal(), signal(), signal()
	local delayed: { { at: number, fn: () -> () } } = {}
	local current: any = PLACED
	local inputs: { [number]: any } = {}
	local clock = { now = 100 }
	local points: { any } = {}
	local knobs: { any } = {}
	local held: { boolean } = {}
	local function input(id: number, x: number, y: number): any
		local i = inputs[id] or { UserInputType = enum.UserInputType.Touch, Position = { X = x, Y = y } }
		inputs[id] = i
		i.Position = { X = x, Y = y }
		return i
	end
	local services: { [string]: any } = {
		ContextActionService = { BindActionAtPriority = function() end },
		GuiService = {
			GetInsetArea = function(_: any, _which: any): any
				return { Min = { X = 0, Y = 0 }, Max = { X = 844, Y = 390 } }
			end,
		},
		ReplicatedStorage = {
			WaitForChild = function(_: any, _name: string): any
				return remotes
			end,
		},
		UserInputService = {
			InputBegan = began,
			InputChanged = changed,
			InputEnded = ended,
			WindowFocusReleased = focus,
		},
	}
	local env = {
		game = {
			GetService = function(_: any, name: string): any
				return services[name] or anything()
			end,
		},
		workspace = { CurrentCamera = { ViewportSize = { X = 844, Y = 390 } } },
		Enum = enum,
		os = {
			clock = function(): number
				return clock.now
			end,
		},
		task = {
			delay = function(seconds: number, fn: () -> ())
				table.insert(delayed, { at = clock.now + seconds, fn = fn })
			end,
		},
		require = requirer(),
	}
	local Controls = luau.load(script("Controls").Source, { environment = env, debugName = "Controls" })()
	Controls.keys({
		arrows = function() end,
		aim = function(): Maze.Heading?
			return aim
		end,
		point = function(q: number?)
			table.insert(points, if q == nil then "nil" else q)
		end,
	})
	Controls.start(function() end, function(h: boolean)
		table.insert(held, h)
	end, function(): any
		return current
	end, function(k: any)
		table.insert(knobs, k)
	end)
	return {
		fired = fired,
		points = points,
		knobs = knobs,
		held = held,
		clock = clock,
		down = function(id: number, x: number, y: number)
			began.fire(input(id, x, y), false)
		end,
		move = function(id: number, x: number, y: number)
			changed.fire(input(id, x, y), false)
		end,
		up = function(id: number, x: number, y: number)
			ended.fire(input(id, x, y), false)
			inputs[id] = nil
		end,
		focusLost = function()
			focus.fire()
		end,
		frame = function()
			local due: { () -> () } = {}
			for i = #delayed, 1, -1 do
				local entry = delayed[i]
				if entry.at <= clock.now then
					table.remove(delayed, i)
					table.insert(due, 1, entry.fn)
				end
			end
			for _, fn in due do
				fn()
			end
		end,
		fireTimers = function()
			local all = delayed
			delayed = {}
			for _, entry in all do
				entry.fn()
			end
		end,
		relayout = function(b: any)
			current = b
		end,
	}
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

local S, L = PLACED.steer, PLACED.look

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
-- find: a frame by name under the Hud ScreenGui that HudView parented to the player's PlayerGui (lesson
-- drawn-from-the-visible-root); screen: a new screen size and core-UI inset, as a turn or a notch gives
type HudWorld = {
	find: (name: string) -> Inst?,
	render: () -> (),
	hud: any,
	layout: () -> Hud.Layout,
	screen: (w: number, h: number, c: Core) -> (),
}

local function hudView(touch: boolean, core: Core?): HudWorld
	local rendered: { () -> () } = {}
	local c: Core = core or { left = 0, top = 0, right = 0, bottom = 0 }
	-- both areas as GetInsetArea reports them: relative to the core-UI area's top-left (Hud.safeInset)
	local area = { Min = { X = -c.left, Y = -c.top }, Max = { X = 844 - c.left, Y = 390 - c.top } }
	local safe = { Min = { X = 0, Y = 0 }, Max = { X = 844 - c.left - c.right, Y = 390 - c.top - c.bottom } }
	local viewport = { X = 844, Y = 390 }
	local playerGui = instance("PlayerGui")
	local services: { [string]: any } = {
		GuiService = {
			GetInsetArea = function(_: any, which: any): any
				return if which.Name == "CoreUISafeInsets" then safe else area
			end,
		},
		Players = {
			LocalPlayer = {
				WaitForChild = function(_: any, _name: string): Inst
					return playerGui
				end,
			},
		},
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
		Instance = { new = instance },
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
		find = function(name: string): Inst?
			local gui = playerGui:FindFirstChild("Hud")
			return if gui and gui.ClassName == "ScreenGui" then gui:FindFirstChild(name) else nil
		end,
		hud = hud,
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
			area.Min = { X = -nc.left, Y = -nc.top }
			area.Max = { X = w - nc.left, Y = h - nc.top }
			safe.Max = { X = w - nc.left - nc.right, Y = h - nc.top - nc.bottom }
		end,
	}
end

local function at(f: Inst?): (number, number, number, number)
	assert(f, "no frame")
	return f.Position.x, f.Position.y, f.Size.x, f.Size.y
end

local function stripped(name: string): string
	local src = script(name).Source :: string
	return (string.gsub(string.gsub(src, "%-%-%[%[.-%]%]", ""), "%-%-[^\n]*", ""))
end

return t.spec("d0149 the touch adapters", function(it)
	it("a pull on the steer circle sends that turn on the Intent remote, once a push", function()
		local w = controls("E")
		w.down(1, S.x, S.y)
		w.move(1, S.x - S.r * 0.9, S.y) -- left
		w.move(1, S.x - S.r * 0.95, S.y + 2)
		t.expect(w.fired).toEqual({ "Left" })
		w.up(1, S.x - S.r * 0.95, S.y + 2)
		w.down(2, S.x, S.y)
		w.move(2, S.x, S.y + S.r * 0.9) -- down
		t.expect(w.fired).toEqual({ "Left", "Back" })
	end)

	it("two quick pulls up boost (f0143's touch taps); two slow pulls up do not", function()
		local w = controls("E")
		w.down(1, S.x, S.y)
		w.move(1, S.x, S.y - S.r * 0.9)
		w.move(1, S.x, S.y)
		w.clock.now += 0.1
		w.move(1, S.x, S.y - S.r * 0.9)
		t.expect(w.fired).toEqual({ "Forward", "Forward", Boost.INTENT })
		local slow = controls("E")
		slow.down(1, S.x, S.y)
		slow.move(1, S.x, S.y - S.r * 0.9)
		slow.move(1, S.x, S.y)
		slow.clock.now += 5
		slow.move(1, S.x, S.y - S.r * 0.9)
		t.expect(count(slow.fired, Boost.INTENT)).toBe(0)
	end)

	it("a short tap on the look circle hops on the lift; a long press or a pull does not", function()
		local w = controls("E")
		w.down(1, L.x, L.y)
		t.expect(#w.fired).toBe(0)
		w.clock.now += 0.1
		w.up(1, L.x + 2, L.y)
		t.expect(w.fired).toEqual({ Hop.INTENT })
		local long = controls("E")
		long.down(1, L.x, L.y)
		long.clock.now += 0.3
		long.up(1, L.x, L.y)
		t.expect(#long.fired).toBe(0)
		local pull = controls("E")
		pull.down(1, L.x, L.y)
		pull.move(1, L.x - L.r, L.y)
		pull.up(1, L.x - L.r, L.y)
		t.expect(#pull.fired).toBe(0)
	end)

	it(
		"a pull on the look circle points the camera through Controls.keys, and the lift lets it go",
		function()
			local w = controls("E")
			w.down(1, L.x, L.y)
			w.move(1, L.x - L.r * 0.8, L.y) -- left
			w.move(1, L.x, L.y + L.r * 0.8) -- behind
			w.up(1, L.x, L.y + L.r * 0.8)
			t.expect(w.points[1]).toBeNear(1, 1e-9) -- going down pointed nothing: it might have been a tap
			t.expect(w.points[2]).toBeNear(2, 1e-9)
			t.expect(w.points[#w.points]).toBe("nil")
			t.expect(#w.fired).toBe(0) -- looking sends nothing to the server
		end
	)

	it(
		"a thumb held still off the look circle's centre points the view on the frame TAP_SECONDS after it went down",
		function()
			local w = controls("E")
			w.down(1, L.x + L.r * 0.6, L.y)
			w.frame()
			t.expect(#w.points).toBe(0)
			w.clock.now += Touch.TAP_SECONDS
			w.frame()
			t.expect(#w.points).toBe(1)
			t.expect(w.points[1]).toBeNear(-1, 1e-9) -- right of the centre: a quarter right
			w.frame()
			t.expect(#w.points).toBe(1)
			w.up(1, L.x + L.r * 0.6, L.y)
			t.expect(w.points[2]).toBe("nil")
			t.expect(#w.fired).toBe(0) -- held too long for a tap: no hop
		end
	)

	it(
		"a thumb held still points when its timer fires, even a moment before the clock says the time is up",
		function()
			local w = controls("E")
			w.down(1, L.x + L.r * 0.6, L.y)
			w.clock.now += Touch.TAP_SECONDS - 0.001
			w.fireTimers()
			t.expect(#w.points).toBe(1)
			t.expect(w.points[1]).toBeNear(-1, 1e-9)
		end
	)

	it(
		"a timer firing after its finger lifted does nothing, and the look circle works for the next finger",
		function()
			local w = controls("E")
			w.down(1, L.x + L.r * 0.6, L.y)
			w.clock.now += 0.1
			w.up(1, L.x + L.r * 0.6, L.y)
			t.expect(w.fired).toEqual({ Hop.INTENT })
			w.clock.now += 1
			w.fireTimers()
			t.expect(#w.points).toBe(0) -- the tap never swings the view, even late
			w.down(2, L.x, L.y)
			w.move(2, L.x - L.r, L.y)
			t.expect(w.points[1]).toBeNear(1, 1e-9) -- the look circle is free again
			w.up(2, L.x - L.r, L.y)
			t.expect(w.points[2]).toBe("nil")
		end
	)

	it(
		"a timer firing after focus was lost or the controls moved does nothing, and a new finger works",
		function()
			for _, how in { "focus", "relayout" } do
				local w = controls("E")
				w.down(1, L.x + L.r * 0.6, L.y)
				local look = L
				if how == "focus" then
					w.focusLost()
				else
					local moved = table.clone(PLACED)
					moved.look = { x = L.x - 60, y = L.y, r = L.r }
					look = moved.look
					w.relayout(moved)
					w.down(9, 1, 1) -- any touch reads the moved controls
					w.up(9, 1, 1)
				end
				local n = #w.points
				w.clock.now += 1
				w.fireTimers()
				t.expect(#w.points).toBe(n) -- nothing from the old finger
				w.down(2, look.x, look.y)
				w.move(2, look.x, look.y + look.r)
				t.expect(w.points[#w.points]).toBeNear(2, 1e-9) -- behind: the new finger points
			end
		end
	)

	it(
		"an old timer that fires while a second look finger is down leaves the second alone: a double tap hops twice",
		function()
			local w = controls("E")
			w.clock.now = 100
			w.down(1, L.x + L.r * 0.6, L.y)
			w.clock.now = 100.1
			w.up(1, L.x + L.r * 0.6, L.y)
			w.clock.now = 100.15
			w.down(2, L.x + L.r * 0.6, L.y) -- the second tap is down when the first tap's timer fires
			w.clock.now = 100.25
			w.frame() -- only the first timer is due
			t.expect(#w.points).toBe(0)
			w.clock.now = 100.3
			w.up(2, L.x + L.r * 0.6, L.y)
			t.expect(w.fired).toEqual({ Hop.INTENT, Hop.INTENT })
			t.expect(#w.points).toBe(0)
		end
	)

	it(
		"after focus loss or a re-layout, the old finger's timer leaves a new tap alone (ids are never reused)",
		function()
			for _, how in { "focus", "relayout" } do
				local w = controls("E")
				w.clock.now = 100
				w.down(1, L.x + L.r * 0.6, L.y)
				local look = L
				if how == "focus" then
					w.focusLost()
				else
					local moved = table.clone(PLACED)
					moved.look = { x = L.x - 60, y = L.y, r = L.r }
					look = moved.look
					w.relayout(moved)
				end
				w.clock.now = 100.1
				w.down(2, look.x + look.r * 0.6, look.y)
				local n = #w.points
				w.clock.now = 100.25
				w.frame() -- the old finger's timer, with the new tap down
				t.expect(#w.points).toBe(n)
				w.clock.now = 100.3
				w.up(2, look.x + look.r * 0.6, look.y)
				t.expect(w.fired).toEqual({ Hop.INTENT })
				t.expect(#w.points).toBe(n)
			end
		end
	)

	it("a tap off the look circle's centre hops and never points the view", function()
		local w = controls("E")
		w.down(1, L.x + L.r * 0.6, L.y + 3)
		w.clock.now += 0.1
		w.frame()
		w.up(1, L.x + L.r * 0.6 + 4, L.y + 3)
		t.expect(w.fired).toEqual({ Hop.INTENT })
		t.expect(#w.points).toBe(0)
	end)

	it(
		"when the controls move (a turn, the top bar), every held finger is let go and pulls nothing more",
		function()
			local w = controls("E")
			w.down(1, S.x, S.y)
			w.down(2, L.x, L.y)
			w.move(2, L.x - L.r, L.y)
			local moved = table.clone(PLACED)
			moved.steer = { x = S.x + 60, y = S.y, r = S.r }
			moved.look = { x = L.x - 60, y = L.y, r = L.r }
			w.relayout(moved)
			w.move(1, S.x + 1, S.y) -- would be a hard pull left from the moved circle's centre
			t.expect(#w.fired).toBe(0)
			t.expect(w.points[#w.points]).toBe("nil") -- the view springs back
			t.expect((next(w.knobs[#w.knobs]))).toBe(nil)
			local n = #w.points
			w.move(2, L.x - L.r - 20, L.y)
			t.expect(#w.points).toBe(n) -- the look finger is let go too
			w.up(1, S.x + 1, S.y)
			w.up(2, L.x, L.y)
			w.down(3, moved.steer.x - moved.steer.r * 0.9, moved.steer.y) -- a new finger uses the new place
			t.expect(w.fired).toEqual({ "Left" })
		end
	)

	it(
		"a new layout table in the same places keeps every held finger (a HUD refresh is no re-layout)",
		function()
			local w = controls("E")
			w.down(1, S.x, S.y)
			local copy = {
				steer = table.clone(PLACED.steer),
				look = table.clone(PLACED.look),
				fire = table.clone(PLACED.fire),
				pick = table.clone(PLACED.pick),
			}
			w.relayout(copy)
			w.move(1, S.x - S.r * 0.9, S.y)
			t.expect(w.fired).toEqual({ "Left" }) -- still steering
			t.expect(#w.points).toBe(0)
		end
	)

	it("losing focus while the look circle is held lets the view go and centres the knobs", function()
		local w = controls("E")
		w.down(1, L.x, L.y)
		w.move(1, L.x - L.r, L.y)
		w.focusLost()
		t.expect(w.points[#w.points]).toBe("nil")
		t.expect((next(w.knobs[#w.knobs]))).toBe(nil)
		t.expect(w.held[#w.held]).toBe(false)
	end)

	it(
		"FIRE sends the aimed shot, as E does; PICK sends the pick, as F does; each on the finger going down",
		function()
			local w = controls("N")
			w.down(1, PLACED.fire.x + 1, PLACED.fire.y + 1)
			t.expect(w.fired).toEqual({ Blaster.intent("N") })
			w.up(1, PLACED.fire.x + 1, PLACED.fire.y + 1)
			w.down(2, PLACED.pick.x + 1, PLACED.pick.y + 1)
			t.expect(w.fired).toEqual({ Blaster.intent("N"), View.PICK_INTENT })
			local none = controls(nil)
			none.down(1, PLACED.fire.x + 1, PLACED.fire.y + 1)
			t.expect(#none.fired).toBe(0) -- no aim yet: no shot
		end
	)

	it("a finger anywhere else sends nothing, points nothing, and still holds the mouse", function()
		local w = controls("E")
		w.down(1, 422, 60)
		w.move(1, 300, 60)
		w.move(1, 700, 200)
		w.up(1, 700, 200)
		t.expect(#w.fired).toBe(0)
		t.expect(#w.points).toBe(0)
		t.expect(w.held).toEqual({ true, false })
	end)

	it("the knobs hook gets Touch.knobs after each touch", function()
		local w = controls("E")
		w.down(1, S.x, S.y)
		w.move(1, S.x, S.y - 3 * S.r)
		local k = w.knobs[#w.knobs]
		t.expect(k.steer.x).toBeNear(S.x, 1e-9)
		t.expect(k.steer.y).toBeNear(S.y - S.r, 1e-9)
		w.up(1, S.x, S.y - 3 * S.r)
		t.expect((next(w.knobs[#w.knobs]))).toBe(nil)
	end)

	it("Camera looks and aims by the point it is given, and the arrows keep it", function()
		local env = {
			game = {
				GetService = function(): any
					return anything()
				end,
			},
			workspace = { CurrentCamera = {} },
			Enum = enumProxy(),
			os = os,
			require = requirer(),
		}
		local Camera = luau.load(script("Camera").Source, { environment = env, debugName = "Camera" })()
		local snap = { tick = 1, player = { heading = "N" } }
		Camera.push(snap)
		t.expect(Camera.aim()).toBe("N")
		Camera.point(1) -- pulled left
		t.expect(Camera.aim()).toBe(Maze.left("N"))
		Camera.arrows({ up = false, down = false, left = false, right = false })
		t.expect(Camera.aim()).toBe(Maze.left("N")) -- the arrows' entry keeps the point
		Camera.arrows({ up = false, down = false, left = false, right = true })
		t.expect(Camera.aim()).toBe(Maze.right("N")) -- a held arrow wins
		Camera.arrows({ up = false, down = false, left = false, right = false })
		Camera.point(nil)
		t.expect(Camera.aim()).toBe("N")
		t.expect(Camera.lookBy).toBe(nil) -- the drag look is gone
	end)

	it(
		"HudView draws both circles, their knobs, FIRE and PICK where Touch.buttons puts them, and no snap or JUMP",
		function()
			local h = hudView(true)
			h.render()
			local b = Touch.buttons(h.layout())
			local circles: { [string]: any } = { Steer = b.steer, Look = b.look }
			for name, c in circles do
				local f = h.find(name)
				local x, y, sw, sh = at(f)
				t.expect({ x, y, sw, sh }).toEqual({ c.x - c.r, c.y - c.r, 2 * c.r, 2 * c.r })
				local frame = f :: Inst
				t.expect(frame.ClassName).toBe("Frame")
				t.expect(frame.Visible).toBe(true)
				t.expect(frame.Active).toBe(false)
				t.expect(frame.BackgroundColor3).toEqual({ r = 255, g = 255, b = 255 })
				t.expect(frame.BackgroundTransparency).toBe(0.8)
				local classes: { [string]: boolean } = {}
				for _, child in frame:GetChildren() do
					classes[child.ClassName] = true
				end
				t.expect(classes.UICorner == true and classes.UIStroke == true).toBe(true)
			end
			local rects: { [string]: any } = { Fire = b.fire, Pick = b.pick }
			for name, r in rects do
				local x, y, sw, sh = at(h.find(name))
				t.expect({ x, y, sw, sh }).toEqual({ r.x, r.y, r.w, r.h })
				t.expect((h.find(name) :: Inst).Visible).toBe(true)
			end
			t.expect((h.find("Fire") :: Inst).BackgroundColor3).toEqual({ r = 0, g = 255, b = 255 })
			t.expect((h.find("Pick") :: Inst).BackgroundColor3).toEqual({ r = 255, g = 215, b = 0 })
			-- the knobs start at their circles' centres, 0.4 of the diameter, half transparent
			local knobs: { [string]: any } = { SteerKnob = b.steer, LookKnob = b.look }
			for name, c in knobs do
				local kx, ky, kw, kh = at(h.find(name))
				t.expect(kw).toBeNear(0.8 * c.r, 1e-9)
				t.expect(kh).toBeNear(0.8 * c.r, 1e-9)
				t.expect(kx + kw / 2).toBeNear(c.x, 1e-9)
				t.expect(ky + kh / 2).toBeNear(c.y, 1e-9)
				t.expect((h.find(name) :: Inst).BackgroundTransparency).toBe(0.5)
			end
			t.expect(h.find("Snap")).toBe(nil)
			t.expect(h.find("Hop")).toBe(nil)
			t.expect(h.hud.buttons()).toEqual(b)
			t.expect(h.hud.snapRect).toBe(nil)
		end
	)

	it("HudView places the controls by the layout's inset, and again when the screen turns", function()
		local h = hudView(true, { left = 47, top = 0, right = 0, bottom = 21 })
		h.render()
		local b = Touch.buttons(h.layout())
		t.expect(b.steer.x - b.steer.r).toBe(47 + h.layout().margin) -- the notch's inset is kept
		local x, y = at(h.find("Steer"))
		t.expect({ x, y }).toEqual({ b.steer.x - b.steer.r, b.steer.y - b.steer.r })
		h.screen(390, 844, { left = 0, top = 47, right = 0, bottom = 34 })
		h.render()
		local turned = Touch.buttons(h.layout())
		local lx, ly, lw = at(h.find("Look"))
		t.expect({ lx, ly, lw })
			.toEqual({ turned.look.x - turned.look.r, turned.look.y - turned.look.r, 2 * turned.look.r })
		local px, py = at(h.find("Pick"))
		t.expect({ px, py }).toEqual({ turned.pick.x, turned.pick.y })
		local kx, _, kw = at(h.find("LookKnob"))
		t.expect(kx + kw / 2).toBeNear(turned.look.x, 1e-9) -- the knobs move with their circles
		t.expect(h.hud.buttons()).toEqual(turned)
	end)

	it("HudView puts each knob at the point it is given, and back at the centre without one", function()
		local h = hudView(true)
		h.render()
		local b = h.hud.buttons()
		h.hud.knobs({ look = { x = b.look.x - b.look.r, y = b.look.y } })
		local x, y, s = at(h.find("LookKnob"))
		t.expect(x + s / 2).toBeNear(b.look.x - b.look.r, 1e-9)
		t.expect(y + s / 2).toBeNear(b.look.y, 1e-9)
		h.hud.knobs({})
		x, y, s = at(h.find("LookKnob"))
		t.expect(x + s / 2).toBeNear(b.look.x, 1e-9)
	end)

	it("a HUD refresh (a shot, a life) leaves a pulled knob where its thumb is; a turn centres it", function()
		local h = hudView(true)
		h.render()
		local b = h.hud.buttons()
		local p = { x = b.steer.x - b.steer.r, y = b.steer.y }
		h.hud.knobs({ steer = p })
		h.hud.shots(2)
		h.hud.show(
			{ phase = "playing", level = 1, score = 0, lives = 2, timer = 0, frightened = 0 } :: Session.PlayFrame
		)
		h.render()
		local x, y, s = at(h.find("SteerKnob"))
		t.expect(x + s / 2).toBeNear(p.x, 1e-9)
		t.expect(y + s / 2).toBeNear(p.y, 1e-9)
		h.screen(390, 844, { left = 0, top = 47, right = 0, bottom = 34 })
		h.render()
		local turned = h.hud.buttons()
		x, y, s = at(h.find("SteerKnob"))
		t.expect(x + s / 2).toBeNear(turned.steer.x, 1e-9)
		t.expect(y + s / 2).toBeNear(turned.steer.y, 1e-9)
	end)

	it("a screen without touch shows none of the touch controls", function()
		local h = hudView(false)
		h.render()
		for _, name in { "Steer", "Look", "SteerKnob", "LookKnob", "Fire", "Pick" } do
			t.expect((h.find(name) :: Inst).Visible).toBe(false)
		end
	end)

	it("Main hands Controls the camera's point and HudView's controls and knobs", function()
		local main = stripped("Main")
		t.expect(string.find(main, "point%s*=%s*Camera%.point") ~= nil).toBe(true)
		local call = string.match(main, "Controls%.start%((.-)%)\n")
		t.expect(call ~= nil).toBe(true)
		local args = string.gsub(call :: string, "%s", "")
		t.expect(args).toBe("Camera.snap,Camera.holdMouse,HudView.buttons,HudView.knobs")
	end)
end)
