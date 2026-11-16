--!strict
-- Server adapter (f0148): each arriving player's start level, claimed once from their stored record (the lobby wrote
-- the choice there before the teleport), and the stored best raised whenever a run reaches a new level. What a start
-- may be is Logic (Best.claim); a store that fails or does not answer in time starts the run on level 1.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Best = require("@game/ReplicatedStorage/Shared/Logic/Best")

local Bests = {}
Bests.WAIT = 10 -- seconds a Ready waits for the claim before the run starts on level 1

local store: DataStore? = nil
local starts: { [Player]: number } = {}

-- The store, opened on first use inside a pcall (opening fails where the place cannot reach DataStores); nil when not.
local function open(): DataStore?
	if store == nil then
		local ok, s = pcall(function(): DataStore
			return DataStoreService:GetDataStore(Best.STORE)
		end)
		store = if ok then s else nil
	end
	return store
end

function Bests.start()
	local function claim(player: Player)
		local s = open()
		local start = 1
		local ok = s ~= nil
			and pcall(function()
				(s :: DataStore):UpdateAsync(tostring(player.UserId), function(raw: any): any
					local n, kept = Best.claim(Best.decode(raw))
					start = n
					return kept
				end)
			end)
		if player.Parent ~= nil then -- a player who left is not remembered
			starts[player] = if ok then start else 1
		end
	end
	Players.PlayerAdded:Connect(claim)
	for _, player in Players:GetPlayers() do
		task.spawn(claim, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		starts[player] = nil
	end)
end

-- The level this player's run starts on: waits (yields) up to WAIT seconds for the claim, else level 1.
function Bests.startOf(player: Player): number
	local waited = 0
	while starts[player] == nil and waited < Bests.WAIT and player.Parent ~= nil do
		waited += task.wait(0.1)
	end
	return starts[player] or 1
end

-- Hears one step's events (Sessions.listen): a run that reaches a new level raises its player's stored best.
function Bests.reached(events: { any })
	for _, e in events do
		if e.kind == "Ready" and e.reason == "level" and type(e.player) == "string" then
			-- the store is asked for only when a run reached a level: this runs for every step of every session, and
			-- a place that cannot reach DataStores would otherwise retry the open 15 times a second
			local s = open()
			if s == nil then
				return
			end
			local key, level = e.player, e.level
			task.spawn(function()
				pcall(function()
					s:UpdateAsync(key, function(raw: any): any
						return Best.raise(Best.decode(raw), level) -- nil: already that high, no write
					end)
				end)
			end)
		end
	end
end

return Bests
