--!strict
-- Lobby client adapter: draws the lobby screen from Lobby's view models and sends one intent, "start".
-- The mouse is free here (there is no maze and no camera control).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lobby = require("@game/ReplicatedStorage/Shared/Logic/Lobby")
local Travel = require("@game/ReplicatedStorage/Shared/Logic/Travel")

local LobbyView = {}

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size, l.Position = size, position
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.Text = text
	l.Parent = parent
	return l
end

function LobbyView.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local startGame = remotes:WaitForChild("StartGame") :: RemoteEvent
	local status = remotes:WaitForChild("Status") :: RemoteEvent

	local gui = Instance.new("ScreenGui")
	gui.Name = "Lobby"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.Parent = gui

	local panel = Lobby.panel(nil)
	label(backdrop, "Title", UDim2.fromScale(0.6, 0.1), UDim2.fromScale(0.5, 0.06), panel.title)
	local list = label(
		backdrop,
		"Rows",
		UDim2.fromScale(0.6, 0.4),
		UDim2.fromScale(0.5, 0.2),
		if panel.empty then panel.empty else ""
	)
	list.TextWrapped = true
	local message = label(backdrop, "Message", UDim2.fromScale(0.6, 0.06), UDim2.fromScale(0.5, 0.66), "")
	local button = Instance.new("TextButton")
	button.Name = "Start"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Size = UDim2.new(0.5, 0, 0.12, Lobby.BUTTON_MIN_PX)
	button.Position = UDim2.fromScale(0.5, 0.74)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Parent = backdrop

	local function show(phase: Travel.Phase, configured: boolean)
		local b = Lobby.button(phase, configured)
		button.Text = b.text
		button.Active = b.enabled
		button.AutoButtonColor = b.enabled
		button.BackgroundColor3 = if b.enabled
			then Color3.fromRGB(255, 221, 0)
			else Color3.fromRGB(90, 90, 90)
		message.Text = b.message or ""
	end
	show("idle", true)

	button.Activated:Connect(function()
		startGame:FireServer()
	end)
	status.OnClientEvent:Connect(show)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return LobbyView
