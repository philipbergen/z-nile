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
	step: (s: Session.Session, events: { Session.Event }, here: boolean) -> boolean, -- false: let a parked session go
}

local Sessions = {}

local sessions: { [Player]: Session.Session } = {}
local startOf: ((Player) -> number)? = nil -- f0148: the level a player's run starts on; nil starts on 1
local listeners: { (events: { Session.Event }) -> () } = {} -- f0148: hear every step's events

-- f0148: the start level of each new session (it may yield while the store answers). Set before `start`.
function Sessions.starts(fn: (Player) -> number)
	startOf = fn
end

local made: { (player: Player, s: Session.Session) -> () } = {} -- f0148: told when a session is made

-- f0148: a function told each new session and its player, once made (after the start's wait: a Ready's own effect
-- may come later than the next resume, so code that needs the session listens here, not with task.defer).
function Sessions.made(fn: (player: Player, s: Session.Session) -> ())
	table.insert(made, fn)
end

-- f0148: a listener that hears every step's events, of every session, parked ones too.
function Sessions.listen(fn: (events: { Session.Event }) -> ())
	table.insert(listeners, fn)
end

-- Whether this player's run is over, as Logic says; a player with no session has no run.
function Sessions.isOver(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and Session.isOver(s, tostring(player.UserId))
end

function Sessions.start(runs: Runs?)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ready = remotes:WaitForChild("Ready") :: RemoteEvent
	local intent = remotes:WaitForChild("Intent") :: RemoteEvent
	local snapshot = remotes:WaitForChild("Snapshot") :: RemoteEvent

	local clock = Session.newClock(Session.STEP_RATE)
	local parked: { Session.Session } = {} -- sessions of players who left, kept while the runs ask for it

	-- the client is listening for snapshots once it signals Ready; a repeat signal is ignored
	ready.OnServerEvent:Connect(function(player: Player)
		if sessions[player] == nil then
			local start = if startOf then startOf(player) else nil
			if sessions[player] ~= nil or player.Parent == nil then
				return -- a repeat Ready made it while this one waited, or the player left
			end
			local s = Session.new(Maze.layout(Maze.DEFAULT), player.UserId, Session.GAME_CONFIG)
			Session.join(s, tostring(player.UserId), start)
			sessions[player] = s
			if runs then
				runs.ready(s, player)
			end
			for _, fn in made do
				fn(player, s)
			end
		end
	end)

	intent.OnServerEvent:Connect(function(player: Player, raw: any)
		local s = sessions[player]
		if s then
			Session.submit(s, tostring(player.UserId), raw)
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
				for _, fn in listeners do
					fn(events)
				end
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
					local events = Session.step(s)
					for _, fn in listeners do
						fn(events)
					end
					if runs.step(s, events, false) then
						table.insert(kept, s)
					end
				end
				parked = kept
			end
		end
	end)
end

return Sessions
