--!strict
-- Lobby server adapter (f0145, on the arcade library since c0202): the gate in front of START GAME. A free start due
-- or a play held lets the player go (the lobby charges nothing: the arrival does); otherwise it opens the play
-- product (Receipts.ask) and refuses. A read that answers "down" lets the player go and leaves the library's pass
-- (Wallet.pass, `pickman/<user id>`), so the arrival lets that one game go free (decided with the user, 2026-10-26);
-- a read already under way ("busy") drops the press. The library bounds the reads (one at a time, answered from the
-- record seen for READ_SECONDS, none for RETRY_SECONDS after a failure). A play granted here presses START for the
-- player at once, and that press goes without a read: the grant is the fact, and a read under way (the one on joining,
-- say) would answer "busy", or later the record it began with, from before the grant. The status goes to the player on
-- PayStatus. Receipts is installed here, once.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaidPlay = require("@game/ReplicatedStorage/Arcade/Logic/PaidPlay")
local Receipts = require("@game/ServerStorage/Arcade/Receipts")
local Wallet = require("@game/ServerStorage/Arcade/Wallet")

local Paid = {}
Paid.TITLE = "pickman" -- the library's catalog name for Pickman

local pressFor: ((Player) -> ())? = nil
local bought: { [Player]: boolean } = {} -- a play granted on this server that no press has used yet
local statusRemote: RemoteEvent? = nil

-- the remote of that name under ReplicatedStorage.Remotes, made at run time (the place file's list stays)
local function remote(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local found = folder:FindFirstChild(name)
	if found then
		return found :: RemoteEvent
	end
	local made = Instance.new("RemoteEvent")
	made.Name = name
	made.Parent = folder
	return made
end

local function tell(player: Player, record: PaidPlay.Record)
	if player.Parent ~= nil and statusRemote then
		statusRemote:FireClient(player, Wallet.mode(Paid.TITLE), PaidPlay.status(record, os.time()))
	end
end

-- Whether this press may go. It may yield (the store's read).
function Paid.allow(player: Player): boolean
	if bought[player] then
		bought[player] = nil -- the play just granted goes, whatever a read under way would say
		return true
	end
	local record, problem = Wallet.read(player, Paid.TITLE)
	if player.Parent == nil then
		return false
	end
	if record == nil then
		if problem == "down" then
			Wallet.pass(player, Paid.TITLE) -- the play place lets this one game go free (decided 2026-10-26)
			return true
		end
		return false -- a read under way: this press is dropped
	end
	tell(player, record)
	local now = PaidPlay.status(record, os.time())
	if now.free or now.plays > 0 then
		return true
	end
	Receipts.ask(player, Paid.TITLE, "play") -- nothing on a closed server (decided 2026-10-26: "Refuse paid play")
	return false
end

-- `press` is Starts' own press (Starts.start(Paid.allow) returns it), used for a press the server makes.
function Paid.start(press: (Player) -> ())
	pressFor = press
	statusRemote = remote("PayStatus")
	Receipts.start({
		granted = function(player: Player, name: string, kind: PaidPlay.Kind)
			if name ~= Paid.TITLE or kind ~= "play" then
				return
			end
			local record = Wallet.read(player, Paid.TITLE) -- the grant's record, seen by this server
			if record then
				tell(player, record)
			end
			bought[player] = true
			local go = pressFor
			if go and player.Parent ~= nil then
				go(player) -- a bought game starts at once
			end
		end,
	})
	Players.PlayerRemoving:Connect(function(player: Player)
		bought[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		-- the line under START GAME from the start
		local record = Wallet.read(player, Paid.TITLE)
		if record then
			tell(player, record)
		end
	end)
end

return Paid
