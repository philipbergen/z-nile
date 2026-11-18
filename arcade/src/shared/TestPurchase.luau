--!strict
-- TestPurchase (f0201): the test purchase screen, which stands in for Roblox's purchase dialog in test mode, so a
-- playtest shows and takes the same choice and charges nothing. A client adapter module: each place's client boots it
-- once (`TestPurchase.start()`). The server opens it with its lines (Receipts.ask); BUY (Return, KeypadEnter or
-- ButtonA) answers "confirm", CANCEL (Backspace or ButtonB) answers "cancel", on the press; the keys are taken only
-- while the screen is open. The client decides nothing: the server grants only a screen it opened.
local PaidPlay = require("./Logic/PaidPlay")

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestPurchase = {}

TestPurchase.ACTION = "ArcadeTestPurchase"
TestPurchase.PRIORITY = 3000 -- above a place's own bindings, so the open screen is asked first
TestPurchase.BUY = "BUY"
TestPurchase.CANCEL = "CANCEL"

local function keyCodes(): { any }
	local codes = {}
	for _, list in { PaidPlay.TEST_KEYS.confirm, PaidPlay.TEST_KEYS.cancel } do
		for _, name in list do
			table.insert(codes, (Enum.KeyCode :: any)[name])
		end
	end
	return codes
end

local started = false
local gui: any = nil

-- Whether the screen is open: a place whose own handlers of the screen's keys or taps are not ContextActionService
-- bindings below TestPurchase.PRIORITY skips them while this is true.
function TestPurchase.isOpen(): boolean
	return gui ~= nil
end

local function listen(remote: any, playerGui: any)
	local function close()
		if gui ~= nil then
			gui:Destroy()
			gui = nil
			ContextActionService:UnbindAction(TestPurchase.ACTION)
		end
	end

	local function send(what: string)
		if gui == nil then
			return
		end
		close()
		remote:FireServer(what)
	end

	local function button(parent: any, text: string, x: number, what: string)
		local b = Instance.new("TextButton")
		b.Name = text
		b.Text = text
		b.Size = UDim2.fromScale(0.4, 0.22)
		b.Position = UDim2.fromScale(x, 0.72)
		b.TextScaled = true
		b.Parent = parent
		b.Activated:Connect(function()
			send(what)
		end)
	end

	local function open(lines: { string })
		close()
		local screen = Instance.new("ScreenGui")
		screen.Name = "ArcadeTestPurchase"
		screen.DisplayOrder = 1000
		screen.ResetOnSpawn = false
		screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		local frame = Instance.new("Frame")
		frame.Name = "Panel"
		frame.Size = UDim2.fromScale(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.25, 0.25)
		frame.Parent = screen
		for i, line in lines do
			local label = Instance.new("TextLabel")
			label.Name = `Line{i}`
			label.RichText = true -- the lines are rich text: a play's struck price (f0395)
			label.Text = line
			label.TextScaled = true
			label.Size = UDim2.fromScale(0.9, 0.18)
			label.Position = UDim2.fromScale(0.05, 0.04 + (i - 1) * 0.2)
			label.Parent = frame
		end
		button(frame, TestPurchase.BUY, 0.05, "confirm")
		button(frame, TestPurchase.CANCEL, 0.55, "cancel")
		screen.Parent = playerGui
		gui = screen
		ContextActionService:BindActionAtPriority(
			TestPurchase.ACTION,
			function(_: string, state: any, input: any): any
				if state == Enum.UserInputState.Begin then
					local what = PaidPlay.testKey(input.KeyCode.Name)
					if what ~= nil then
						send(what)
					end
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			TestPurchase.PRIORITY,
			table.unpack(keyCodes())
		)
	end

	remote.OnClientEvent:Connect(function(what: any, lines: any)
		if what ~= "open" or type(lines) ~= "table" then
			return
		end
		local text = {}
		for _, line in lines do
			if type(line) == "string" then
				table.insert(text, line)
			end
		end
		open(text)
	end)
end

-- Boots the screen once; returns at once and waits for the server's remote in its own thread.
function TestPurchase.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		listen(
			ReplicatedStorage:WaitForChild("ArcadePaidPlay"):WaitForChild("TestPurchase"),
			Players.LocalPlayer:WaitForChild("PlayerGui")
		)
	end)
end

return TestPurchase
