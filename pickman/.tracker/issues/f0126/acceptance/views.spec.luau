--!strict
-- f0126 AC6 (what the adapters build): HudView, MazeView and Main run from their real source on a small stub
-- engine, as tests/place/hud-shots does, and are judged by what they make, not by how their source reads (design
-- review 004 F1). HudView places the pick bar and the boon banner exactly at Hud.pickBox and Hud.boonBox of its
-- layout, inset included, and fills and shows them from the frame; MazeView builds gold MarkedWall parts at the
-- marked runs, leaves the holes open, keeps the rest of the model, and flashes the marked walls with the others;
-- Main rebuilds the walls once per change of View.wallsKey, from View.frameMaze, and hands the radar, the camera
-- and the HUD what the frame says.
-- The stub require falls back to the real Logic modules for any Logic feature, so an adapter that requires one more
-- (an issue in flight) still loads (pickman-test lesson stub-loaders-fall-back).
local Awareness = require("@logic/Awareness")
local Blaster = require("@logic/Blaster")
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
local Ghosts = require("@logic/Ghosts")
local Hiscores = require("@logic/Hiscores")
local Hop = require("@logic/Hop")
local Hud = require("@logic/Hud")
local Levels = require("@logic/Levels")
local Lobby = require("@logic/Lobby")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Pellets = require("@logic/Pellets")
local Picks = require("@logic/Picks")
local Session = require("@logic/Session")
local Touch = require("@logic/Touch")
local Travel = require("@logic/Travel")
local View = require("@logic/View")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()
local classic = Maze.layout("classic")
local GOLD = { r = 255, g = 215, b = 0 }
-- f0109's colours are read from View (f0109 owns them, and may tune them); only the marks' gold is f0126's
local function copy(c: any): any
	return { r = c.r, g = c.g, b = c.b }
end
local LIT = copy(View.WHITE)
local BLUE = copy((View :: any).WALL_COLOR)

local LOGIC: { [string]: any } = {
	Awareness = Awareness,
	Blaster = Blaster,
	Flow = Flow,
	Game = Game,
	Ghosts = Ghosts,
	Hiscores = Hiscores,
	Hop = Hop,
	Hud = Hud,
	Levels = Levels,
	Lobby = Lobby,
	Maze = Maze,
	Movement = Movement,
	Pellets = Pellets,
	Picks = Picks,
	Session = Session,
	Touch = Touch,
	Travel = Travel,
	View = View,
}

