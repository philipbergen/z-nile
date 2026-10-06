--!strict
-- Lobby server adapter: a player's request to start the game becomes a teleport to the game place. It only
-- relays the request, the clock and the engine's answer to Travel; whether the request is allowed is Logic.
-- The destination is configuration (an attribute the publisher sets), never something the client sends.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Travel = require("@game/ReplicatedStorage/Shared/Logic/Travel")

local Starts = {}

function Starts.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local startGame = remotes:WaitForChild("StartGame") :: RemoteEvent
	local status = remotes:WaitForChild("Status") :: RemoteEvent

	local destination = Travel.destination(ServerScriptService:GetAttribute("GamePlaceId"))
	local travel = Travel.new()
	local shown: { [Player]: string } = {}

	local function push(player: Player, phase: Travel.Phase)
		-- a report can arrive after the player has gone
		if player.Parent == nil then
			return
		end
		if shown[player] ~= phase then
			shown[player] = phase
			status:FireClient(player, phase, destination ~= nil)
		end
	end

	-- tell the player what Travel says now (a report from the engine may have changed nothing)
	local function sync(player: Player)
		push(player, Travel.status(travel, tostring(player.UserId), os.clock()))
	end

	startGame.OnServerEvent:Connect(function(player: Player)
		local id = tostring(player.UserId)
		if destination == nil then
			push(player, "idle")
			return
		end
		local answer, ticket = Travel.request(travel, id, os.clock())
		if answer == "go" then
			push(player, "going")
			local ok = pcall(TeleportService.TeleportAsync, TeleportService, destination, { player })
			if ok then
				Travel.answered(travel, id, os.clock(), ticket)
			else
				Travel.failed(travel, id, os.clock(), ticket)
				sync(player)
			end
		end
	end)

	TeleportService.TeleportInitFailed:Connect(function(player: Player)
		Travel.failed(travel, tostring(player.UserId), os.clock())
		sync(player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		push(player, "idle")
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		Travel.left(travel, tostring(player.UserId))
		shown[player] = nil
	end)

	-- a cool-down or a timeout ends by itself: tell the player once a second
	local last = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last >= 1 then
			last = now
			for _, player in Players:GetPlayers() do
				push(player, Travel.status(travel, tostring(player.UserId), now))
			end
		end
	end)
end

return Starts
