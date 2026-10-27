--!strict
-- Client adapter (f0146): the one tracker of the controller that drives, read by Sticks and Camera. The most
-- recently used controller drives (the user, 2026-10-25): every gamepad input is folded through Pad.track, a button
-- press counting fully and a stick only by its tilt, so a stick alone takes over and an idle pad's drift never does
-- (design review 002 F3: LastInputType is not relied on). Buttons need no tracking: any controller's act.
local UserInputService = game:GetService("UserInputService")

local Pad = require("@game/ReplicatedStorage/Shared/Logic/Pad")

local Pads = {}

local active: string? = nil

local function seen(input: InputObject, begun: boolean)
	local name = input.KeyCode.Name
	local magnitude = 0
	if name == "Thumbstick1" or name == "Thumbstick2" then
		magnitude = math.sqrt(input.Position.X * input.Position.X + input.Position.Y * input.Position.Y)
	elseif begun then
		magnitude = 1
	end
	active = Pad.track(active, input.UserInputType.Name, magnitude)
end

function Pads.start()
	UserInputService.InputBegan:Connect(function(input: InputObject)
		seen(input, true)
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		seen(input, false)
	end)
end

-- A stick's position (KeyCode name "Thumbstick1" or "Thumbstick2") on the controller that drives, and that
-- controller's input type name (so a fold over the readings can tell when its source changed); nil when none drives
-- yet or it is disconnected.
function Pads.stick(name: string): (number?, number?, string?)
	local current = active
	if current == nil then
		return nil, nil, nil
	end
	local pad = (Enum.UserInputType :: any)[current]
	if not UserInputService:GetGamepadConnected(pad) then
		return nil, nil, nil
	end
	for _, state in UserInputService:GetGamepadState(pad) do
		if state.KeyCode.Name == name then
			return state.Position.X, state.Position.Y, current
		end
	end
	return nil, nil, nil
end

return Pads