local function script(name: string): any
	local node = game:FindFirstChild("StarterPlayer")
	for _, child in { "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(child)
	end
	t.expect(node ~= nil).toBe(true)
	return node
end

type Inst = { [string]: any }

-- A stub instance: plain fields; setting Parent files it under its parent, in order; Destroy takes it out.
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
			elseif key == "GetDescendants" then
				return function(): { Inst }
					local out: { Inst } = {}
					local function walk(list: { Inst })
						for _, c in list do
							table.insert(out, c)
							walk(c.children)
						end
					end
					walk(children)
					return out
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
			elseif key == "Destroy" then
				return function()
					local parent = props.Parent
					if parent then
						local list = parent.children
						local i = table.find(list, self)
						if i then
							table.remove(list, i)
						end
					end
					props.Parent = nil
				end
			elseif key == "GetAttribute" then
				return function(_: any, name: string): any
					return (props.attributes or {})[name]
				end
			elseif key == "SetAttribute" then
				return function(_: any, name: string, value: any)
					props.attributes = props.attributes or {}
					props.attributes[name] = value
				end
			elseif key == "ClearAllChildren" then
				return function()
					table.clear(children)
				end
			elseif key == "IsA" then
				return function(_: any, c: string): boolean
					return props.ClassName == c or (c == "BasePart" and props.ClassName == "Part")
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
				-- as in Roblox: the same parent again changes nothing; a new one takes it from the old
				if value == props.Parent then
					return
				end
				local old = props.Parent
				if old then
					local i = table.find(old.children, self)
					if i then
						table.remove(old.children, i)
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

-- A stand-in that answers every call and field with another stand-in: for a sibling adapter or a service the
-- case does not look at.
local function anything(): any
	return setmetatable({}, {
		__index = function(_: any, _key: string): any
			return function(): any
				return anything()
			end
		end,
		__call = function(): any
			return anything()
		end,
	})
end

-- The stub require, open on every side (design review 005 F2): the given stubs first; any Logic feature as itself
-- (one added after this spec is loaded by name); any other sibling adapter as a stand-in.
local function requirer(stubs: { [string]: any }): (string) -> any
	return function(spec: string): any
		local stub = stubs[spec]
		if stub ~= nil then
			return stub
		end
		local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
		if name then
			return LOGIC[name] or (require :: any)("@logic/" .. name)
		end
		if string.match(spec, "^%./[%w_]+$") then
			return anything()
		end
		error(`unexpected require {spec}`)
	end
end

local function baseEnv(made: { Inst }): { [string]: any }
	return {
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
		Vector2 = {
			new = function(x: number, y: number): any
				return { x = x, y = y }
			end,
		},
		Vector3 = {
			new = function(x: number, y: number, z: number): any
				return { x = x, y = y, z = z }
			end,
		},
		Color3 = {
			fromRGB = function(r: number, g: number, b: number): any
				return { r = r, g = g, b = b }
			end,
		},
	}
end

-- ---------------------------------------------------------------------------------------------------------------
-- HudView

type HudWorld = {
	hud: any,
	render: () -> (),
	find: (string) -> Inst?,
	layout: () -> Hud.Layout,
	screen: (number, number, { left: number, top: number, right: number, bottom: number }) -> (),
}

local function hudWorld(
	w: number,
	h: number,
	core: { left: number, top: number, right: number, bottom: number }
): HudWorld
	local rendered: { () -> () } = {}
	local made: { Inst } = {}
	local none = { Min = { X = 0, Y = 0 }, Max = { X = w, Y = h } }
	local safe = { Min = { X = core.left, Y = core.top }, Max = { X = w - core.right, Y = h - core.bottom } }
	local viewport = { X = w, Y = h }
	local services: { [string]: any } = {
		GuiService = {
			GetInsetArea = function(_: any, which: any): any
				return if which.Name == "CoreUISafeInsets" then safe else none
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
	local env = baseEnv(made)
	env.game = {
		GetService = function(_: any, name: string): any
			return assert(services[name], name)
		end,
	}
	env.workspace = { CurrentCamera = { ViewportSize = viewport } }
	env.require = requirer({})
	local hud = luau.load(script("HudView").Source, { environment = env, debugName = "HudView" })()
	hud.start()
	return {
		hud = hud,
		render = function()
			for _, fn in rendered do
				fn()
			end
		end,
		find = function(name: string): Inst?
			for _, i in made do
				if i.Name == name then
					return i
				end
			end
			return nil
		end,
		layout = function(): Hud.Layout
			return Hud.layout(viewport.X, viewport.Y, Hud.safeInset(none, safe))
		end,
		screen = function(
			nw: number,
			nh: number,
			c: { left: number, top: number, right: number, bottom: number }
		)
			viewport.X, viewport.Y = nw, nh
			none.Max = { X = nw, Y = nh }
			safe.Min = { X = c.left, Y = c.top }
			safe.Max = { X = nw - c.right, Y = nh - c.bottom }
		end,
	}
end

local function boxOf(i: Inst): Hud.Box
	return { x = i.Position.x, y = i.Position.y, w = i.Size.x, h = i.Size.y }
end

local function play(): Session.PlayFrame
	return { phase = "playing", level = 1, score = 0, lives = 3, timer = 0, frightened = 0 }
end

-- ---------------------------------------------------------------------------------------------------------------
-- MazeView

local function mazeView(): (any, Inst)
	local made: { Inst } = {}
	local env = baseEnv(made)
	local world = instance("Workspace")
	env.workspace = world
	env.require = requirer({})
	local mv = luau.load(script("MazeView").Source, { environment = env, debugName = "MazeView" })()
	return mv, world
end

local function partsNamed(model: Inst, name: string): { Inst }
	local out: { Inst } = {}
	for _, c in model:GetDescendants() do
		if c.Name == name then
			table.insert(out, c)
		end
	end
	return out
end

-- a part's tile run, from its centre and size (View.world: x * tileStuds; a run of n tiles is n * tileStuds wide)
local function runOf(p: Inst): string
	local s = View.SCALE.tileStuds
	local n = math.floor(p.Size.x / s + 0.5)
	local cx = p.Position.x / s
	local x0 = math.floor(cx - (n - 1) / 2 + 0.5)
	return `{x0},{math.floor(p.Position.z / s + 0.5)},{x0 + n - 1}`
end

local function runsOf(rects: { View.Rect }, marked: boolean): { string }
	local out: { string } = {}
	for _, r in rects do
		if (r.marked == true) == marked then
			table.insert(out, `{r.x0 + 0},{r.y0 + 0},{r.x1 + 0}`) -- + 0 turns a -0 bound into 0
		end
	end
	table.sort(out)
	return out
end

local function runsOfParts(parts: { Inst }): { string }
	local out: { string } = {}
	for _, p in parts do
		table.insert(out, runOf(p))
	end
	table.sort(out)
	return out
end

local function at(x: number, y: number): Maze.Tile
	return { x = x, y = y }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Main

type Calls = { [string]: { { any } } }

local function mainWorld(): ((Session.Frame) -> (), Calls, any)
	local calls: Calls = {}
	local function recorder(module: string): any
		return setmetatable({}, {
			__index = function(_: any, fn: string): any
				return function(...: any): any
					local key = `{module}.{fn}`
					calls[key] = calls[key] or {}
					table.insert(calls[key], table.pack(...))
					if key == "MazeView.build" then
						return { model = true }
					elseif key == "PelletView.build" then
						return { pellets = true }
					elseif key == "FlowView.trip" then
						return nil
					end
					return nil
				end
			end,
		})
	end
	local onFrame: ((Session.Frame) -> ())? = nil
	local remote = {
		OnClientEvent = {
			Connect = function(_: any, fn: (Session.Frame) -> ())
				onFrame = fn
			end,
		},
		FireServer = function() end,
	}
	local remotes = {
		WaitForChild = function(_: any, _name: string): any
			return remote
		end,
	}
	local made: { Inst } = {}
	local env = baseEnv(made)
	env.game = {
		GetService = function(_: any, name: string): any
			if name ~= "ReplicatedStorage" then
				return anything() -- a service Main may come to use; the cases do not look at it
			end
			return {
				WaitForChild = function(_: any, _n: string): any
					return remotes
				end,
			}
		end,
	}
	env.print = function() end
	local stubs: { [string]: any } = {}
	for _, name in
		{
			"BlastView",
			"Camera",
			"Controls",
			"DangerHud",
			"FlowView",
			"GhostView",
			"HudView",
			"MazeView",
			"PelletView",
		}
	do
		stubs["./" .. name] = recorder(name)
	end
	-- Flow's overlay of a frame, real: it needs a trip from FlowView, which the stub gives as nil
	env.require = requirer(stubs)
	luau.load(script("Main").Source, { environment = env, debugName = "Main" })()
	return function(frame: Session.Frame)
		(onFrame :: (Session.Frame) -> ())(frame)
	end, calls, nil
end

local function frame(opened: { Maze.Tile }, marked: { Maze.Tile }): Session.Frame
	local s = Session.new(classic, 1)
	Session.join(s, "p")
	local f = Session.frame(s, "p")
	f.walls = { opened = opened, marked = marked }
	return f
end

return t.spec("f0126 what the adapters build", function(it)
	it(
		"HudView puts the pick bar and the banner at Hud.pickBox and Hud.boonBox of its layout, inset included",
		function()
			for _, core in
				{
					{ left = 0, top = 0, right = 0, bottom = 0 },
					{ left = 47, top = 0, right = 47, bottom = 21 },
				}
			do
				local w = hudWorld(844, 390, core)
				w.hud.show(play())
				w.render()
				local pick: Session.Pick = { wall = at(2, 2), started = 100, ticks = 40, fast = false }
				w.hud.pick(pick, { tick = 100, kind = "shot" }, 110)
				w.render()
				local bar, banner = w.find("PickBar"), w.find("Boon")
				t.expect(bar ~= nil and banner ~= nil).toBe(true)
				t.expect(boxOf(bar :: Inst)).toEqual(Hud.pickBox(w.layout()))
				t.expect(boxOf(banner :: Inst)).toEqual(Hud.boonBox(w.layout()))
			end
		end
	)

	it(
		"HudView shows the bar filled as far as the pick has gone, and the banner's words, only while they last",
		function()
			local w = hudWorld(1280, 720, { left = 0, top = 0, right = 0, bottom = 0 })
			w.hud.show(play())
			w.render()
			local pick: Session.Pick = { wall = at(2, 2), started = 100, ticks = 40, fast = false }
			w.hud.pick(pick, { tick = 100, kind = "longpill" }, 120)
			local bar, banner = w.find("PickBar") :: Inst, w.find("Boon") :: Inst
			local fill = (bar :: Inst).children[1]
			t.expect(bar.Visible).toBe(true)
			t.expect(fill.Size.sx).toBe(0.5)
			t.expect(banner.Visible).toBe(true)
			t.expect(banner.Text).toBe(Hud.BOON_LABELS.longpill)
			w.hud.pick(nil, { tick = 100, kind = "longpill" }, 100 + Hud.BOON_TICKS)
			t.expect(bar.Visible).toBe(false)
			t.expect(banner.Visible).toBe(false)
		end
	)

	it("MazeView gives each marked run a gold MarkedWall part, and every other run a Wall", function()
		local mv = mazeView()
		local marks = { at(2, 2), at(7, 2), at(25, 6) }
		local model = mv.build(classic)
		mv.rewall(model, classic, marks)
		local rects = View.walls(classic, nil, marks)
		local gold = partsNamed(model, "MarkedWall")
		t.expect(runsOfParts(gold)).toEqual(runsOf(rects, true))
		for _, p in gold do
			t.expect(p.Color).toEqual(GOLD)
		end
		local walls = partsNamed(model, "Wall")
		t.expect(runsOfParts(walls)).toEqual(runsOf(rects, false))
		for _, p in walls do
			t.expect(p.Color).toEqual(BLUE)
		end
	end)

	it("MazeView leaves the holes open and keeps the rest of the model when it rebuilds the walls", function()
		local mv = mazeView()
		local model = mv.build(classic)
		local pellet = instance("Part")
		pellet.Name = "Pellet"
		pellet.Parent = model
		local holed = Maze.opened(classic, { at(2, 2), at(14, 10) })
		mv.rewall(model, holed, { at(7, 2) }) -- a mark that the next rebuild moves
		mv.rewall(model, holed, { at(3, 2) })
		t.expect(model:FindFirstChild("Pellet")).toBe(pellet)
		-- the wall parts are the maze model's own children, as f0109's checks read them
		for _, name in { "Wall", "MarkedWall" } do
			for _, p in partsNamed(model, name) do
				t.expect(p.Parent).toBe(model)
			end
		end
		local rects = View.walls(holed, nil, { at(3, 2) })
		t.expect(runsOfParts(partsNamed(model, "Wall"))).toEqual(runsOf(rects, false))
		-- and the marked walls are exactly the new marks: the old gold walls are gone
		t.expect(runsOfParts(partsNamed(model, "MarkedWall"))).toEqual(runsOf(rects, true))
		for _, p in partsNamed(model, "Wall") do
			local x0, y, x1 = string.match(runOf(p), "^(-?%d+),(-?%d+),(-?%d+)$")
			local row, a, b = tonumber(y), tonumber(x0), tonumber(x1)
			t.expect(not (row == 2 and (a :: number) <= 2 and 2 <= (b :: number))).toBe(true)
			t.expect(not (row == 10 and (a :: number) <= 14 and 14 <= (b :: number))).toBe(true)
		end
	end)

	it("MazeView's flash lights the marked walls with the rest, and gives them back their gold", function()
		local mv = mazeView()
		local model = mv.build(classic)
		mv.rewall(model, classic, { at(2, 2) })
		mv.flash(model, true)
		for _, name in { "Wall", "MarkedWall" } do
			for _, p in partsNamed(model, name) do
				t.expect(p.Color).toEqual(LIT)
			end
		end
		mv.flash(model, false)
		for _, p in partsNamed(model, "MarkedWall") do
			t.expect(p.Color).toEqual(GOLD)
		end
		for _, p in partsNamed(model, "Wall") do
			t.expect(p.Color).toEqual(BLUE)
		end
		mv.flash(model, true)
		mv.rewall(model, classic, { at(2, 2) }) -- rebuilt while lit: lit
		for _, p in partsNamed(model, "MarkedWall") do
			t.expect(p.Color).toEqual(LIT)
		end
	end)

	it("Main rebuilds the walls once per change of the holes or the marks, from the frame's maze", function()
		local push, calls = mainWorld()
		local marks = { at(2, 2), at(7, 2), at(25, 6) }
		push(frame({}, marks))
		push(frame({}, marks))
		push(frame({}, marks))
		local rewalls = calls["MazeView.rewall"] or {}
		t.expect(#rewalls).toBe(1)
		t.expect(rewalls[1][2]).toBe(classic)
		t.expect(rewalls[1][3]).toEqual(marks)
		local hole = { at(2, 2) }
		local next = frame(hole, { at(7, 2), at(25, 6), at(3, 2) })
		push(next)
		push(frame(hole, { at(7, 2), at(25, 6), at(3, 2) }))
		t.expect(#rewalls).toBe(2)
		t.expect(rewalls[2][2]).toBe(View.frameMaze(next))
		t.expect(Maze.kind(rewalls[2][2], at(2, 2))).toBe("empty")
	end)

	it(
		"Main hands the radar the frame's maze, the camera the hop's length, and the HUD the pick and the boon",
		function()
			local push, calls = mainWorld()
			local f = frame({ at(2, 2) }, {})
			f.hopped, f.hopTicks = 40, Hop.LONG_TICKS
			f.pick = { wall = at(7, 2), started = 50, ticks = 43, fast = true }
			f.boon = { tick = 30, kind = "jumps" }
			push(f)
			local radar = (calls["DangerHud.push"] or {})[1]
			t.expect(radar ~= nil).toBe(true)
			t.expect(Maze.kind(radar[2], at(2, 2))).toBe("empty")
			t.expect((calls["Camera.hopTicks"] or {})[1][1]).toBe(Hop.LONG_TICKS)
			local hud = (calls["HudView.pick"] or {})[1]
			t.expect(hud[1]).toEqual(f.pick)
			t.expect(hud[2]).toEqual(f.boon)
			t.expect(hud[3]).toBe(f.tick)
		end
	)

	it("HudView places the bar and the banner again when the screen turns or its insets move", function()
		local w = hudWorld(844, 390, { left = 47, top = 0, right = 0, bottom = 21 })
		w.hud.show(play())
		w.render()
		w.hud.pick(
			{ wall = at(2, 2), started = 100, ticks = 40, fast = false },
			{ tick = 100, kind = "shot" },
			110
		)
		w.render()
		local turns: { { w: number, h: number, core: { left: number, top: number, right: number, bottom: number } } } =
			{
				{ w = 390, h = 844, core = { left = 0, top = 47, right = 0, bottom = 34 } }, -- turned upright
				{ w = 844, h = 390, core = { left = 0, top = 0, right = 47, bottom = 21 } }, -- turned the other way
			}
		for _, s in turns do
			w.screen(s.w, s.h, s.core)
			w.render()
			t.expect(boxOf(w.find("PickBar") :: Inst)).toEqual(Hud.pickBox(w.layout()))
			t.expect(boxOf(w.find("Boon") :: Inst)).toEqual(Hud.boonBox(w.layout()))
		end
	end)

	it("Main rebuilds the walls when only the marks change too (a new level with no pick yet)", function()
		local push, calls = mainWorld()
		push(frame({ at(14, 10) }, { at(2, 2), at(7, 2), at(25, 6) }))
		push(frame({}, { at(3, 2), at(7, 2), at(25, 6) })) -- holes closed, marks rolled anew
		push(frame({}, { at(3, 2), at(8, 2), at(25, 6) })) -- the same holes, other marks
		local rewalls = calls["MazeView.rewall"] or {}
		t.expect(#rewalls).toBe(3)
		t.expect(rewalls[3][3]).toEqual({ at(3, 2), at(8, 2), at(25, 6) })
	end)

	it(
		"while the ghosts are edible the walls are green and the marked walls stay gold, rebuilt or not",
		function()
			local GREEN = copy((View :: any).WALL_EDIBLE_COLOR)
			local mv = mazeView()
			local model = mv.build(classic)
			mv.rewall(model, classic, { at(2, 2) })
			mv.edible(model, true)
			for _, p in partsNamed(model, "Wall") do
				t.expect(p.Color).toEqual(GREEN)
			end
			for _, p in partsNamed(model, "MarkedWall") do
				t.expect(p.Color).toEqual(GOLD) -- the user: marked walls stay gold while the walls are green
			end
			-- a pick finishing while the ghosts are edible (a pill boon) rebuilds the walls: they come out green and gold
			mv.rewall(model, Maze.opened(classic, { at(2, 2) }), { at(7, 2) })
			t.expect(#partsNamed(model, "Wall") > 0).toBe(true)
			for _, p in partsNamed(model, "Wall") do
				t.expect(p.Color).toEqual(GREEN)
			end
			for _, p in partsNamed(model, "MarkedWall") do
				t.expect(p.Color).toEqual(GOLD)
			end
			mv.edible(model, false)
			for _, p in partsNamed(model, "Wall") do
				t.expect(p.Color).toEqual(BLUE)
			end
		end
	)
end)
