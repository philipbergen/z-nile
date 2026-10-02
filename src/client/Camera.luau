--!strict
-- Client adapter: a scripted first-person camera at the latest replicated position.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")
local View = require("@game/ReplicatedStorage/Shared/Logic/View")

local Camera = {}

local prev: Session.Snapshot? = nil
local latest: Session.Snapshot? = nil
local arrived = 0
local look: View.Look = { yaw = 0, pitch = 0 }
local yaw: number? = nil
local cursor = false -- the mouse is free (and shown) for a prompt

-- Snapshots only move forward: a connected client's session is never replaced.
function Camera.push(snap: Session.Snapshot)
	if latest == nil or snap.tick > latest.tick then
		prev = latest
		latest = snap
		arrived = os.clock()
	end
end

function Camera.snap()
	look = View.snap(look)
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
		local delta = UserInputService:GetMouseDelta()
		look = View.look(look, delta.X, delta.Y)

		local snap = latest
		if snap == nil then
			return
		end
		local pose = View.interpolate(prev, snap, View.alpha(os.clock() - arrived))
		local target = View.headingYaw(snap.player.heading)
		local turned = View.approachYaw(yaw or target, target, View.turnRate() * dt)
		yaw = turned

		local x, z = View.world(pose.x, pose.y)
		camera.CFrame = CFrame.new(x, View.SCALE.eyeHeight, z)
			* CFrame.Angles(0, turned + look.yaw, 0)
			* CFrame.Angles(look.pitch, 0, 0)
	end)
end

return Camera
