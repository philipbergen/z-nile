--!strict
-- Client adapter: a scripted first-person camera at the latest replicated position.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Awareness = require("@game/ReplicatedStorage/Shared/Logic/Awareness")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")
local View = require("@game/ReplicatedStorage/Shared/Logic/View")

local Camera = {}

local prev: Session.Snapshot? = nil
local latest: Session.Snapshot? = nil
local arrived = 0
local look: View.Look = { yaw = 0, pitch = 0 }
local yaw: number? = nil
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

-- Frees the mouse and shows it (true), or locks it to the centre and hides it (false), from the next frame.
function Camera.setCursor(free: boolean)
	cursor = free
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

		local snap = latest
		if snap == nil then
			return
		end
		local pose = View.interpolate(prev, snap, View.alpha(os.clock() - arrived))
		local target = View.headingYaw(snap.player.heading)
		local turned = View.approachYaw(yaw or target, target, View.turnRate() * dt)
		yaw = turned

		current = { x = pose.x, y = pose.y, yaw = turned + look.yaw }
		local x, z = View.world(pose.x, pose.y)
		camera.CFrame = CFrame.new(x, View.SCALE.eyeHeight, z)
			* CFrame.Angles(0, turned + look.yaw, 0)
			* CFrame.Angles(look.pitch, 0, 0)
	end)
end

return Camera
