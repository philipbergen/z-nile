--!strict
-- f0147 AC3: the HUD shows how close the player is to the next level (the user, 2026-10-31: "Yes, show picks/10"),
-- and the power bar follows the session's own frightened period. With a ramp the frame's play record carries the
-- level's finished picks, the goal and the power period; Hud.model turns them into "PICKS n/10"; Hud.picksBox puts
-- the counter in the row under the score, left-aligned like it, clear of every other HUD block, both radars, the
-- touch buttons and f0126's pick bar and boon banner on every sample screen. HudView draws it there and hides it
-- without a ramp. The tenth pick's banner says "BONANZA!".
local Awareness = require("@logic/Awareness")
local Hud = require("@logic/Hud")
local Levels = require("@logic/Levels")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Session = require("@logic/Session")
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

type Rect = { x: number, y: number, w: number, h: number }

local function overlap(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- f0126's sample screens and insets
local SCREENS = {
	{ 320, 568 },
	{ 360, 640 },
	{ 360, 800 },
	{ 375, 667 },
	{ 390, 844 },
	{ 480, 320 },
	{ 500, 900 },
	{ 568, 320 },
	{ 667, 375 },
	{ 844, 390 },
	{ 900, 500 },
	{ 1024, 768 },
	{ 1080, 1920 },
	{ 1280, 720 },
	{ 1920, 1080 },
}
local INSETS: { Hud.Inset } = {
	{ top = 0, bottom = 0, left = 0, right = 0 },
	{ top = 0, bottom = 21, left = 47, right = 0 },
	{ top = 0, bottom = 21, left = 0, right = 47 },
	{ top = 47, bottom = 34, left = 0, right = 0 },
	{ top = 58, bottom = 0, left = 0, right = 0 },
}

local function play(fields: { [string]: any }): Session.PlayFrame
	local p: { [string]: any } =
		{ phase = "playing", level = 1, score = 0, lives = 3, timer = 0, frightened = 0 }
	for k, v in fields do
		p[k] = v
	end
	return p :: any
end

return t.spec("f0147 the HUD's pick counter and power share", function(it)
	it("Hud.model shows the level's finished picks out of the goal, and nothing without them", function()
		t.expect(Hud.model(play({ picks = 3, picksGoal = 10 })).picks).toBe("PICKS 3/10")
		t.expect(Hud.model(play({ picks = 0, picksGoal = 10 })).picks).toBe("PICKS 0/10")
		t.expect(Hud.model(play({ picks = 9, picksGoal = 10, level = 7 })).picks).toBe("PICKS 9/10")
		t.expect(Hud.model(play({})).picks).toBe(nil)
		t.expect(Hud.model(play({ level = 4 })).level).toBe("LEVEL 4") -- the level line is as before
	end)

	it("the power bar is the share of the frame's own power period, else the classic table's", function()
		-- the ramp's level 17 has level 1's 180 ticks; the classic level 17 has none
		t.expect(Hud.model(play({ level = 17, frightened = 90, power = 180 })).power).toBe(0.5)
		t.expect(Hud.model(play({ level = 17, frightened = 90 })).power).toBe(0)
		t.expect(Hud.model(play({ level = 2, frightened = 75 })).power).toBe(0.5) -- classic level 2: 150 ticks
		t.expect(Hud.model(play({ level = 1, frightened = 360, power = 180 })).power).toBe(1) -- a long pill: full
	end)

	it(
		"a ramped session's frame carries the picks, the goal and the power period; a classic one only its period",
		function()
			local m = Maze.parse({ "#######", "#  P  #", "#######" }, "room")
			local ramped = Session.new(
				m,
				1,
				{ movement = Movement.DEFAULT_CONFIG, maxIntentsPerTick = 4, ramp = Levels.RAMP }
			)
			Session.join(ramped, "p")
			local f = Session.frame(ramped, "p").play
			t.expect(f.picks).toBe(0)
			t.expect(f.picksGoal).toBe(10);
			(ramped :: any).members.p.play.level = 17
			t.expect(Session.frame(ramped, "p").play.power).toBe(180)
			local classic = Session.new(m, 1, Session.DEFAULT_CONFIG)
			Session.join(classic, "p")
			local c = Session.frame(classic, "p").play
			t.expect(c.picks).toBe(nil)
			t.expect(c.picksGoal).toBe(nil);
			(classic :: any).members.p.play.level = 17
			t.expect(Session.frame(classic, "p").play.power).toBe(0)
			t.expect(Hud.model(Session.frame(ramped, "p").play).picks).toBe("PICKS 0/10")
		end
	)

	it("the counter sits in the row under the score, its size, inside the safe area", function()
		for _, s in SCREENS do
			for _, inset in INSETS do
				local l = Hud.layout(s[1], s[2], inset)
				local score = Touch.blocks(l).score
				local box = Hud.picksBox(score)
				t.expect(box).toEqual({ x = score.x, y = score.y + score.h, w = score.w, h = score.h })
				t.expect(box.x >= l.safeX and box.y >= l.safeY).toBe(true)
				t.expect(box.x + box.w <= l.safeX + l.safeW and box.y + box.h <= l.safeY + l.safeH).toBe(true)
			end
		end
	end)

	it(
		"the counter is clear of every other HUD block, both radars, the touch buttons, the pick bar and banner",
		function()
			local RADAR = (Awareness.RADAR_RADIUS * 2 + 1) * 8 -- DangerHud's CELL of 8 pixels
			for _, s in SCREENS do
				for _, inset in INSETS do
					for _, band in { 0, 36, 58 } do
						local l = Hud.layout(s[1], s[2], inset)
						local blocks = Touch.blocks(l)
						local box = Hud.picksBox(blocks.score)
						local b = Touch.buttons(l) :: any
						local others: { Rect } = {
							blocks.score,
							blocks.level,
							blocks.lives,
							blocks.power,
							b.snap,
							b.fire,
							b.hop,
							b.pick,
							Hud.pickBox(l),
							Hud.boonBox(l),
							Hud.radarBox(s[1], s[2], RADAR, false),
							Hud.radarBox(s[1], s[2], RADAR, true, band),
						}
						for lives = 0, 6 do
							for _, sh in Hud.shotIcons(l, lives, 3) do
								table.insert(others, {
									x = blocks.lives.x + sh.x,
									y = blocks.lives.y + sh.y,
									w = sh.w,
									h = sh.h,
								})
							end
						end
						for i, o in others do
							if overlap(box, o) then
								error(
									`{s[1]}x{s[2]} inset {inset.left},{inset.top} band {band}: the counter meets block {i}`
								)
							end
						end
					end
				end
			end
		end
	)

	it("the tenth pick's banner says BONANZA! for the banner's time", function()
		t.expect(Hud.BOON_LABELS.bonanza).toBe("BONANZA!")
		local grant: Session.BoonGrant = { tick = 100, kind = "bonanza" }
		t.expect(Hud.boonBanner(grant, 100)).toBe("BONANZA!")
		t.expect(Hud.boonBanner(grant, 100 + Hud.BOON_TICKS - 1)).toBe("BONANZA!")
		t.expect(Hud.boonBanner(grant, 100 + Hud.BOON_TICKS)).toBe(nil)
	end)

	-- HudView, its real source on a stub engine (f0110's harness) ----------------------------------------------------

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
				elseif key == "FindFirstChild" then
					return function(_: any, name: string): Inst?
						for _, c in children do
							if c.Name == name then
								return c
							end
						end
						return nil
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

	local luau = require("@lune/luau")
	local place = require("@tests/lib/place")
	local game = place.load() -- the built place: HudView as Rojo builds it

	type Screen = {
		hud: any,
		root: Inst,
		render: () -> (),
		resize: (number, number) -> (),
		notch: (left: number, top: number, right: number, bottom: number) -> (),
	}

	-- HudView started on a w x h screen with no inset (f0110's harness). `notch` keeps pixels on each edge for the
	-- device: both areas are then reported relative to the core-UI area's top-left, as GetInsetArea reports them.
	-- Any Logic feature HudView requires is loaded as itself, so a later issue's new require does not break this.
	local function hudView(w: number, h: number): Screen
		local rendered: { () -> () } = {}
		local area = { Min = { X = 0, Y = 0 }, Max = { X = w, Y = h } }
		local core = { Min = { X = 0, Y = 0 }, Max = { X = w, Y = h } }
		local viewport = { X = w, Y = h }
		local playerGui = instance("PlayerGui")
		local services: { [string]: any } = {
			GuiService = {
				GetInsetArea = function(_: any, which: any): any
					return if which.Name == "CoreUISafeInsets" then core else area
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
			UserInputService = { TouchEnabled = false },
		}
		local function enum(name: string): any
			return setmetatable({}, {
				__index = function(_: any, k: string): any
					return { Name = k, Value = 0, EnumType = name }
				end,
			})
		end
		local env: { [string]: any } = {
			game = {
				GetService = function(_: any, name: string): any
					return assert(services[name], name)
				end,
			},
			workspace = { CurrentCamera = { ViewportSize = viewport } },
			require = function(path: string): any
				local name = string.match(path, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
				assert(name, `HudView requires {path}`)
				return (require :: any)("@logic/" .. name)
			end,
			Instance = {
				new = function(class: string): Inst
					return instance(class)
				end,
			},
			Enum = setmetatable({}, {
				__index = function(_: any, k: string): any
					return enum(k)
				end,
			}),
			UDim2 = {
				fromOffset = function(x: number, y: number): any
					return { X = { Offset = x }, Y = { Offset = y } }
				end,
				fromScale = function(x: number, y: number): any
					return { X = { Scale = x }, Y = { Scale = y } }
				end,
				new = function(xs: number, xo: number, ys: number, yo: number): any
					return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
				end,
			},
			UDim = {
				new = function(sc: number, o: number): any
					return { Scale = sc, Offset = o }
				end,
			},
			Color3 = {
				fromRGB = function(r: number, g: number, b: number): any
					return { R = r, G = g, B = b }
				end,
			},
			Vector2 = {
				new = function(x: number, y: number): any
					return { X = x, Y = y }
				end,
			},
		}
		local node = game:FindFirstChild("StarterPlayer")
		for _, child in { "StarterPlayerScripts", "Client", "HudView" } do
			node = node and node:FindFirstChild(child)
		end
		assert(node, "HudView in the built place")
		local mod = luau.load(node.Source, { debugName = "HudView", environment = env })()
		mod.start()
		return {
			hud = mod,
			root = playerGui,
			render = function()
				for _, fn in rendered do
					fn()
				end
			end,
			resize = function(nw: number, nh: number)
				area.Min, area.Max = { X = 0, Y = 0 }, { X = nw, Y = nh }
				core.Min, core.Max = { X = 0, Y = 0 }, { X = nw, Y = nh }
				viewport.X, viewport.Y = nw, nh
			end,
			notch = function(left: number, top: number, right: number, bottom: number)
				local vw, vh = viewport.X, viewport.Y
				area.Min = { X = -left, Y = -top }
				area.Max = { X = vw - left, Y = vh - top }
				core.Max = { X = vw - left - right, Y = vh - top - bottom }
			end,
		}
	end

	local function find(root: Inst, name: string): Inst?
		for _, c in root.children do
			if c.Name == name then
				return c
			end
			local inner = find(c, name)
			if inner then
				return inner
			end
		end
		return nil
	end

	-- the label's place for a screen and an inset, as Hud lays it out
	local function expected(w: number, h: number, inset: Hud.Inset?): Rect
		return Hud.picksBox(Touch.blocks(Hud.layout(w, h, inset)).score)
	end
	local function placed(l: Inst): Rect
		return { x = l.Position.X.Offset, y = l.Position.Y.Offset, w = l.Size.X.Offset, h = l.Size.Y.Offset }
	end

	it(
		"HudView draws the counter under the score from the frame, left-aligned, and hides it without picks",
		function()
			local screen = hudView(1280, 720)
			screen.render()
			screen.hud.show(play({ picks = 4, picksGoal = 10, level = 2 }))
			screen.render()
			local gui = find(screen.root, "Hud")
			t.expect(gui ~= nil and (gui :: Inst).Parent == screen.root).toBe(true)
			local label = find(gui :: Inst, "Picks")
			t.expect(label ~= nil).toBe(true)
			local l = label :: Inst
			t.expect(l.Parent).toBe(gui)
			t.expect(l.Text).toBe("PICKS 4/10")
			t.expect(l.Visible).toBe(true)
			t.expect(l.TextXAlignment.Name).toBe("Left")
			t.expect(l.TextSize).toBe(Hud.layout(1280, 720).textSize)
			t.expect(placed(l)).toEqual(expected(1280, 720))
			local score = find(gui :: Inst, "Score") :: Inst
			t.expect(l.TextColor3).toEqual(score.TextColor3) -- drawn as the score is
			screen.hud.show(play({}))
			screen.render()
			t.expect(l.Visible).toBe(false)
			screen.hud.show(play({ picks = 9, picksGoal = 10 }))
			t.expect(l.Visible).toBe(true)
			t.expect(l.Text).toBe("PICKS 9/10")
		end
	)

	it("HudView places the counter by the layout's inset, and again when the screen turns", function()
		local screen = hudView(844, 390)
		screen.notch(47, 0, 47, 21)
		screen.render()
		screen.hud.show(play({ picks = 1, picksGoal = 10 }))
		local l = find(screen.root, "Picks") :: Inst
		local inset = { top = 0, bottom = 21, left = 47, right = 47 }
		t.expect(placed(l)).toEqual(expected(844, 390, inset))
		t.expect(l.Position.X.Offset >= 47).toBe(true)
		screen.resize(390, 844) -- turned to portrait, no inset
		screen.render()
		t.expect(placed(l)).toEqual(expected(390, 844))
		t.expect(l.TextSize).toBe(Hud.layout(390, 844).textSize)
	end)
end)
