--!strict
-- Narrowed by c0182: dropped the five Controls.start cases (old 5-arg signature and JUMP button; taken over by
-- d0149/acceptance/adapters.spec) and the Hop (JUMP) frame assertions in HudView (d0149 removes JUMP). Keeps HudView's
-- FIRE button drawing, re-layout, inset placement, touch-only visibility, read-only HUD, and Main's HudView.buttons.
-- f0110 AC3: the adapters. Controls' real source runs on a small stub engine (touch signals, one inset area, a
-- recording Intent remote) with the real Touch and View, as tests/place/touch-adapters does: a tap on the fire
-- button sends Blaster.intent of the camera's aim, the same as E; a tap on the hop button sends Hop.INTENT, the
-- same as Space; the rectangles are read from the called buttons hook on every event. HudView's real source runs
-- on a stub engine as tests/place/hud-shots does: on a touch screen it draws a non-active Fire and Hop frame at
-- Touch.buttons' rectangles, re-lays them when the screen changes, and HudView.buttons reports them. Main hands
-- HudView.buttons to Controls.start.
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

local function source(name: string): string
	return (string.gsub(script(name).Source, "%-%-[^\n]*", ""))
end

type Rect = { x: number, y: number, w: number, h: number }
type Buttons = { snap: Rect, fire: Rect, hop: Rect }

-- Enum.<Group>.<Item> is a stable table per item, so identity compares work.
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

local function requirer(modules: { [string]: any }): (string) -> any
	return function(spec: string): any
		local given = modules[spec]
		if given ~= nil then
			return given
		end
		local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
		if name then
			return (require :: any)("@logic/" .. name)
		end
		error(`unexpected require {spec}`)
	end
end

-- Controls ------------------------------------------------------------------------------------------------------

-- HudView -------------------------------------------------------------------------------------------------------

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

type Hv = { start: () -> (), show: (Session.PlayFrame) -> (), buttons: () -> Buttons? }
type Screen = {
	hud: Hv,
	render: () -> (),
	frame: (name: string) -> Inst,
	resize: (number, number) -> (),
	notch: (left: number, top: number, right: number, bottom: number) -> (),
}

