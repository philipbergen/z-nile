--!strict
-- Hiscores: period keys, the replace rule, ranking and the top-N read of the all-time, daily and weekly boards,
-- and the retry policy that writes them. The store and the clock are parameters: time comes in as a unix
-- instant, and a store is any table of this shape, so specs use the in-memory fake and the server adapter hands
-- in the ordered store. No other feature is required.

export type BoardId = "all" | "day" | "week"
export type Board = { id: BoardId, period: string? }
-- `run` and `at` name the run that made a row (its top-N list id and instant); rows written before d0124 have neither
export type Attempt =
	{ name: string, userId: string, level: number, score: number, run: string?, at: number? }
export type Companion = {
	name: string,
	userId: string,
	level: number,
	score: number,
	run: string?,
	at: number?,
}
export type Row = {
	rank: number,
	name: string,
	userId: string,
	score: number,
	level: number,
	run: string?,
	at: number?,
	runScore: number?, -- the companion's own score: the score of the run the row names (the page score can lag it)
}
export type PageEntry = { key: string, score: number }
export type Page = { PageEntry }
export type Store = {
	get: (board: Board, key: string) -> Companion?,
	set: (board: Board, key: string, packed: number, entry: Companion) -> (),
	top: (board: Board, n: number) -> { Page },
}
export type Io = {
	get: (board: Board, key: string) -> (Companion?, string?),
	updateEntry: (board: Board, key: string, transform: (Companion?) -> Companion?) -> (Companion?, string?),
	updateScore: (board: Board, key: string, transform: (number?) -> number?) -> (number?, string?),
	top: (board: Board) -> ({ Page }?, string?),
	budget: (op: string) -> number,
	wait: (seconds: number) -> (),
}
export type Retry = { attempts: number, base: number, cap: number }
export type DriveResult = { wrote: { [string]: boolean }, rank: number?, rows: { Row }? } -- rows: the all-time board read after the write
export type RunState = { run: number, done: { [number]: boolean }, waited: number, drop: boolean }
export type Submission = { score: number, level: number, run: number }
export type StepEvent = { kind: string, score: number?, level: number? }
export type CacheEntry = { at: number, rows: { Row } }
export type Failure = { at: number, count: number } -- consecutive failed reads of one board key
export type TopRun = { id: string, name: string, userId: string, score: number, level: number, at: number }
export type TopIo = { update: (transform: ({ TopRun }?) -> { TopRun }?) -> (any, string?) }
export type TopResult = { known: boolean, place: number?, missed: number? }
export type Best = { score: number, level: number }

local Hiscores = {}

Hiscores.N = 10 -- the board size: the lobby panel's cap
Hiscores.ORDERED_STORE = "Hiscores"
Hiscores.COMPANION_STORE = "HiscoreEntries"
Hiscores.LEVEL_CAP = 10000 -- the ordered integer is score * LEVEL_CAP + min(level, LEVEL_CAP - 1)
Hiscores.RETRY = table.freeze({ attempts = 3, base = 0.25, cap = 1 }) :: Retry
Hiscores.LEAVE_STEPS = 45 -- how long a departed player's run is kept: the classic dying pause, in steps
Hiscores.CACHE_TTL = 15 -- seconds a read board is shared before it is read again
Hiscores.READ_GAP = 1 -- the first wait after a failed read; it doubles up to CACHE_TTL
Hiscores.CLOSE_WAIT = 25 -- seconds a closing server is held for hiscore work (the engine allows 30)
Hiscores.TOP_STORE = "HiscoreTop" -- the all-time top-N list of runs: one key holds the whole list
Hiscores.TOP_SCOPE = "all"
Hiscores.TOP_KEY = "runs"

local SECONDS_PER_DAY = 86400
local MAX_INTEGER = 2 ^ 53 - 1
local MAX_SCORE = math.floor((MAX_INTEGER - (Hiscores.LEVEL_CAP - 1)) / Hiscores.LEVEL_CAP)
local NAME_MAX = 20
local ALL: BoardId, DAY: BoardId, WEEK: BoardId = "all", "day", "week"
local BOARD_IDS: { BoardId } = { ALL, DAY, WEEK }

local function whole(x: any): boolean
	return type(x) == "number" and x == math.floor(x) and math.abs(x) ~= math.huge
