--!strict
-- f0235 AC4 (the eye): Camera's real source on a small stub engine, whose CFrame.new records the height each frame is
-- built at. Camera.eye() is that height, the eye the camera drew, on every frame: nil before any snapshot; the
-- standing height on the ground; eyeHeight + Hop.RISE at a hop's top; and, through a hop and a long hop drawn step by
-- step, the drawn height each time (so a rise between the clearance and the wall height, which only the eye and not
-- the rise puts over the walls, is elevated). Camera.pose() is the place PelletView's clearance is measured from.
-- The stub resolves any Logic feature by name, so a Camera that requires one more still loads (pickman-test lesson
-- stub-loaders-fall-back); a Camera that adds more to the drawn eye (f0234's hold) is judged the same way.
local Hop = require("@logic/Hop")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local View = require("@logic/View")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local V = View :: any
local game = place.load()
local SOURCE = (function(): string
	local node = game:FindFirstChild("StarterPlayer")
	for _, child in { "StarterPlayerScripts", "Client", "Camera" } do
		node = node and node:FindFirstChild(child)
	end
	assert(node, "no Client.Camera in the game place")
	return node.Source
end)()

local EYE = View.SCALE.eyeHeight

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

type Rig = {
	camera: any,
	snap: Session.Snapshot,
	render: () -> number?, -- one render step; the height its CFrame was built at (nil: none built)
}

local function rig(push: boolean): Rig
	local step: ((number) -> ())? = nil
	local heights: { number } = {}
	local frame: any = setmetatable({}, {
		__mul = function(a: any, _b: any): any
			return a
		end,
	})
	local cframe = {
		new = function(_x: number, y: number, _z: number): any
			table.insert(heights, y)
			return frame
		end,
		Angles = function(_x: number, _y: number, _z: number): any
			return frame
		end,
	}
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_: any, _name: string, _priority: number, fn: (number) -> ())
				step = fn
			end,
			RenderStepped = {
				Connect = function(_: any, _fn: () -> ()) end,
			},
		},
		UserInputService = {
			GetMouseDelta = function(): any
				return { X = 0, Y = 0 }
			end,
		},
	}
	local env = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], name)
			end,
		},
		workspace = { CurrentCamera = {} },
		Enum = enumProxy(),
		CFrame = cframe,
		require = function(spec: string): any
			local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
			return (require :: any)("@logic/" .. assert(name, spec))
		end,
		os = {
			clock = function(): number
				return 0 -- the frame just arrived: the shown tick is the latest snapshot's
			end,
		},
	}
	local camera = luau.load(SOURCE, { environment = env, debugName = "Camera" })() :: any
	camera.start()
	local s = Session.new(Maze.layout("classic"), 1, Session.GAME_CONFIG)
	Session.join(s, "p")
	local snap = Session.snapshot(s, "p")
	if push then
		camera.push(snap)
	end
	return {
		camera = camera,
		snap = snap,
		render = function(): number?
			local before = #heights;
			(step :: (number) -> ())(1 / 60)
			return if #heights > before then heights[#heights] else nil
		end,
	}
end

return t.spec("f0235 Camera.eye is the eye the camera drew", function(it)
	it("before any snapshot it is nil, and no frame is drawn", function()
		local r = rig(false)
		t.expect(r.render()).toBe(nil)
		t.expect(r.camera.eye()).toBe(nil)
	end)

	it("on the ground it is the standing height the frame was built at", function()
		local r = rig(true)
		local drawn = r.render()
		t.expect(drawn).toBe(EYE)
		t.expect(r.camera.eye()).toBe(drawn)
		t.expect(V.elevated(r.camera.eye())).toBe(false)
	end)

	it("at a hop's top it is eyeHeight + Hop.RISE, as drawn, and elevated", function()
		local r = rig(true)
		r.camera.hopped(r.snap.tick - Hop.TICKS / 2)
		local drawn = r.render()
		t.expect(drawn).toBe(EYE + Hop.RISE)
		t.expect(r.camera.eye()).toBe(drawn)
		t.expect(V.elevated(r.camera.eye())).toBe(true)
	end)

	it("through a hop and a long hop, step by step, it is the drawn height on every frame", function()
		local lengths: { number } = { Hop.TICKS, Hop.LONG_TICKS }
		for _, ticks in lengths do
			local r = rig(true)
			r.camera.hopTicks(ticks)
			local between = false
			for k = 0, ticks + 2 do
				r.camera.hopped(r.snap.tick - k)
				local drawn = r.render() :: number
				t.expect(drawn).toBeNear(EYE + Hop.rise(r.snap.tick - k, r.snap.tick, ticks), 1e-9)
				t.expect(r.camera.eye()).toBe(drawn)
				local rise = drawn - EYE
				if rise > Hop.CLEARANCE and rise <= View.SCALE.wallHeight then
					between = true -- the rise alone is not over the walls; the eye is
					t.expect(V.elevated(r.camera.eye())).toBe(true)
				end
			end
			if ticks == Hop.LONG_TICKS then
				t.expect(between).toBe(true)
			end
		end
	end)

	it("after landing it is the standing height again", function()
		local r = rig(true)
		r.camera.hopped(r.snap.tick - Hop.TICKS / 2)
		r.render()
		r.camera.hopped(r.snap.tick - Hop.TICKS)
		local drawn = r.render()
		t.expect(drawn).toBe(EYE)
		t.expect(r.camera.eye()).toBe(EYE)
	end)

	it("Camera.pose is the drawn place, in tile coordinates", function()
		local r = rig(true)
		r.render()
		local pose = r.camera.pose()
		t.expect(pose ~= nil).toBe(true)
		t.expect(pose.x).toBe(r.snap.player.x)
		t.expect(pose.y).toBe(r.snap.player.y)
	end)
end)
