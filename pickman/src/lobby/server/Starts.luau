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

-- f0148: stores the player's chosen start level before the teleport (it may yield); nil stores nothing. Read at each
-- press, so it may be set before or after `start` (f0145's gate is `start`'s own argument).
local choose: ((Player, any) -> ())? = nil
function Starts.choosing(fn: (Player, any) -> ())
	choose = fn
end

-- `allow` (f0145's paid-play gate, optional) is asked before a request goes, while the player's travel is idle; it
-- may yield. Returns the press function, for a press the server makes (a game bought in the lobby).
function Starts.start(allow: ((Player) -> boolean)?): (Player) -> ()
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

	-- f0148: the level of a press that did not go, kept for the next press that does (a server-side press, such as
	-- f0145's after a purchase, carries no level of its own)
	local held: { [Player]: any } = {}

	local function press(player: Player, requested: any)
		local id = tostring(player.UserId)
		if requested ~= nil then
			held[player] = requested
		end
		if destination == nil then
			push(player, "idle")
			return
		end
		if allow and Travel.status(travel, id, os.clock()) == "idle" and not allow(player) then
			return
		end
		local answer, ticket = Travel.request(travel, id, os.clock())
		if answer == "go" then
			push(player, "going")
			local level = held[player]
			held[player] = nil
			local store = choose
			if store then
				store(player, level)
			end
			local ok = pcall(TeleportService.TeleportAsync, TeleportService, destination, { player })
			if ok then
				Travel.answered(travel, id, os.clock(), ticket)
			else
				Travel.failed(travel, id, os.clock(), ticket)
				sync(player)
			end
		end
	end
	startGame.OnServerEvent:Connect(press)

	TeleportService.TeleportInitFailed:Connect(function(player: Player)
		Travel.failed(travel, tostring(player.UserId), os.clock())
		sync(player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		push(player, "idle")
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		Travel.left(travel, tostring(player.UserId))
		held[player] = nil
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
	return function(player: Player)
		press(player, nil)
	end
end

return Starts
