--!strict
-- Plays (f0208): the server side of the play buttons. A client only asks: play a title in a mode, cancel a wait, or
-- invite a friend (ReplicatedStorage.Remotes.Play). The server checks the player's record through the arcade's
-- Wallet and decides (Logic/Play): a free start due or a held play goes at once, a failed or slow read goes on the
-- portal's pass, else it opens the 1 R$ play product (Receipts) and goes once the grant arrives. Going is a teleport
-- to the title's place from the place-id attributes (Places, never from the client): PLAY to a public server, ARENA
-- to the shared arena's reserved server (Logic/Arena), 2 PLAYERS after a second player joins the title's waiting
-- line (Logic/Pairing), both together to a fresh reserved server. Nothing is charged here: the game place consumes
-- the entitlement on arrival (Wallet.arrive), and nothing is put in TeleportData. Receipts is installed here, once.
-- One player's MemoryStore writes are bounded in number (Play.spend) and each in time (Play.WRITE_SECONDS); the
-- waiting counts go to everyone at most once a second; every failure rests the title's buttons COOL_SECONDS.
local Arena = require("@game/ReplicatedStorage/Shared/Logic/Arena")
local Games = require("@game/ReplicatedStorage/Shared/Games")
local Invites = require("./Invites")
local Modes = require("@game/ReplicatedStorage/Shared/Modes")
local PaidPlay = require("@game/ReplicatedStorage/Arcade/Logic/PaidPlay")
local Pairing = require("@game/ReplicatedStorage/Shared/Logic/Pairing")
local Places = require("@game/ReplicatedStorage/Arcade/Places")
local Play = require("@game/ReplicatedStorage/Shared/Logic/Play")
local Receipts = require("@game/ServerStorage/Arcade/Receipts")
local Travel = require("@game/ReplicatedStorage/Arcade/Logic/Travel")
local Wallet = require("@game/ServerStorage/Arcade/Wallet")

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

type Slot = {
	phase: Play.Phase,
	name: string?,
	mode: Play.Mode?,
	flight: number,
	invited: boolean,
	cool: number, -- os.clock() before which a failed play's buttons rest
}

local Plays = {}

local started = false

-- Runs `fn` in a thread of its own and waits at most `seconds` for it: true and whether it raised nothing when it
-- ended in time, false when it did not (it goes on, and what it does later is its own).
local function within(seconds: number, fn: () -> ()): (boolean, boolean)
	local co = coroutine.running()
	local done, ok, waiting = false, false, false
	task.spawn(function()
		ok = pcall(fn)
		done = true
		if waiting then
			waiting = false
			task.spawn(co)
		end
	end)
	if not done then
		waiting = true
		task.delay(seconds, function()
			if waiting then
				waiting = false
				task.spawn(co)
			end
		end)
		coroutine.yield()
	end
	return done, ok
end

