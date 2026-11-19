--!strict
-- Board (f0206): a card's hiscores. Pure view models and rules: the three tabs and the keys that step them, what a row,
-- the header and the "your best" line say (revives used, "—" for none; the best not known yet told apart from no best),
-- the client's defensive read of an answer, the board's layout and columns in its slot, which boards the client asks
-- for and when, and the server's read policy: when an ask may make the arcade's Boards read the stores (a refresh,
-- under a read allowance and the engine's request budget), when it only joins the arcade's fresh cache (a forward), and
-- when the server answers from the rows it holds, with each player's rank tied to the rows it was heard with. A title is
-- a card's `name` (src/shared/Games.luau); the arcade's Hiscores and HiscoreGames reach this module only as values the
-- adapters pass in. The text size follows Card's text model, whose glyph width the view passes in (`glyph`).

-- a board id, one of TABS ("all", "day", "week"); a string because the Roblox type pass widens a literal union across
-- a require (f0201 E6)
export type Id = string
-- one row as the server sends it: rank, name, score, the title's progress figure (`level`) and the revives used
export type Row = { rank: number, name: string, score: number, level: number, revives: number }
export type Best = { score: number, level: number, revives: number }
-- ok: the rows are the stores'; failed: the last read failed, the rows are those held; wait: nothing read yet
export type Status = "ok" | "failed" | "wait"
-- best: the player's all-time best on this title; pending: the server has not heard it yet (best nil and pending false
-- is a player with no run)
export type Answer = {
	name: string,
	id: Id,
	rows: { Row },
	rank: number?,
	status: Status,
	best: Best?,
	pending: boolean,
}
-- the client's knowledge of its own all-time best on one title: known once an answer said it (nil best: no run)
export type Mine = { known: boolean, best: Best? }
export type Line = { cells: { string }, mine: boolean }
-- best: the your-best line's cells, one per column (nil: no line)
export type View = { header: { string }, lines: { Line }, note: string, best: { string }? }
-- pixels in the Boards slot: the tab bar, one text line, the rows' visible height, their whole height, and the size of
-- every text on the board
export type Layout = { tabs: number, line: number, view: number, canvas: number, text: number }
-- one column: its name, the characters it shows whole, its label's left edge and width (shares of the slot's width,
-- inset GUTTER / 2 characters inside the column's box) and its text's alignment
export type Column = { name: string, chars: number, x: number, width: number, align: string }
-- the client's last ask for one board (os.clock), and whether its answer asked to be asked again soon
export type Asked = { at: number, wait: boolean }
export type Want = { name: string, id: Id }
-- the server's rows of one board: when its last refresh began (os.time), what the last answer said, the rows, and their
-- version (raised whenever the arcade's rows differ from those held)
export type Snap = { at: number?, failed: boolean, known: boolean, rows: { Row }, version: number }
-- the refreshes this server may still start: a count and when it was filled
export type Bucket = { tokens: number, at: number? }
-- the engine's request budget left this minute: standard reads (GetAsync) and sorted reads (GetSortedAsync)
export type Budget = { standard: number, sorted: number }
export type Ask = {
	snap: Snap?, -- the board's rows held by the server, nil before any ask
	last: number?, -- when this player's best for this title was last read through the arcade (os.time)
	all: boolean, -- the all-time board, whose arcade answer carries the player's best
	bucket: Bucket,
	budget: Budget,
	players: number, -- players in the server
	now: number, -- os.time
	ttl: number, -- the arcade's Hiscores.CACHE_TTL
}
export type Act = "refresh" | "forward" | "answer"
-- best: the forward makes the arcade read the asker's best, so the adapter records `last = now`
export type Plan = { act: Act, bucket: Bucket, best: boolean }
-- a player's rank on a board, heard with the rows of `version`
export type Held = { rank: number?, version: number }

local Board = {}

Board.TABS = table.freeze({ "all", "day", "week" }) -- left to right
Board.TAB_TEXT = table.freeze({ all = "ALL-TIME", day = "TODAY", week = "THIS WEEK" })
Board.N = 10 -- rows a board shows: the arcade's Hiscores.N
Board.NONE = "—" -- no revives; no best
Board.PENDING = "…" -- the best not heard yet
Board.LOADING = "LOADING"
Board.EMPTY = "NO SCORES YET"
Board.DOWN = "SCORES UNAVAILABLE"
Board.BEST = "YOUR BEST" -- the your-best line on the all-time board
Board.BEST_EVER = "BEST EVER" -- the same line on today's and this week's: the best is all-time
-- the columns: each shows `chars` characters whole (a rank to 10, a name's first 7, a score to 6 digits, LEVEL, REVIVES)
-- in a box GUTTER characters wider, so neighbouring texts never touch; CHARS is the line's whole width in characters
Board.GUTTER = 0.4
Board.CHARS = 29
local SPEC = {
	{ name = "Rank", chars = 2, align = "Right" },
	{ name = "Name", chars = 7, align = "Left" },
	{ name = "Score", chars = 6, align = "Right" },
	{ name = "Progress", chars = 5, align = "Right" },
	{ name = "Revives", chars = 7, align = "Right" },
}
local columns: { Column } = {}
do
	local at = 0
	for _, c in SPEC do
		table.insert(
			columns,
			table.freeze({
				name = c.name,
				chars = c.chars,
				x = (at + Board.GUTTER / 2) / Board.CHARS,
				width = c.chars / Board.CHARS,
				align = c.align,
			})
		)
		at += c.chars + Board.GUTTER
	end
end
Board.COLUMNS = table.freeze(columns)
-- the tab keys, by KeyCode name: W, Up and the left trigger the tab before; S, Down and the right trigger the next
Board.KEYS = table.freeze({ W = -1, Up = -1, ButtonL2 = -1, S = 1, Down = 1, ButtonR2 = 1 })
Board.ACTION = "PortalBoards" -- the ContextActionService action name
Board.PRIORITY = 2500 -- above the default controls (2000), below the test purchase screen's 3000 (f0201)
Board.REASK = 30 -- seconds between the client's asks for one board
Board.WAIT_RETRY = 2 -- seconds before the client asks again after a wait, or while its best is pending
Board.TAB_PX = 44 -- the tab bar's height: the smallest touch target
Board.MIN_LINE_PX = 13 -- at least Card.MIN_TEXT (f0205)
Board.MAX_LINE_PX = 28
Board.REFRESH = 30 -- seconds a board's rows are held before an ask may read them again
Board.MARGIN = 2 -- seconds short of the arcade's cache time in which a forward still finds its cache fresh
Board.BEST_GAP = 60 -- seconds before an ask may read a player's best for a title again
Board.RATE = 1.5 -- refreshes a minute the server may start, per player in it
Board.FLOOR = 4 -- refreshes a minute any server may start, however few players it has
Board.BURST = 12 -- refreshes it may start at once: one per board (four titles, three tabs), so every first visit answers at once
Board.KEEP = 4 -- tokens a refresh of a board with rows leaves for boards with none: a tab's four, so a first visit never starves
Board.COST = table.freeze({ standard = 12, sorted = 2 }) :: Budget -- a refresh's most: a list, two page tries, ten rows, a best
Board.RESERVE = table.freeze({ standard = 20, sorted = 2 }) :: Budget -- left for the wallet and the purchases

local function whole(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v == math.floor(v)
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function int(n: number): string
	return string.format("%d", n)
end

-- A board id: "all", "day" or "week", and nothing else.
function Board.id(raw: any): Id?
	if raw == "all" then
		return "all"
	elseif raw == "day" then
		return "day"
	elseif raw == "week" then
		return "week"
	end
	return nil
end

-- The tab `by` places from `current`, wrapping both ways; a step that is not a whole number stays.
function Board.tab(current: Id, by: number): Id
	local at = table.find(Board.TABS, current) or 1
	if not whole(by) then
		return Board.TABS[at]
	end
	return Board.TABS[(at - 1 + by) % #Board.TABS + 1]
end

-- The tab step of a key, by its KeyCode name; nil for any other key.
function Board.step(key: string): number?
	return (Board.KEYS :: any)[key]
end

-- Revives as a row shows them: the count, or "—" for none (0, or anything that is not a whole count).
function Board.revives(n: any): string
	if whole(n) and n >= 1 then
		return int(n)
	end
	return Board.NONE
end

-- The header: one text per column, the progress column named by the title's figure ("Level" shows LEVEL).
function Board.header(progress: string): { string }
	return { "#", "NAME", "SCORE", string.upper(progress), "REVIVES" }
end

-- One row's texts, one per column.
function Board.cells(row: Row): { string }
	return { int(row.rank), row.name, int(row.score), int(row.level), Board.revives(row.revives) }
end

-- The label of the "your best" line on a board: YOUR BEST on the all-time board, BEST EVER on the others (the best is
-- the player's all-time one, never the day's or the week's).
function Board.bestLabel(id: Id): string
	return if id == "all" then Board.BEST else Board.BEST_EVER
end

-- The "your best" line, one text per column like a row: its label where the name goes (it spans the rank's column
-- too), then the score, the figure and the revives; a dash in each for a player with no best.
function Board.bestCells(best: Best?, id: Id): { string }
	local label = Board.bestLabel(id)
	if best == nil then
		return { "", label, Board.NONE, Board.NONE, Board.NONE }
	end
	return { "", label, int(best.score), int(best.level), Board.revives(best.revives) }
end

-- The "your best" line while the player's best is not known yet: the pending mark in each figure's place.
function Board.pendingCells(id: Id): { string }
	return { "", Board.bestLabel(id), Board.PENDING, Board.PENDING, Board.PENDING }
end

-- What a card's board shows for the answer held for its tab and the player's own all-time best on its title: the
-- header, a line per row (the player's own marked), a note (LOADING before an answer or on wait, NO SCORES YET for an
-- empty board, SCORES UNAVAILABLE for a failed read with no rows), and, once answered, the "your best" line under every
-- tab: the best when known, the pending mark until then.
function Board.view(answer: Answer?, progress: string, mine: Mine?): View
	local lines: { Line } = {}
	local note = Board.LOADING
	local best: { string }? = nil
	if answer ~= nil and answer.status ~= "wait" then
		for _, row in answer.rows do
			table.insert(
				lines,
				{ cells = Board.cells(row), mine = answer.rank ~= nil and row.rank == answer.rank }
			)
		end
		if #lines > 0 then
			note = ""
		elseif answer.status == "failed" then
			note = Board.DOWN
		else
			note = Board.EMPTY
		end
		best = if mine ~= nil and mine.known
			then Board.bestCells(mine.best, answer.id)
			else Board.pendingCells(answer.id)
	end
	return { header = Board.header(progress), lines = lines, note = note, best = best }
end

local function row(raw: any): Row?
	if type(raw) ~= "table" then
		return nil
	end
	local rank, name, score, level = raw.rank, raw.name, raw.score, raw.level
	if not whole(rank) or rank < 1 or rank > Board.N or type(name) ~= "string" then
		return nil
	end
	if not whole(score) or score < 0 or not whole(level) or level < 1 then
		return nil
	end
	local revives = if whole(raw.revives) and raw.revives >= 0 then raw.revives else 0
	return { rank = rank, name = name, score = score, level = level, revives = revives }
end

local function best(raw: any): Best?
	if type(raw) ~= "table" then
		return nil
	end
	if not whole(raw.score) or raw.score < 0 or not whole(raw.level) or raw.level < 1 then
		return nil
	end
	local revives = if whole(raw.revives) and raw.revives >= 0 then raw.revives else 0
	return { score = raw.score, level = raw.level, revives = revives }
end

-- The client's read of an answer (name, id, rows, rank, status, best): nil unless the title is one of `names`, the
-- id a board id and the status one of ok, failed and wait. Rows that make no sense are dropped, the rest sorted by
-- rank and cut to N; a rank that is not a row's is nil. The best is the player's all-time best on that title, on any
-- board: `false` is pending (not heard yet), a best that makes no sense or nil is none. Never raises.
function Board.parse(names: { [string]: boolean }, ...: any): Answer?
	local name, rawId, rawRows, rawRank, rawStatus, rawBest = ...
	if type(name) ~= "string" or names[name] ~= true then
		return nil
	end
	local id = Board.id(rawId)
	if id == nil then
		return nil
	end
	local status: Status
	if rawStatus == "ok" then
		status = "ok"
	elseif rawStatus == "failed" then
		status = "failed"
	elseif rawStatus == "wait" then
		status = "wait"
	else
		return nil
	end
	local rows: { Row } = {}
	if type(rawRows) == "table" then
		for _, raw in ipairs(rawRows) do
			local r = row(raw)
			if r ~= nil then
				table.insert(rows, r)
			end
		end
	end
	table.sort(rows, function(a: Row, b: Row): boolean
		return a.rank < b.rank
	end)
	while #rows > Board.N do
		table.remove(rows)
	end
	local rank: number? = nil
	for _, r in rows do
		if r.rank == rawRank then
			rank = r.rank
		end
	end
	return {
		name = name,
		id = id,
		rows = rows,
		rank = rank,
		status = status,
		best = best(rawBest),
		pending = rawBest == false,
	}
end

-- The player's own best on a title after an answer: an answer that is not pending says it (nil: no run); a pending
-- answer leaves what was known.
function Board.learn(mine: Mine?, answer: Answer): Mine
	if answer.pending then
		return mine or { known = false, best = nil }
	end
	return { known = true, best = answer.best }
end

-- The board's layout in a slot `width` x `height` pixels: the tab bar, then the header line, the rows' view and the
-- best line, each line between MIN_LINE_PX and MAX_LINE_PX; the rows' whole height (canvas) scrolls in the view when
-- it is taller. Every text is one size, whole pixels: the line's height, or less where a line of CHARS characters
-- would not fit the width (Card's text model: a character is `glyph` of the size wide; the view passes Card.GLYPH).
function Board.layout(width: number, height: number, glyph: number): Layout
	local w = if finite(width) and width > 0 then width else 0
	local h = if finite(height) and height > 0 then height else 0
	local g = if finite(glyph) and glyph > 0 then glyph else 1
	local line = math.clamp((h - Board.TAB_PX) / (Board.N + 2), Board.MIN_LINE_PX, Board.MAX_LINE_PX)
	return {
		tabs = Board.TAB_PX,
		line = line,
		view = math.max(0, h - Board.TAB_PX - 2 * line),
		canvas = Board.N * line,
		text = math.floor(math.min(line, w / (g * Board.CHARS))),
	}
end

-- The boards the client asks for: every card's board on the chosen tab, and, while a title's own best is not known,
-- that card's all-time board too (only the arcade's all-time answer brings the best).
function Board.wants(tab: Id, names: { string }, mine: { [string]: Mine }): { Want }
	local out: { Want } = {}
	for _, name in names do
		table.insert(out, { name = name, id = tab })
		local m = mine[name]
		if tab ~= "all" and (m == nil or not m.known) then
			table.insert(out, { name = name, id = "all" })
		end
	end
	return out
end

-- Whether the client asks for one board now: never asked, a clock that went back, or REASK since the last ask
-- (WAIT_RETRY when its answer was a wait or its best pending). A time that is not finite asks nothing.
function Board.askDue(last: Asked?, now: number): boolean
	if not finite(now) then
		return false
	end
	if last == nil or now < last.at then
		return true
	end
	return now - last.at >= (if last.wait then Board.WAIT_RETRY else Board.REASK)
end

-- The read allowance after `now`: max(RATE a minute per player, FLOOR) a minute, at most BURST; full when never
-- filled, and only re-dated when the clock went back.
function Board.fill(b: Bucket, now: number, players: number): Bucket
	if not finite(now) then
		return b
	end
	if b.at == nil then
		return { tokens = Board.BURST, at = now }
	end
	local at = b.at :: number
	if now < at then
		return { tokens = b.tokens, at = now }
	end
	local count = if finite(players) then math.max(players, 0) else 0
	local per = math.max(Board.RATE * count, Board.FLOOR) / 60
	return { tokens = math.min(Board.BURST, b.tokens + per * (now - at)), at = now }
end

-- Whether this ask would make the arcade read the player's best: never asked, a clock that went back, or BEST_GAP
-- since; "fresh" while the arcade still holds the last one (inside ttl - MARGIN); "hold" in between.
function Board.bestRead(last: number?, now: number, ttl: number): "read" | "fresh" | "hold"
	if last == nil or now < last then
		return "read"
	elseif now - last < ttl - Board.MARGIN then
		return "fresh"
	elseif now - last >= Board.BEST_GAP then
		return "read"
	end
	return "hold"
end

-- What the server does with one ask. A forward while the board's last refresh is inside the arcade's cache time
-- (ttl - MARGIN) and its answer did not fail: the arcade answers from its cache or its read under way, reading no
-- board. A refresh once REFRESH has passed (or never read, or a clock that went back), when the allowance has a
-- token (KEEP more for a board that has rows) and the engine's budget holds COST above RESERVE. Else the server
-- answers from the rows it holds. A forward of the all-time board that would read the player's best needs one
-- standard read above RESERVE, and is held back inside BEST_GAP.
function Board.plan(a: Ask): Plan
	local now = a.now
	if not finite(now) or not finite(a.ttl) then
		return { act = "answer", bucket = a.bucket, best = false }
	end
	local bucket = Board.fill(a.bucket, now, a.players)
	local reads = if a.all then Board.bestRead(a.last, now, a.ttl) else "fresh"
	local snap = a.snap
	if snap ~= nil and snap.at ~= nil and not snap.failed then
		local at = snap.at :: number
		if now >= at and now - at < a.ttl - Board.MARGIN then
			if reads == "hold" or (reads == "read" and a.budget.standard < Board.RESERVE.standard + 1) then
				return { act = "answer", bucket = bucket, best = false }
			end
			return { act = "forward", bucket = bucket, best = reads == "read" }
		end
	end
	local due = snap == nil
		or snap.at == nil
		or now < (snap.at :: number)
		or now - (snap.at :: number) >= Board.REFRESH
	if
		due
		and bucket.tokens >= 1 + (if snap ~= nil and snap.known then Board.KEEP else 0)
		and a.budget.sorted >= Board.RESERVE.sorted + Board.COST.sorted
		and a.budget.standard >= Board.RESERVE.standard + Board.COST.standard
	then
		return {
			act = "refresh",
			bucket = { tokens = bucket.tokens - 1, at = bucket.at },
			best = reads ~= "fresh",
		}
	end
	return { act = "answer", bucket = bucket, best = false }
end

-- What a board's held rows say: wait before any answer, failed after a failed one, else ok.
function Board.status(snap: Snap?): Status
	if snap == nil or not snap.known then
		return "wait"
	elseif snap.failed then
		return "failed"
	end
	return "ok"
end

-- Whether two lists of rows say the same: each row's rank, name, score, level and revives, in order.
function Board.sameRows(a: { Row }, b: { Row }): boolean
	if #a ~= #b then
		return false
	end
	for i, x in a do
		local y = b[i]
		if
			x.rank ~= y.rank
			or x.name ~= y.name
			or x.score ~= y.score
			or x.level ~= y.level
			or x.revives ~= y.revives
		then
			return false
		end
	end
	return true
end

-- A player's rank on the board's held rows: the one heard with the rows held now (the same version), else nil.
function Board.rankFor(held: Held?, snap: Snap?): number?
	if held == nil or snap == nil or held.version ~= snap.version then
		return nil
	end
	return held.rank
end

return table.freeze(Board)
