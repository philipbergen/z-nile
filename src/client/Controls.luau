--!strict
-- Client adapter: binds the key map from View and relays intents to the server. On a touch screen it feeds
-- every finger through Touch's fold and applies what it emits.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService") :: any -- the type library lacks GetInsetArea
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Touch = require("@game/ReplicatedStorage/Shared/Logic/Touch")
local View = require("@game/ReplicatedStorage/Shared/Logic/View")

local Controls = {}

function Controls.start(
	onSnap: () -> (),
	onLook: ((dx: number, dy: number) -> ())?,
	snapRect: (() -> Touch.Rect?)?,
	onTouch: ((held: boolean) -> ())?
)
	local intent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Intent") :: RemoteEvent

	local function handle(
		_name: string,
		state: Enum.UserInputState,
		input: InputObject
	): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			local action = View.action(input.KeyCode.Name)
			if action == "Snap" then
				onSnap()
			elseif action then
				intent:FireServer(action)
			end
		end
		return Enum.ContextActionResult.Sink
	end

	local keys: { EnumItem } = {}
	for name in View.KEYS do
		table.insert(keys, (Enum.KeyCode :: any)[name])
	end
	ContextActionService:BindActionAtPriority(
		"PickmanControls",
		handle,
		false,
		Enum.ContextActionPriority.High.Value,
		table.unpack(keys)
	)

	-- the platform thumbstick would take the left half, which is the turn zone
	GuiService.TouchControlsEnabled = false
	local camera = workspace.CurrentCamera :: Camera
	local fingers = Touch.empty()
	local ids: { [InputObject]: number } = {}
	local lastId = 0
	local held = false

	-- Every touch event is converted to screen pixels and measured against the full screen, read afresh each
	-- time: the first frames can report an empty area, and a rotation changes it.
	local function onInput(input: InputObject, phase: Touch.Phase)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local id = ids[input]
		if id == nil then
			if phase ~= "begin" then
				return
			end
			lastId += 1
			id = lastId
			ids[input] = id
		end
		if phase == "end" then
			ids[input] = nil
		end
		local sx, sy = Touch.toScreen(
			GuiService:GetInsetArea(Enum.ScreenInsets.None),
			input.Position.X,
			input.Position.Y
		)
		local sw = Touch.screenSize(
			GuiService:GetInsetArea(Enum.ScreenInsets.None),
			camera.ViewportSize.X,
			camera.ViewportSize.Y
		)
		local rect = if snapRect then snapRect() else nil
		local effects
		fingers, effects = Touch.track(
			fingers,
			{ id = id, phase = phase, x = sx, y = sy },
			{ width = sw, snap = rect }
		)
		for _, effect in effects do
			if effect.kind == "turn" then
				intent:FireServer(effect.intent)
			elseif effect.kind == "look" then
				if onLook then
					onLook(effect.dx, effect.dy)
				end
			elseif effect.kind == "snap" then
				onSnap()
			end
		end
		local down = next(fingers.fingers) ~= nil
		if down ~= held then
			held = down
			if onTouch then
				onTouch(held)
			end
		end
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, _: boolean)
		onInput(input, "begin")
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, _: boolean)
		onInput(input, "move")
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject, _: boolean)
		onInput(input, "end")
	end)
end

return Controls
