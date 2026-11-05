--!strict
-- Client adapter: a scripted first-person camera at the latest replicated position.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Awareness = require("@game/ReplicatedStorage/Shared/Logic/Awareness")
local Hop = require("@game/ReplicatedStorage/Shared/Logic/Hop")
local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local Pad = require("@game/ReplicatedStorage/Shared/Logic/Pad")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")
local View = require("@game/ReplicatedStorage/Shared/Logic/View")

local Camera = {}

local prev: Session.Snapshot? = nil
local latest: Session.Snapshot? = nil
local arrived = 0
local look: View.Look = { yaw = 0, pitch = 0 }
local steer: View.Steer = { look = { yaw = 0, pitch = 0 }, spring = false } -- the arrow look, as of the last frame
local arrows: View.Arrows = { up = false, down = false, left = false, right = false }
local hopped: number? = nil -- the tick the latest hop started, from the server's frame (f0101)
local hopTicks: number? = nil -- that hop's length, from the frame (f0126's longer jumps)
local yaw: number? = nil
local padStick: ((name: string) -> (number?, number?, string?))? = nil -- the driving controller's sticks (Pads.stick)
local cursor = false -- the mouse is free (and shown) for a prompt
local current: Awareness.Pose? = nil
-- a touch looked, or a finger went down or came up, since the last render step; and a finger is down (the
-- locked mouse's delta is then the touch)
local lookedThisFrame, mouseHeld = false, false

-- Snapshots only move forward: a connected client's session is never replaced.
function Camera.push(snap: Session.Snapshot)
	if latest == nil or snap.tick > latest.tick then
		prev = latest
		latest = snap
		arrived = os.clock()
	end
end

-- The camera's pose in tile coordinates and its yaw as View and Awareness define it, as of the last frame,
-- for other client views.
function Camera.pose(): Awareness.Pose?
	return current
end

function Camera.snap()
	look = View.snap(look)
end

-- A touch look of dx, dy pixels, at the mouse's rate and pitch limit.
function Camera.lookBy(dx: number, dy: number)
	lookedThisFrame = true
	look = View.look(look, dx, dy)
end

-- Whether a touch finger is down; while it is, the mouse delta is not applied. The frame of the change is
-- skipped too: a finger that lifts before the render step has already moved the mouse this frame.
function Camera.holdMouse(held: boolean)
	mouseHeld = held
	lookedThisFrame = true
end

-- The arrow keys held (f0104): they look, and the view springs back when they are let go.
function Camera.arrows(a: View.Arrows)
	arrows = { up = a.up, down = a.down, left = a.left, right = a.right }
end

-- The spy hop (f0101): the tick the latest hop started, as the server's frame says (nil: none yet). The server
-- decides when a hop starts and when the player is airborne; the camera only shows it.
function Camera.hopped(tick: number?)
	hopped = tick
end

-- The latest hop's length in steps, as the server's frame says (nil: Hop.TICKS).
function Camera.hopTicks(ticks: number?)
	hopTicks = ticks
end

-- The heading a shot would go now (f0100, f0104), nil before the first snapshot.
function Camera.aim(): Maze.Heading?
	local last = latest
	if last == nil then
		return nil
	end
	return View.aim(last.player.heading, steer, arrows)
end

-- Frees the mouse and shows it (true), or locks it to the centre and hides it (false), from the next frame.
function Camera.setCursor(free: boolean)
	cursor = free
end

-- The driving controller's sticks (f0146: Pads.stick, the one tracker Sticks reads too).
function Camera.pad(read: (name: string) -> (number?, number?, string?))
	padStick = read
end

function Camera.start()
	local camera = workspace.CurrentCamera :: Camera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = View.SCALE.fieldOfView

	RunService:BindToRenderStep("PickmanCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		UserInputService.MouseBehavior = if cursor
			then Enum.MouseBehavior.Default
			else Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = cursor
		local delta = UserInputService:GetMouseDelta() -- read every frame: the read clears it
		if not mouseHeld and not lookedThisFrame then
			look = View.look(look, delta.X, delta.Y)
		end
		-- cleared here, after the guard read it: a touch that began and ended before this step still counts
		lookedThisFrame = false
		-- the right stick looks (f0146), at a rate, and stays where it is left, like the mouse
		local read = padStick
		if read then
			local x, y = read("Thumbstick2")
			if x and y then
				look = View.look(look, Pad.look(x, y, dt))
			end
		end
		steer = View.steer(steer, look, arrows, dt)
		look = steer.look

		local snap = latest
		if snap == nil then
			return
		end
		local pose = View.interpolate(prev, snap, View.alpha(os.clock() - arrived))
		local shown = View.shownTick(prev, snap, View.alpha(os.clock() - arrived))
		local target = View.headingYaw(snap.player.heading)
		local turned = View.approachYaw(yaw or target, target, View.turnRate() * dt)
		yaw = turned

		current = { x = pose.x, y = pose.y, yaw = turned + look.yaw }
		local x, z = View.world(pose.x, pose.y)
		camera.CFrame = CFrame.new(x, View.SCALE.eyeHeight + Hop.rise(hopped, shown, hopTicks), z)
			* CFrame.Angles(0, turned + look.yaw, 0)
			* CFrame.Angles(look.pitch, 0, 0)
	end)
end

return Camera
