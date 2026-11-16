--!strict
-- Client adapter (f0146): the left stick turns. Every frame it reads the driving controller's left stick (Pads.stick,
-- the one tracker), folds it through Pad.steer, which emits one turn intent a push, and sends that intent on the
-- Intent remote. The right stick's look is the camera's. A quick double push of the stick up boosts (f0143: it
-- owns every boost trigger): every Forward the fold emits is a push, folded through the stick's own Boost.Taps.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Boost = require("@game/ReplicatedStorage/Shared/Logic/Boost")
local Movement = require("@game/ReplicatedStorage/Shared/Logic/Movement")
local Pad = require("@game/ReplicatedStorage/Shared/Logic/Pad")

local Sticks = {}

function Sticks.start(stick: (name: string) -> (number?, number?, string?))
	local intent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Intent") :: RemoteEvent
	local steer = Pad.steerStart()
	local taps = Boost.taps() -- the stick's own double-push fold; it shares nothing with Controls' keys
	local source: string? = nil -- the controller the fold's state came from
	RunService.Heartbeat:Connect(function()
		local x, y, from = stick("Thumbstick1")
		if x == nil or y == nil then
			-- nothing to read (a dropout): not a change of source, so the fold is kept; the same pad coming back
			-- still held is the same push, and another pad coming back is a change of source below
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
			if emitted == "Forward" then
				local pair: boolean
				taps, pair = Boost.tap(taps, os.clock())
				if pair then
					intent:FireServer(Boost.INTENT)
				end
			end
		end
	end)
end

return Sticks
