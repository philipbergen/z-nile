--!strict
-- Server adapter: one Session per player who signals Ready, stepped on the server clock. It only
-- relays remote events and time to Session; validation, limits and stepping are Logic.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")

local Sessions = {}

function Sessions.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ready = remotes:WaitForChild("Ready") :: RemoteEvent
	local intent = remotes:WaitForChild("Intent") :: RemoteEvent
	local snapshot = remotes:WaitForChild("Snapshot") :: RemoteEvent

	local sessions: { [Player]: Session.Session } = {}
	local clock = Session.newClock()

	-- the client is listening for snapshots once it signals Ready; a repeat signal is ignored
	ready.OnServerEvent:Connect(function(player: Player)
		if sessions[player] == nil then
			local s = Session.new(Maze.layout(Maze.DEFAULT), player.UserId)
			Session.join(s, tostring(player.UserId))
			sessions[player] = s
		end
	end)

	intent.OnServerEvent:Connect(function(player: Player, raw: any)
		local s = sessions[player]
		if s then
			Session.submit(s, tostring(player.UserId), raw)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		for _ = 1, Session.advance(clock, dt) do
			for player, s in sessions do
				Session.step(s)
				snapshot:FireClient(player, Session.snapshot(s, tostring(player.UserId)))
			end
		end
	end)
end

return Sessions
