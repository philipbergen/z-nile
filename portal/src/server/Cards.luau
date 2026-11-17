--!strict
-- Portal server adapter (f0205): tells each player what their cards show. Which places are published is read once
-- from the place-id attributes (the arcade's Places); whether a game's free start is due is the arcade's Wallet read
-- of that player's record and PaidPlay's status. Each ask (asks closer than Card.ASK_GAP answered together) is
-- answered at once and reads every published game again; a busy or failed read is read again later (Card.answer),
-- one retry at a time per game. A client only asks; what it sends with the ask is ignored, and no place id ever
-- leaves the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Card = require("@game/ReplicatedStorage/Shared/Logic/Card")
local Games = require("@game/ReplicatedStorage/Shared/Games")
local PaidPlay = require("@game/ReplicatedStorage/Arcade/Logic/PaidPlay")
local Places = require("@game/ReplicatedStorage/Arcade/Places")
local Wallet = require("@game/ServerStorage/Arcade/Wallet")

type Slot = {
	reads: { [string]: Card.Read },
	reading: { [string]: boolean },
	retry: { [string]: number }, -- the current retry's token per game; a timer with an older one does nothing
	asked: number?, -- os.clock() of the last answered ask
	waiting: boolean, -- an ask is held for the end of ASK_GAP
}

local Cards = {}
local started = false

function Cards.start()
	if started then
		return
	end
	started = true
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Cards") :: RemoteEvent
	local ids = Places.read(function(attribute: string): any
		return ServerScriptService:GetAttribute(attribute)
	end)
	local published: { [string]: boolean } = {}
	for _, entry in Games.LIST do
		published[entry.name] = Card.published(entry, ids :: any)
	end
	local waits: Card.Waits =
		{ busy = Wallet.WAIT_SECONDS, down = Wallet.RETRY_SECONDS, most = Wallet.READ_SECONDS }
	local slots: { [Player]: Slot } = {}

	local function live(player: Player, slot: Slot): boolean
		return player.Parent ~= nil and slots[player] == slot
	end

	local function send(player: Player, slot: Slot)
		if live(player, slot) then
			local free: { [string]: boolean } = {}
			for name, r in slot.reads do
				if r.free ~= nil then
					free[name] = r.free
				end
			end
			remote:FireClient(player, Card.states(Games.LIST, published, free))
		end
	end

	local function read(player: Player, slot: Slot, name: string)
		if not published[name] or slot.reading[name] then
			return
		end
		slot.reading[name] = true
		task.spawn(function()
			local record, reason = Wallet.read(player, name)
			slot.reading[name] = nil
			if not live(player, slot) then
				return
			end
			local due = if record ~= nil then PaidPlay.status(record, os.time()).free == true else nil
			local after, delay = Card.answer(slot.reads[name], due, reason, waits)
			slot.reads[name] = after
			local token = (slot.retry[name] or 0) + 1
			slot.retry[name] = token
			send(player, slot)
			if delay ~= nil then
				task.delay(delay, function()
					if live(player, slot) and slot.retry[name] == token then
						read(player, slot, name)
					end
				end)
			end
		end)
	end

	local function answer(player: Player, slot: Slot)
		slot.asked = os.clock()
		send(player, slot)
		for _, entry in Games.LIST do
			read(player, slot, entry.name)
		end
	end

	remote.OnServerEvent:Connect(function(player: Player)
		if player.Parent == nil then
			return
		end
		local slot = slots[player]
		if slot == nil then
			slot = { reads = {}, reading = {}, retry = {}, asked = nil, waiting = false }
			slots[player] = slot
		end
		local mine: Slot = slot
		local wait = Card.asked(mine.asked, os.clock())
		if wait == nil then
			answer(player, mine)
		elseif not mine.waiting then
			mine.waiting = true
			task.delay(wait, function()
				mine.waiting = false
				if live(player, mine) then
					answer(player, mine)
				end
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		slots[player] = nil
	end)
end

return Cards
