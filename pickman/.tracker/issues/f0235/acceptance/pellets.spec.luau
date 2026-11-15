--!strict
-- f0235 AC3: PelletView, run from its real source in the built place on a small stub engine, and judged by the
-- parts it makes, found from the model it was handed (pickman-test lesson drawn-from-the-visible-root). For each
-- power pellet it builds one part named "Beacon" in the "Pellets" model: anchored, colliding, queried and touched by
-- nothing, casting no shadow, neon, in the pellets' own colour, not a ball, at View.beacon's centre and size, and
-- hidden. Each render step it reads the eye's height and place from the two getters PelletView.start was given
-- (Camera.eye, Camera.pose): while View.elevated says the eye is above the walls, the beacon of every power pellet the
-- last shown code holds has View.BEACON.transparency, unless the eye is within View.BEACON.clear tiles of it, and every
-- other beacon 1; a frame that changes no beacon's state writes no beacon. The beacons keep View.beacon's size and
-- place every frame (they do not pulse). The pellets themselves stay as the code says, whatever the eye, and the power
-- pellets still pulse. A maze built again has its own beacons lit.
-- The stub require gives the real Logic for any Logic feature, by name for one added later (pickman-test lesson
-- stub-loaders-fall-back).
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local View = require("@logic/View")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local V = View :: any
local game = place.load()
local classic = Maze.layout("classic")
local STAND = View.SCALE.eyeHeight
local TOP = View.SCALE.eyeHeight + 14 -- a jump's top (Hop.RISE), as the camera draws it

local LOGIC: { [string]: any } = { Maze = Maze, Pellets = Pellets, View = View }

