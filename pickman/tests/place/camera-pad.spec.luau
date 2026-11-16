--!strict
-- R0058 code review 001 F1: Camera's real source runs on a small stub engine, so the right stick's look is pinned by
-- what the camera does, not by its text: the stick turns the view (yaw and pitch, at Pad.look's rate through
-- View.look), the look stays where it is left when the stick is released, a read of nothing or inside the dead zone
-- changes nothing, it applies in play (the mouse locked) as well as with the cursor free, and R2 then fires where the
-- player looks (Camera.aim). Expected values come from the same Logic calls, so the spec does not restate the rates.
local Maze = require("@logic/Maze")
local Pad = require("@logic/Pad")
local Session = require("@logic/Session")
local View = require("@logic/View")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()
local SOURCE = (function(): string
	local node = game:FindFirstChild("StarterPlayer")
	for _, child in { "StarterPlayerScripts", "Client", "Camera" } do
		node = node and node:FindFirstChild(child)
	end
	assert(node, "no Client.Camera in the game place")
	return node.Source
end)()

local DT = 1 / 60
local NO_ARROWS: View.Arrows = { up = false, down = false, left = false, right = false }

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
	render: (frames: number) -> (),
	stick: { x: number?, y: number? },
	pitch: () -> number, -- the pitch of the latest frame's CFrame (its last CFrame.Angles x)
	heading: Maze.Heading,
}

local function rig(): Rig
	local step: ((number) -> ())? = nil
	local angles: { { number } } = {}
	local frame: any = {}
	local cframe = {
		new = function(): any
			return frame
		end,
		Angles = function(x: number, y: number, z: number): any
			table.insert(angles, { x, y, z })
			return frame
		end,
	}
	setmetatable(frame, {
		__mul = function(a: any, _b: any): any
			return a
		end,
	})
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_: any, _name: string, _priority: number, fn: (number) -> ())
				step = fn
			end,
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
				return 0
			end,
		},
	}
	local camera = luau.load(SOURCE, { environment = env, debugName = "Camera" })() :: any
	local stick: { x: number?, y: number? } = { x = nil, y = nil }
	camera.pad(function(name: string): (number?, number?)
		if name == "Thumbstick2" then
			return stick.x, stick.y
		end
		return nil, nil
	end)
	camera.start()
	local s = Session.new(Maze.layout(Maze.DEFAULT), 1)
	Session.join(s, "p")
	local snap = Session.snapshot(s, "p")
	camera.push(snap)
	return {
		camera = camera,
		stick = stick,
		heading = snap.player.heading,
		render = function(frames: number)
			for _ = 1, frames do
				(step :: (number) -> ())(DT)
			end
		end,
		pitch = function(): number
			return angles[#angles][1]
		end,
	}
end

-- the look the stick at (x, y) gives after `frames` render steps, by the Logic the camera uses
local function expected(x: number, y: number, frames: number): View.Look
	local l: View.Look = { yaw = 0, pitch = 0 }
	for _ = 1, frames do
		l = View.look(l, Pad.look(x, y, DT))
	end
	return l
end

-- the camera's look yaw: its pose's yaw less the heading's, as View defines both
local function lookYaw(r: Rig): number
	return (r.camera.pose().yaw :: number) - View.headingYaw(r.heading)
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

return t.spec("Camera's right stick on a stub engine", function(it)
	it(
		"the stick pushed right turns the view right at Pad.look's rate, and the look stays when released",
		function()
			local r = rig()
			r.render(1)
			t.expect(near(lookYaw(r), 0)).toBe(true)
			r.stick.x, r.stick.y = 1, 0
			r.render(30)
			local want = expected(1, 0, 30)
			t.expect(want.yaw ~= 0).toBe(true)
			t.expect(near(lookYaw(r), want.yaw)).toBe(true)
			r.stick.x, r.stick.y = 0, 0
			r.render(30)
			t.expect(near(lookYaw(r), want.yaw)).toBe(true) -- not sprung back, as the mouse's look
		end
	)

	it("the stick pushed up raises the pitch", function()
		local r = rig()
		r.stick.x, r.stick.y = 0, 1
		r.render(20)
		local want = expected(0, 1, 20)
		t.expect(want.pitch ~= 0).toBe(true)
		t.expect(near(r.pitch(), want.pitch)).toBe(true)
	end)

	it("a read of nothing, or a tilt inside the dead zone, changes nothing", function()
		local r = rig()
		r.render(10)
		r.stick.x, r.stick.y = Pad.LOOK_DEAD / 2, 0
		r.render(10)
		t.expect(near(lookYaw(r), 0)).toBe(true)
		r.stick.x, r.stick.y = 1, nil
		r.render(10)
		t.expect(near(lookYaw(r), 0)).toBe(true)
		t.expect(near(r.pitch(), 0)).toBe(true)
	end)

	it("the stick looks in play (the mouse locked) as well as with the cursor free", function()
		for _, free in { false, true } do
			local r = rig()
			r.camera.setCursor(free)
			r.stick.x, r.stick.y = -1, 0
			r.render(15)
			t.expect(near(lookYaw(r), expected(-1, 0, 15).yaw)).toBe(true)
		end
	end)

	it("after a look to the right, R2's aim is the heading to the right of the run's", function()
		local r = rig()
		r.stick.x, r.stick.y = 1, 0
		r.render(30)
		local want = View.aim(r.heading, { look = expected(1, 0, 30), spring = false }, NO_ARROWS)
		t.expect(want ~= r.heading).toBe(true)
		t.expect(r.camera.aim()).toBe(want)
	end)
end)
