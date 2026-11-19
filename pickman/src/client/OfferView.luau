--!strict
-- Client adapter (f0145): the continue offer's controls. While Flow's overlay says the offer is up, CONTINUE and
-- END GAME show (with the price line under them), and Return, KeypadEnter or ButtonA ask while Backspace or ButtonB
-- decline, on the key going down; the key is sunk. At any other time the keys pass on (FlowView's Return still
-- returns to the lobby at the game over): OfferView binds after FlowView, so it is asked first. It also boots the
-- arcade library's test purchase screen (c0202), which takes the same keys above every binding of the place while it
-- is open; the buttons, which may lie under it, do nothing while it is open. The server decides everything: the
-- answers are only asks.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flow = require("@game/ReplicatedStorage/Shared/Logic/Flow")
local TestPurchase = require("@game/ReplicatedStorage/Arcade/TestPurchase")

local OfferView = {}

local up = false
local buttons: Frame? = nil
local price: TextLabel? = nil
local report: Flow.OfferReport? = nil
local ask: RemoteEvent? = nil

local function send(what: string)
	if ask then
		ask:FireServer(what)
	end
end

function OfferView.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Offer"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(0.2, 0.62) -- 20% to 80% of the width, clear of a phone's side and top insets
	row.Size = UDim2.fromScale(0.6, 0.16)
	row.Visible = false
	row.Parent = gui
	local yes = Instance.new("TextButton")
	yes.Name = "Continue"
	yes.Text = Flow.OFFER.buy
	yes.Size = UDim2.fromScale(0.48, 0.6)
	yes.Parent = row
	local no = Instance.new("TextButton")
	no.Name = "Decline"
	no.Text = Flow.OFFER.no
	no.Position = UDim2.fromScale(0.52, 0)
	no.Size = UDim2.fromScale(0.48, 0.6)
	no.Parent = row
	local line = Instance.new("TextLabel")
	line.Name = "Price"
	line.BackgroundTransparency = 1
	line.Position = UDim2.fromScale(0, 0.65)
	line.Size = UDim2.fromScale(1, 0.35)
	line.TextColor3 = Color3.fromRGB(255, 255, 255)
	line.TextScaled = true
	line.Text = Flow.offerPrice(nil)
	line.Parent = row
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	buttons, price = row, line

	yes.Activated:Connect(function()
		if up and not TestPurchase.isOpen() then
			send("ask")
		end
	end)
	no.Activated:Connect(function()
		if up and not TestPurchase.isOpen() then
			send("decline")
		end
	end)
	local codes: { any } = {}
	for _, names in { Flow.OFFER_KEYS.ask, Flow.OFFER_KEYS.decline } do
		for _, name in names do
			table.insert(codes, (Enum.KeyCode :: any)[name])
		end
	end
	ContextActionService:BindAction(
		"PickmanOffer",
		function(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			local what = Flow.offerKey(input.KeyCode.Name)
			if not up or what == nil then
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.Begin then
				send(what :: string)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		table.unpack(codes)
	)
	TestPurchase.start()

	-- the remotes are made by the server at run time: wait for them without holding the client's boot
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		ask = remotes:WaitForChild("Continue") :: RemoteEvent
		local status = remotes:WaitForChild("PayStatus") :: RemoteEvent
		status.OnClientEvent:Connect(function(mode: any, said: any)
			-- the library's PaidPlay.Status (c0202): the revives held
			local held = if type(said) == "table" and type(said.revives) == "number" then said.revives else 0
			report = { mode = if type(mode) == "string" then mode else nil, held = held }
			if price then
				price.Text = Flow.offerPrice(report)
			end
		end)
	end)
end

-- every frame, with Flow's overlay of it
function OfferView.show(overlay: Flow.Overlay)
	up = overlay.offer == true
	if buttons then
		buttons.Visible = up
	end
	if price then
		price.Text = Flow.offerPrice(report)
	end
end

return OfferView
