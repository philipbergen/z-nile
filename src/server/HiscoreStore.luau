--!strict
-- Server adapter: writes a finished run to the hiscore boards. Everything that decides anything (the replace rule,
-- the retries, the budgets, the ordered integer, the rank) is Hiscores.drive; this module only opens the stores,
-- spends no thought on policy, and hands drive the calls it needs. A submit never waits: the write runs on its own
-- thread. The stores are shared by every place of the experience, and a beta server has stores of its own because
-- it is another experience, so the names carry no environment prefix.
local DataStoreService = game:GetService("DataStoreService")

local Hiscores = require("@game/ReplicatedStorage/Shared/Logic/Hiscores")

local HiscoreStore = {}

local pending = 0
local listener: ((userId: string, run: number, rank: number) -> ())? = nil

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

-- Write a finished run. Returns at once; `listen` hears the player's all-time rank once the write is done.
function HiscoreStore.submit(userId: string, name: string, score: number, level: number, run: number)
	pending += 1
	local ok, err = pcall(task.spawn, function()
		local fine, failure = pcall(function()
			local attempt = { name = name, userId = userId, level = level, score = score }
			local result = Hiscores.drive(io, attempt, os.time(), Hiscores.RETRY)
			if result.rank ~= nil and listener ~= nil then
				listener(userId, run, result.rank)
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

-- The one function called with (userId, run, rank) when a write found the player on the all-time board.
function HiscoreStore.listen(fn: (userId: string, run: number, rank: number) -> ())
	listener = fn
end

return HiscoreStore
