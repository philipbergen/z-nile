--!strict
-- R0012 code reviews 001 and 002: how the touch adapters call the Touch fold and act on what it returns. The
-- fold itself is pinned by the f0027-f0029 acceptance specs. Controls' real source runs here on its own small
-- stub engine (touch signals, one inset area, a recording Intent remote) with the real Touch and View, so its
-- wiring is pinned by what it does. Camera and HudView keep source pins for one line each.
local Blaster = require("@logic/Blaster")
local Hop = require("@logic/Hop")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Pad = require("@logic/Pad")
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

local function source(name: string): string
	return (string.gsub(script(name).Source, "%-%-[^\n]*", ""))
end

-- The text of `function <name>(` up to the first line that is exactly `end`.
local function body(src: string, name: string): string
	local s = string.find(src, "function " .. name .. "(", 1, true)
	t.expect(s ~= nil).toBe(true)
	local e = string.find(src, "\nend", s :: number, true)
	t.expect(e ~= nil).toBe(true)
	return string.sub(src, s :: number, e :: number)
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

-- Enum.<Group>.<Item> is a stable table per item, with a numeric Value, so identity compares work.
local function enumGroup(group: string): any
	return setmetatable({}, {
		__index = function(self: any, item: string): any
			local v = { Name = item, Value = 0, group = group }
			rawset(self, item, v)
			return v
		end,
	})
end

type World = {
	fired: { any },
	snaps: number,
	looks: { { number } },
	holds: { boolean },
	began: Signal,
	changed: Signal,
	ended: Signal,
	unfocused: Signal,
	touch: () -> any,
	enum: any,
	bound: { handler: any, codes: { any } },
	arrows: { View.Arrows },
}

type Keys = { aim: () -> Maze.Heading? }

-- Starts Controls on an 800 x 400 screen with the snap rectangle `rect` (nil: none passed). With `keys`,
-- Controls.keys is called first with that aim and a recording arrows hook.
local function start(rect: Touch.Rect?, keys: Keys?): World
	local enum = setmetatable({}, {
		__index = function(self: any, group: string): any
			local g = enumGroup(group)
			rawset(self, group, g)
			return g
		end,
	})
	local fired: { any } = {}
	local remote = {
		FireServer = function(_: any, intent: any)
			table.insert(fired, intent)
		end,
	}
	local remotes = {
		WaitForChild = function(_: any, name: string): any
			assert(name == "Intent", name)
			return remote
		end,
	}
	local world: World = {
		fired = fired,
		snaps = 0,
		looks = {},
		holds = {},
		began = signal(),
		changed = signal(),
		ended = signal(),
		unfocused = signal(),
		touch = function(): any
			return { UserInputType = enum.UserInputType.Touch, Position = { X = 0, Y = 0 } }
		end,
		enum = enum,
		bound = { handler = nil, codes = {} },
		arrows = {},
	}
	local services: { [string]: any } = {
		ContextActionService = {
			BindActionAtPriority = function(
				_: any,
				_name: string,
				handler: any,
				_button: boolean,
				_p: number,
				...: any
			)
				world.bound.handler = handler
				world.bound.codes = { ... }
			end,
		},
		GuiService = {
			GetInsetArea = function(_: any, _which: any): any
				return { Min = { X = 0, Y = 0 }, Max = { X = 800, Y = 400 } }
			end,
		},
		ReplicatedStorage = {
			WaitForChild = function(_: any, name: string): any
				assert(name == "Remotes", name)
				return remotes
			end,
		},
		UserInputService = {
			InputBegan = world.began,
			InputChanged = world.changed,
			InputEnded = world.ended,
			WindowFocusReleased = world.unfocused,
		},
	}
	local modules: { [string]: any } = {
		["@game/ReplicatedStorage/Shared/Logic/Blaster"] = Blaster,
		["@game/ReplicatedStorage/Shared/Logic/Pad"] = Pad,
		["@game/ReplicatedStorage/Shared/Logic/Hop"] = Hop,
		["@game/ReplicatedStorage/Shared/Logic/Maze"] = Maze,
		["@game/ReplicatedStorage/Shared/Logic/Movement"] = Movement,
		["@game/ReplicatedStorage/Shared/Logic/Touch"] = Touch,
		["@game/ReplicatedStorage/Shared/Logic/View"] = View,
	}
	local env = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], name)
			end,
		},
		workspace = { CurrentCamera = { ViewportSize = { X = 800, Y = 400 } } },
		Enum = enum,
		require = function(spec: string): any
			return assert(modules[spec], spec)
		end,
	}
	local Controls = luau.load(script("Controls").Source, { environment = env, debugName = "Controls" })()
	if keys then
		Controls.keys({
			arrows = function(a: View.Arrows)
				table.insert(world.arrows, table.clone(a))
			end,
			aim = keys.aim,
		})
	end
	Controls.start(
		function()
			world.snaps += 1
		end,
		function(dx: number, dy: number)
			table.insert(world.looks, { dx, dy })
		end,
		if rect
			then function(): Touch.Rect?
				return rect
			end
			else nil,
		function(held: boolean)
			table.insert(world.holds, held)
		end
	)
	return world
