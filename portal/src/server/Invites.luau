--!strict
-- Invites (f0208): a friend invited to a 2 PLAYERS wait reaches the inviter's portal server. The inviter's server
-- records the invite (MemoryStore, by the inviter's user id: this server's job id and the title), once per wait. A
-- player who joins with an inviter's id as launch data (the invite's), and lands in another portal server while the
-- inviter is not there, is sent to the inviter's server when the invite is on record and they are friends; there the
-- friend presses 2 PLAYERS on that card. The launch data only names whom to look up: the record is the server's.
-- The record goes when the wait ends (Invites.withdraw); Plays bounds how often either is written.
local Modes = require("@game/ReplicatedStorage/Shared/Modes")
local Play = require("@game/ReplicatedStorage/Shared/Logic/Play")

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local Invites = {}

Invites.MAP = "PortalInvites" -- MemoryStore hash map, key the inviter's user id
Invites.SECONDS = 600 -- an invite is on record this long

local map: any = nil
local started = false

local function invites(): any
	if map == nil then
		map = MemoryStoreService:GetHashMap(Invites.MAP)
	end
	return map
end

-- Records that `player` invites a friend to wait with them on `name` in this server.
function Invites.offer(player: any, name: string)
	pcall(function()
		invites():SetAsync(tostring(player.UserId), { job = game.JobId, name = name }, Invites.SECONDS)
	end)
end

-- Removes `player`'s invite: their wait ended, so a friend is no longer sent to this server for it.
function Invites.withdraw(player: any)
	pcall(function()
		invites():RemoveAsync(tostring(player.UserId))
	end)
end

local function follow(friend: any)
	local okData, data = pcall(function(): any
		return friend:GetJoinData()
	end)
	local inviter = if okData and type(data) == "table" then Play.inviter(data.LaunchData) else nil
	if inviter == nil or inviter == friend.UserId or Players:GetPlayerByUserId(inviter) ~= nil then
		return
	end
	local okRead, raw = pcall(function(): any
		return invites():GetAsync(tostring(inviter))
	end)
	local record = if okRead then Play.invite(raw, Modes) else nil
	if record == nil or record.job == game.JobId then
		return
	end
	local okFriends, friends = pcall(function(): any
		return friend:IsFriendsWith(inviter)
	end)
	if not okFriends or friends ~= true or friend.Parent == nil then
		return
	end
	pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ServerInstanceId = record.job
		TeleportService:TeleportAsync(game.PlaceId, { friend }, options)
	end)
end

-- Sends each invited friend who joins to the inviter's server; once per server.
function Invites.start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(function(player: any)
		task.spawn(follow, player)
	end)
end

return Invites
