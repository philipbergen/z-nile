--!strict
-- Portal client adapter (f0205): draws the carousel of game cards and moves it. Each card shows its title, tagline,
-- a turning 3-D preview and its price badge from the server's states (Card's view models, the arcade's Prices words);
-- A/D, the arrows, the shoulders, the wheel and a swipe move the row (Carousel); Enter, KeypadEnter or ButtonA play
-- the front card, which the play listeners hear (f0208 starts the game). Each card keeps two empty slots, Buttons
-- (f0208) and Boards (f0206).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Card = require("@game/ReplicatedStorage/Shared/Logic/Card")
local Carousel = require("@game/ReplicatedStorage/Shared/Logic/Carousel")
local Games = require("@game/ReplicatedStorage/Shared/Games")
local Prices = require("@game/ReplicatedStorage/Arcade/Prices")

local CarouselView = {}

local SHAPES: { [string]: Enum.PartType } = {
	Ball = Enum.PartType.Ball,
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
}

local listeners: { (name: string) -> () } = {}
local row = Carousel.new(#Games.LIST)
local states: { [string]: Card.State } = {}
local frames: { [string]: Frame } = {}
local started = false

-- Play listeners hear the front card's name when the player plays it (Enter, KeypadEnter, ButtonA).
function CarouselView.onPlay(fn: (name: string) -> ())
	table.insert(listeners, fn)
end

-- The front card's name.
function CarouselView.focused(): string
	return Games.LIST[row.index].name
end

-- A card's frame (its Buttons and Boards slots are its children), nil before start or for another name.
function CarouselView.card(name: string): Frame?
	return frames[name]
end

local function label(parent: Instance, name: string, region: Card.Region, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(Card.INSET, region.top)
	l.Size = UDim2.fromScale(1 - 2 * Card.INSET, region.height)
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.Text = text
	l.Parent = parent
	return l
end

local function slot(parent: Instance, name: string, region: Card.Region): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Position = UDim2.fromScale(Card.INSET, region.top)
	f.Size = UDim2.fromScale(1 - 2 * Card.INSET, region.height)
	f.Parent = parent
	return f
end

local function preview(parent: Instance, entry: Card.Entry): Model
	local region = Card.REGIONS.Preview
	local view = Instance.new("ViewportFrame")
	view.Name = "Preview"
	view.BackgroundTransparency = 1
	view.Position = UDim2.fromScale(0, region.top)
	view.Size = UDim2.fromScale(1, region.height)
	local camera = Instance.new("Camera")
	camera.FieldOfView = Card.CAMERA.fov
	camera.CFrame =
		CFrame.lookAt(Vector3.new(0, Card.CAMERA.height, Card.CAMERA.distance), Vector3.new(0, 0, 0))
	camera.Parent = view
	view.CurrentCamera = camera
	local scene = Instance.new("Model")
	scene.Name = "Scene"
	for i, p in entry.preview do
		local part = Instance.new("Part")
		part.Name = `Part{i}`
		part.Anchored = true
		part.Shape = SHAPES[p.shape]
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		part.Position = Vector3.new(p.at[1], p.at[2], p.at[3])
		part.Color = Color3.fromRGB(p.color[1], p.color[2], p.color[3])
		part.Parent = scene
	end
	scene.Parent = view
	view.Parent = parent
	return scene
end

local function build(gui: ScreenGui): { [string]: Model }
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 8, 24)
	backdrop.Parent = gui
	local cards = Instance.new("Frame")
	cards.Name = "Cards"
	cards.BackgroundTransparency = 1
	cards.Size = UDim2.fromScale(1, 1)
	cards.Parent = gui
	local scenes: { [string]: Model } = {}
	for _, entry in Games.LIST do
		local card = Instance.new("Frame")
		card.Name = entry.name
		card.BackgroundColor3 = Color3.fromRGB(24, 24, 60)
		card.Parent = cards
		label(card, "Title", Card.REGIONS.Title, entry.title)
		local tagline = label(card, "Tagline", Card.REGIONS.Tagline, entry.tagline)
		tagline.TextWrapped = true
		scenes[entry.name] = preview(card, entry)
		local badge = slot(card, "Badge", Card.REGIONS.Badge)
		local struck = label(badge, "Struck", { top = 0, height = 1 }, "")
		struck.Position = UDim2.fromScale(0, 0)
		struck.Size = UDim2.fromScale(Card.BADGE.struck, 1)
		struck.RichText = true
		local offer = label(badge, "Offer", { top = 0, height = 1 }, "")
		offer.Position = UDim2.fromScale(Card.BADGE.struck + Card.BADGE.gap, 0)
		offer.Size = UDim2.fromScale(Card.BADGE.offer, 1)
		slot(card, "Buttons", Card.REGIONS.Buttons)
		slot(card, "Boards", Card.REGIONS.Boards)
		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.ZIndex = 10
		dim.Parent = card
		frames[entry.name] = card
	end
	return scenes
end

local function draw(gui: ScreenGui)
	local size = gui.AbsoluteSize
	for i, entry in Games.LIST do
		local card = frames[entry.name]
		local box = Carousel.box(Carousel.offset(row, i), size.X, size.Y)
		card.Position = UDim2.fromOffset(box.x, box.y)
		card.Size = UDim2.fromOffset(box.width, box.height)
		card.Visible = box.shown
		local dim = card:FindFirstChild("Dim") :: Frame
		dim.BackgroundTransparency = 1 - box.dim
		local badge = Card.badge(states[entry.name], Prices, Card.WORDS)
		local holder = card:FindFirstChild("Badge") :: Frame
		local struck = holder:FindFirstChild("Struck") :: TextLabel
		local offer = holder:FindFirstChild("Offer") :: TextLabel
		struck.Text = badge.struck
		offer.Text = badge.text
	end
end

-- the intent as a string: the Roblox type pass widens a literal union across a require (f0201 E6)
local function act(gui: ScreenGui, intent: string?)
	if intent == "prev" then
		row = Carousel.step(row, -1)
		draw(gui)
	elseif intent == "next" then
		row = Carousel.step(row, 1)
		draw(gui)
	elseif intent == "play" then
		local name = CarouselView.focused()
		local state = states[name]
		if state ~= nil and state.published then
			for _, fn in listeners do
				task.spawn(fn, name)
			end
		end
	end
end

-- Builds the screen, binds the inputs and asks the server for the cards' states. Once; returns at once.
function CarouselView.start()
	if started then
		return
	end
	started = true
	-- no character here: the platform thumbstick and jump button would only sit over the cards and take their touches
	GuiService.TouchControlsEnabled = false
	local gui = Instance.new("ScreenGui")
	gui.Name = "Portal"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local scenes = build(gui)
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	draw(gui)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		draw(gui)
	end)

	local inputs: { any } = { Enum.UserInputType.MouseWheel }
	for key in Carousel.KEYS do
		table.insert(inputs, (Enum.KeyCode :: any)[key])
	end
	ContextActionService:BindActionAtPriority(
		Carousel.ACTION,
		function(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if UserInputService:GetFocusedTextBox() ~= nil then
				return Enum.ContextActionResult.Pass -- typing (the chat box): the keys are the text's
			end
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				local intent: string?
				row, intent = Carousel.wheel(row, input.Position.Z, os.clock())
				act(gui, intent)
			elseif state == Enum.UserInputState.Begin then
				act(gui, Carousel.key(input.KeyCode.Name))
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Carousel.PRIORITY,
		table.unpack(inputs)
	)
	-- a swipe moves the row wherever it starts, over a button or a board too
	UserInputService.TouchSwipe:Connect(function(direction: Enum.SwipeDirection)
		act(gui, Carousel.swipe(direction.Name))
	end)

	RunService.RenderStepped:Connect(function()
		local angle = Card.angle(os.clock())
		for name, scene in scenes do
			if frames[name].Visible then
				scene:PivotTo(CFrame.Angles(0, angle, 0))
			end
		end
	end)

	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Cards") :: RemoteEvent
		remote.OnClientEvent:Connect(function(raw: any)
			states = Card.parse(raw, Games.LIST)
			draw(gui)
		end)
		remote:FireServer()
	end)
end

return CarouselView
