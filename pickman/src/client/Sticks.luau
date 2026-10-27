--!strict
-- Client adapter (f0146): the left stick turns. Every frame it reads the driving controller's left stick (Pads.stick,
-- the one tracker), folds it through Pad.steer, which emits one turn intent a push, and sends that intent on the
-- Intent remote. The right stick's look is the camera's. A boost from the stick is f0143's (it owns every boost
-- trigger).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Movement = require("@game/ReplicatedStorage/Shared/Logic/Movement")
local Pad = require("@game/ReplicatedStorage/Shared/Logic/Pad")

local Sticks = {}

function Sticks.start(stick: (name: string) -> (number?, number?, string?))
	local intent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Intent") :: RemoteEvent
	local steer = Pad.steerStart()
	local source: string? = nil -- the controller the fold's state came from
	RunService.Heartbeat:Connect(function()
		local x, y, from = stick("Thumbstick1")
		if x == nil or y == nil then
			-- nothing to read (a disconnect): the fold starts afresh, so the next push of any controller counts
			steer, source = Pad.steerStart(), nil
			return
		end
		if from ~= source then
			-- another controller drives now: its stick is a new reading, not the old one held (R0058 review 001 F3)
			steer, source = Pad.steerStart(), from
		end
		local emitted: Movement.Intent?
		steer, emitted = Pad.steer(steer, x, y)
		if emitted then
			intent:FireServer(emitted)
		end
	end)
end

return Sticks
