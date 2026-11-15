--!strict
-- f0234 AC3: the camera's real source on a small stub engine, fed the frames of a real run (Session.GAME_CONFIG) the
-- way Main feeds them (push, hopped, hopTicks, ready). While a READY pause runs (the run's start, a new life) the
-- eye is the standing height plus Hop.held at the tick being shown: the top of a hop, held, then the landing, down
-- on the standing height when the first step in play is shown. The look stays live through the pause (the right
-- stick and the mouse turn the view at the top), a hop in play still lifts the eye by Hop.rise, and the height
-- follows the clock, not the frame rate. Expected values come from the same Logic calls the design names.
local Hop = require("@logic/Hop")
local Maze = require("@logic/Maze")
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

local EYE = View.SCALE.eyeHeight
local RULES = assert(Session.GAME_CONFIG.play, "Session.GAME_CONFIG has no play rules")
local STEP = 1 / Session.STEP_RATE -- real seconds per server step

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
	s: Session.Session,
	now: number, -- the stub's os.clock
	stick: { x: number?, y: number? },
	mouse: { x: number, y: number },
	render: (dt: number?) -> number, -- one render step; the eye height it set
	send: () -> Session.Frame, -- one server step, its frame handed to the camera as Main hands it
	pitch: () -> number,
	yaw: () -> number,
}