end

-- Civil date of a day count since 1970-01-01 (proleptic Gregorian), by arithmetic: a host time zone cannot move it.
local function civil(days: number): (number, number, number)
	local z = days + 719468
	local era = z // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local d = doy - (153 * mp + 2) // 5 + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	if m <= 2 then
		y += 1
	end
	return y, m, d
end

local function dateKey(days: number): string
	local y, m, d = civil(days)
	return string.format("%04d-%02d-%02d", y, m, d)
end

local function dayCount(unix: number): number
	if type(unix) ~= "number" or unix ~= unix or math.abs(unix) == math.huge then
		error("Hiscores: the instant must be a finite number", 3)
	end
	return unix // SECONDS_PER_DAY
end

function Hiscores.dayKey(unix: number): string
	return dateKey(dayCount(unix))
end

-- The Monday of the UTC week. 1970-01-01 was a Thursday, so a day count d is (d + 3) % 7 days past its Monday.
function Hiscores.weekKey(unix: number): string
	local days = dayCount(unix)
	return dateKey(days - (days + 3) % 7)
end

function Hiscores.board(id: BoardId, unix: number): Board
	if id == "day" then
		return { id = id, period = Hiscores.dayKey(unix) }
	elseif id == "week" then
		return { id = id, period = Hiscores.weekKey(unix) }
	end
	return { id = "all", period = nil }
end

function Hiscores.scope(board: Board): string
	if board.period == nil then
		return board.id
	end
	return `{board.id}:{board.period}`
end

function Hiscores.cacheKey(id: BoardId, unix: number): string
	return Hiscores.scope(Hiscores.board(id, unix))
end

function Hiscores.entryKey(userId: string, board: Board): string
	if board.period == nil then
		return userId
	end
	return `{userId}:{board.period}`
end

function Hiscores.userIdFromKey(key: string, board: Board): string?
	if board.period == nil then
		return if string.match(key, "^%-?%d+$") then key else nil
	end
	local id, period = string.match(key, "^(%-?%d+):(.+)$")
	if id ~= nil and period == board.period then
		return id
	end
	return nil
end

function Hiscores.cleanName(raw: any): string
	if type(raw) ~= "string" then
		return "Player"
	end
	local name = string.gsub(raw, "%c", "")
	name = string.match(name, "^%s*(.-)%s*$") :: string
	local chars = utf8.len(name)
	if chars ~= nil and chars > NAME_MAX then
		name = string.sub(name, 1, (utf8.offset(name, NAME_MAX + 1) :: number) - 1)
	elseif chars == nil and #name > NAME_MAX then
		name = string.sub(name, 1, NAME_MAX)
	end
	name = string.match(name, "^(.-)%s*$") :: string
	if name == "" then
		return "Player"
	end
	return name
end

function Hiscores.valid(attempt: any): boolean
	if type(attempt) ~= "table" then
		return false
	end
	local userId, score, level = attempt.userId, attempt.score, attempt.level
	return type(userId) == "string"
		and string.match(userId, "^%-?%d+$") ~= nil
		and whole(score)
		and score >= 0
		and score <= MAX_SCORE
		and whole(level)
		and level >= 1
		and level <= MAX_INTEGER
		and type(attempt.name) == "string"
end

-- A row is replaced only by a strictly higher score, or the same score at a strictly higher level.
function Hiscores.qualifies(stored: Companion?, attempt: Attempt): boolean
	if not Hiscores.valid(attempt) then
		return false
	end
	if stored == nil then
		return true
	end
	return attempt.score > stored.score or (attempt.score == stored.score and attempt.level > stored.level)
end

-- The row to store, or nil when the stored one must stay. Never mutates `stored`.
function Hiscores.commit(stored: Companion?, attempt: Attempt): Companion?
	if not Hiscores.qualifies(stored, attempt) then
		return nil
	end
	local named = type(attempt.run) == "string" and attempt.run ~= "" and whole(attempt.at)
	return {
		name = Hiscores.cleanName(attempt.name),
		userId = attempt.userId,
		level = attempt.level,
		score = attempt.score,
		run = if named then attempt.run else nil,
		at = if named then attempt.at else nil,
	}
end

