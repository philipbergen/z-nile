--!strict
-- Client adapter: binds the key map from View and relays intents to the server. The movement keys, the fire key
-- and the jump (a hop, f0101) send intents; the arrow look is the camera's, handed in through Controls.keys (f0104). On a touch
-- screen it feeds every finger through Touch's fold and applies what it emits.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService") :: any -- the type library lacks GetInsetArea
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Blaster = require("@game/ReplicatedStorage/Shared/Logic/Blaster")
local Hop = require("@game/ReplicatedStorage/Shared/Logic/Hop")
local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local Movement = require("@game/ReplicatedStorage/Shared/Logic/Movement")
local Touch = require("@game/ReplicatedStorage/Shared/Logic/Touch")
local View = require("@game/ReplicatedStorage/Shared/Logic/View")

-- What the keys drive besides the intents: the camera's arrow look, and the way a shot would go now (nil before the
-- first snapshot).
export type Keys = {
	arrows: (View.Arrows) -> (),
	aim: () -> Maze.Heading?,
}

local Controls = {}

local keys: Keys? = nil
local held: View.Arrows = { up = false, down = false, left = false, right = false }

function Controls.keys(k: Keys)
	keys = k
end

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
		local action: View.Action? = View.action(input.KeyCode.Name)
		local k = keys
		if state == Enum.UserInputState.Begin then
			if action == "Snap" then
				onSnap()
			elseif Movement.isIntent(action) then
				intent:FireServer(action)
			elseif action == "Fire" and k then
				local h: Maze.Heading? = k.aim()
				if h then
					intent:FireServer(Blaster.intent(h))
				end
			elseif action == "Jump" then
				intent:FireServer(Hop.INTENT)
			end
		end
		-- the arrows are held: they look while down, and a cancelled input (focus lost) lets go
		local down = state == Enum.UserInputState.Begin
		if down or state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			local nextHeld = View.press(held, action, down)
			if
				nextHeld.up ~= held.up
				or nextHeld.down ~= held.down
				or nextHeld.left ~= held.left
				or nextHeld.right ~= held.right
			then
				held = nextHeld
				if k then
					k.arrows(held)
				end
			end
		end
		return Enum.ContextActionResult.Sink
	end

	local codes: { EnumItem } = {}
	for name in View.KEYS do
		table.insert(codes, (Enum.KeyCode :: any)[name])
	end
	ContextActionService:BindActionAtPriority(
		"PickmanControls",
		handle,
		false,
		Enum.ContextActionPriority.High.Value,
		table.unpack(codes)
	)

	-- the platform thumbstick would take the left half, which is the turn zone
	GuiService.TouchControlsEnabled = false
	local camera = workspace.CurrentCamera :: Camera
	local fingers = Touch.empty()
	local ids: { [InputObject]: number } = {}
	local lastId = 0
	local touching = false

	-- Held while any physical touch is down, including one the fold ignored: it still moves the locked mouse.
	local function hold()
		local down = next(ids) ~= nil
		if down ~= touching then
			touching = down
			if onTouch then
				onTouch(touching)
			end
		end
	end

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
		hold()
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
	-- a touch held while the window loses focus may never end; drop every finger so no zone stays locked
	UserInputService.WindowFocusReleased:Connect(function()
		fingers = Touch.empty()
		ids = {}
		hold()
	end)
end

return Controls