function Plays.start()
	if started then
		return
	end
	started = true
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Play") :: RemoteEvent
	local ids = Places.read(function(attribute: string): any
		return ServerScriptService:GetAttribute(attribute)
	end)
	local destination: { [string]: number } = {}
	for _, entry in Games.LIST do
		local id = (ids :: any)[entry.place]
		if id ~= nil and Modes[entry.name] ~= nil then
			destination[entry.name] = id
		end
	end
	local travel = Travel.new()
	local slots: { [any]: Slot } = {}
	local writes: { [any]: { number } } = {} -- each player's recent MemoryStore writes, kept across plays
	local offered: { [any]: boolean } = {} -- an invite on record for the player, not withdrawn yet
	local queue = Pairing.new()
	local dirty = false -- the waiting counts changed since they were last sent
	local serial = 0
	local arenas: any = nil

	local function idOf(player: any): string
		return tostring(player.UserId)
	end

	local function tell(player: any)
		local slot = slots[player]
		if player.Parent == nil or slot == nil then
			return
		end
		remote:FireClient(player, "status", { phase = slot.phase, name = slot.name, mode = slot.mode })
	end

	local function counts(): { [string]: number }
		local out: { [string]: number } = {}
		for name, list in Modes do
			if table.find(list, "pair") ~= nil then
				out[name] = Pairing.count(queue, name)
			end
		end
		return out
	end

	-- one more MemoryStore write for the player, if their budget allows it
	local function spend(player: any): boolean
		local ok, kept = Play.spend(writes[player] or {}, os.clock())
		writes[player] = kept
		return ok
	end

	-- the player's invite record goes when their wait ends (a cancel, a pair, another play, a leave)
	local function withdraw(player: any)
		if offered[player] then
			offered[player] = nil
			if spend(player) then
				task.spawn(Invites.withdraw, player)
			end
		end
	end

	local function unwait(player: any)
		queue = Pairing.leave(queue, idOf(player))
		dirty = true
		withdraw(player)
	end

	local function set(player: any, phase: Play.Phase)
		local slot = slots[player]
		if slot ~= nil and slot.phase ~= phase then
			slot.phase = phase
			tell(player)
		end
	end

	-- a failure: COULD NOT START, and the title's buttons rest COOL_SECONDS
	local function fail(player: any)
		local slot = slots[player]
		if slot ~= nil then
			slot.cool = os.clock() + Play.COOL_SECONDS
			set(player, "failed")
		end
	end

	local function current(player: any, flight: number): boolean
		local slot = slots[player]
		return player.Parent ~= nil and slot ~= nil and slot.flight == flight
	end

	-- the teleport of one start: every player's travel goes, then one TeleportAsync for them all, tried once more
	-- RETRY_SECONDS later when it raises (Roblox advises retrying, reserved servers above all)
	local function go(players: { any }, name: string, reserved: string?)
		for _, p in players do
			if Travel.status(travel, idOf(p), os.clock()) ~= "idle" then
				for _, q in players do
					fail(q)
				end
				return
			end
		end
		local tickets: { [any]: number? } = {}
		for _, p in players do
			local _, ticket = Travel.request(travel, idOf(p), os.clock())
			tickets[p] = ticket
			set(p, "going")
		end
		local function attempt(): boolean
			return pcall(function()
				local options = Instance.new("TeleportOptions")
				if reserved ~= nil then
					options.ReservedServerId = reserved
				end
				TeleportService:TeleportAsync(destination[name], players, options)
			end)
		end
		local ok = attempt()
		if not ok then
			task.wait(Play.RETRY_SECONDS)
			local all = true
			for _, p in players do
				local slot = slots[p]
				if p.Parent == nil or slot == nil or slot.phase ~= "going" then
					all = false
				end
			end
			ok = all and attempt()
		end
		for _, p in players do
			if ok then
				Travel.answered(travel, idOf(p), os.clock(), tickets[p])
			else
				Travel.failed(travel, idOf(p), os.clock(), tickets[p])
				fail(p)
			end
		end
	end

	-- the player is entitled: go alone, to the title's shared arena, or to its waiting line. The slot says going
	-- before anything yields, so a press or a second grant meanwhile does nothing.
	local function proceed(player: any, flight: number)
		local slot = slots[player]
		if not current(player, flight) or slot.name == nil then
			return
		end
		local name = slot.name :: string
		set(player, "going")
		if slot.mode == "solo" then
			go({ player }, name, nil)
		elseif slot.mode == "arena" then
			if not spend(player) then
				fail(player)
				return
			end
			local fresh = HttpService:GenerateGUID(false)
			local last: Arena.Record? = nil
			local _, ok = within(Play.WRITE_SECONDS, function()
				if arenas == nil then
					arenas = MemoryStoreService:GetHashMap(Arena.MAP)
				end
				arenas:UpdateAsync(name, function(raw: any): any
					last = Arena.join(raw, fresh, os.time())
					return last
				end, Arena.OPEN_SECONDS)
			end)
			if not current(player, flight) then
				return
			end
			if not ok or last == nil then -- failed, or not back within WRITE_SECONDS
				fail(player)
				return
			end
			go({ player }, name, (last :: Arena.Record).id)
		else
			local pair
			queue, pair = Pairing.join(queue, name, idOf(player))
			dirty = true
			if pair == nil then
				set(player, "waiting")
				return
			end
			local first = Players:GetPlayerByUserId(tonumber(pair[1]) :: number)
			withdraw(player)
			if first == nil or slots[first] == nil then
				fail(player)
				return
			end
			withdraw(first)
			go({ first, player }, name, HttpService:GenerateGUID(false))
		end
	end

	-- the record check, reading again while another read of it is under way; after CHECK_SECONDS of that the
	-- decision is the pass. The decision as a string: the Roblox type pass widens a literal union across a require
	local function check(player: any, name: string, flight: number): string?
		local began = os.clock()
		while true do
			local record, problem = Wallet.read(player, name)
			if not current(player, flight) then
				return nil
			end
			local read: Play.Read? = nil
			if record ~= nil then
				local status = PaidPlay.status(record, os.time())
				read = { free = status.free, plays = status.plays }
			end
			local decision = Play.decide(read, problem, Wallet.mode(name), os.clock() - began)
			if decision ~= "busy" then
				return decision
			end
			task.wait(Play.BUSY_SECONDS)
			if not current(player, flight) then
				return nil
			end
		end
	end

	local function run(player: any, name: string, mode: Play.Mode)
		serial += 1
		local flight = serial
		slots[player] =
			{ phase = "checking", name = name, mode = mode, flight = flight, invited = false, cool = 0 }
		tell(player)
		local decision = check(player, name, flight)
		if decision == nil then
			return
		elseif decision == "closed" then
			set(player, "closed")
		elseif decision == "buy" then
			set(player, "buying")
			if not Receipts.ask(player, name, "play") then
				fail(player)
				return
			end
			task.delay(Play.BUY_SECONDS, function()
				local now = slots[player]
				if current(player, flight) and now.phase == "buying" then
					set(player, "idle")
				end
			end)
		else
			set(player, "going")
			if decision == "pass" and spend(player) then
				within(Play.WRITE_SECONDS, function()
					Wallet.pass(player, name)
				end)
			end
			proceed(player, flight)
		end
	end

	Receipts.start({
		granted = function(player: any, name: string, kind: PaidPlay.Kind)
			local slot = slots[player]
			if kind == "play" and slot ~= nil and slot.phase == "buying" and slot.name == name then
				proceed(player, slot.flight)
			end
		end,
		closed = function(player: any, name: string, kind: PaidPlay.Kind, bought: boolean)
			local slot = slots[player]
			if kind ~= "play" or slot == nil or slot.phase ~= "buying" or slot.name ~= name then
				return
			end
			if not bought then
				set(player, "idle")
				return
			end
			local flight = slot.flight
			task.delay(Play.RECEIPT_SECONDS, function()
				local now = slots[player]
				if current(player, flight) and now.phase == "buying" then
					set(player, "idle")
				end
			end)
		end,
	})
	Invites.start()

	remote.OnServerEvent:Connect(function(player: any, action: any, name: any, mode: any)
		if player.Parent == nil then
			return
		end
		local intent = Play.intent(action, name, mode, Modes)
		if intent == nil then
			return
		end
		local slot = slots[player]
		if intent.action == "cancel" then
			if slot ~= nil and slot.phase == "waiting" then
				unwait(player)
				set(player, "idle")
			end
			return
		elseif intent.action == "invite" then
			if slot ~= nil and slot.phase == "waiting" and slot.mode == "pair" then
				if not slot.invited then
					slot.invited = true
					if spend(player) then
						offered[player] = true
						task.spawn(Invites.offer, player, slot.name :: string)
					end
				end
				remote:FireClient(player, "invite")
			end
			return
		end
		local title = intent.name :: string
		if destination[title] == nil then
			return
		end
		if slot ~= nil and (slot.phase == "checking" or slot.phase == "buying" or slot.phase == "going") then
			return
		end
		if slot ~= nil and slot.phase == "failed" and os.clock() < slot.cool then
			return
		end
		if slot ~= nil and slot.phase == "waiting" then
			unwait(player)
		end
		run(player, title, intent.mode :: Play.Mode)
	end)

	TeleportService.TeleportInitFailed:Connect(function(player: any)
		Travel.failed(travel, idOf(player), os.clock())
		local slot = slots[player]
		if slot ~= nil and slot.phase == "going" then
			fail(player)
		end
	end)

	Players.PlayerAdded:Connect(function(player: any)
		remote:FireClient(player, "waiting", counts())
	end)
	Players.PlayerRemoving:Connect(function(player: any)
		if Pairing.line(queue, idOf(player)) ~= nil then
			unwait(player)
		end
		Travel.left(travel, idOf(player))
		slots[player] = nil
		writes[player] = nil
		offered[player] = nil
	end)

	-- once a second: the waiting counts to everyone when they changed; a start that never left times out in Travel;
	-- a failed play's buttons come back once its cool-down and Travel's are over
	local last = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last < 1 then
			return
		end
		last = now
		if dirty then
			dirty = false
			remote:FireAllClients("waiting", counts())
		end
		for player, slot in slots do
			local phase = Travel.status(travel, idOf(player), now)
			if slot.phase == "going" and phase == "cooling" then
				fail(player)
			elseif slot.phase == "failed" and now >= slot.cool and phase == "idle" then
				set(player, "idle")
			end
		end
	end)
end

return Plays
