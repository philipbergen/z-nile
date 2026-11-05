--!strict
-- Server adapter: writes a finished run to the hiscore boards. Everything that decides anything (the replace rule,
-- the retries, the budgets, the ordered integer, the rank) is Hiscores.drive; this module only opens the stores,
-- spends no thought on policy, and hands drive the calls it needs. A submit never waits: the write runs on its own
-- thread. The stores are shared by every place of the experience, and a beta server has stores of its own because
-- it is another experience, so the names carry no environment prefix. A run first goes to the per-player boards
-- (Hiscores.drive), then, with the all-time bests drive read back, to the all-time top-N list of runs
-- (Hiscores.driveTop); the rank a player hears is the run's place on that list, or that it missed it.
local DataStoreService = game:GetService("DataStoreService")

local Hiscores = require("@game/ReplicatedStorage/Shared/Logic/Hiscores")

local HiscoreStore = {}

local pending = 0
local listener: ((userId: string, run: number, rank: number?, missed: number?) -> ())? = nil

local BUDGETS: { [string]: EnumItem } = {
	get = Enum.DataStoreRequestType.StandardRead,
	set = Enum.DataStoreRequestType.StandardWrite,
	getSorted = Enum.DataStoreRequestType.OrderedRead,
	setSorted = Enum.DataStoreRequestType.OrderedWrite,
}

local function orderedStore(board: Hiscores.Board): OrderedDataStore
	local name, scope = Hiscores.storeTarget("ordered", board, true)
	return DataStoreService:GetOrderedDataStore(name, scope)
end

local function companionStore(board: Hiscores.Board): DataStore
	local name, scope = Hiscores.storeTarget("companion", board, true)
	return DataStoreService:GetDataStore(name, scope)
end

local function topStore(): DataStore
	return DataStoreService:GetDataStore(Hiscores.TOP_STORE, Hiscores.TOP_SCOPE)
end

-- a pcall's result as the (value, error) pair Hiscores.Io uses
local function answer(call: () -> any): (any, string?)
	local ok, value = pcall(call)
	if ok then
		return value, nil
	end
	return nil, tostring(value)
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
	top = function(board: Hiscores.Board): ({ Hiscores.Page }?, string?)
		local failure: string? = nil
		for attempt = 1, 2 do
			local size = Hiscores.pageAttempt(attempt) :: number
			local ok, page = pcall(function()
				local pages = orderedStore(board):GetSortedAsync(false, size)
				return Hiscores.scorePage(pages:GetCurrentPage(), Hiscores.N)
			end)
			if ok then
				return { page }, nil
			end
			failure = tostring(page)
		end
		return nil, failure
	end,
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

-- Write a finished run. Returns at once; `listen` hears the run's place on the top-N list once the write is done.
function HiscoreStore.submit(userId: string, name: string, score: number, level: number, run: number)
	pending += 1
	local ok, err = pcall(task.spawn, function()
		local fine, failure = pcall(function()
			local now = os.time()
			local entry = Hiscores.topRun(
				{ name = name, userId = userId, level = level, score = score },
				now,
				run,
				(game :: any).JobId
			)
			-- the per-player rows this run writes name it, so a server that merges this best first uses the run's id
			local attempt = {
				name = name,
				userId = userId,
				level = level,
				score = score,
				run = if entry then entry.id else nil,
				at = if entry then entry.at else nil,
			}
			local result = Hiscores.drive(io, attempt, now, Hiscores.RETRY)
			local placed = Hiscores.driveTop(top, io, entry, result.rows, Hiscores.RETRY)
			if placed.known and listener ~= nil then
				listener(userId, run, placed.place, placed.missed)
			end
		end)
		if not fine then
			warn(`[pickman] hiscore write failed: {failure}`)
		end
		pending -= 1
	end)
	if not ok then
		pending -= 1
		warn(`[pickman] hiscore write could not start: {err}`)
	end
end

-- Submits whose write has not ended yet: a closing server waits for them.
function HiscoreStore.pending(): number
	return pending
end

-- The one function called with (userId, run, rank, missed) once a run's place is known: `rank` is its place on the
-- top-N list, or `missed` is N when it is not on it.
function HiscoreStore.listen(fn: (userId: string, run: number, rank: number?, missed: number?) -> ())
	listener = fn
end

return HiscoreStore
