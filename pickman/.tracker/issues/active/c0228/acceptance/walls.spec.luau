--!strict
-- c0228 AC2: each wall is built once. MazeView.build takes the marks and draws them as rewall does; a rewall to the
-- walls the model already has drawn (equal runs, View.runsKey) makes and destroys no part and keeps their colours; a
-- rewall to other walls still draws them. Main, run from its real source with MazeView's real source beside it, builds
-- every wall once on a maze's first frame (with the frame's holes and marks), none again while they stay, and only the
-- new walls' parts once when they change. f0126's views.spec still pins that Main calls MazeView.rewall once per
-- change of View.wallsKey (the first frame's included). The stub engine is f0126's views.spec's, copied.
local Flow = require("@logic/Flow")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
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
local GREEN = copy((View :: any).WALL_EDIBLE_COLOR)

local LOGIC: { [string]: any } = { Flow = Flow, Maze = Maze, Session = Session, View = View }

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
-- MazeView

-- MazeView's real source on the stub engine, and every instance it makes, in order
local function mazeView(): (any, { Inst })
	local made: { Inst } = {}
	local env = baseEnv(made)
	local world = instance("Workspace")
	env.workspace = world
	env.require = requirer({})
	local mv = luau.load(script("MazeView").Source, { environment = env, debugName = "MazeView" })()
	return mv, made
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

-- the wall parts (Wall and MarkedWall) among `made` from index `from` on: the ones made since then
local function wallsMade(made: { Inst }, from: number): number
	local n = 0
	for i = from, #made do
		local name = made[i].Name
		if name == "Wall" or name == "MarkedWall" then
			n += 1
		end
	end
	return n
end

-- the model's wall parts, in order
local function wallParts(model: Inst): { Inst }
	local out: { Inst } = {}
	for _, c in model:GetChildren() do
		if c.Name == "Wall" or c.Name == "MarkedWall" then
			table.insert(out, c)
		end
	end
	return out
end

-- the model's walls are exactly the runs of `m` with `marked` gold, coloured `wall` and `gold`
local function drawnAs(model: Inst, m: Maze.Maze, marked: { Maze.Tile }?, wall: any, gold: any)
	local rects = View.walls(m, nil, marked)
	t.expect(runsOfParts(partsNamed(model, "Wall"))).toEqual(runsOf(rects, false))
	t.expect(runsOfParts(partsNamed(model, "MarkedWall"))).toEqual(runsOf(rects, true))
	for _, p in partsNamed(model, "Wall") do
		t.expect(p.Color).toEqual(wall)
	end
	for _, p in partsNamed(model, "MarkedWall") do
		t.expect(p.Color).toEqual(gold)
	end
end

-- a wall tile that is a run of one tile in classic's walls, so marking it keeps the run's bounds
local function lone(): Maze.Tile
	for _, r in View.walls(classic) do
		if r.x0 == r.x1 and r.x0 >= 0 and r.x0 < classic.width and r.y0 >= 0 and r.y0 < classic.height then
			return at(r.x0, r.y0)
		end
	end
	error("classic has no one-tile wall run")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Main, with MazeView's real source

type Main = { push: (Session.Frame) -> (), made: { Inst }, model: () -> Inst? }

local function mainWorld(): Main
	local made: { Inst } = {}
	local env = baseEnv(made)
	local world = instance("Workspace")
	env.workspace = world
	env.print = function() end
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
	env.game = {
		GetService = function(_: any, name: string): any
			if name ~= "ReplicatedStorage" then
				return anything()
			end
			return {
				WaitForChild = function(_: any, _n: string): any
					return remotes
				end,
			}
		end,
	}
	env.require = requirer({})
	local mv = luau.load(script("MazeView").Source, { environment = env, debugName = "MazeView" })()
	-- the other adapters as stand-ins, but FlowView's trip is nil (Flow.overlay is real) and PelletView builds a handle
	local stubs: { [string]: any } = {
		["./MazeView"] = mv,
		["./FlowView"] = setmetatable({
			trip = function(): any
				return nil
			end,
		}, {
			__index = function(_: any, _key: string): any
				return function() end
			end,
		}),
		["./PelletView"] = setmetatable({
			build = function(): any
				return { pellets = true }
			end,
		}, {
			__index = function(_: any, _key: string): any
				return function() end
			end,
		}),
	}
	env.require = requirer(stubs)
	luau.load(script("Main").Source, { environment = env, debugName = "Main" })()
	return {
		push = function(f: Session.Frame)
			(onFrame :: (Session.Frame) -> ())(f)
		end,
		made = made,
		model = function(): Inst?
			local found: Inst? = nil
			for _, c in world:GetChildren() do
				if c.Name == "Maze" then
					t.expect(found).toBe(nil) -- one maze model in the world
					found = c
				end
			end
			return found
		end,
	}
end

local function frame(opened: { Maze.Tile }, marked: { Maze.Tile }): Session.Frame
	local s = Session.new(classic, 1)
	Session.join(s, "p")
	local f = Session.frame(s, "p")
	f.walls = { opened = opened, marked = marked }
	return f
end

return t.spec("c0228 walls built once per maze", function(it)
	it(
		"MazeView.build draws the walls with the marks it is given: gold where marked, blue elsewhere",
		function()
			local mv, made = mazeView()
			local holed = Maze.opened(classic, { at(2, 2), at(14, 10) })
			local marks = { at(7, 2), at(25, 6), at(3, 2) }
			local model = mv.build(holed, marks)
			drawnAs(model, holed, marks, BLUE, GOLD)
			t.expect(wallsMade(made, 1)).toBe(#View.walls(holed, nil, marks)) -- each run drawn once
			t.expect(#partsNamed(model, "Door") > 0 and #partsNamed(model, "Floor") == 1).toBe(true)
		end
	)

	it("MazeView.build without marks draws every wall blue and none gold, as before", function()
		local mv, made = mazeView()
		local model = mv.build(classic)
		drawnAs(model, classic, nil, BLUE, GOLD)
		t.expect(#partsNamed(model, "MarkedWall")).toBe(0)
		t.expect(wallsMade(made, 1)).toBe(#View.walls(classic))
	end)

	it(
		"a rewall to the walls the model has drawn makes and destroys no part, however the maze and marks were made",
		function()
			local mv, made = mazeView()
			local holes = { at(2, 2), at(14, 10) }
			local model = mv.build(Maze.opened(classic, holes), { at(7, 2), at(25, 6) })
			local before = wallParts(model)
			local n = #made
			-- an equal maze (another table) and the same marks (new tables, another order)
			mv.rewall(
				model,
				Maze.opened(Maze.layout("classic"), { at(14, 10), at(2, 2) }),
				{ at(25, 6), at(7, 2) }
			)
			t.expect(#made).toBe(n)
			t.expect(wallParts(model)).toEqual(before) -- the same parts, in the same order
			for _, p in before do
				t.expect(p.Parent).toBe(model)
			end
			-- walls a rewall drew are drawn walls too
			local moved = { at(3, 2), at(25, 6) }
			mv.rewall(model, Maze.opened(classic, holes), moved)
			local after = wallParts(model)
			local m = #made
			mv.rewall(model, Maze.opened(classic, holes), { at(3, 2), at(25, 6) })
			t.expect(#made).toBe(m)
			t.expect(wallParts(model)).toEqual(after)
		end
	)

	it("a rewall to the drawn walls keeps their lit and edible colours", function()
		local mv = mazeView()
		local marks = { at(2, 2) }
		local model = mv.build(classic, marks)
		mv.edible(model, true)
		mv.rewall(model, classic, { at(2, 2) })
		drawnAs(model, classic, marks, GREEN, GOLD)
		mv.flash(model, true)
		mv.rewall(model, classic, { at(2, 2) })
		drawnAs(model, classic, marks, LIT, LIT)
		mv.flash(model, false)
		mv.edible(model, false)
		drawnAs(model, classic, marks, BLUE, GOLD)
	end)

	it(
		"a rewall to other walls draws them: a moved mark, a new hole, a one-tile run marked or not",
		function()
			local mv, made = mazeView()
			local model = mv.build(classic, { at(2, 2) })
			local cases: { { m: Maze.Maze, marks: { Maze.Tile } } } = {
				{ m = classic, marks = { at(3, 2) } }, -- the mark moved
				{ m = Maze.opened(classic, { at(2, 2) }), marks = { at(3, 2) } }, -- a hole opened
				{ m = Maze.opened(classic, { at(2, 2) }), marks = { at(3, 2), lone() } }, -- a one-tile run marked
				{ m = Maze.opened(classic, { at(2, 2) }), marks = { at(3, 2) } }, -- and unmarked again
				{ m = classic, marks = {} }, -- the hole closed, no marks
			}
			for _, c in cases do
				local n = #made
				mv.rewall(model, c.m, c.marks)
				drawnAs(model, c.m, c.marks, BLUE, GOLD)
				t.expect(wallsMade(made, n + 1)).toBe(#View.walls(c.m, nil, c.marks)) -- drawn whole, once
			end
		end
	)

	-- design review 001 F1: f0126's "rebuilt while lit: lit" now reaches a skip, so the draw under each colour state
	-- is checked here, each with a newly marked run (the flash wins over the edible green)
	it(
		"a rewall to other walls draws them in the model's lit and edible colours, a new mark included",
		function()
			local mv, made = mazeView()
			local model = mv.build(classic, { at(2, 2) })
			local states = {
				{ lit = false, edible = false, wall = BLUE, gold = GOLD, marks = { at(3, 2) } },
				{ lit = false, edible = true, wall = GREEN, gold = GOLD, marks = { at(7, 2) } },
				{ lit = true, edible = false, wall = LIT, gold = LIT, marks = { at(25, 6) } },
				{ lit = true, edible = true, wall = LIT, gold = LIT, marks = { at(8, 2) } },
			}
			for _, st in states do
				mv.flash(model, st.lit)
				mv.edible(model, st.edible)
				local n = #made
				mv.rewall(model, classic, st.marks)
				-- the new mark is a wall, drawn marked (more than once where View.walls draws a tunnel margin's copy)
				t.expect(#partsNamed(model, "MarkedWall") > 0).toBe(true)
				drawnAs(model, classic, st.marks, st.wall, st.gold)
				t.expect(wallsMade(made, n + 1)).toBe(#View.walls(classic, nil, st.marks)) -- drawn whole, once
			end
		end
	)

	-- design review 001 F2: what a model has drawn is that model's own
	it("each maze model keeps its own drawn walls", function()
		local mv, made = mazeView()
		local marks = { at(2, 2), at(7, 2) }
		local other = { at(3, 2) }
		local a = mv.build(classic, marks)
		local b = mv.build(classic, { at(2, 2), at(7, 2) }) -- equal walls, another model
		drawnAs(a, classic, marks, BLUE, GOLD)
		drawnAs(b, classic, marks, BLUE, GOLD)
		t.expect(wallsMade(made, 1)).toBe(2 * #View.walls(classic, nil, marks))
		local n = #made
		mv.rewall(a, classic, other) -- A to other walls: drawn, once
		t.expect(wallsMade(made, n + 1)).toBe(#View.walls(classic, nil, other))
		drawnAs(a, classic, other, BLUE, GOLD)
		n = #made
		mv.rewall(b, classic, { at(7, 2), at(2, 2) }) -- B to its own walls: nothing
		t.expect(#made).toBe(n)
		drawnAs(b, classic, marks, BLUE, GOLD)
		mv.rewall(b, classic, { at(3, 2) }) -- B to A's new walls: drawn whole, once
		t.expect(wallsMade(made, n + 1)).toBe(#View.walls(classic, nil, other))
		drawnAs(b, classic, other, BLUE, GOLD)
		drawnAs(a, classic, other, BLUE, GOLD)
	end)

	it("Main builds every wall once on a maze's first frame, with the frame's holes and marks", function()
		for _, opened in { {}, { at(2, 2), at(14, 10) } } do
			local w = mainWorld()
			local marks = { at(7, 2), at(25, 6), at(3, 2) }
			local f = frame(opened, marks)
			w.push(f)
			local model = w.model() :: Inst
			t.expect(model ~= nil).toBe(true)
			local m = View.frameMaze(f)
			t.expect(wallsMade(w.made, 1)).toBe(#View.walls(m, nil, marks))
			drawnAs(model, m, marks, BLUE, GOLD)
			-- the floor is the layout's, holes or not: picks open interior walls only, so View.bounds' tunnel
			-- margins are the same for the frame's maze as for the layout (design review 001 F4)
			local floors = partsNamed(model, "Floor")
			t.expect(#floors).toBe(1)
			local plain = mazeView().build(classic)
			t.expect(floors[1].Size).toEqual(partsNamed(plain, "Floor")[1].Size)
			t.expect(floors[1].Position).toEqual(partsNamed(plain, "Floor")[1].Position)
		end
	end)

	it(
		"Main draws no wall again while the holes and marks stay, and each new wall once when they change",
		function()
			local w = mainWorld()
			local marks = { at(7, 2), at(25, 6), at(3, 2) }
			w.push(frame({}, marks))
			local model = w.model() :: Inst
			local before = wallParts(model)
			local n = #w.made
			w.push(frame({}, { at(7, 2), at(25, 6), at(3, 2) }))
			w.push(frame({}, { at(3, 2), at(7, 2), at(25, 6) })) -- the same marks in another order
			t.expect(wallsMade(w.made, n + 1)).toBe(0)
			t.expect(wallParts(model)).toEqual(before)
			-- a pick: a hole opens and a new mark comes
			local picked = { at(7, 2), at(25, 6), at(8, 2) }
			local next = frame({ at(3, 2) }, picked)
			w.push(next)
			local m = View.frameMaze(next)
			t.expect(wallsMade(w.made, n + 1)).toBe(#View.walls(m, nil, picked))
			drawnAs(model, m, picked, BLUE, GOLD)
			t.expect(w.model()).toBe(model) -- the same maze model: only its walls were drawn again
		end
	)
end)
