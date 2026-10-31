--!strict
-- Lobby client adapter (f0146): with a controller, Roblox's own gamepad selection starts on START GAME, so the D-pad
-- moves between it and the board tabs and the select button presses them through LobbyView's own handlers.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Pad = require("@game/ReplicatedStorage/Shared/Logic/Pad")

local LobbyPad = {}

function LobbyPad.start()
	local gui = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local function choose(inputType: Enum.UserInputType)
		if not (Pad.isPad(inputType.Name) and GuiService.SelectedObject == nil) then
			return
		end
		local start = gui:FindFirstChild("Start", true)
		if start and start:IsA("GuiObject") then
			GuiService.SelectedObject = start
		end
	end
	choose(UserInputService:GetLastInputType())
	UserInputService.LastInputTypeChanged:Connect(choose)
	-- a cleared selection (ButtonB) is selected again while a controller is in use
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		choose(UserInputService:GetLastInputType())
	end)
end

return LobbyPad
