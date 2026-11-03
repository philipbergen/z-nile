--!strict
-- Lobby server adapter: answers a player's request for a hiscore board. It only reads. The client sends a board id,
-- never a score; what counts as an id, how long a read is shared and how a failing board is left alone are
-- Hiscores. Every request is answered once, also when the read fails, and requests that arrive while a read is
-- under way share it. Boards are kept per board key: one cache, one in-flight flag, one waiter list and one failure
-- run each. The all-time board is the top-N list of runs, or the per-player board while no list is stored yet; its
-- answer also carries the asker's own best. That is the one thing kept per player: a held best per present player,
-- read at most once per CACHE_TTL, never twice at once, and dropped when they leave.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
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
		if id == "all" then
			local list = DataStoreService:GetDataStore(Hiscores.TOP_STORE, Hiscores.TOP_SCOPE)
				:GetAsync(Hiscores.TOP_KEY)
			local listed = Hiscores.topRows(list)
			if listed ~= nil then
				return listed
			end
		end
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
	-- each present player's all-time best and when it was read, keyed by user id and forgotten when they leave
	local bests: { [string]: { at: number, best: Hiscores.Best?, reading: boolean } } = {}

	Players.PlayerRemoving:Connect(function(player: Player)
		bests[tostring(player.UserId)] = nil
	end)

	-- read the player's best unless it is held fresh or already being read; a read that ends after the player left,
	-- or after a newer read began, is dropped
	local function readBest(player: Player, now: number)
		local userId = tostring(player.UserId)
		local held = bests[userId]
		if not Hiscores.needsRead(held, now, Hiscores.CACHE_TTL) then
			return
		end
		local mark = { at = now, best = if held then held.best else nil, reading = true }
		bests[userId] = mark
		local ok, got = pcall(function()
			local board = Hiscores.board("all", now)
			local name, scope = Hiscores.storeTarget("companion", board, true)
			return DataStoreService:GetDataStore(name, scope):GetAsync(Hiscores.entryKey(userId, board))
		end)
		if bests[userId] == mark and player.Parent ~= nil then
			bests[userId] = { at = now, best = if ok then Hiscores.best(got) else nil, reading = false }
		end
	end

	local function answer(player: Player, id: string, rows: { Hiscores.Row }, failed: boolean)
		if player.Parent == nil then
			return
		end
		local held = if id == "all" then bests[tostring(player.UserId)] else nil
		remote:FireClient(
			player,
			id,
			Hiscores.lobbyRows(rows),
			Hiscores.rankOf(rows, tostring(player.UserId)),
			failed,
			if held then held.best else nil
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
		if id == "all" then
			readBest(player, now)
		end
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