-- The ordered store keeps an integer only: the score, then the level (clamped) as the tie-break.
function Hiscores.pack(score: number, level: number): number
	return score * Hiscores.LEVEL_CAP + math.min(level, Hiscores.LEVEL_CAP - 1)
end

-- Try 1 waits nothing, later tries double from `base` up to `cap`. Nil outside 1..attempts.
function Hiscores.retryDelay(policy: Retry, n: number): number?
	if not whole(n) or n < 1 or n > policy.attempts then
		return nil
	end
	if n == 1 then
		return 0
	end
	return math.min(policy.base * 2 ^ (n - 2), policy.cap)
end

function Hiscores.attemptDelays(policy: Retry): { number }
	local out: { number } = {}
	for n = 1, policy.attempts do
		table.insert(out, Hiscores.retryDelay(policy, n) :: number)
	end
	return out
end

function Hiscores.spend(left: number, cost: number): (boolean, number)
	if cost < 1 or left < cost then
		return false, left
	end
	return true, left - cost
end

-- Page size of the ordered read: 10, then 50 once if the store rejects 10.
function Hiscores.pageAttempt(n: number): number?
	if n == 1 then
		return 10
	elseif n == 2 then
		return 50
	end
	return nil
end

-- The one place a packed integer becomes a displayed score. Entries without a whole `value` are skipped.
function Hiscores.scorePage(entries: { any }, n: number?): Page
	local page: Page = {}
	for _, entry in entries do
		if n ~= nil and #page >= n then
			break
		end
		if type(entry) == "table" and type(entry.key) == "string" and whole(entry.value) then
			table.insert(page, { key = entry.key, score = math.floor(entry.value / Hiscores.LEVEL_CAP) })
		end
	end
	return page
end

function Hiscores.globalName(base: string, scope: string): string
	return `{base}_{string.gsub(scope, "[^%w]", "_")}`
end

-- (store name, scope) for a board. Without scopes the scope is part of the name and the scope is "global".
function Hiscores.storeTarget(kind: string, board: Board, useScope: boolean): (string, string)
	local base = if kind == "ordered" then Hiscores.ORDERED_STORE else Hiscores.COMPANION_STORE
	local scope = Hiscores.scope(board)
	if useScope then
		return base, scope
	end
	return Hiscores.globalName(base, scope), "global"
end

