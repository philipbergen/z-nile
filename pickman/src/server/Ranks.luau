--!strict
-- Server adapter: tells a player their run's all-time place (or that it missed the top N) once it is written.
-- The rank comes from the server's own write; nothing arrives from the client on this remote. It is created here, not in the place file.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HiscoreStore = require("./HiscoreStore")

local Ranks = {}

function Ranks.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Rank"
	remote.Parent = remotes

	HiscoreStore.listen(function(userId: string, run: number, rank: number?, missed: number?)
		local player = Players:GetPlayerByUserId(tonumber(userId) or 0)
		-- the write can finish after the player has gone
		if player ~= nil and player.Parent ~= nil then
			remote:FireClient(player, run, rank, missed)
		end
	end)
end

return Ranks
