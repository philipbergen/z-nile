--!strict
-- Client adapter: the HUD as a ScreenGui over the whole screen. Hud.model of each frame's play record gives the
-- content, Hud.layout of the screen and its safe inset the sizes, and Touch.blocks the places: score top-left,
-- level top-right, a disc per life bottom-left, and the power bar bottom-right, hidden when no power is
-- running. The snap control sits left of the bar (Touch.snapRect); Controls hit-tests the same rectangle.
local GuiService = game:GetService("GuiService") :: any -- the type library lacks GetInsetArea
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Hud = require("@game/ReplicatedStorage/Shared/Logic/Hud")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")
local Touch = require("@game/ReplicatedStorage/Shared/Logic/Touch")

local WHITE = Color3.fromRGB(255, 255, 255)
local YELLOW = Color3.fromRGB(255, 255, 0)
local BLUE = Color3.fromRGB(33, 33, 222)

local HudView = {}

local score: TextLabel? = nil
local level: TextLabel? = nil
local lives: Frame? = nil
local bar: Frame? = nil
local fill: Frame? = nil
local snapFrame: Frame? = nil
local shownLives = -1
local snapAt: Touch.Rect? = nil
-- the screen size and inset of the last layout, so a change of any of them re-lays
type Key = { sw: number, sh: number, inset: Hud.Inset }
local laidFor: Key? = nil

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

-- Places everything for a screen of sw x sh pixels with `inset` kept free, in screen pixels.
local function lay(sw: number, sh: number, inset: Hud.Inset)
	local l = Hud.layout(sw, sh, inset)
	local blocks = Touch.blocks(l)
	if score and level then
		for _, lab in { score, level } do
			lab.TextSize = l.textSize
		end
		score.Size = UDim2.fromOffset(blocks.score.w, blocks.score.h)
		score.Position = UDim2.fromOffset(blocks.score.x, blocks.score.y)
		level.Size = UDim2.fromOffset(blocks.level.w, blocks.level.h)
		level.Position = UDim2.fromOffset(blocks.level.x, blocks.level.y)
	end
	if lives then
		lives.Position = UDim2.fromOffset(blocks.lives.x, blocks.lives.y)
		lives.Size = UDim2.fromOffset(blocks.lives.w, blocks.lives.h)
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
		bar.Size = UDim2.fromOffset(blocks.power.w, blocks.power.h)
		bar.Position = UDim2.fromOffset(blocks.power.x, blocks.power.y)
	end
	local rect = Touch.snapRect(l)
	snapAt = rect
	if snapFrame then
		snapFrame.Size = UDim2.fromOffset(rect.w, rect.h)
		snapFrame.Position = UDim2.fromOffset(rect.x, rect.y)
	end
end

-- The snap control's rectangle in screen pixels, or nil before the first layout.
function HudView.snapRect(): Touch.Rect?
	return snapAt
end

function HudView.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1 -- above Flow's fade: the score and lives stay readable through a death
	-- the whole screen, origin its top-left: setting IgnoreGuiInset also sets ScreenInsets, so it goes first
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
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
	-- drawn only: a touch on it is the snap zone in Touch's fold, so it takes no input itself
	local s = Instance.new("Frame")
	s.Name = "Snap"
	s.Active = false
	s.BackgroundColor3 = WHITE
	s.BackgroundTransparency = 0.6
	s.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = s
	s.Parent = gui
	snapFrame = s
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local camera = workspace.CurrentCamera :: Camera
	-- polled: the first frames can report an empty area, and a half turn swaps the side insets without
	-- changing ViewportSize
	RunService:BindToRenderStep("PickmanHud", Enum.RenderPriority.Last.Value, function()
		local none = GuiService:GetInsetArea(Enum.ScreenInsets.None)
		local core = GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
		local sw, sh = Touch.screenSize(none, camera.ViewportSize.X, camera.ViewportSize.Y)
		local inset = Hud.safeInset(none, core)
		local last = laidFor
		if
			last == nil
			or last.sw ~= sw
			or last.sh ~= sh
			or last.inset.top ~= inset.top
			or last.inset.bottom ~= inset.bottom
			or last.inset.left ~= inset.left
			or last.inset.right ~= inset.right
		then
			laidFor = { sw = sw, sh = sh, inset = inset }
			lay(sw, sh, inset)
		end
	end)
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
		local last = laidFor
		if last then
			lay(last.sw, last.sh, last.inset)
		end
	end
	if bar and fill then
		bar.Visible = m.power > 0
		fill.Size = UDim2.fromScale(m.power, 1)
	end
end

return HudView
