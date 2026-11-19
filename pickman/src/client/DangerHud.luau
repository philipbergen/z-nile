--!strict
-- Client adapter: the danger aids. A radar in the bottom-right corner, one margin above the power bar, or on a
-- touch screen above Roblox's jump button corner (Hud.radarBox), the maze around the player turned so up is
-- where the camera looks, and the danger ring (f0158): 48 translucent dots on a circle round the middle of the
-- area below Roblox's top bar, a sector lit in one warning colour, more opaque the closer the nearest dangerous
-- ghost there is along the maze. All the geometry is Awareness (and the colours View); this only draws it. The
-- ring sits in the core-UI safe area, under the HUD.
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
local LOOK_COLORS: { [string]: Color3 } = {
	normal = Color3.fromRGB(255, 60, 60),
	frightened = Color3.fromRGB(80, 80, 255),
	blinking = Color3.fromRGB(230, 230, 255),
	eyes = Color3.fromRGB(200, 200, 200),
}

local DangerHud = {}

local function ringDot(parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Visible = true
	f.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	f.Parent = parent
	return f
end

local latest: Session.Snapshot? = nil
local maze: Maze.Maze? = nil

-- f0109: the radar's walls follow the maze's colour rule (View.wallColor): lit in the level-clear flash, green
-- while the ghosts are edible, blue otherwise. Main hands the state over each frame.
local wallLit, wallEdible = false, false
function DangerHud.wallState(lit: boolean, edible: boolean)
	wallLit, wallEdible = lit, edible
end

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
	-- the ring: its own screen, in the core-UI safe area below Roblox's top bar (G8), under everything else
	local edge = Instance.new("ScreenGui")
	edge.Name = "Ring"
	edge.ResetOnSpawn = false
	edge.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
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
	local function wallColor(): Color3
		local c = View.wallColor(wallLit, wallEdible)
		return Color3.fromRGB(c.r, c.g, c.b)
	end
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
	local dots: { Frame } = {}
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
		local wc = wallColor() -- once per step: the state changes a few times per power pellet
		for i, w in r.walls do
			local f: Frame = walls[i] or dot(radar, wc, CELL)
			walls[i] = f
			f.Visible = true
			f.BackgroundColor3 = wc
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
		local danger = View.DANGER_COLOR
		local warning = Color3.fromRGB(danger.r, danger.g, danger.b)
		local ring = Awareness.RING
		for i, d in Awareness.ring(list, area.X, area.Y) do
			local f: Frame = dots[i] or ringDot(edge)
			dots[i] = f
			f.Position = UDim2.fromOffset(d.x, d.y)
			f.Size = UDim2.fromOffset(d.w, d.h)
			if d.lit then
				f.BackgroundColor3 = warning
				f.BackgroundTransparency = 1 - (ring.lit.min + (ring.lit.max - ring.lit.min) * d.closeness)
			else
				f.BackgroundColor3 = Color3.new(1, 1, 1)
				f.BackgroundTransparency = 1 - ring.idle
			end
		end
	end)
end

return DangerHud
