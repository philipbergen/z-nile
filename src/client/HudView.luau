--!strict
-- Client adapter: the HUD as a ScreenGui. Hud.model of each frame's play record gives the content,
-- Hud.layout of the viewport the sizes: score top-left, level top-right, a disc per life bottom-left,
-- and the power bar bottom-right, hidden when no power is running.
local Players = game:GetService("Players")

local Hud = require("@game/ReplicatedStorage/Shared/Logic/Hud")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")

local WHITE = Color3.fromRGB(255, 255, 255)
local YELLOW = Color3.fromRGB(255, 255, 0)
local BLUE = Color3.fromRGB(33, 33, 222)

local HudView = {}

local score: TextLabel? = nil
local level: TextLabel? = nil
local lives: Frame? = nil
local bar: Frame? = nil
local fill: Frame? = nil
local shownLives = -1

local function label(name: string, align: Enum.TextXAlignment, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Arcade
	l.TextColor3 = WHITE
	l.TextXAlignment = align
	l.Text = ""
	l.Parent = parent
	return l
end

local function lay()
	local camera = workspace.CurrentCamera :: Camera
	local l = Hud.layout(camera.ViewportSize.X, camera.ViewportSize.Y)
	if score and level then
		for _, lab in { score, level } do
			lab.TextSize = l.textSize
			lab.Size = UDim2.new(0.5, -2 * l.margin, 0, l.textSize)
		end
		score.Position = UDim2.fromOffset(l.margin, l.margin)
		level.Position = UDim2.new(0.5, l.margin, 0, l.margin)
	end
	if lives then
		lives.Position = UDim2.new(0, l.margin, 1, -(l.iconSize + l.margin))
		lives.Size = UDim2.new(0.5, 0, 0, l.iconSize)
		local i = 0
		for _, icon in lives:GetChildren() do
			if icon:IsA("Frame") then
				icon.Size = UDim2.fromOffset(l.iconSize, l.iconSize)
				icon.Position = UDim2.fromOffset(i * (l.iconSize + l.margin), 0)
				i += 1
			end
		end
	end
	if bar then
		bar.Size = UDim2.fromOffset(l.barWidth, l.barHeight)
		bar.Position = UDim2.new(1, -(l.barWidth + l.margin), 1, -(l.barHeight + l.margin))
	end
end

function HudView.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	score = label("Score", Enum.TextXAlignment.Left, gui)
	level = label("Level", Enum.TextXAlignment.Right, gui)
	local lf = Instance.new("Frame")
	lf.Name = "Lives"
	lf.BackgroundTransparency = 1
	lf.Parent = gui
	lives = lf
	local b = Instance.new("Frame")
	b.Name = "Power"
	b.BackgroundColor3 = BLUE
	b.BorderSizePixel = 0
	b.Visible = false
	b.Parent = gui
	bar = b
	local f = Instance.new("Frame")
	f.Name = "Fill"
	f.BackgroundColor3 = WHITE
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(0, 1)
	f.Parent = b
	fill = f
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local camera = workspace.CurrentCamera :: Camera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(lay)
	lay()
end

function HudView.show(play: Session.PlayFrame)
	local m = Hud.model(play)
	if score and level then
		score.Text = m.score
		level.Text = m.level
	end
	if lives and m.lives ~= shownLives then
		shownLives = m.lives
		lives:ClearAllChildren()
		for _ = 1, m.lives do
			local disc = Instance.new("Frame")
			disc.BackgroundColor3 = YELLOW
			disc.BorderSizePixel = 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = disc
			disc.Parent = lives
		end
		lay()
	end
	if bar and fill then
		bar.Visible = m.power > 0
		fill.Size = UDim2.fromScale(m.power, 1)
	end
end

return HudView