-- HudView on a 1000 x 600 screen with no inset. `notch` keeps pixels on each edge for the device: both areas are
-- then reported relative to the core-UI area's top-left, as GetInsetArea reports them (f0029).
local function hudView(touch: boolean): Screen
	local rendered: { () -> () } = {}
	local area = { Min = { X = 0, Y = 0 }, Max = { X = 1000, Y = 600 } }
	local core = { Min = { X = 0, Y = 0 }, Max = { X = 1000, Y = 600 } }
	local viewport = { X = 1000, Y = 600 }
	local playerGui = instance("PlayerGui") -- what is drawn hangs under it
	local services: { [string]: any } = {
		GuiService = {
			GetInsetArea = function(_: any, which: any): any
				return if which.Name == "CoreUISafeInsets" then core else area
			end,
		},
		Players = {
			LocalPlayer = {
				WaitForChild = function(_: any, name: string): Inst
					assert(name == "PlayerGui", name)
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
		workspace = { CurrentCamera = { ViewportSize = viewport } },
		Enum = enumProxy(),
		Instance = {
			new = function(class: string): Inst
				return instance(class)
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
		require = requirer(modules),
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
			area.Min = { X = 0, Y = 0 }
			area.Max = { X = w, Y = h }
			core.Max = { X = w, Y = h }
			viewport.X, viewport.Y = w, h
		end,
		notch = function(left: number, top: number, right: number, bottom: number)
			local w, h = viewport.X, viewport.Y
			area.Min = { X = -left, Y = -top }
			area.Max = { X = w - left, Y = h - top }
			core.Max = { X = w - left - right, Y = h - top - bottom }
		end,
		-- the named frame, found from the player's screen down: the one Hud ScreenGui, then its children
		frame = function(name: string): Inst
			local guis = {}
			for _, g in playerGui:GetChildren() do
				if g.ClassName == "ScreenGui" and g.Name == "Hud" then
					table.insert(guis, g)
				end
			end
			assert(#guis == 1, "one Hud ScreenGui under PlayerGui")
			for _, i in guis[1]:GetChildren() do
				if i.Name == name and i.ClassName == "Frame" then
					return i
				end
			end
			error("no " .. name .. " frame in the Hud ScreenGui")
		end,
	}
end

local function rectOf(f: Inst): Rect
	return { x = f.Position.x, y = f.Position.y, w = f.Size.x, h = f.Size.y }
end

local function want(w: number, h: number, inset: any?): any
	return (Touch :: any).buttons(Hud.layout(w, h, inset or { top = 0, bottom = 0, left = 0, right = 0 }))
end

-- every TextLabel under a frame
local function captions(f: Inst): { Inst }
	local out = {}
	for _, c in f:GetChildren() do
		if c.ClassName == "TextLabel" then
			table.insert(out, c)
		end
	end
	return out
end

-- every UICorner under a frame
local function corners(f: Inst): { Inst }
	local out = {}
	for _, c in f:GetChildren() do
		if c.ClassName == "UICorner" then
			table.insert(out, c)
		end
	end
	return out
end

-- How a button is drawn, sentence by sentence from the Design's HudView bullet: a translucent disc of `colour`
-- with no border and one round corner, holding one caption named Caption: `text` in the HUD's white Arcade font,
-- centred, at the HUD's text size, with a full black outline (so the caption, not the colour alone, tells FIRE
-- from JUMP), no background, the frame's full size, taking no input.
local function expectDrawn(
	f: Inst,
	colour: { r: number, g: number, b: number },
	text: string,
	textSize: number
)
	t.expect(f.BackgroundColor3).toEqual(colour)
	t.expect(f.BackgroundTransparency).toBe(0.6)
	t.expect(f.BorderSizePixel).toBe(0)
	local round = corners(f)
	t.expect(#round).toBe(1)
	t.expect(round[1].CornerRadius).toEqual({ s = 0.5, o = 0 })
	local caps = captions(f)
	t.expect(#caps).toBe(1)
	local c = caps[1]
	t.expect(c.Name).toBe("Caption")
	t.expect(c.Font and c.Font.Name).toBe("Arcade") -- the HUD's font, through HudView's label()
	t.expect(c.TextXAlignment and c.TextXAlignment.Name).toBe("Center")
	t.expect(c.Text).toBe(text)
	t.expect(c.TextSize).toBe(textSize)
	t.expect(c.TextColor3).toEqual({ r = 255, g = 255, b = 255 })
	t.expect(c.TextStrokeColor3).toEqual({ r = 0, g = 0, b = 0 })
	t.expect(c.TextStrokeTransparency).toBe(0)
	t.expect(c.BackgroundTransparency).toBe(1)
	t.expect(c.Size).toEqual({ sx = 1, sy = 1 })
	t.expect(c.Active).toBe(false)
end

return t.spec("f0110 touch adapters", function(it)
	it("HudView draws a non-active Fire frame at Touch.buttons' fire rectangle on a touch screen", function()
		local s = hudView(true)
		t.expect(s.hud.buttons()).toBe(nil) -- before the first layout
		s.render()
		local b = want(1000, 600)
		t.expect(s.hud.buttons()).toEqual(b)
		local drawn: { [string]: Rect } = { Fire = b.fire }
		for name, r in drawn do
			local f = s.frame(name)
			t.expect(rectOf(f)).toEqual(r)
			t.expect(f.Active).toBe(false)
			t.expect(f.Visible).toBe(true)
		end
		local size = Hud.layout(1000, 600).textSize
		expectDrawn(s.frame("Fire"), { r = 0, g = 255, b = 255 }, "FIRE", size) -- the shot bars' cyan
	end)

	it("HudView re-lays the buttons when the screen changes", function()
		local s = hudView(true)
		s.render()
		s.resize(390, 844)
		s.render()
		local b = want(390, 844)
		t.expect(s.hud.buttons()).toEqual(b)
		t.expect(rectOf(s.frame("Fire"))).toEqual(b.fire)
		-- the captions follow the new screen's text size
		t.expect(captions(s.frame("Fire"))[1].TextSize).toBe(Hud.layout(390, 844).textSize)
	end)

	it(
		"HudView places the buttons in the safe rectangle the device's insets leave, as the snap control",
		function()
			local s = hudView(true)
			s.resize(844, 390)
			s.notch(47, 0, 47, 21) -- a landscape phone: the notch and its mirror, and the home indicator
			s.render()
			local b = want(844, 390, { top = 0, bottom = 21, left = 47, right = 47 })
			t.expect(s.hud.buttons()).toEqual(b)
			t.expect(rectOf(s.frame("Fire"))).toEqual(b.fire)
		end
	)

	it("a screen without touch does not show the buttons", function()
		local s = hudView(false)
		s.render()
		t.expect(s.frame("Fire").Visible).toBe(false)
	end)

	it("HudView sends nothing, and Main hands HudView.buttons to Controls.start", function()
		local hud = source("HudView")
		t.expect((string.find(hud, "FireServer", 1, true))).toBe(nil)
		t.expect((string.find(hud, "Remotes", 1, true))).toBe(nil)
		local main = source("Main")
		local call = string.match(main, "Controls%.start%b()") or ""
		t.expect(string.find(call, "HudView%.buttons%s*[,%)]") ~= nil).toBe(true)
	end)
end)