local function sameUser(key: string, userId: string): boolean
	return key == userId or string.sub(key, 1, #userId + 1) == `{userId}:`
end

-- The top `n` rows of the pages the store gave. `lookup` answers a key's companion: (nil, nil) is an absent row
-- (skipped), an error is a row the page says exists but cannot be read, which makes the whole board unknown (nil).
function Hiscores.rows(pages: { Page }, lookup: (string) -> (Companion?, string?), n: number): { Row }?
	local out: { Row } = {}
	if n < 1 then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, page in pages do
		for _, entry in page do
			local key = entry.key
			if type(key) ~= "string" or type(entry.score) ~= "number" or seen[key] then
				continue
			end
			seen[key] = true
			local companion, err = lookup(key)
			if err ~= nil then
				return nil
			end
			if
				type(companion) == "table"
				and type(companion.userId) == "string"
				and whole(companion.level)
				and companion.level >= 1
				and sameUser(key, companion.userId)
			then
				local named = type(companion.run) == "string" and companion.run ~= "" and whole(companion.at)
				table.insert(out, {
					rank = 0,
					name = Hiscores.cleanName(companion.name),
					userId = companion.userId,
					score = entry.score,
					level = companion.level,
					run = if named then companion.run else nil,
					at = if named then companion.at else nil,
					runScore = if whole(companion.score) and companion.score >= 0
						then companion.score
						else nil,
				})
			end
		end
	end
	table.sort(out, function(a: Row, b: Row): boolean
		if a.score ~= b.score then
			return a.score > b.score
		elseif a.level ~= b.level then
			return a.level > b.level
		end
		return a.userId < b.userId
	end)
	while #out > n do
		table.remove(out)
	end
	for i, row in out do
		row.rank = i
	end
	return out
end

function Hiscores.rankOf(rows: { Row }, userId: string): number?
	for _, row in rows do
		if row.userId == userId then
			return row.rank
		end
	end
	return nil
end

function Hiscores.lobbyRows(rows: { Row }): { { rank: number, name: string, score: number, level: number } }
	local out = {}
	for _, row in rows do
		table.insert(out, { rank = row.rank, name = row.name, score = row.score, level = row.level })
	end
	return out
end

-- The in-memory store: one companion and one packed integer per scope and key.
function Hiscores.fake(): Store
	local entries: { [string]: { [string]: Companion } } = {}
	local packs: { [string]: { [string]: number } } = {}
	local store = {}
	function store.get(board: Board, key: string): Companion?
		local held = entries[Hiscores.scope(board)]
		return if held then held[key] else nil
	end
	function store.set(board: Board, key: string, packed: number, entry: Companion)
		local scope = Hiscores.scope(board)
		entries[scope] = entries[scope] or {}
		packs[scope] = packs[scope] or {}
		entries[scope][key] = entry
		packs[scope][key] = packed
	end
	function store.top(board: Board, n: number): { Page }
		local list: { { key: string, value: number } } = {}
		local held: { [string]: number } = packs[Hiscores.scope(board)] or {}
		for key, value in held do
			table.insert(list, { key = key, value = value })
		end
		table.sort(list, function(a, b)
			if a.value ~= b.value then
				return a.value > b.value
			end
			return a.key < b.key
		end)
		while #list > n do
			table.remove(list)
		end
		return { Hiscores.scorePage(list) }
	end
	return store
end

-- Write an attempt to every board it improves. Returns which boards were written.
function Hiscores.submit(store: Store, attempt: Attempt, unix: number): { [string]: boolean }
	local wrote = { all = false, day = false, week = false }
	if not Hiscores.valid(attempt) then
		return wrote
	end
	for _, id: BoardId in BOARD_IDS do
		local board = Hiscores.board(id, unix)
		local key = Hiscores.entryKey(attempt.userId, board)
		local made = Hiscores.commit(store.get(board, key), attempt)
		if made ~= nil then
			store.set(board, key, Hiscores.pack(made.score, made.level), made)
			wrote[id] = true
		end
	end
	return wrote
end

function Hiscores.top(store: Store, id: BoardId, unix: number): { Row }
	local board = Hiscores.board(id, unix)
	local pages = store.top(board, Hiscores.N)
	return Hiscores.rows(pages, function(key: string): (Companion?, string?)
		return store.get(board, key), nil
	end, Hiscores.N) or {}
end

local function affords(io: Io, ...: string): boolean
	for _, op in { ... } do
		if not (Hiscores.spend(io.budget(op), 1)) then
			return false
		end
	end
	return true
end

-- Write one board with retries. The companion row and the ordered integer are both transforms the store applies
-- to what it actually holds, so a snapshot taken earlier is never published; the ordered one only ever raises.
local function driveBoard(io: Io, id: BoardId, attempt: Attempt, unix: number, delays: { number }): boolean
	local board = Hiscores.board(id, unix)
	local key = Hiscores.entryKey(attempt.userId, board)
	local seen: Companion? = nil
	local made: Companion? = nil
	local function entry(old: Companion?): Companion?
		seen = old
		made = Hiscores.commit(old, attempt)
		return made
	end
	local kept: Companion? = nil
	local replaced = false
	local function score(old: number?): number?
		local row = kept :: Companion
		return math.max(old or 0, Hiscores.pack(row.score, row.level))
	end
	for _, delay in delays do
		if delay > 0 then
			io.wait(delay)
		end
		if kept == nil and affords(io, "get", "set") then
			local _, err = io.updateEntry(board, key, entry)
			if err == nil then
				replaced = made ~= nil
				kept = made or seen
				if kept == nil then
					return false
				end
			end
		end
		if kept ~= nil and affords(io, "getSorted", "setSorted") then
			local _, err = io.updateScore(board, key, score)
			if err == nil then
				return replaced
			end
		end
	end
	return false
end

-- The all-time per-player board through `io`: one page, then each row's companion, each companion read spending
-- "get". Nil when the page or any row on it cannot be read. The list budget reads 0 by contract, so the page
-- read is never gated on it.
function Hiscores.readAll(io: Io, unix: number): { Row }?
	local all = Hiscores.board("all", unix)
	local pages = io.top(all)
	if pages == nil then
		return nil
	end
	return Hiscores.rows(pages, function(key: string): (Companion?, string?)
		if not (Hiscores.spend(io.budget("get"), 1)) then
			return nil, "budget"
		end
		return io.get(all, key)
	end, Hiscores.N)
end

-- Submit an attempt through `io` and read the all-time board to find its rank. A board that fails does not
-- stop the others. The rank is nil when the page or any of its rows cannot be read.
function Hiscores.drive(io: Io, attempt: Attempt, unix: number, policy: Retry): DriveResult
	local wrote = { all = false, day = false, week = false }
	if Hiscores.valid(attempt) then
		local delays = Hiscores.attemptDelays(policy)
		for _, id: BoardId in BOARD_IDS do
			wrote[id] = driveBoard(io, id, attempt, unix, delays)
		end
	end
	local rank: number? = nil
	local rows = Hiscores.readAll(io, unix)
	if rows ~= nil then
		rank = Hiscores.rankOf(rows, attempt.userId)
	end
	return { wrote = wrote, rank = rank, rows = rows }
end

-- One submit per run: record `runId` on a copy of `done`, or refuse it (a bad id, or one already recorded).
function Hiscores.once(done: { [number]: boolean }, runId: number): (boolean, { [number]: boolean })
	if not whole(runId) or runId < 1 or done[runId] then
		return false, done
	end
	local nextDone = table.clone(done)
	nextDone[runId] = true
	return true, nextDone
end

-- The state of a session's first run. The run id is this counter, never a value a client or a tick supplies.
function Hiscores.newRun(): RunState
	return { run = 1, done = {}, waited = 0, drop = false }
end

-- A play again that the session accepted starts the next run; one it refused changes nothing.
function Hiscores.onAgain(state: RunState, ok: boolean): RunState
	if not ok then
		return state
	end
	return { run = state.run + 1, done = state.done, waited = state.waited, drop = false }
end

-- Keep a departed player's run for the dying pause, or drop it: at once when it has ended.
function Hiscores.leave(stepsWaited: number, sawOver: boolean): "drop" | "keep"
	if sawOver or stepsWaited >= Hiscores.LEAVE_STEPS then
		return "drop"
	end
	return "keep"
end

-- One server step of a run. Returns the next state and the submission when this step ended the run with a score.
-- `here` is whether the player is still in the server; the steps away are counted.
function Hiscores.onStep(state: RunState, events: { StepEvent }, here: boolean): (RunState, Submission?)
	local saw = false
	local done = state.done
	local submission: Submission? = nil
	for _, event in events do
		if event.kind ~= "GameOver" then
			continue
		end
		saw = true
		if type(event.score) == "number" and type(event.level) == "number" then
			local fresh, nextDone = Hiscores.once(done, state.run)
			if fresh then
				done = nextDone
				submission = { score = event.score, level = event.level, run = state.run }
			end
		end
	end
	local waited = if here then 0 else state.waited + 1
	local drop = not here and Hiscores.leave(waited, saw) == "drop"
	return { run = state.run, done = done, waited = waited, drop = drop }, submission
end

-- Whether a closing server still waits: while a run or a write is pending, and not past CLOSE_WAIT.
function Hiscores.holdClose(runs: number, drives: number, waited: number): boolean
	return (runs > 0 or drives > 0) and waited < Hiscores.CLOSE_WAIT
end

-- A board id a client may ask for: "all", "day" or "week", and nothing else (a number or a table is nil).
function Hiscores.boardId(raw: any): BoardId?
	if raw == "all" then
		return ALL
	elseif raw == "day" then
		return DAY
	elseif raw == "week" then
		return WEEK
	end
	return nil
end

-- How long a key that has failed `count` reads in a row is left alone: gap * 2^count, at most `ttl`.
function Hiscores.failureWait(gap: number, ttl: number, count: number): number
	return math.min(gap * 2 ^ count, ttl)
end

-- The shared read of one board key. A fresh cache answers; a stale one is read again unless a read is already
-- under way or the key is inside the wait that its failed reads earned. `fetch` returns the rows, or nil for a
-- failed read; an empty board is a board. Returns the cache, the rows (nil when nothing answered) and the failure.
function Hiscores.lookup(
	cache: CacheEntry?,
	now: number,
	ttl: number,
	gap: number,
	inflight: boolean,
	fetch: (() -> { Row }?)?,
	failure: Failure?
): (CacheEntry?, { Row }?, Failure?)
	if type(now) ~= "number" or now ~= now then
		return cache, nil, failure
	end
	if cache ~= nil and now >= cache.at and now - cache.at < ttl then
		return cache, cache.rows, failure
	end
	if inflight or fetch == nil then
		return cache, nil, failure
	end
	if
		failure ~= nil
		and (now < failure.at or now - failure.at < Hiscores.failureWait(gap, ttl, failure.count))
	then
		return cache, nil, failure
	end
	local rows = fetch()
	if rows == nil then
		return cache, nil, { at = now, count = (if failure then failure.count else 0) + 1 }
	end
	return { at = now, rows = rows }, rows, nil
end

-- The all-time top-N list of runs ----------------------------------------------------------------------------------
-- One key of Hiscores.TOP_STORE holds the N best runs of all players, so one player can hold several places. It
-- lives beside the per-player boards, which keep each player's best as before.

-- A run's id: unique per player, instant, run counter and server. `server` is the engine's job id, "" without one.
function Hiscores.runId(userId: string, unix: number, run: number, server: string?): string
	local job = if type(server) == "string" then server else ""
	return `{userId}:{string.format("%d", unix)}:{string.format("%d", run)}:{job}`
end

-- The list entry for a finished run, or nil for an attempt `valid` refuses.
function Hiscores.topRun(attempt: Attempt, unix: number, run: number, server: string?): TopRun?
	if not Hiscores.valid(attempt) or not whole(unix) or not whole(run) then
		return nil
	end
	return {
		id = Hiscores.runId(attempt.userId, unix, run, server),
		name = Hiscores.cleanName(attempt.name),
		userId = attempt.userId,
		score = attempt.score,
		level = attempt.level,
		at = unix,
	}
end

local function validRun(e: any): boolean
	return type(e) == "table"
		and type(e.id) == "string"
		and e.id ~= ""
		and type(e.name) == "string"
		and whole(e.at)
		and Hiscores.valid({ name = e.name, userId = e.userId, score = e.score, level = e.level })
end

local function before(a: TopRun, b: TopRun): boolean
	if a.score ~= b.score then
		return a.score > b.score
	elseif a.level ~= b.level then
		return a.level > b.level
	elseif a.at ~= b.at then
		return a.at < b.at -- the earlier run keeps a tied place
	end
	return a.id < b.id
end

-- The stored list in order: valid entries only, each id once, at most N.
local function ordered(list: any): { TopRun }
	local out: { TopRun } = {}
	if type(list) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, e in list do
		if validRun(e) and not seen[e.id] then
			seen[e.id] = true
			table.insert(out, {
				id = e.id,
				name = Hiscores.cleanName(e.name),
				userId = e.userId,
				score = e.score,
				level = e.level,
				at = e.at,
			})
		end
	end
	table.sort(out, before)
	while #out > Hiscores.N do
		table.remove(out)
	end
	return out
end

-- A per-player best row as a list entry, taken whole from its companion row: the companion's score and level, and,
-- when it names its run, that run's id and instant, so the same run has one id (and one score) whichever server
-- merges it. A row from before d0124 is an older run (at 0) with the id "best:<userId>:<score>:<level>", so a raised
-- best is a new entry and the older one, a real older run, stays. Nil for a row without a valid companion score.
function Hiscores.bestRun(row: Row): TopRun?
	local score = row.runScore
	if type(score) ~= "number" or not whole(score) or score < 0 then
		return nil
	end
	if type(row.run) == "string" and row.run ~= "" and whole(row.at) then
		return {
			id = row.run :: string,
			name = row.name,
			userId = row.userId,
			score = score,
			level = row.level,
			at = row.at :: number,
		}
	end
	return {
		id = `best:{row.userId}:{string.format("%d", score)}:{string.format("%d", row.level)}`,
		name = row.name,
		userId = row.userId,
		score = score,
		level = row.level,
		at = 0,
	}
end

-- Put `run`, then every per-player best in `bests`, into `list`: the new list (at most N, in order) and the run's
-- place in it, nil when it does not make the list. Entries are one per id, and an id already stored keeps its
-- stored entry and place; nothing else is skipped. Never mutates `list`.
function Hiscores.mergeRun(list: { TopRun }, run: TopRun, bests: { Row }): ({ TopRun }, number?)
	-- the stored copy comes first, so `ordered` keeps it when an id is already there
	local all = ordered(list)
	table.insert(all, run)
	for _, row in bests do
		local made = Hiscores.bestRun(row)
		if made ~= nil then
			table.insert(all, made)
		end
	end
	local out = ordered(all)
	for i, e in out do
		if e.id == run.id then
			return out, i
		end
	end
	return out, nil
end

-- `mergeRun` with no bests.
function Hiscores.addRun(list: { TopRun }, run: TopRun): ({ TopRun }, number?)
	return Hiscores.mergeRun(list, run, {})
end

-- The lobby's rows of a stored list, ranked 1..N; nil when nothing is stored yet (not a table).
function Hiscores.topRows(list: any): { Row }?
	if type(list) ~= "table" then
		return nil
	end
	local out: { Row } = {}
	for i, e in ordered(list) do
		table.insert(out, { rank = i, name = e.name, userId = e.userId, score = e.score, level = e.level })
	end
	return out
end

local function sameIds(a: { TopRun }, b: { TopRun }): boolean
	if #a ~= #b then
		return false
	end
	for i, e in a do
		if e.id ~= b[i].id then
			return false
		end
	end
	return true
end

-- Write a run to the top-N list with retries, and say where it stands. `bests` is the per-player all-time board
-- (drive's own read, after its write), merged in on every write so a best written by a build without the list is
-- listed too; nil when it could not be read. The write is a transform the store applies to what it holds, so
-- another server's list is never lost, and it writes nothing when the list would not change. A list is never
-- created without the bests: with no list and no bests nothing is written. `known` is false when nothing was
-- written or found, and then nothing is said about the run; otherwise `place` is its place, or `missed` is N.
function Hiscores.driveTop(top: TopIo, io: Io, run: TopRun?, bests: { Row }?, policy: Retry): TopResult
	local unknown: TopResult = { known = false, place = nil, missed = nil }
	if run == nil or not validRun(run) then
		return unknown
	end
	local entry = run :: TopRun
	local place: number? = nil
	local blind = false -- no list stored and no bests to start it from
	local function transform(old: { TopRun }?): { TopRun }?
		place = nil
		blind = type(old) ~= "table" and bests == nil
		if blind then
			return nil
		end
		local base: { TopRun } = if type(old) == "table" then old else {}
		local made, at = Hiscores.mergeRun(base, entry, bests or {})
		place = at
		if type(old) == "table" and sameIds(ordered(old), made) then
			return nil -- nothing changes
		end
		return made
	end
	for _, delay in Hiscores.attemptDelays(policy) do
		if delay > 0 then
			io.wait(delay)
		end
		if affords(io, "get", "set") then
			local _, err = top.update(transform)
			if err == nil then
				if blind then
					return unknown
				end
				return { known = true, place = place, missed = if place == nil then Hiscores.N else nil }
			end
		end
	end
	return unknown
end

-- A player's best from their all-time companion row: score and level, or nil when there is none.
function Hiscores.best(companion: any): Best?
	if type(companion) ~= "table" or not whole(companion.score) or companion.score < 0 then
		return nil
	end
	if not whole(companion.level) or companion.level < 1 then
		return nil
	end
	return { score = companion.score, level = companion.level }
end

-- Whether a player's held best must be read again: nothing held, or a finished read that is no longer fresh. A
-- read in flight is never doubled.
function Hiscores.needsRead(held: { at: number, reading: boolean }?, now: number, ttl: number): boolean
	if held == nil then
		return true
	end
	return not held.reading and not Hiscores.fresh(held.at, now, ttl)
end

-- Whether a value read at `at` still answers at `now`: not from the future, and younger than `ttl` seconds.
function Hiscores.fresh(at: number?, now: number, ttl: number): boolean
	return type(at) == "number" and type(now) == "number" and now >= at and now - at < ttl
end

return Hiscores
