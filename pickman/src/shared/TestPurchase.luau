--!strict
-- Shared client adapter (f0145): the test purchase screen, which test mode opens instead of Roblox's own. The server
-- opens it on the Purchase remote (with the product); BUY and CANCEL answer "confirm" or "cancel", by tap, Return,
-- KeypadEnter or ButtonA, and Backspace or ButtonB. The keys are sunk only while the screen is open. Nothing here is
-- trusted: the server grants a confirm only for a screen it opened, in test mode only.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flow = require("@game/ReplicatedStorage/Shared/Logic/Flow")

local TestPurchase = {}
TestPurchase.NOTE = "TEST PURCHASE: NOTHING IS CHARGED"
local KEYS: { [string]: { string } } = {
	confirm = { "Return", "KeypadEnter", "ButtonA" },
	cancel = { "Backspace", "ButtonB" },
}
TestPurchase.KEYS = table.freeze(KEYS)

local WORDS = { play = "1 GAME", continue = "3 NEW LIVES" }

local started = false

local function answerOf(name: string): string?
	for answer, names in KEYS do
		if table.find(names, name) then
			return answer
		end
	end
	return nil
end

function TestPurchase.start()
	if started then
		return
	end
	started = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "TestPurchase"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.Enabled = false
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.5, 0.4) -- the middle half, clear of a phone's insets
	panel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	panel.Parent = gui
	local label = Instance.new("TextLabel")
	label.Name = "Lines"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.6)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Parent = panel
	local buy = Instance.new("TextButton")
	buy.Name = "BUY"
	buy.Text = "BUY"
	buy.Position = UDim2.fromScale(0.05, 0.65)
	buy.Size = UDim2.fromScale(0.425, 0.3)
	buy.Parent = panel
	local cancel = Instance.new("TextButton")
	cancel.Name = "CANCEL"
	cancel.Text = "CANCEL"
	cancel.Position = UDim2.fromScale(0.525, 0.65)
	cancel.Size = UDim2.fromScale(0.425, 0.3)
	cancel.Parent = panel
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local remote: RemoteEvent? = nil
	local function answer(what: string)
		gui.Enabled = false
		if remote then
			remote:FireServer(what)
		end
	end

	buy.Activated:Connect(function()
		if gui.Enabled then
			answer("confirm")
		end
	end)
	cancel.Activated:Connect(function()
		if gui.Enabled then
			answer("cancel")
		end
	end)
	local codes: { any } = {}
	for _, names in KEYS do
		for _, name in names do
			table.insert(codes, (Enum.KeyCode :: any)[name])
		end
	end
	ContextActionService:BindAction(
		"PickmanTestPurchase",
		function(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			local what = answerOf(input.KeyCode.Name)
			if not gui.Enabled or what == nil then
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.Begin then
				answer(what :: string)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		table.unpack(codes)
	)

	-- the remote is made by the server at run time: wait for it without holding the client's boot
	task.spawn(function()
		local found = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Purchase") :: RemoteEvent
		remote = found
		found.OnClientEvent:Connect(function(product: any)
			local words = WORDS[product]
			if words == nil then
				return
			end
			label.Text = `{words}\n{Flow.OFFER.price}\n{TestPurchase.NOTE}`
			gui.Enabled = true
		end)
	end)
end

return TestPurchase
