--!strict
-- Client adapter: the danger aids. A radar in the bottom-right corner, one margin above the power bar, or on a
-- touch screen above Roblox's jump button corner (Hud.radarBox), the maze around the player turned so up is
-- where the camera looks, and arrows on the screen edge for ghosts out of view, larger and brighter the closer
-- they are along the maze. All the geometry is Awareness; this only draws it.
local GuiService = game:GetService("GuiService") :: any -- the type library lacks GetInsetArea
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Awareness = require("@game/ReplicatedStorage/Shared/Logic/Awareness")
local Hud = require("@game/ReplicatedStorage/Shared/Logic/Hud")
local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")

local CELL = 8 -- pixels per tile on the radar
local ARROW_MAX = 56 -- pixels at full size
local LOOK_COLORS: { [string]: Color3 } = {
	normal = Color3.fromRGB(255, 60, 60),
	frightened = Color3.fromRGB(80, 80, 255),
	blinking = Color3.fromRGB(230, 230, 255),
	eyes = Color3.fromRGB(200, 200, 200),
}

local DangerHud = {}

local function arrow(parent: Instance): TextLabel
	local a = Instance.new("TextLabel")
	a.AnchorPoint = Vector2.new(0.5, 0.5)
	a.BackgroundTransparency = 1
	a.Text = "▲"
	a.Font = Enum.Font.GothamBold
	a.Parent = parent
	return a
end

local latest: Session.Snapshot? = nil
local maze: Maze.Maze? = nil

function DangerHud.push(snap: Session.Snapshot, m: Maze.Maze)
	if latest == nil or snap.tick > latest.tick then
		latest = snap
		maze = m
	end
end

function DangerHud.start(getPose: () -> Awareness.Pose?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Danger"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	local radarSize = (Awareness.RADAR_RADIUS * 2 + 1) * CELL
	local radar = Instance.new("Frame")
	radar.Name = "Radar"
	radar.Size = UDim2.fromOffset(radarSize, radarSize)
	radar.BackgroundColor3 = Color3.new(0, 0, 0)
	radar.BackgroundTransparency = 0.35
	radar.ClipsDescendants = true
	radar.Parent = gui
	local function dot(parent: Instance, color: Color3, size: number): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(size, size)
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Parent = parent
		return f
	end
	local you = dot(radar, Color3.fromRGB(255, 255, 0), CELL)
	you.Position = UDim2.fromOffset(radarSize / 2, radarSize / 2)
	local walls: { Frame } = {}
	local blips: { Frame } = {}
	local arrows: { TextLabel } = {}
	-- the top bar between this frame (the device safe area) and the HUD's (the core-UI safe area); read every
	-- frame, because a rotation changes it
	local function bandTop(): number
		return Hud.bandTop(
			GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets),
			GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
		)
	end
	RunService.RenderStepped:Connect(function()
		local view = gui.AbsoluteSize
		local box = Hud.radarBox(view.X, view.Y, radarSize, UserInputService.TouchEnabled, bandTop())
		radar.Position = UDim2.fromOffset(box.x, box.y)
		local snap, m, pose = latest, maze, getPose()
		if snap == nil or m == nil or pose == nil or snap.ghosts == nil then
			return
		end
		local ghosts: { Awareness.Ghost } = {}
		for _, g in snap.ghosts do
			table.insert(ghosts, { x = g.x, y = g.y, look = g.look })
		end
		local r = Awareness.radar(m, pose, ghosts)
		for i, w in r.walls do
			local f: Frame = walls[i] or dot(radar, Color3.fromRGB(33, 33, 222), CELL)
			walls[i] = f
			f.Visible = true
			f.Position = UDim2.fromOffset(radarSize / 2 + w.x * CELL, radarSize / 2 + w.y * CELL)
		end
		for i = #r.walls + 1, #walls do
			walls[i].Visible = false
		end
		for i = 1, #ghosts do
			local f: Frame = blips[i] or dot(radar, Color3.new(1, 1, 1), CELL)
			blips[i] = f
			f.Visible = false
		end
		for i, b in r.blips do
			local f: Frame = blips[i]
			f.Visible = true
			f.BackgroundColor3 = LOOK_COLORS[b.look] or LOOK_COLORS.normal
			f.Position = UDim2.fromOffset(radarSize / 2 + b.x * CELL, radarSize / 2 + b.y * CELL)
		end

		local aspect = view.X / math.max(view.Y, 1)
		local list = Awareness.indicators(m, pose, ghosts, {
			verticalFieldOfView = math.rad(workspace.CurrentCamera.FieldOfView),
			aspect = aspect,
		})
		for i = 1, #ghosts do
			local a: TextLabel = arrows[i] or arrow(gui)
			arrows[i] = a
			a.Visible = false
		end
		for i, ind in list do
			local a: TextLabel = arrows[i]
			local u, v = Awareness.edgePoint(ind.bearing, aspect)
			local px = (u * 0.5 + 0.5) * view.X
			local py = (v * 0.5 + 0.5) * view.Y
			-- keep the arrow fully on screen
			local size = ARROW_MAX * ind.size
			px = math.clamp(px, size / 2, view.X - size / 2)
			py = math.clamp(py, size / 2, view.Y - size / 2)
			a.Visible = true
			a.Position = UDim2.fromOffset(px, py)
			a.Size = UDim2.fromOffset(size, size)
			a.TextSize = size
			a.TextColor3 = (LOOK_COLORS[ind.look] or LOOK_COLORS.normal):Lerp(
				Color3.new(1, 1, 1),
				1 - ind.brightness
			)
			a.TextTransparency = 1 - ind.brightness
			-- the arrow points at the ghost: toward the screen centre rotated by the bearing
			a.Rotation = math.deg(-ind.bearing)
		end
	end)
end

return DangerHud
