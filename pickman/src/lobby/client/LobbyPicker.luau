--!strict
-- Lobby client adapter (f0148): the level picker, two arrows either side of START (◀ lower, ▶ higher), shown once the
-- player's best (the attribute the lobby server sets) is 2 or more. Which level is chosen and which arrow works is
-- Logic (Best.picker, Best.step); LobbyView shows the level on START and sends it.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local Best = require("@game/ReplicatedStorage/Shared/Logic/Best")
local Lobby = require("@game/ReplicatedStorage/Shared/Logic/Lobby")

export type Picker = { level: () -> number?, changed: (() -> ()) -> (), attach: () -> () }

local LobbyPicker = {}

function LobbyPicker.new(): Picker
	local player = Players.LocalPlayer :: Player
	local chosen: number? = nil
	local listeners: { () -> () } = {}
	local arrows: { down: TextButton?, up: TextButton? } = {}

	local function best(): number
		local v = player:GetAttribute(Best.ATTRIBUTE)
		return if type(v) == "number" then v else 1
	end

	local function render()
		local p = Best.picker(best(), chosen)
		for name, b: TextButton in arrows :: { [string]: TextButton } do
			local live = if name == "down" then p.down else p.up
			b.Visible = p.shown
			b.Active = live
			b.AutoButtonColor = live
			b.Selectable = p.shown
			b.BackgroundColor3 = if live then Color3.fromRGB(255, 221, 0) else Color3.fromRGB(90, 90, 90)
		end
		for _, fn in listeners do
			fn()
		end
	end

	local function arrow(parent: Instance, name: string, text: string, x: number, delta: number): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = text
		b.AnchorPoint = Vector2.new(0.5, 0)
		b.Size = UDim2.new(0.1, Lobby.BUTTON_MIN_PX, 0.12, Lobby.BUTTON_MIN_PX)
		b.Position = UDim2.fromScale(x, 0.74)
		b.Font = Enum.Font.GothamBold
		b.TextScaled = true
		b.Parent = parent
		b.Activated:Connect(function()
			chosen = Best.step(best(), chosen, delta)
			render()
		end)
		return b
	end

	local picker: Picker
	picker = {
		level = function(): number?
			local p = Best.picker(best(), chosen)
			return if p.shown then p.level else nil
		end,
		changed = function(fn: () -> ())
			table.insert(listeners, fn)
		end,
		-- the arrows, in the lobby screen LobbyView made
		attach = function()
			local backdrop = player:WaitForChild("PlayerGui"):WaitForChild("Lobby"):WaitForChild("Backdrop")
			arrows.down = arrow(backdrop, "LevelDown", "◀", 0.12, -1)
			arrows.up = arrow(backdrop, "LevelUp", "▶", 0.88, 1)
			player:GetAttributeChangedSignal(Best.ATTRIBUTE):Connect(render)
			-- the keyboard: Left and Right step the level while the picker is shown (Best.keyStep), bound above the
			-- default camera (which turns on the arrow keys) and sunk only when they stepped
			ContextActionService:BindActionAtPriority(
				"PickmanLevel",
				function(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
					local delta = Best.keyStep(input.KeyCode.Name)
					if
						state ~= Enum.UserInputState.Begin
						or delta == nil
						or not Best.picker(best(), chosen).shown
					then
						return Enum.ContextActionResult.Pass
					end
					chosen = Best.step(best(), chosen, delta)
					render()
					return Enum.ContextActionResult.Sink
				end,
				false,
				Enum.ContextActionPriority.High.Value,
				Enum.KeyCode.Left,
				Enum.KeyCode.Right
			)
			render()
		end,
	}
	return picker
end

return LobbyPicker