end

local function at(input: any, x: number, y: number): any
	input.Position = { X = x, Y = y }
	return input
end

return t.spec("touch adapters", function(it)
	it("Controls hit-tests the called snap rectangle, even on the look half", function()
		local w = start({ x = 600, y = 300, w = 44, h = 44 })
		local a = w.touch()
		w.began.fire(at(a, 610, 310), false)
		w.changed.fire(at(a, 640, 320), false)
		w.ended.fire(at(a, 640, 320), false)
		t.expect(w.snaps).toBe(1)
		t.expect(w.looks).toEqual({})
		t.expect(w.fired).toEqual({})
	end)

	it("Controls fires a swipe's intent and looks by dx then dy", function()
		local w = start(nil)
		local turn, look = w.touch(), w.touch()
		w.began.fire(at(turn, 200, 200), false)
		w.ended.fire(at(turn, 120, 200), false)
		t.expect(w.fired).toEqual({ "Left" })
		w.began.fire(at(look, 600, 100), false)
		w.changed.fire(at(look, 630, 90), false)
		t.expect(w.looks).toEqual({ { 30, -10 } })
		t.expect(w.snaps).toBe(0)
	end)

	it("Controls reports held only on a change, while any physical touch is down", function()
		local w = start(nil)
		local a, b = w.touch(), w.touch()
		w.began.fire(at(a, 100, 200), false)
		w.began.fire(at(b, 150, 200), false) -- ignored by the fold: the turn zone is taken
		w.changed.fire(at(b, 160, 200), false)
		w.ended.fire(at(a, 100, 200), false)
		t.expect(w.holds).toEqual({ true })
		w.ended.fire(at(b, 160, 200), false)
		t.expect(w.holds).toEqual({ true, false })
	end)

	it("Controls drops every finger when the window loses focus, so the zone is free again", function()
		local w = start(nil)
		local lost, fresh = w.touch(), w.touch()
		w.began.fire(at(lost, 200, 200), false)
		w.unfocused.fire()
		t.expect(w.holds).toEqual({ true, false })
		w.ended.fire(at(lost, 100, 200), false)
		t.expect(w.fired).toEqual({})
		w.began.fire(at(fresh, 200, 200), false)
		w.ended.fire(at(fresh, 280, 200), false)
		t.expect(w.fired).toEqual({ "Right" })
		t.expect(w.holds).toEqual({ true, false, true, false })
	end)

	it(
		"Camera.holdMouse also skips the mouse delta of the frame in which a finger went down or up",
		function()
			local hold = body(source("Camera"), "Camera.holdMouse")
			t.expect(string.find(hold, "mouseHeld = held", 1, true) ~= nil).toBe(true)
			t.expect(string.find(hold, "lookedThisFrame = true", 1, true) ~= nil).toBe(true)
		end
	)

	it("HudView shows the snap frame only on a touch screen", function()
		local src = source("HudView")
		t.expect(string.find(src, "s.Visible = UserInputService.TouchEnabled", 1, true) ~= nil).toBe(true)
	end)
	-- R0035 code review 001 F1: Controls' key handler runs here, so its branches are pinned by what it does.
	local function press(w: World, key: string, state: string): any
		return w.bound.handler("PickmanControls", w.enum.UserInputState[state], { KeyCode = { Name = key } })
	end

	local function arrowsOf(up: boolean, down: boolean, left: boolean, right: boolean): View.Arrows
		return { up = up, down = down, left = left, right = right }
	end

	it(
		"Controls binds exactly the keys of View.KEYS and Pad.BUTTONS, and sinks every one but the pad's continue",
		function()
			local w = start(nil)
			local names = {}
			for _, code in w.bound.codes do
				table.insert(names, code.Name)
			end
			table.sort(names)
			local wantNames = {}
			for name in View.KEYS do
				table.insert(wantNames, name)
			end
			for name in Pad.BUTTONS do
				table.insert(wantNames, name)
			end
			table.sort(wantNames)
			t.expect(names).toEqual(wantNames)
			for name in View.KEYS do
				t.expect(press(w, name, "Begin")).toBe(w.enum.ContextActionResult.Sink)
				t.expect(press(w, name, "End")).toBe(w.enum.ContextActionResult.Sink)
			end
		end
	)

	it("Controls sends W A S D as movement intents on the key going down only", function()
		local w = start(nil)
		for _, key in { "W", "A", "S", "D" } do
			press(w, key, "Begin")
			press(w, key, "End")
		end
		t.expect(w.fired).toEqual({ "Forward", "Left", "Back", "Right" })
	end)

	it("Controls holds an arrow from down to up, and a cancelled input lets it go", function()
		local w = start(nil, {
			aim = function(): Maze.Heading?
				return "N"
			end,
		})
		press(w, "Up", "Begin")
		press(w, "Left", "Begin")
		press(w, "Up", "Begin") -- no change: no second report
		press(w, "Up", "End")
		press(w, "Left", "Cancel")
		press(w, "Right", "Change") -- neither down nor up: nothing
		t.expect(w.arrows).toEqual({
			arrowsOf(true, false, false, false),
			arrowsOf(true, false, true, false),
			arrowsOf(false, false, true, false),
			arrowsOf(false, false, false, false),
		})
		press(w, "Down", "Begin")
		press(w, "Down", "End")
		t.expect(w.arrows[5]).toEqual(arrowsOf(false, true, false, false))
		t.expect(w.arrows[6]).toEqual(arrowsOf(false, false, false, false))
		t.expect(w.fired).toEqual({}) -- looking sends nothing to the server
	end)

	it("Controls fires the aimed shot on E, and nothing with no aim or no camera", function()
		local aim: Maze.Heading? = "E"
		local w = start(nil, {
			aim = function(): Maze.Heading?
				return aim
			end,
		})
		press(w, "E", "Begin")
		press(w, "E", "End")
		aim = "S"
		press(w, "E", "Begin")
		aim = nil -- before the first snapshot
		press(w, "E", "Begin")
		t.expect(w.fired).toEqual({ Blaster.intent("E"), Blaster.intent("S") })
		local bare = start(nil) -- Controls.keys never called
		press(bare, "E", "Begin")
		t.expect(bare.fired).toEqual({})
	end)

	it("Controls sends the hop intent on Space going down, and Space no longer snaps", function()
		local w = start(nil)
		press(w, "Space", "Begin")
		press(w, "Space", "End")
		t.expect(w.fired).toEqual({ Hop.INTENT })
		t.expect(w.snaps).toBe(0)
	end)
end)
