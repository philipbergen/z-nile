--!strict
-- Client adapter: the game over's revives line (f0186), the continues the run used, under FlowView's results. Flow
-- decides the text (`Flow.revivesLine`, nil outside the game over); this only draws it.
local Players = game:GetService("Players")

local Flow = require("@game/ReplicatedStorage/Shared/Logic/Flow")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")

local YELLOW = Color3.fromRGB(255, 255, 0)

local RevivesView = {}

local label: TextLabel? = nil

function RevivesView.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Revives"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1 -- above Flow's fade (FlowView's gui is 0), as HudView's is: the line stays as bright as the results
	local l = Instance.new("TextLabel")
	l.Name = "Revives"
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Arcade
	l.TextColor3 = YELLOW
	l.TextScaled = true
	l.Size = UDim2.fromScale(0.6, 0.05)
	l.Position = UDim2.fromScale(0.2, 0.64) -- under FlowView's prompt (0.58 to 0.63)
	l.Text = ""
	l.Visible = false
	l.Parent = gui
	label = l
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
end

function RevivesView.show(play: Session.PlayFrame)
	local line = Flow.revivesLine(play)
	if label then
		label.Text = line or ""
		label.Visible = line ~= nil
	end
end

return RevivesView
