--!strict
-- Lobby server adapter (f0148): reads each player's best level into a player attribute (Best.ATTRIBUTE) for the
-- picker, and writes the level a player chose into their record before the teleport, where the game place claims it.
-- What the record holds and what a choice may be is Logic (Best); a store that fails leaves the run on level 1.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Best = require("@game/ReplicatedStorage/Shared/Logic/Best")

local Bests = {}

local store: DataStore? = nil

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
	local function show(player: Player)
		local s = open()
		if s == nil then
			return
		end
		local ok, raw = pcall(function(): any
			return s:GetAsync(tostring(player.UserId))
		end)
		if ok and player.Parent ~= nil then
			player:SetAttribute(Best.ATTRIBUTE, Best.decode(raw).best)
		end
	end
	Players.PlayerAdded:Connect(show)
	for _, player in Players:GetPlayers() do
		task.spawn(show, player)
	end
end

Bests.CHOOSE_WAIT = 5 -- seconds the teleport waits for the write, well under Travel's cap (60 s)

-- The player's choice, written before the teleport: waits (yields) for the write up to CHOOSE_WAIT seconds, then lets
-- the teleport go; a write that lands later leaves its choice for the next claim. A failed write is not retried.
function Bests.choose(player: Player, requested: any)
	local s = open()
	if s == nil then
		return
	end
	local done = false
	task.spawn(function()
		pcall(function()
			s:UpdateAsync(tostring(player.UserId), function(raw: any): any
				return Best.choose(Best.decode(raw), requested)
			end)
		end)
		done = true
	end)
	local waited = 0
	while not done and waited < Bests.CHOOSE_WAIT do
		waited += task.wait(0.1)
	end
end

return Bests
