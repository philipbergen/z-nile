--!strict
-- Client adapter: the danger aids. A radar in the bottom-right corner, one margin above the power bar, or on a
-- touch screen above Roblox's jump button corner (Hud.radarBox), the maze around the player turned so up is
-- where the camera looks, and glows in eight places on the screen edge (f0102), one per direction a ghost is in
-- from where the camera looks, coloured as the nearest ghost there and larger and brighter the closer it is along
-- the maze. All the geometry is Awareness (and the colours View); this only draws it. The glows sit in the
-- device's safe area, under the HUD.
local GuiService = game:GetService("GuiService") :: any -- the type library lacks GetInsetArea
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Awareness = require("@game/ReplicatedStorage/Shared/Logic/Awareness")
local Hud = require("@game/ReplicatedStorage/Shared/Logic/Hud")
local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")
local View = require("@game/ReplicatedStorage/Shared/Logic/View")

local CELL = 8 -- pixels per tile on the radar
local GLOW_ALPHA = 0.85 -- the opacity of a glow at full brightness
local LOOK_COLORS: { [string]: Color3 } = {
	normal = Color3.fromRGB(255, 60, 60),
	frightened = Color3.fromRGB(80, 80, 255),
	blinking = Color3.fromRGB(230, 230, 255),
	eyes = Color3.fromRGB(200, 200, 200),
}

local DangerHud = {}

local function glow(parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = "Glow"
	f.BorderSizePixel = 0
	f.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	-- brightest at the middle, fading out toward the edge of the disc
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = f
	f.Parent = parent
	return f
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
	-- the glows: their own screen, in the device's safe area, under everything else
	local edge = Instance.new("ScreenGui")
	edge.Name = "Glows"
	edge.ResetOnSpawn = false
	edge.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	edge.DisplayOrder = -1 -- under the radar (Danger, 0), the Flow overlay (0) and the HUD (1)
	edge.Parent = gui.Parent

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
	local glows: { Frame } = {}
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
			local entry: Awareness.Ghost = { x = g.x, y = g.y, look = g.look, name = g.name, flash = g.flash }
			table.insert(ghosts, entry)
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

		local area = edge.AbsoluteSize
		local aspect = area.X / math.max(area.Y, 1)
		local list = Awareness.indicators(m, pose, ghosts, {
			verticalFieldOfView = math.rad(workspace.CurrentCamera.FieldOfView),
			aspect = aspect,
			inView = true,
		})
		local lit = Awareness.glows(list, aspect)
		for i = 1, Awareness.SECTORS do
			local f: Frame = glows[i] or glow(edge)
			glows[i] = f
			f.Visible = false
		end
		for i, g in lit do
			local f: Frame = glows[i]
			local u, v = Awareness.edgePoint(g.bearing, aspect)
			local place = Awareness.glowBox(u, v, g.size, area.X, area.Y)
			local rgb = View.ghostColor(g.name or "", g.look, g.flash == true)
			f.Visible = true
			f.Position = UDim2.fromOffset(place.x, place.y)
			f.Size = UDim2.fromOffset(place.w, place.h)
			f.BackgroundColor3 = Color3.fromRGB(rgb.r, rgb.g, rgb.b)
			f.BackgroundTransparency = 1 - GLOW_ALPHA * g.brightness
		end
	end)
end

return DangerHud
