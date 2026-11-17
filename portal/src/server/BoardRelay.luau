--!strict
-- Portal server adapter (f0206): every card's hiscores. Each title's boards are the arcade's (`Boards.open(prefix)`,
-- f0197); this module serves each one on a relay of its own (a table with the two members `serve` uses,
-- `OnServerEvent` and `FireClient`, so no client can reach it) and puts one RemoteEvent, `Remotes.Boards`, in front
-- of them all. A client asks with (title, board id); the server answers (title, id, rows, rank, status, best). Which
-- asks may make the arcade read its stores is Board.plan's rule: a refresh under a read allowance and the engine's
-- request budget, a forward while the arcade's cache is fresh, else an answer from the rows this server holds.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require("@game/ReplicatedStorage/Shared/Logic/Board")
local Boards = require("@game/ServerStorage/Arcade/Boards")
local Games = require("@game/ReplicatedStorage/Shared/Games")
local HiscoreGames = require("@game/ReplicatedStorage/Arcade/HiscoreGames")
local Hiscores = require("@game/ReplicatedStorage/Arcade/Logic/Hiscores")

type Slot = {
	ranks: { [string]: Board.Held }, -- by "<title>|<board key>": the rank heard, with the rows' version
	best: { [string]: Board.Best? }, -- by title: the best the arcade last sent with an all-time answer
	heard: { [string]: boolean }, -- by title: an all-time answer of the arcade has reached this player
	last: { [string]: number }, -- by title: when an ask last made the arcade read this player's best
}
type Handler = (Player, any) -> ()

local BoardRelay = {}

local started = false

-- Starts the relay once per server: serves every title's boards and answers the clients' asks.
function BoardRelay.start()
	if started then
		return
	end
	started = true
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Boards") :: RemoteEvent
	local known: { [string]: boolean } = {}
	local snaps: { [string]: { [string]: Board.Snap } } = {}
	local handlers: { [string]: { Handler } } = {}
	local slots: { [Player]: Slot } = {}
	local bucket: Board.Bucket = { tokens = 0, at = nil }

	local function snapOf(name: string, key: string): Board.Snap
		local byKey = snaps[name]
		local found = byKey[key]
		if found == nil then
			found = { at = nil, failed = false, known = false, rows = {}, version = 0 }
			byKey[key] = found
		end
		return found :: Board.Snap
	end

	-- the boards of past days and weeks are over: forget their rows
	local function sweep(name: string, now: number)
		local current: { [string]: boolean } = {}
		for _, id in Board.TABS do
			current[Hiscores.cacheKey(id :: any, now)] = true
		end
		for key in snaps[name] do
			if not current[key] then
				snaps[name][key] = nil
			end
		end
	end

	local function slotOf(player: Player): Slot
		local found = slots[player]
		if found == nil then
			found = { ranks = {}, best = {}, heard = {}, last = {} }
			slots[player] = found
		end
		return found :: Slot
	end

	-- the player's all-time best on a title as an answer carries it: the best (nil: no run) once the arcade's all-time
	-- answer has reached them, else false (pending)
	local function mineOf(slot: Slot?, name: string): any
		if slot == nil or not slot.heard[name] then
			return false
		end
		return slot.best[name]
	end

	local function budget(): Board.Budget
		local ok, standard, sorted = pcall(function(): (number, number)
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardRead),
				DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedList)
		end)
		if not ok then
			return { standard = 0, sorted = 0 }
		end
		return { standard = standard, sorted = sorted }
	end

	-- the arcade's answer to one forwarded ask: held as the board's rows, and passed on to the player
	local function heard(
		name: string,
		player: Player,
		rawId: any,
		rows: any,
		rank: any,
		failed: any,
		best: any
	)
		local id = Board.id(rawId)
		if id == nil then
			return
		end
		local now = os.time()
		local key = Hiscores.cacheKey(id :: any, now)
		local snap = snapOf(name, key)
		local given: { Board.Row } = if type(rows) == "table" then rows else {}
		if not snap.known or not Board.sameRows(snap.rows, given) then
			snap.version += 1
		end
		snap.rows = given
		snap.known = true
		snap.failed = failed == true
		local slot = slots[player]
		if slot ~= nil then
			slot.ranks[`{name}|{key}`] = { rank = rank, version = snap.version }
			if id == "all" then
				slot.best[name] = best
				slot.heard[name] = true
			end
		end
		if player.Parent ~= nil then
			remote:FireClient(player, name, id, snap.rows, rank, Board.status(snap), mineOf(slot, name))
		end
	end

	for _, entry in Games.LIST do
		local name = entry.name
		local hiscores = (HiscoreGames :: any)[name]
		if hiscores ~= nil then
			local list: { Handler } = {}
			local relay = {
				OnServerEvent = {
					Connect = function(_: any, fn: Handler): any
						table.insert(list, fn)
						return { Disconnect = function() end }
					end,
				},
				FireClient = function(_: any, player: Player, ...: any)
					heard(name, player, ...)
				end,
			}
			local ok, err = pcall(function()
				Boards.open(hiscores.prefix).serve(relay :: any)
			end)
			if ok then
				known[name] = true
				snaps[name] = {}
				handlers[name] = list
			else
				warn(`[portal] boards of {name} not served: {err}`)
			end
		end
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		slots[player] = nil
	end)

	remote.OnServerEvent:Connect(function(player: Player, rawName: any, rawId: any)
		if player.Parent == nil or type(rawName) ~= "string" or not known[rawName] then
			return
		end
		local id = Board.id(rawId)
		if id == nil then
			return
		end
		local name = rawName :: string
		local now = os.time()
		sweep(name, now)
		local key = Hiscores.cacheKey(id :: any, now)
		local snap = snapOf(name, key)
		local slot = slotOf(player)
		local plan = Board.plan({
			snap = snap,
			last = slot.last[name],
			all = id == "all",
			bucket = bucket,
			budget = budget(),
			players = #Players:GetPlayers(),
			now = now,
			ttl = Hiscores.CACHE_TTL,
		})
		bucket = plan.bucket
		if plan.act == "answer" then
			remote:FireClient(
				player,
				name,
				id,
				snap.rows,
				Board.rankFor(slot.ranks[`{name}|{key}`], snap),
				Board.status(snap),
				mineOf(slot, name)
			)
			return
		end
		if plan.best then
			slot.last[name] = now
		end
		if plan.act == "refresh" then
			snap.at = now
		end
		for _, fn in handlers[name] do
			task.spawn(fn, player, id)
		end
	end)
end

return BoardRelay
