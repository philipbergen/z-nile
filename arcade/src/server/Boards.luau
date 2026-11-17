--!strict
-- Server adapter: one game's hiscore boards, for every place. `Boards.open(prefix)` names the game's stores
-- (Hiscores.names), and its handle writes finished runs (`submit`, from pickman's HiscoreStore) and answers players'
-- board requests (`serve`, from pickman's lobby Boards). Everything that decides anything (the replace rule, the
-- retries, the budgets, the ordered integer, the rank, the list of runs, the shared read and the failure wait) is
-- Hiscores; this module opens the stores and hands Hiscores the calls it needs. The stores are shared by every place
-- of the experience and carry no environment prefix: a beta server is another experience with stores of its own.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Hiscores = require("@game/ReplicatedStorage/Arcade/Logic/Hiscores")

export type Listener = (userId: string, run: number, rank: number?, missed: number?) -> ()
export type Game = {
	names: Hiscores.Names,
	-- write a finished run; returns at once, and the listener hears the run's place once the write is done. `score`
	-- is a whole number from 0, `level` (the title's progress figure) one from 1 and `revives` one from 0: a run
	-- outside them is refused with a warning and writes nothing
	submit: (userId: string, name: string, score: number, level: number, revives: number, run: number) -> (),
	-- submits whose write has not ended yet: a closing server waits for them
	pending: () -> number,
	-- the one function told (userId, run, rank, missed) once a run's place on the top-N list is known
	listen: (fn: Listener) -> (),
	-- answer every request on `remote` for a board id with (id, rows, rank, failed, best). A title is served on one
	-- remote per place: its waiters are the handle's, so serving it again on the same remote does nothing, and on
	-- another remote is an error
	serve: (remote: RemoteEvent) -> (),
}

type KeyState = {
	cache: Hiscores.CacheEntry?,
	inflight: boolean,
	waiters: { Player },
	failure: Hiscores.Failure?,
}
type Held = { at: number, best: Hiscores.Best?, reading: boolean }

local BUDGETS: { [string]: EnumItem } = {
	get = Enum.DataStoreRequestType.StandardRead,
	set = Enum.DataStoreRequestType.StandardWrite,
	getSorted = Enum.DataStoreRequestType.OrderedRead,
	setSorted = Enum.DataStoreRequestType.OrderedWrite,
}

-- a pcall's result as the (value, error) pair Hiscores.Io uses
local function answer(call: () -> any): (any, string?)
	local ok, value = pcall(call)
	if ok then
		return value, nil
	end
	return nil, tostring(value)
end

local Boards = {}

local games: { [string]: Game } = {}

local function make(names: Hiscores.Names): Game
	local pending = 0
	local listener: Listener? = nil
	local keys: { [string]: KeyState } = {}
	-- each present player's all-time best and when it was read, keyed by user id and forgotten when they leave
	local bests: { [string]: Held } = {}
	local leaving = false
	-- the one remote this title's boards are served on, once `serve` has run
	local served: RemoteEvent? = nil

	local function orderedStore(board: Hiscores.Board): OrderedDataStore
		local name, scope = Hiscores.storeTarget(names, "ordered", board, true)
		return DataStoreService:GetOrderedDataStore(name, scope)
	end

	local function companionStore(board: Hiscores.Board): DataStore
		local name, scope = Hiscores.storeTarget(names, "companion", board, true)
		return DataStoreService:GetDataStore(name, scope)
	end

	local function topStore(): DataStore
		return DataStoreService:GetDataStore(names.top, Hiscores.TOP_SCOPE)
	end

	-- the first page of a board's ordered store, size 10 and then 50 once
	local function page(board: Hiscores.Board): ({ Hiscores.Page }?, string?)
		local failure: string? = nil
		for attempt = 1, 2 do
			local size = Hiscores.pageAttempt(attempt) :: number
			local ok, got = pcall(function()
				local pages = orderedStore(board):GetSortedAsync(false, size)
				return Hiscores.scorePage(pages:GetCurrentPage(), Hiscores.N)
			end)
			if ok then
				return { got }, nil
			end
			failure = tostring(got)
		end
		return nil, failure
	end

	local io: Hiscores.Io = {
		get = function(board: Hiscores.Board, key: string): (Hiscores.Companion?, string?)
			return answer(function()
				return companionStore(board):GetAsync(key)
			end)
		end,
		updateEntry = function(
			board: Hiscores.Board,
			key: string,
			transform: (Hiscores.Companion?) -> Hiscores.Companion?
		): (Hiscores.Companion?, string?)
			return answer(function()
				return companionStore(board):UpdateAsync(key, transform :: any)
			end)
		end,
		updateScore = function(
			board: Hiscores.Board,
			key: string,
			transform: (number?) -> number?
		): (number?, string?)
			return answer(function()
				return orderedStore(board):UpdateAsync(key, transform :: any)
			end)
		end,
		top = page,
		budget = function(op: string): number
			return DataStoreService:GetRequestBudgetForRequestType(BUDGETS[op])
		end,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
	}

	local top: Hiscores.TopIo = {
		update = function(transform: ({ Hiscores.TopRun }?) -> { Hiscores.TopRun }?): (any, string?)
			return answer(function()
				return topStore():UpdateAsync(Hiscores.TOP_KEY, transform :: any)
			end)
		end,
	}

	-- The rows of one board from the stores, or nil when any part of the read failed. The all-time board is the
	-- top-N list of runs, or the per-player board while no list is stored yet.
	local function read(id: Hiscores.BoardId, now: number): { Hiscores.Row }?
		local ok, result = pcall(function()
			if id == "all" then
				local listed = Hiscores.topRows((topStore():GetAsync(Hiscores.TOP_KEY)))
				if listed ~= nil then
					return listed
				end
			end
			local board = Hiscores.board(id, now)
			local pages, failure = page(board)
			if pages == nil then
				error(failure or "no page", 0)
			end
			local rows = Hiscores.rows(pages, function(key: string): (Hiscores.Companion?, string?)
				return io.get(board, key)
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

	local handle: Game

	-- read the player's best unless it is held fresh or already being read; a read that ends after the player left,
	-- or after a newer read began, is dropped
	local function readBest(player: Player, now: number)
		local userId = tostring(player.UserId)
		local held = bests[userId]
		if not Hiscores.needsRead(held, now, Hiscores.CACHE_TTL) then
			return
		end
		local mark: Held = { at = now, best = if held then held.best else nil, reading = true }
		bests[userId] = mark
		local board = Hiscores.board("all", now)
		local got, err = io.get(board, Hiscores.entryKey(userId, board))
		if bests[userId] == mark and player.Parent ~= nil then
			bests[userId] =
				{ at = now, best = if err == nil then Hiscores.best(got) else nil, reading = false }
		end
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

	handle = {
		names = names,
		submit = function(
			userId: string,
			name: string,
			score: number,
			level: number,
			revives: number,
			run: number
		)
			pending += 1
			local ok, err = pcall(task.spawn, function()
				local fine, failure = pcall(function()
					local now = os.time()
					local attempt: Hiscores.Attempt =
						{ name = name, userId = userId, level = level, score = score, revives = revives }
					if not Hiscores.valid(attempt) then
						-- a progress figure below 1 or a bad revives count: nothing is written, so say so
						warn(`[arcade] hiscore run refused ({names.ordered})`)
					end
					local entry = Hiscores.topRun(attempt, now, run, (game :: any).JobId)
					-- the per-player rows this run writes name it, so a server that merges this best first uses its id
					attempt.run = if entry then entry.id else nil
					attempt.at = if entry then entry.at else nil
					local result = Hiscores.drive(io, attempt, now, Hiscores.RETRY)
					local placed = Hiscores.driveTop(top, io, entry, result.rows, Hiscores.RETRY)
					if placed.known and listener ~= nil then
						listener(userId, run, placed.place, placed.missed)
					end
				end)
				if not fine then
					warn(`[arcade] hiscore write failed ({names.ordered}): {failure}`)
				end
				pending -= 1
			end)
			if not ok then
				pending -= 1
				warn(`[arcade] hiscore write could not start ({names.ordered}): {err}`)
			end
		end,
		pending = function(): number
			return pending
		end,
		listen = function(fn: Listener)
			listener = fn
		end,
		serve = function(remote: RemoteEvent)
			if served == remote then
				return
			end
			if served ~= nil then
				error(`Boards: {names.ordered} is already served on another remote`, 2)
			end
			served = remote
			local function reply(player: Player, id: string, rows: { Hiscores.Row }, failed: boolean)
				if player.Parent == nil then
					return
				end
				local held = if id == "all" then bests[tostring(player.UserId)] else nil
				remote:FireClient(
					player,
					id,
					Hiscores.boardRows(rows),
					Hiscores.rankOf(rows, tostring(player.UserId)),
					failed,
					if held then held.best else nil
				)
			end
			if not leaving then
				leaving = true
				Players.PlayerRemoving:Connect(function(player: Player)
					bests[tostring(player.UserId)] = nil
				end)
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
						reply(waiter, id, rows or before, rows == nil)
					end
				elseif rows ~= nil then
					reply(player, id, rows, false)
				elseif state.inflight then
					table.insert(state.waiters, player)
				else
					-- inside the wait a failed board earned: the rows held, without a read
					reply(player, id, before, true)
				end
			end)
		end,
	}
	return handle
end

-- One game's boards, named from its prefix (Hiscores.names: "" is Pickman's stores). The same prefix is the same
-- handle, so every caller in a place shares its pending count, its listener and its cache.
function Boards.open(prefix: string): Game
	local names = Hiscores.names(prefix)
	local found = games[names.ordered]
	if found == nil then
		found = make(names)
		games[names.ordered] = found
	end
	return found :: Game
end

return Boards