local function source(name: string): string
	local node = game:FindFirstChild("StarterPlayer")
	for _, child in { "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(child)
	end
	t.expect(node ~= nil).toBe(true)
	return node.Source
end

type Inst = { [string]: any }

local writes: { [Inst]: { [string]: number } } = {}

-- A stub instance: plain fields; setting Parent files it under its parent; each write is counted.
local function instance(class: string): Inst
	local children: { Inst } = {}
	local props: { [string]: any } = { ClassName = class, Transparency = 0 }
	local self: Inst
	self = setmetatable({}, {
		__index = function(_: any, key: string): any
			if key == "children" then
				return children
			elseif key == "Destroy" then
				return function()
					local parent = props.Parent
					if parent then
						local i = table.find(parent.children, self)
						if i then
							table.remove(parent.children, i)
						end
					end
					props.Parent = nil
				end
			end
			return props[key]
		end,
		__newindex = function(_: any, key: string, value: any)
			if key == "Parent" and value ~= props.Parent then
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
			local w = writes[self] or {}
			writes[self] = w
			w[key] = (w[key] or 0) + 1
			props[key] = value
		end,
	}) :: any
	return self
end

local function transparencyWrites(i: Inst): number
	local w = writes[i]
	return if w then w.Transparency or 0 else 0
end

local function enumProxy(): any
	return setmetatable({}, {
		__index = function(self: any, group: string): any
			local g = setmetatable({}, {
				__index = function(gs: any, item: string): any
					local v = { Name = item, EnumType = group }
					rawset(gs, item, v)
					return v
				end,
			})
			rawset(self, group, g)
			return g
		end,
	})
end

local vmeta = {}
local function vec(x: number, y: number, z: number): any
	return setmetatable({ X = x, Y = y, Z = z }, vmeta)
end
vmeta.__mul = function(a: any, k: any): any
	if type(a) == "number" then
		a, k = k, a
	end
	return vec(a.X * k, a.Y * k, a.Z * k)
end

type World = {
	view: any,
	render: () -> (),
	setEye: (number?) -> (),
	setPose: (View.Pose?) -> (),
	clock: (number) -> (),
}

local function world(): World
	local stepped: { () -> () } = {}
	local eye: number? = nil
	local pose: View.Pose? = nil
	local now = 0
	local env: { [string]: any } = {
		Enum = enumProxy(),
		Instance = {
			new = function(class: string): Inst
				return instance(class)
			end,
		},
		Vector3 = { new = vec, one = vec(1, 1, 1), zero = vec(0, 0, 0) },
		Color3 = {
			fromRGB = function(r: number, g: number, b: number): any
				return { R = r, G = g, B = b }
			end,
		},
		os = setmetatable({
			clock = function(): number
				return now
			end,
		}, { __index = os }),
		game = {
			GetService = function(_: any, name: string): any
				t.expect(name).toBe("RunService")
				local function connect(_: any, fn: () -> ())
					table.insert(stepped, fn)
				end
				return {
					RenderStepped = { Connect = connect },
					BindToRenderStep = function(_: any, _n: string, _p: number, fn: () -> ())
						table.insert(stepped, fn)
					end,
				}
			end,
		},
	}
	env.require = function(spec: string): any
		local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
		if name then
			return LOGIC[name] or (require :: any)("@logic/" .. name)
		end
		error(`unexpected require {spec}`)
	end
	local view = luau.load(source("PelletView"), { environment = env, debugName = "PelletView" })()
	view.start(function(): number?
		return eye
	end, function(): View.Pose?
		return pose
	end)
	t.expect(#stepped >= 1).toBe(true) -- the pulse's handler, and the beacons' (one handler or two)
	return {
		view = view,
		render = function()
			for _, fn in stepped do
				fn()
			end
		end,
		setEye = function(e: number?)
			eye = e
		end,
		setPose = function(p: View.Pose?)
			pose = p
		end,
		clock = function(s: number)
			now = s
		end,
	}
end

local function named(parent: Inst, name: string): { Inst }
	local out: { Inst } = {}
	for _, c in parent.children do
		if c.Name == name then
			table.insert(out, c)
		end
	end
	return out
end

local function pelletsModel(parent: Inst): Inst
	local models = named(parent, "Pellets")
	t.expect(#models).toBe(1)
	return models[1]
end

local function beacons(parent: Inst): { Inst }
	return named(pelletsModel(parent), "Beacon")
end

local function powerSlots(): { Pellets.Slot }
	local out: { Pellets.Slot } = {}
	for _, slot in Pellets.slots(classic) do
		if slot.kind == "power" then
			table.insert(out, slot)
		end
	end
	return out
end

-- the beacon standing over `slot`'s tile, by its centre
local function beaconAt(parent: Inst, slot: Pellets.Slot): Inst
	local want = V.beacon(slot)
	local found: Inst? = nil
	for _, b in beacons(parent) do
		local p = b.Position
		if p and math.abs(p.X - want.x) < 1e-6 and math.abs(p.Z - want.z) < 1e-6 then
			t.expect(found).toBe(nil)
			found = b
		end
	end
	t.expect(found ~= nil).toBe(true)
	return found :: Inst
end

local function codeWithout(eaten: { Maze.Tile }): string
	local p = Pellets.new(classic)
	for _, tile in eaten do
		Pellets.eat(p, tile)
	end
	return Pellets.encode(p)
end

local FULL = codeWithout({})
local POWER = Pellets.tiles(Pellets.new(classic), "power")

local function built(): (World, Inst, any)
	local w = world()
	local parent = instance("Model")
	local h = w.view.build(classic, parent)
	return w, parent, h
end

local function lit(b: Inst): boolean
	return b.Transparency == V.BEACON.transparency
end

local function hidden(b: Inst): boolean
	return b.Transparency == 1
end

return t.spec("f0235 PelletView's beacons", function(it)
	it(
		"builds one Beacon per power pellet in the Pellets model, placed and sized by View.beacon, hidden",
		function()
			local _, parent = built()
			t.expect(#beacons(parent)).toBe(#powerSlots())
			local ball = named(pelletsModel(parent), "power")[1]
			t.expect(ball ~= nil).toBe(true)
			for _, slot in powerSlots() do
				local b = beaconAt(parent, slot)
				local want = V.beacon(slot)
				t.expect(b.ClassName).toBe("Part")
				t.expect(b.Anchored).toBe(true)
				t.expect(b.CanCollide).toBe(false)
				t.expect(b.CanQuery).toBe(false)
				t.expect(b.CanTouch).toBe(false)
				t.expect(b.CastShadow).toBe(false)
				t.expect(b.Material and b.Material.Name).toBe("Neon")
				t.expect(b.Shape == nil or b.Shape.Name == "Block").toBe(true)
				t.expect(b.Color).toEqual(ball.Color)
				t.expect(b.Position.Y).toBeNear(want.y, 1e-9)
				t.expect(b.Size.X).toBeNear(want.width, 1e-9)
				t.expect(b.Size.Y).toBeNear(want.height, 1e-9)
				t.expect(b.Size.Z).toBeNear(want.width, 1e-9)
				t.expect(hidden(b)).toBe(true)
			end
		end
	)

	it("standing, no beacon shows", function()
		local w, parent, h = built()
		w.view.show(h, FULL)
		w.setEye(STAND)
		w.render()
		for _, b in beacons(parent) do
			t.expect(hidden(b)).toBe(true)
		end
	end)

	it("before the camera has drawn an eye, no beacon shows", function()
		local w, parent, h = built()
		w.view.show(h, FULL)
		w.setEye(nil)
		w.render()
		for _, b in beacons(parent) do
			t.expect(hidden(b)).toBe(true)
		end
	end)

	it("at a jump's top every power pellet left has its beacon, an eaten one none", function()
		local w, parent, h = built()
		w.view.show(h, codeWithout({ POWER[1], POWER[3] }))
		w.setEye(TOP)
		w.render()
		for _, slot in powerSlots() do
			local eaten = (slot.x == POWER[1].x and slot.y == POWER[1].y)
				or (slot.x == POWER[3].x and slot.y == POWER[3].y)
			t.expect(lit(beaconAt(parent, slot))).toBe(not eaten)
			t.expect(hidden(beaconAt(parent, slot))).toBe(eaten)
		end
	end)

	it(
		"the wall tops are the line: at them hidden, a hair over shown, and back under hidden again",
		function()
			local w, parent, h = built()
			w.view.show(h, FULL)
			local cases: { { eye: number, shown: boolean } } = {
				{ eye = View.SCALE.wallHeight, shown = false },
				{ eye = View.SCALE.wallHeight + 0.01, shown = true },
				{ eye = 8.5, shown = false },
			}
			for _, case in cases do
				w.setEye(case.eye)
				w.render()
				for _, b in beacons(parent) do
					t.expect(lit(b)).toBe(case.shown)
				end
			end
		end
	)

	it("held at a jump's top, the beacons stay shown frame after frame (f0234's wait)", function()
		local w, parent, h = built()
		w.view.show(h, FULL)
		w.setEye(TOP)
		for _ = 1, 5 do
			w.render()
			for _, b in beacons(parent) do
				t.expect(lit(b)).toBe(true)
			end
		end
	end)

	it("a power pellet eaten or brought back while up changes its beacon at the next frame", function()
		local w, parent, h = built()
		local target = powerSlots()[2]
		w.view.show(h, FULL)
		w.setEye(TOP)
		w.render()
		t.expect(lit(beaconAt(parent, target))).toBe(true)
		w.view.show(h, codeWithout({ { x = target.x, y = target.y } }))
		w.render()
		t.expect(hidden(beaconAt(parent, target))).toBe(true)
		w.view.show(h, FULL) -- the pellets-back boon (f0126)
		w.render()
		t.expect(lit(beaconAt(parent, target))).toBe(true)
	end)

	it("landing hides every beacon", function()
		local w, parent, h = built()
		w.view.show(h, FULL)
		w.setEye(TOP)
		w.render()
		w.setEye(STAND + 1)
		w.render()
		for _, b in beacons(parent) do
			t.expect(hidden(b)).toBe(true)
		end
	end)

	it("a frame that changes no beacon's state writes no beacon", function()
		local w, parent, h = built()
		w.view.show(h, FULL)
		w.setEye(TOP)
		w.render()
		local before: { [Inst]: number } = {}
		for _, b in beacons(parent) do
			before[b] = transparencyWrites(b)
		end
		w.setEye(TOP - 2) -- still over the walls
		w.render()
		w.setPose({ x = 13.5, y = 23 }) -- far from every power pellet, and moving
		w.render()
		w.setPose({ x = 14, y = 23 })
		w.render()
		w.view.show(h, FULL)
		w.render()
		for _, b in beacons(parent) do
			t.expect(transparencyWrites(b)).toBe(before[b])
		end
	end)

	it("the pellets stay as the code says whatever the eye, and the power pellets still pulse", function()
		local w, parent, h = built()
		local code = codeWithout({ POWER[1], { x = 1, y = 1 } })
		w.view.show(h, code)
		local present = Pellets.decode(classic, code)
		local model = pelletsModel(parent)
		local function check()
			local i = 0
			for _, c in model.children do
				if c.Name ~= "Beacon" then
					i += 1
					local slot = Pellets.slots(classic)[i]
					t.expect(c.Name).toBe(slot.kind)
					t.expect(c.Transparency).toBe(if present[i] then 0 else 1)
				end
			end
			t.expect(i).toBe(#Pellets.slots(classic))
		end
		for _, eye in { STAND, TOP, STAND } do
			w.setEye(eye)
			w.render()
			check()
		end
		w.clock(V.PELLET.pulseSeconds / 2) -- half a pulse in: the power pellets at their smallest
		w.render()
		local ball = named(model, "power")[1]
		t.expect(ball.Size.X).toBeNear(V.PELLET.power * V.pulse("power", V.PELLET.pulseSeconds / 2), 1e-9)
	end)

	it("the beacons keep View.beacon's size and place every frame: they do not pulse", function()
		local w, parent, h = built()
		w.view.show(h, FULL)
		w.setEye(TOP)
		for _, at in { 0, V.PELLET.pulseSeconds / 4, V.PELLET.pulseSeconds / 2, V.PELLET.pulseSeconds * 0.8 } do
			w.clock(at)
			w.render()
			for _, slot in powerSlots() do
				local b = beaconAt(parent, slot)
				local want = V.beacon(slot)
				t.expect(lit(b)).toBe(true)
				t.expect(b.Position.Y).toBeNear(want.y, 1e-9)
				t.expect(b.Size.X).toBeNear(want.width, 1e-9)
				t.expect(b.Size.Y).toBeNear(want.height, 1e-9)
				t.expect(b.Size.Z).toBeNear(want.width, 1e-9)
			end
		end
	end)

	it(
		"a hop down a power pellet's corridor hides its beacon while the eye is near it, then shows it again",
		function()
			local w, parent, h = built()
			w.view.show(h, FULL)
			w.setEye(TOP)
			local target = powerSlots()[1]
			local clear = V.BEACON.clear
			local hid, relit = false, false
			for k = -16, 16 do
				local x = target.x + k / 4
				w.setPose({ x = x, y = target.y })
				w.render()
				local near = math.abs(x - target.x) < clear
				t.expect(lit(beaconAt(parent, target))).toBe(not near)
				t.expect(hidden(beaconAt(parent, target))).toBe(near)
				hid = hid or near
				relit = relit or (hid and not near)
				for _, other in powerSlots() do
					if other.x ~= target.x or other.y ~= target.y then
						t.expect(lit(beaconAt(parent, other))).toBe(true)
					end
				end
			end
			t.expect(hid and relit).toBe(true)
		end
	)

	it("an eye exactly clear tiles away shows the beacon; a hair nearer hides it", function()
		local w, parent, h = built()
		w.view.show(h, FULL)
		w.setEye(TOP)
		local target = powerSlots()[3]
		local clear = V.BEACON.clear
		w.setPose({ x = target.x, y = target.y + clear })
		w.render()
		t.expect(lit(beaconAt(parent, target))).toBe(true)
		w.setPose({ x = target.x, y = target.y + clear - 0.01 })
		w.render()
		t.expect(hidden(beaconAt(parent, target))).toBe(true)
	end)

	it("a maze built again has its own beacons shown, from its own code", function()
		local w, _, h = built()
		w.view.show(h, FULL)
		w.setEye(TOP)
		w.render()
		local parent2 = instance("Model")
		local h2 = w.view.build(classic, parent2)
		w.view.show(h2, codeWithout({ POWER[4] }))
		w.render()
		local shown = 0
		for _, b in beacons(parent2) do
			if lit(b) then
				shown += 1
			end
		end
		t.expect(shown).toBe(3)
	end)
end)
