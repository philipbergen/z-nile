--!strict
-- Lobby server adapter: answers a player's request for a hiscore board. It only reads. The client sends a board id,
-- never a score; what counts as an id, how long a read is shared and how a failing board is left alone are
-- Hiscores. Every request is answered once, also when the read fails, and requests that arrive while a read is
-- under way share it. Nothing is kept per player: one cache, one in-flight flag, one waiter list and one failure
-- run per board key.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hiscores = require("@game/ReplicatedStorage/Shared/Logic/Hiscores")

type KeyState = {
	cache: Hiscores.CacheEntry?,
	inflight: boolean,
	waiters: { Player },
	failure: Hiscores.Failure?,
}

local Boards = {}

-- The rows of one board from the stores, or nil when any part of the read failed (a store that will not open, a
-- page the store refuses, a row that cannot be read).
local function read(id: Hiscores.BoardId, now: number): { Hiscores.Row }?
	local ok, result = pcall(function()
		local board = Hiscores.board(id, now)
		local orderedName, orderedScope = Hiscores.storeTarget("ordered", board, true)
		local companionName, companionScope = Hiscores.storeTarget("companion", board, true)
		local ordered = DataStoreService:GetOrderedDataStore(orderedName, orderedScope)
		local companion = DataStoreService:GetDataStore(companionName, companionScope)
		local page: { any }? = nil
		local failure = "no page"
		for attempt = 1, 2 do
			local size = Hiscores.pageAttempt(attempt) :: number
			local fine, got = pcall(function()
				return ordered:GetSortedAsync(false, size):GetCurrentPage()
			end)
			if fine then
				page = got
				break
			end
			failure = tostring(got)
		end
		if page == nil then
			error(failure, 0)
		end
		local pages = { Hiscores.scorePage(page, Hiscores.N) }
		local rows = Hiscores.rows(pages, function(key: string): (Hiscores.Companion?, string?)
			local fine, got = pcall(function()
				return companion:GetAsync(key)
			end)
			if fine then
				return got, nil
			end
			return nil, tostring(got)
		end, Hiscores.N)
		if rows == nil then
			error("a row could not be read", 0)
		end
		return rows
	end)
	if ok then
		return result
	end
	return nil
end

function Boards.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Board"
	remote.Parent = remotes

	local keys: { [string]: KeyState } = {}

	local function answer(player: Player, id: string, rows: { Hiscores.Row }, failed: boolean)
		if player.Parent == nil then
			return
		end
		remote:FireClient(
			player,
			id,
			Hiscores.lobbyRows(rows),
			Hiscores.rankOf(rows, tostring(player.UserId)),
			failed
		)
	end

	-- the boards of other days and weeks are over: forget their state
	local function sweep(now: number)
		local current: { [string]: boolean } = {}
		for _, id in { "all", "day", "week" } do
			current[Hiscores.cacheKey(id :: Hiscores.BoardId, now)] = true
		end
		for key, held in keys do
			if not current[key] and not held.inflight then
				keys[key] = nil
			end
		end
	end

	remote.OnServerEvent:Connect(function(player: Player, raw: any)
		local id: Hiscores.BoardId? = Hiscores.boardId(raw)
		if id == nil then
			return
		end
		local now = os.time()
		sweep(now)
		local key = Hiscores.cacheKey(id, now)
		local held = keys[key]
		if held == nil then
			held = { cache = nil, inflight = false, waiters = {}, failure = nil }
			keys[key] = held
		end
		local state = held :: KeyState
		local before = if state.cache then state.cache.rows else {}
		local fetched = false
		local cache, rows, failure = Hiscores.lookup(
			state.cache,
			now,
			Hiscores.CACHE_TTL,
			Hiscores.READ_GAP,
			state.inflight,
			function(): { Hiscores.Row }?
				fetched = true
				state.inflight = true
				table.insert(state.waiters, player)
				local result = read(id, now)
				state.inflight = false
				return result
			end,
			state.failure
		)
		if fetched then
			-- this request ran the read: every request that waited for it is answered, once
			state.cache, state.failure = cache, failure
			local waiting = state.waiters
			state.waiters = {}
			for _, waiter in waiting do
				answer(waiter, id, rows or before, rows == nil)
			end
		elseif rows ~= nil then
			answer(player, id, rows, false)
		elseif state.inflight then
			table.insert(state.waiters, player)
		else
			-- inside the wait a failed board earned: the rows held, without a read
			answer(player, id, before, true)
		end
	end)
end

return Boards
