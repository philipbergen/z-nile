--!strict
-- Lobby client adapter (f0145): the line under START GAME saying what a game costs (Lobby.payLine, from what the
-- server says on PayStatus), redrawn every 30 s so the minutes to the next free game count down; and the test
-- purchase screen. LobbyView is unchanged: this view only adds its own line.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lobby = require("@game/ReplicatedStorage/Shared/Logic/Lobby")
local Pay = require("@game/ReplicatedStorage/Shared/Logic/Pay")
local TestPurchase = require("@game/ReplicatedStorage/Shared/TestPurchase")

local PayView = {}
PayView.REDRAW_SECONDS = 30

function PayView.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PayLine"
	gui.ResetOnSpawn = false
	local line = Instance.new("TextLabel")
	line.Name = "PayLine"
	line.BackgroundTransparency = 1
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.fromScale(0.5, 0.8)
	line.Size = UDim2.fromScale(0.8, 0.06)
	line.TextColor3 = Color3.fromRGB(255, 255, 255)
	line.TextScaled = true
	line.RichText = true -- f0186: the price of a play is struck through (Lobby.salePrice)
	line.Text = ""
	line.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	TestPurchase.start()

	local status: Pay.Status? = nil
	local mode: string? = nil
	local function draw()
		line.Text = Lobby.payLine(status, mode, os.time()) or ""
	end
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PayStatus") :: RemoteEvent
		remote.OnClientEvent:Connect(function(said: any, now: any)
			mode = if type(said) == "string" then said else nil
			status = if type(now) == "table" then now :: Pay.Status else nil
			draw()
		end)
	end)
	task.spawn(function()
		while gui.Parent do
			task.wait(PayView.REDRAW_SECONDS)
			draw()
		end
	end)
end

return PayView