local function rig(): Rig
	local r: Rig
	local renderStep: ((number) -> ())? = nil
	local heights: { number } = {}
	local angles: { { number } } = {}
	local frame: any = {}
	setmetatable(frame, {
		__mul = function(a: any, _b: any): any
			return a
		end,
	})
	local cframe = {
		new = function(_x: number, y: number, _z: number): any
			table.insert(heights, y)
			return frame
		end,
		Angles = function(x: number, y: number, z: number): any
			table.insert(angles, { x, y, z })
			return frame
		end,
	}
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_: any, _name: string, _priority: number, fn: (number) -> ())
				renderStep = fn
			end,
		},
		UserInputService = {
			GetMouseDelta = function(): any
				local d = { X = r.mouse.x, Y = r.mouse.y }
				r.mouse = { x = 0, y = 0 } -- the read clears it, as the engine's does
				return d
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
				return r.now
			end,
		},
	}
	local camera = luau.load(SOURCE, { environment = env, debugName = "Camera" })() :: any
	local s = Session.new(Maze.layout("classic"), 1, Session.GAME_CONFIG)
	Session.join(s, "p")
	r = {
		camera = camera,
		s = s,
		now = 0,
		stick = { x = nil, y = nil },
		mouse = { x = 0, y = 0 },
		render = function(dt: number?): number
			local before = #heights
			local fn = renderStep :: (number) -> ()
			fn(dt or 1 / 60)
			t.expect(#heights).toBe(before + 1)
			return heights[#heights]
		end,
		send = function(): Session.Frame
			Session.step(s)
			local f = Session.frame(s, "p")
			camera.push(f)
			camera.hopped(f.hopped)
			camera.hopTicks(f.hopTicks)
			camera.ready(f.play, f.tick)
			return f
		end,
		pitch = function(): number
			return angles[#angles][1]
		end,
		yaw = function(): number
			return camera.pose().yaw
		end,
	}
	camera.pad(function(name: string): (number?, number?)
		if name == "Thumbstick2" then
			return r.stick.x, r.stick.y
		end
		return nil, nil
	end)
	camera.start()
	return r
end

-- the tick the camera shows `elapsed` real seconds after the frame `latest` arrived, `prev` the one before
local function shownAt(prev: Session.Frame?, latest: Session.Frame, elapsed: number): number
	return View.shownTick(prev, latest, View.alpha(elapsed))
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

-- one server step every STEP real seconds, rendered `per` times in each; `check(height, shown, frame)` for each render
local function play(r: Rig, steps: number, per: number, check: (number, number, Session.Frame) -> ())
	local prev: Session.Frame? = nil
	for _ = 1, steps do
		local f = r.send()
		local arrived = r.now
		for i = 1, per do
			r.now = arrived + STEP * i / per
			check(r.render(), shownAt(prev, f, r.now - arrived), f)
		end
		prev = f
	end
end

return t.spec("f0234 the camera waits at the top of a hop", function(it)
	it(
		"from the run's first frame the eye is at the top of a hop, and stays there through the pause",
		function()
			local r = rig()
			local f = r.send()
			t.expect(f.play.phase).toBe("ready")
			t.expect(r.render()).toBe(EYE + Hop.RISE)
			play(r, 40, 3, function(h: number)
				t.expect(h).toBe(EYE + Hop.RISE)
			end)
		end
	)

	it("comes down the last half hop of the pause and stands when the first step in play is shown", function()
		local r = rig()
		local playAt: number? = nil
		local landed = false
		local last = math.huge
		play(r, 70, 4, function(h: number, shown: number, f: Session.Frame)
			if f.play.phase == "ready" then
				playAt = f.tick + f.play.timer
			end
			local at = assert(playAt, "the run starts in READY")
			t.expect(near(h, EYE + Hop.held(at, shown))).toBe(true)
			t.expect(h <= last + 1e-9).toBe(true) -- it never rises again
			last = h
			if shown >= at then
				t.expect(h).toBe(EYE)
				landed = true
			elseif at - shown < Hop.TICKS / 2 then
				t.expect(h > EYE and h < EYE + Hop.RISE).toBe(true)
			end
		end)
		t.expect(playAt).toBe(60)
		t.expect(landed).toBe(true)
	end)

	it("after a death the new life's pause is at the top of a hop too, and lands as play resumes", function()
		local r = rig()
		play(r, 70, 1, function() end)
		Session.kill(r.s, "p")
		local sawDying, sawTop, landed = false, false, false
		local playAt: number? = nil
		play(r, RULES.dyingTicks + 70, 2, function(h: number, shown: number, f: Session.Frame)
			if f.play.phase == "dying" then
				sawDying = true
				t.expect(h).toBe(EYE) -- the death itself is on the ground
			elseif f.play.phase == "ready" then
				playAt = f.tick + f.play.timer
				if f.play.timer > Hop.TICKS then
					t.expect(h).toBe(EYE + Hop.RISE)
					sawTop = true
				end
			elseif f.play.phase == "playing" and playAt and shown >= (playAt :: number) then
				t.expect(h).toBe(EYE)
				landed = true
			end
		end)
		t.expect(sawDying and sawTop and landed).toBe(true)
	end)

	it("the right stick and the mouse turn the view at the top of the pause", function()
		local r = rig()
		r.send()
		r.render()
		local yaw0 = r.yaw()
		r.stick.x, r.stick.y = 1, 1
		local h = 0
		for _ = 1, 20 do
			h = r.render()
		end
		t.expect(h).toBe(EYE + Hop.RISE)
		t.expect(math.abs(r.yaw() - yaw0) > 0.1).toBe(true)
		t.expect(r.pitch() ~= 0).toBe(true)
		r.stick.x, r.stick.y = 0, 0
		local yaw1, pitch1 = r.yaw(), r.pitch()
		r.mouse = { x = 50, y = -40 }
		t.expect(r.render()).toBe(EYE + Hop.RISE)
		t.expect(near(r.yaw(), yaw1 - 50 * View.MOUSE_RADIANS_PER_PIXEL)).toBe(true)
		local pitch = math.clamp(pitch1 + 40 * View.MOUSE_RADIANS_PER_PIXEL, -View.MAX_PITCH, View.MAX_PITCH)
		t.expect(near(r.pitch(), pitch)).toBe(true)
	end)

	it("a hop in play still lifts the eye by Hop.rise, with nothing held", function()
		local r = rig()
		play(r, 70, 1, function() end)
		local ok = Session.submit(r.s, "p", Hop.INTENT)
		t.expect(ok).toBe(true)
		local rose = false
		play(r, Hop.TICKS + 2, 3, function(h: number, shown: number, f: Session.Frame)
			t.expect(near(h, EYE + Hop.rise(f.hopped, shown, f.hopTicks))).toBe(true)
			rose = rose or h > EYE + Hop.CLEARANCE
		end)
		t.expect(rose).toBe(true)
	end)

	it("the height follows the clock, not the frame rate", function()
		local a, b = rig(), rig()
		for _ = 1, 57 do
			a.send()
			b.send()
		end
		a.now, b.now = 0.5 * STEP, 0.5 * STEP
		t.expect(near(a.render(1 / 30), b.render(1 / 240))).toBe(true)
		t.expect(a.render(1 / 30) < EYE + Hop.RISE).toBe(true) -- inside the landing
	end)
end)
