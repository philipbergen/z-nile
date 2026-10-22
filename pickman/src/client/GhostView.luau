--!strict
-- Client adapter: one model per ghost, moved to View's interpolated pose every frame and coloured by its look.
-- It draws what the snapshots say; every decision about a ghost was made on the server.
local RunService = game:GetService("RunService")

local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")
local View = require("@game/ReplicatedStorage/Shared/Logic/View")

local COLORS: { [string]: Color3 } = {
	blinky = Color3.fromRGB(255, 0, 0),
	pinky = Color3.fromRGB(255, 184, 255),
	inky = Color3.fromRGB(0, 255, 255),
	clyde = Color3.fromRGB(255, 184, 82),
}
local FRIGHTENED = Color3.fromRGB(33, 33, 255)
local FLASH_WHITE = Color3.fromRGB(255, 255, 255)
local EYE = Color3.fromRGB(255, 255, 255)
local PUPIL = Color3.fromRGB(33, 33, 255)
local EYES = {
	{ name = "EyeL", offset = CFrame.new(-1.4, 1.2, -2.6) },
	{ name = "EyeR", offset = CFrame.new(1.4, 1.2, -2.6) },
	{ name = "PupilL", offset = CFrame.new(-1.4, 1.2, -3.2) },
	{ name = "PupilR", offset = CFrame.new(1.4, 1.2, -3.2) },
}
local BODY = Vector3.new(6, 7, 6) -- taller than the 4-stud eye height, so a ghost shows over the pellets

local GhostView = {}

local models: { Model } = {}
local prev: Session.Snapshot? = nil
local latest: Session.Snapshot? = nil
local arrived = 0

local function part(parent: Model, name: string, size: Vector3, color: Color3, shape: Enum.PartType): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Parent = parent
	return p
end

local function build(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local body = part(model, "Body", BODY, COLORS[name] or FLASH_WHITE, Enum.PartType.Block)
	model.PrimaryPart = body
	for _, part_ in EYES do
		local size = if string.sub(part_.name, 1, 3) == "Eye"
			then Vector3.new(1.6, 2, 1.6)
			else Vector3.new(0.8, 1, 0.8)
		part(
			model,
			part_.name,
			size,
			if string.sub(part_.name, 1, 3) == "Eye" then EYE else PUPIL,
			Enum.PartType.Ball
		)
	end
	model.Parent = workspace
	return model
end

local function paint(model: Model, name: string, look: string, flash: boolean)
	local body = model:FindFirstChild("Body") :: Part
	body.Transparency = if look == "eyes" then 1 else 0
	if look == "frightened" then
		body.Color = FRIGHTENED
	elseif look == "blinking" then
		body.Color = if flash then FLASH_WHITE else FRIGHTENED
	else
		body.Color = COLORS[name] or FLASH_WHITE
	end
end

-- Snapshots only move forward, as in Camera.
function GhostView.push(snap: Session.Snapshot)
	if latest == nil or snap.tick > latest.tick then
		prev = latest
		latest = snap
		arrived = os.clock()
	end
end

function GhostView.start()
	RunService:BindToRenderStep("PickmanGhosts", Enum.RenderPriority.Camera.Value, function()
		local snap = latest
		if snap == nil or snap.ghosts == nil then
			return
		end
		local poses = View.interpolateGhosts(prev, snap, View.alpha(os.clock() - arrived))
		for i, pose in poses do
			local g = (snap.ghosts :: { Session.GhostSnapshot })[i]
			local model: Model = models[i] or build(g.name)
			models[i] = model
			paint(model, g.name, pose.look, pose.flash)
			local x, z = View.world(pose.x, pose.y)
			local facing = CFrame.new(x, BODY.Y / 2, z) * CFrame.Angles(0, View.headingYaw(pose.heading), 0)
			model:PivotTo(facing)
			-- the eyes sit on the front face, so a ghost coming toward the player reads differently
			for _, eye in EYES do
				local p = model:FindFirstChild(eye.name) :: Part
				p.CFrame = facing * eye.offset
			end
		end
	end)
end

return GhostView
