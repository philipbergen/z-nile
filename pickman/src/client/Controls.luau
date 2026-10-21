--!strict
-- Client adapter: binds the key map from View and relays intents to the server.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local View = require("@game/ReplicatedStorage/Shared/Logic/View")

local Controls = {}

function Controls.start(onSnap: () -> ())
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
end

return Controls
