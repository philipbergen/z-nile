--!strict
-- f0143 AC3 (design review 002 F3): HudView's real source runs on a stub engine (hud-shots.spec's, with a side inset
-- and a loader that falls back to the real Logic modules), so the boost's chevron is pinned where the player sees
-- it: at the lives block's corner plus Hud.boostIcon(l, lives shown, shots held) in the safe area, re-laid when the
-- lives, the shots or the screen change; yellow when ready, white while boosting, grey (90) while cooling; hidden
-- before the first status.
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

type Hv = {
	start: () -> (),
	show: (Session.PlayFrame) -> (),
	shots: (number?) -> (),
	boost: (string) -> (),
}
type World =
	{ hud: Hv, render: () -> (), chevron: () -> Inst, resize: (number, number) -> (), area: () -> any }

local function start(): World
	local rendered: { () -> () } = {}
	local made: { Inst } = {}
	local area = { Min = { X = 0, Y = 0 }, Max = { X = 1000, Y = 600 } }
	-- the core UI's safe area: a side inset of 44 on the left (a notch) and 20 on the right
	local function core(): any
		return { Min = { X = area.Min.X + 44, Y = area.Min.Y }, Max = { X = area.Max.X - 20, Y = area.Max.Y } }
	end
	local viewport = { X = 1000, Y = 600 }
	local services: { [string]: any } = {
		GuiService = {
			GetInsetArea = function(_: any, which: any): any
				return if which.Name == "None" then area else core()
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
	local env = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], name)
			end,
		},
		workspace = { CurrentCamera = { ViewportSize = viewport } },
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
			local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
			return (require :: any)("@logic/" .. assert(name, spec))
		end,
		os = {
			clock = function(): number
				return 0
			end,
		},
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
		resize = function(w: number, h: number)
			area.Max = { X = w, Y = h }
			viewport.X, viewport.Y = w, h
		end,
		chevron = function(): Inst
			for _, i in made do
				if i.Name == "Boost" then
					return i
				end
			end
			error("no Boost chevron")
		end,
		area = function(): any
			return area
		end,
	}
end

local function play(lives: number): Session.PlayFrame
	return { phase = "playing", level = 1, score = 0, lives = lives, timer = 0, frightened = 0 }
end

-- where the chevron should be on a w x h screen with the stub's insets: the lives block's corner in the safe
-- layout plus Hud.boostIcon's box
local function want(lives: number, shots: number, w: number, h: number): { number }
	local none = { Min = { X = 0, Y = 0 }, Max = { X = w, Y = h } }
	local core = { Min = { X = 44, Y = 0 }, Max = { X = w - 20, Y = h } }
	local sw, sh = Touch.screenSize(none, w, h)
	local l = Hud.layout(sw, sh, Hud.safeInset(none, core))
	local block = Touch.blocks(l).lives
	local box = Hud.boostIcon(l, lives, shots)
	return { block.x + box.x, block.y + box.y, box.w, box.h }
end

local function at(c: Inst): { number }
	return { c.Position.x, c.Position.y, c.Size.x, c.Size.y }
end

return t.spec("f0143 the boost's chevron on the HUD", function(it)
	it(
		"sits after the shot bars in the safe area, and moves with the lives, the shots and the screen",
		function()
			local w = start()
			w.hud.show(play(3))
			w.hud.shots(2)
			w.render()
			local c = w.chevron()
			t.expect(at(c)).toEqual(want(3, 2, 1000, 600))
			t.expect(c.Position.x >= 44).toBe(true) -- inside the left inset
			w.hud.show(play(2))
			t.expect(at(c)).toEqual(want(2, 2, 1000, 600))
			w.hud.shots(0)
			t.expect(at(c)).toEqual(want(2, 0, 1000, 600))
			w.resize(600, 1000) -- the screen turns
			w.render()
			t.expect(at(c)).toEqual(want(2, 0, 600, 1000))
		end
	)

	it("is hidden before the first status, then yellow ready, white boosting, grey cooling", function()
		local w = start()
		w.render()
		local c = w.chevron()
		t.expect(c.Visible).toBe(false)
		w.hud.boost("ready")
		t.expect(c.Visible).toBe(true)
		t.expect(c.TextColor3).toEqual({ r = 255, g = 255, b = 0 })
		w.hud.boost("boosting")
		t.expect(c.TextColor3).toEqual({ r = 255, g = 255, b = 255 })
		w.hud.boost("cooling")
		t.expect(c.TextColor3).toEqual({ r = 90, g = 90, b = 90 })
		w.hud.boost("ready")
		t.expect(c.TextColor3).toEqual({ r = 255, g = 255, b = 0 })
	end)
end)
