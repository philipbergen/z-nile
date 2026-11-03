--!strict
-- Lobby client adapter: draws the lobby screen from Lobby's view models and sends one intent, "start".
-- The mouse is free here (there is no maze and no camera control). When the server has a Board remote, the
-- screen also asks it for a board id (never a score), draws the answer, and asks again after a failed one.
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
	local title = label(backdrop, "Title", UDim2.fromScale(0.6, 0.1), UDim2.fromScale(0.5, 0.06), panel.title)
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

	-- the board remote is made by the server script when it runs, so a screen without it keeps the empty panel
	local boardRemote = remotes:FindFirstChild("Board")
	if boardRemote then
		local board = boardRemote :: RemoteEvent
		local wanted = "all" -- the board last asked for: the start ask, or the last tap
		local asks = 0 -- asks sent, so a scheduled retry can tell that a newer ask has gone out
		local failures = 0 -- failed answers in a row

		local function ask(id: string)
			asks += 1
			board:FireServer(id)
		end

		board.OnClientEvent:Connect(function(id: any, rows: any, highlight: any, failed: any, best: any)
			local shown = Lobby.board(id)
			if shown == nil or shown ~= wanted then
				return -- an answer for a board the player has left
			end
			local drawn = Lobby.boardPanel(rows, shown)
			title.Text = drawn.title
			list.Text = Lobby.text(drawn, highlight, best, shown)
			if failed == true then
				failures += 1
				local wait = Lobby.retryAfter(failures)
				if wait ~= nil then
					local sent = asks
					task.delay(wait, function()
						if asks == sent and wanted == shown then
							ask(shown)
						end
					end)
				end
			else
				failures = 0
			end
		end)

		-- the board row sits along the top edge, clear of START GAME at any height; the title and list make room
		local rowHeight = Lobby.BUTTON_MIN_PX + 4
		title.Position = UDim2.new(0.5, 0, 0.06, rowHeight)
		list.Position = UDim2.new(0.5, 0, 0.2, rowHeight)
		list.Size = UDim2.fromScale(0.6, 0.32)
		for index, id in { "all", "day", "week" } do
			local pick = Instance.new("TextButton")
			pick.Name = `Board{id}`
			pick.AnchorPoint = Vector2.new(0.5, 0)
			pick.Size = UDim2.new(0.18, 0, 0, Lobby.BUTTON_MIN_PX)
			pick.Position = UDim2.new(0.26 + 0.24 * (index - 1), 0, 0, 4)
			pick.Font = Enum.Font.GothamBold
			pick.TextScaled = true
			pick.Text = Lobby.boardTitle(id)
			pick.Parent = backdrop
			pick.Activated:Connect(function()
				wanted = id
				failures = 0
				ask(id)
			end)
		end
		ask(wanted)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return LobbyView
