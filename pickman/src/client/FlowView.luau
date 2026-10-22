--!strict
-- Client adapter: the run's overlay (READY!, the dying fade, GAME OVER and the play-again prompt) and
-- the play-again request. Flow decides what shows (the all-time rank line too); the server decides whether a new
-- run starts and what rank a run has.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flow = require("@game/ReplicatedStorage/Shared/Logic/Flow")

local YELLOW = Color3.fromRGB(255, 255, 0)
local BLACK = Color3.fromRGB(0, 0, 0)
local BUTTON_HEIGHT = 48 -- pixels: above the 44 pt touch target

local FlowView = {}

local fade: Frame? = nil
local banner: TextLabel? = nil
local detail: TextLabel? = nil
local button: TextButton? = nil
local live = false -- the latest overlay's playAgain: only then is a request sent
local rankLabel: TextLabel? = nil
local rankView: Flow.RankView = { over = 0 }
local gameOverUp = false -- whether the latest overlay was GAME OVER

local function text(name: string, parent: Instance, height: number, y: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Arcade
	l.TextColor3 = YELLOW
	l.TextScaled = true
	l.Size = UDim2.fromScale(0.6, height)
	l.Position = UDim2.fromScale(0.2, y)
	l.Visible = false
	l.Parent = parent
	return l
end

local function drawRank()
	if rankLabel then
		local line = Flow.shownRank(rankView, gameOverUp)
		rankLabel.Text = line or ""
		rankLabel.Visible = line ~= nil
	end
end

function FlowView.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("PlayAgain") :: RemoteEvent
	local gui = Instance.new("ScreenGui")
	gui.Name = "Flow"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 0 -- under the HUD

	local f = Instance.new("Frame")
	f.Name = "Fade"
	f.BackgroundColor3 = BLACK
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.Parent = gui
	fade = f
	banner = text("Banner", gui, 0.12, 0.34)
	detail = text("Detail", gui, 0.05, 0.47)
	rankLabel = text("Rank", gui, 0.05, 0.52)

	local b = Instance.new("TextButton")
	b.Name = "PlayAgain"
	b.Text = "PLAY AGAIN (Enter)"
	b.Font = Enum.Font.Arcade
	b.TextScaled = true
	b.TextColor3 = BLACK
	b.BackgroundColor3 = YELLOW
	b.Size = UDim2.new(0.3, 0, 0, BUTTON_HEIGHT)
	b.Position = UDim2.fromScale(0.35, 0.58)
	b.Visible = false
	b.Parent = gui
	button = b
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	-- the server's own rank for a run, sent after its write; the remote is made when the server script runs
	local rank = remotes:FindFirstChild("Rank")
	if rank then
		(rank :: RemoteEvent).OnClientEvent:Connect(function(run: number, place: number)
			rankView = Flow.hearRank(rankView, run, place, gameOverUp)
			drawRank()
		end)
	end

	local function ask()
		if live then
			remote:FireServer()
		end
	end
	b.Activated:Connect(ask)

	local keys: { EnumItem } = {}
	for _, name in Flow.PLAY_AGAIN_KEYS do
		table.insert(keys, (Enum.KeyCode :: any)[name])
	end
	ContextActionService:BindAction(
		"PickmanPlayAgain",
		function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin and Flow.isPlayAgainKey(input.KeyCode.Name) then
				ask()
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		table.unpack(keys)
	)
end

function FlowView.show(o: Flow.Overlay)
	live = o.playAgain
	rankView, gameOverUp = Flow.follow(rankView, o.banner == "GAME OVER", gameOverUp)
	drawRank()
	if fade then
		fade.BackgroundTransparency = 1 - o.fade
	end
	if banner then
		banner.Text = o.banner or ""
		banner.Visible = o.banner ~= nil
	end
	if detail then
		detail.Text = o.detail or ""
		detail.Visible = o.detail ~= nil
	end
	if button then
		button.Visible = o.playAgain
	end
end

return FlowView
