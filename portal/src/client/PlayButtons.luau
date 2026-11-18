--!strict
-- Portal client adapter (f0208): the play buttons in each card's Buttons slot (CarouselView, f0205). PLAY on every
-- card, ARENA on Snake, 2 PLAYERS on Invaders and Asteroids, each with its price ("FREE", or 5 R$ struck through and
-- 1 R$); while the player's play of a title is under way that card says so, and a 2 PLAYERS wait shows CANCEL and
-- INVITE FRIEND. A tap, the carousel's PLAY keys (Enter, KeypadEnter, ButtonA through CarouselView.onPlay), 2 or
-- the gamepad's X for the second button, Backspace or B to cancel and I or Y to invite only ask the server
-- (Remotes.Play); the server decides. Nothing acts while the test purchase screen is open, and the keys pass on while
-- the player types in a text box.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local UserInputService = game:GetService("UserInputService")

local Card = require("@game/ReplicatedStorage/Shared/Logic/Card")
local CarouselView = require("./CarouselView")
local Games = require("@game/ReplicatedStorage/Shared/Games")
local Modes = require("@game/ReplicatedStorage/Shared/Modes")
local Play = require("@game/ReplicatedStorage/Shared/Logic/Play")
local Prices = require("@game/ReplicatedStorage/Arcade/Prices")
local TestPurchase = require("@game/ReplicatedStorage/Arcade/TestPurchase")

local PlayButtons = {}

local KINDS = { "solo", "arena", "pair", "cancel", "invite" }

local started = false
local remote: RemoteEvent? = nil
local states: { [string]: Card.State } = {}
local status: Play.Status? = nil
local waiting: { [string]: number } = {}
local views: { [string]: Play.View } = {}

local function send(kind: string, name: string)
	if remote == nil or TestPurchase.isOpen() then
		return
	end
	if kind == "cancel" or kind == "invite" then
		remote:FireServer(kind)
	else
		remote:FireServer("play", name, kind)
	end
end

local function build(name: string, slot: Instance)
	local note = Instance.new("TextLabel")
	note.Name = "Note"
	note.BackgroundTransparency = 1
	note.TextColor3 = Color3.new(1, 1, 1)
	note.TextScaled = true
	note.TextWrapped = true
	note.Text = ""
	note.Visible = false
	note.Parent = slot
	for _, kind in KINDS do
		local b = Instance.new("TextButton")
		b.Name = kind
		b.RichText = true
		b.TextScaled = true
		b.TextWrapped = false -- one line each: the name, then the price under it
		b.Selectable = false -- the gamepad's A stays the carousel's PLAY
		b.Visible = false
		b.Text = ""
		b.Parent = slot
		b.Activated:Connect(function()
			local view = views[name]
			if view == nil then
				return
			end
			for _, button in view.buttons do
				if button.kind == kind and button.enabled then
					send(kind, name)
				end
			end
		end)
	end
end

local function draw()
	for _, entry in Games.LIST do
		local frame = CarouselView.card(entry.name)
		local slot = if frame ~= nil then frame:FindFirstChild("Buttons") else nil
		local modes = Modes[entry.name]
		if slot ~= nil and modes ~= nil then
			local view =
				Play.view(entry.name, modes, states[entry.name], status, waiting[entry.name] or 0, Prices)
			views[entry.name] = view
			local note = slot:FindFirstChild("Note") :: TextLabel
			note.Text = view.note
			note.Visible = view.note ~= ""
			local box = Play.noteBox(#view.buttons)
			note.Position = UDim2.fromScale(box.x, box.y)
			note.Size = UDim2.fromScale(box.width, box.height)
			local places = Play.slots(#view.buttons, view.note ~= "")
			local shown: { [string]: boolean } = {}
			for i, button in view.buttons do
				local b = slot:FindFirstChild(button.kind) :: TextButton
				b.Text = if button.price ~= "" then `{button.text}\n{button.price}` else button.text
				b.Position = UDim2.fromScale(places[i].x, places[i].y)
				b.Size = UDim2.fromScale(places[i].width, places[i].height)
				b.AutoButtonColor = button.enabled
				b.Active = button.enabled
				b.Visible = true
				shown[button.kind] = true
			end
			for _, kind in KINDS do
				if not shown[kind] then
					(slot:FindFirstChild(kind) :: TextButton).Visible = false
				end
			end
		end
	end
end

-- the front card's button of a kind, when it shows enabled
local function pressable(name: string, kind: string): boolean
	local view = views[name]
	if view == nil then
		return false
	end
	for _, button in view.buttons do
		if button.kind == kind and button.enabled then
			return true
		end
	end
	return false
end

local function key(name: string): boolean
	local which = Play.key(name)
	local front = CarouselView.focused()
	if which == "second" then
		local modes = Modes[front]
		local second = if modes ~= nil then Play.second(modes) else nil
		if second ~= nil and pressable(front, second) then
			send(second, front)
			return true
		end
	elseif which ~= nil and status ~= nil and status.phase == "waiting" then
		if which == "cancel" or (which == "invite" and pressable(status.name :: string, "invite")) then
			send(which, front)
			return true
		end
	end
	return false
end

local function invite()
	task.spawn(function()
		local me = Players.LocalPlayer
		local ok, can = pcall(function(): any
			return SocialService:CanSendGameInviteAsync(me)
		end)
		if ok and can == true then
			pcall(function()
				local options = Instance.new("ExperienceInviteOptions")
				options.LaunchData = tostring(me.UserId)
				SocialService:PromptGameInvite(me, options)
			end)
		end
	end)
end

-- Fills each card's Buttons slot and listens; once. Call after CarouselView.start(). Returns at once.
function PlayButtons.start()
	if started then
		return
	end
	started = true
	for _, entry in Games.LIST do
		local frame = CarouselView.card(entry.name)
		local slot = if frame ~= nil then frame:FindFirstChild("Buttons") else nil
		if slot ~= nil and Modes[entry.name] ~= nil then
			build(entry.name, slot)
		end
	end
	draw()
	CarouselView.onPlay(function(name: string)
		if pressable(name, "solo") then
			send("solo", name)
		end
	end)
	local keys: { any } = {}
	for name in Play.KEYS do
		table.insert(keys, (Enum.KeyCode :: any)[name])
	end
	ContextActionService:BindActionAtPriority(
		Play.ACTION,
		function(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if UserInputService:GetFocusedTextBox() ~= nil then
				return Enum.ContextActionResult.Pass -- typing (the chat box): the keys are the text's
			end
			if
				state == Enum.UserInputState.Begin
				and not TestPurchase.isOpen()
				and key(input.KeyCode.Name)
			then
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Play.PRIORITY,
		table.unpack(keys)
	)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local play = remotes:WaitForChild("Play") :: RemoteEvent
		local cards = remotes:WaitForChild("Cards") :: RemoteEvent
		play.OnClientEvent:Connect(function(what: any, raw: any)
			if what == "status" then
				status = Play.parse(raw, Modes)
				draw()
			elseif what == "waiting" and type(raw) == "table" then
				local out: { [string]: number } = {}
				for name in Modes do
					local n = raw[name]
					if type(n) == "number" then
						out[name] = n
					end
				end
				waiting = out
				draw()
			elseif what == "invite" then
				invite()
			end
		end)
		cards.OnClientEvent:Connect(function(raw: any)
			states = Card.parse(raw, Games.LIST)
			draw()
		end)
		remote = play
		cards:FireServer()
	end)
end

return PlayButtons
