--!strict
-- Server adapter: one Session per player who signals Ready, stepped on the server clock. It only
-- relays remote events and time to Session; validation, limits, stepping and the rules are Logic.
-- An optional `runs` hook hears each session's start and every step's events, and keeps a departed session
-- stepping until it says to let go; Sessions knows nothing about what the hook does with them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")

export type Runs = {
	ready: (s: Session.Session, player: Player) -> (), -- a session was made on Ready
	again: (s: Session.Session) -> (), -- Session.playAgain accepted
	step: (s: Session.Session, events: { Session.Event }, here: boolean) -> boolean, -- false: let a parked session go
}

local Sessions = {}

function Sessions.start(runs: Runs?)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ready = remotes:WaitForChild("Ready") :: RemoteEvent
	local intent = remotes:WaitForChild("Intent") :: RemoteEvent
	local snapshot = remotes:WaitForChild("Snapshot") :: RemoteEvent
	local playAgain = remotes:WaitForChild("PlayAgain") :: RemoteEvent

	local sessions: { [Player]: Session.Session } = {}
	local clock = Session.newClock(Session.STEP_RATE)
	local parked: { Session.Session } = {} -- sessions of players who left, kept while the runs ask for it

	-- the client is listening for snapshots once it signals Ready; a repeat signal is ignored
	ready.OnServerEvent:Connect(function(player: Player)
		if sessions[player] == nil then
			local s = Session.new(Maze.layout(Maze.DEFAULT), player.UserId, Session.GAME_CONFIG)
			Session.join(s, tostring(player.UserId))
			sessions[player] = s
			if runs then
				runs.ready(s, player)
			end
		end
	end)

	intent.OnServerEvent:Connect(function(player: Player, raw: any)
		local s = sessions[player]
		if s then
			Session.submit(s, tostring(player.UserId), raw)
		end
	end)

	-- only the sender's own run, and only if Logic says the run is over; anything the client sends is ignored
	playAgain.OnServerEvent:Connect(function(player: Player)
		local s = sessions[player]
		if s then
			local _, ok = Session.playAgain(s, tostring(player.UserId))
			if ok and runs then
				runs.again(s)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local s = sessions[player]
		sessions[player] = nil
		if s and runs then
			table.insert(parked, s)
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		for _ = 1, Session.advance(clock, dt) do
			for player, s in sessions do
				local events = Session.step(s)
				local here = player.Parent ~= nil
				if runs then
					runs.step(s, events, here)
				end
				if here then
					snapshot:FireClient(player, Session.frame(s, tostring(player.UserId)))
				end
			end
			if runs and #parked > 0 then
				-- a departed session steps on, unseen, until the runs let it go
				local kept: { Session.Session } = {}
				for _, s in parked do
					if runs.step(s, Session.step(s), false) then
						table.insert(kept, s)
					end
				end
				parked = kept
			end
		end
	end)
end

return Sessions
