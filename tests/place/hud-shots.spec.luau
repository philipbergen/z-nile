--!strict
-- R0035 code review 001 F2: HudView's real source runs on a small stub engine, with the real Hud, Session and
-- Touch, so the arguments it gives Hud.shotIcons (the lives shown and the shots held) are pinned by where the
-- bars end up, and so is the re-lay when either count changes.
local Hud = require("@logic/Hud")
local Session = require("@logic/Session")
local Touch = require("@logic/Touch")
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

local W, H = 1000, 600

type Inst = { [string]: any }

-- A stub instance: its properties are plain fields; setting Parent files it under its parent, in order.
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
			if key == "Parent" and value ~= nil then
				table.insert(value.children, self)
			end
			props[key] = value
		end,
	}) :: any
	return self
end

local function enumProxy(): any
	return setmetatable({}, {
		__index = function(self: any, group: string): any
			local g = setmetatable({}, {
				__index = function(gs: any, item: string): any
					local v = { Name = item, Value = 0 }
					rawset(gs, item, v)
					return v
				end,
			})
			rawset(self, group, g)
			return g
		end,
	})
end

type Hv = { start: () -> (), show: (Session.PlayFrame) -> (), shots: (number?) -> () }
type World = { hud: Hv, render: () -> (), gui: () -> Inst }

local function start(): World
	local rendered: { () -> () } = {}
	local made: { Inst } = {}
	local area = { Min = { X = 0, Y = 0 }, Max = { X = W, Y = H } }
	local services: { [string]: any } = {
		GuiService = {
			GetInsetArea = function(_: any, _which: any): any
				return area
			end,
		},
		Players = { LocalPlayer = instance("Player") },
		RunService = {
			BindToRenderStep = function(_: any, _name: string, _priority: number, fn: () -> ())
				table.insert(rendered, fn)
			end,
		},
		UserInputService = { TouchEnabled = false },
	}
	local modules: { [string]: any } = {
		["@game/ReplicatedStorage/Shared/Logic/Hud"] = Hud,
		["@game/ReplicatedStorage/Shared/Logic/Session"] = Session,
		["@game/ReplicatedStorage/Shared/Logic/Touch"] = Touch,
	}
	local env = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], name)
			end,
		},
		workspace = { CurrentCamera = { ViewportSize = { X = W, Y = H } } },
		Enum = enumProxy(),
		Instance = {
			new = function(class: string): Inst
				local i = instance(class)
				table.insert(made, i)
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
		Color3 = {
			fromRGB = function(r: number, g: number, b: number): any
				return { r = r, g = g, b = b }
			end,
		},
		require = function(spec: string): any
			return assert(modules[spec], spec)
		end,
	}
	local hud = luau.load(script("HudView").Source, { environment = env, debugName = "HudView" })() :: Hv
	hud.start()
	return {
		hud = hud,
		render = function()
			for _, fn in rendered do
				fn()
			end
		end,
		gui = function(): Inst
			for _, i in made do
				if i.Name == "Shots" then
					return i
				end
			end
			error("no Shots frame")
		end,
	}
end

local function play(lives: number): Session.PlayFrame
	return { phase = "playing", level = 1, score = 0, lives = lives, timer = 0, frightened = 0 }
end

-- where the stub frames ended up, as Hud boxes
local function placed(shots: Inst): { Hud.Box }
	local out = {}
	for _, icon in shots:GetChildren() do
		table.insert(out, { x = icon.Position.x, y = icon.Position.y, w = icon.Size.x, h = icon.Size.y })
	end
	return out
end

local function want(lives: number, shots: number): { Hud.Box }
	return Hud.shotIcons(Hud.layout(W, H, { top = 0, bottom = 0, left = 0, right = 0 }), lives, shots)
end

return t.spec("HudView shot bars", function(it)
	it("draws one bar per shot after the lives shown, at Hud.shotIcons' boxes", function()
		local w = start()
		w.hud.show(play(3))
		w.render()
		w.hud.shots(2)
		local got = placed(w.gui())
		t.expect(#got).toBe(2)
		t.expect(got).toEqual(want(3, 2))
		t.expect(got[1].x > 0).toBe(true) -- after the lives, not over them
	end)

	it("re-lays the bars when the lives change, and when the shots change", function()
		local w = start()
		w.hud.show(play(3))
		w.render()
		w.hud.shots(1)
		t.expect(placed(w.gui())).toEqual(want(3, 1))
		w.hud.show(play(2))
		t.expect(placed(w.gui())).toEqual(want(2, 1))
		w.hud.shots(3)
		t.expect(placed(w.gui())).toEqual(want(2, 3))
		w.hud.shots(nil) -- an older server's frame: no shots
		t.expect(placed(w.gui())).toEqual({})
	end)

	it("bars that arrive before the first layout are placed by it", function()
		local w = start()
		w.hud.show(play(1))
		w.hud.shots(2)
		w.render()
		t.expect(placed(w.gui())).toEqual(want(1, 2))
	end)
end)
