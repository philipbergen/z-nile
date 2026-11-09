--!strict
-- The board's pure rules (c0118): an issue's column, raft bands, the done window's age, the UTC week of an instant, a
-- landed raft's review rounds, and the two charts' weekly series. No reads: board.luau gathers the inputs.
local stats = require("./stats")

local boardview = {}

export type Column = "ticket" | "design" | "raft" | "ready" | "run" | "done"
export type Band = { raft: string?, ids: { string } }
export type Landed = { id: string, at: number, design: number, code: number }
export type TokenRow = { at: number, phase: string, tokens: number, model: string? }
export type Series = { key: string, label: string, values: { number? } }
export type Range = { key: string, label: string, days: number? }
export type Weekly = { labels: { string }, weeks: { string }, series: { Series } }

-- The six columns, left to right, and the pipeline step behind each (zz-rules, Board).
boardview.COLUMNS = { "ticket", "design", "raft", "ready", "run", "done" } :: { Column }
boardview.LABELS = {
	ticket = "Ticket",
	design = "Design",
	raft = "Raft",
	ready = "Ready",
	run = "Run",
	done = "Done",
}

local HOUR, DAY = 3600, 86400
-- The done window: 24 hours by default, from 1 hour to 30 days.
boardview.WINDOWS =
	{ HOUR, 3 * HOUR, 6 * HOUR, 12 * HOUR, DAY, 2 * DAY, 3 * DAY, 7 * DAY, 14 * DAY, 30 * DAY }
boardview.WINDOW = DAY
-- The charts' range: 90 days by default, open to all history (`days` nil).
local RANGES: { Range } = {
	{ key = "30d", label = "30 days", days = 30 },
	{ key = "90d", label = "90 days", days = 90 },
	{ key = "1y", label = "1 year", days = 365 },
	{ key = "all", label = "All", days = nil },
}
boardview.RANGES = RANGES
boardview.RANGE = "90d"
-- The spend phases the tokens chart reads, and its cap on named model series (the rest are "other models").
boardview.REVIEW_PHASES = { ["design-review"] = true, ["code-review"] = true }
boardview.MAX_MODELS = 8
boardview.UNRECORDED = "unrecorded"

-- The column of an issue whose effective status (status.effective) is `stage`; `launched` is whether its raft has a
-- branch (local or origin). Every effective status maps to exactly one column; anything else is refused.
function boardview.column(stage: string, launched: boolean): Column
	if stage == "done" then
		return "done"
	elseif stage == "active" then
		return if launched then "run" else "ready"
	elseif stage == "prepared" then
		return "raft"
	elseif stage == "preparing" then
		return "design"
	elseif stage == "new" then
		return "ticket"
	end
	error(`boardview.column: {stage} is not an effective status (new, preparing, prepared, active, done)`, 0)
end

-- Cards of one column grouped into bands: one per raft, in raft id order, then the raftless cards; ids sorted.
function boardview.bands(cards: { { id: string, raft: string? } }): { Band }
	local byRaft: { [string]: { string } } = {}
	local loose: { string } = {}
	local rafts: { string } = {}
	for _, c in cards do
		local r = c.raft
		if r then
			if not byRaft[r] then
				byRaft[r] = {}
				table.insert(rafts, r)
			end
			table.insert(byRaft[r], c.id)
		else
			table.insert(loose, c.id)
		end
	end
	table.sort(rafts)
	local out: { Band } = {}
	for _, r in rafts do
		table.sort(byRaft[r])
		table.insert(out, { raft = r, ids = byRaft[r] })
	end
	if #loose > 0 then
		table.sort(loose)
		table.insert(out, { raft = nil, ids = loose })
	end
	return out
end

-- How long before `asOf` a card arrived in done/, in seconds (never negative); nil when either instant is unknown.
-- The page shows a done card while its age is at most the chosen window.
function boardview.age(doneAt: number?, asOf: number?): number?
	if doneAt == nil or asOf == nil then
		return nil
	end
	return math.max(0, asOf - doneAt)
end

-- The Monday (UTC) that starts the ISO week holding the instant `at` (epoch seconds), as YYYY-MM-DD.
function boardview.weekOf(at: number): string
	return stats.floor(os.date("!%Y-%m-%d", math.floor(at)) :: string, "week")
end

local function addDays(day: string, n: number): string
	local y, m, d = string.match(day, "^(%d+)%-(%d+)%-(%d+)$")
	local t = os.time({
		year = tonumber(y) :: number,
		month = tonumber(m) :: number,
		day = (tonumber(d) :: number) + n,
		hour = 12,
	})
	return os.date("%Y-%m-%d", t) :: string
end

-- Every week from the week of `from` to the week of `to`, inclusive.
local function weeks(from: number, to: number): { string }
	local out: { string } = {}
	local last = boardview.weekOf(to)
	local w = boardview.weekOf(from)
	while w <= last do
		table.insert(out, w)
		w = addDays(w, 7)
	end
	return out
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local function label(week: string): string
	local _, m, d = string.match(week, "^(%d+)%-(%d+)%-(%d+)$")
	return `{MONTHS[tonumber(m) :: number]} {tonumber(d)}`
end

-- A landed raft's review rounds from the files of its folders (its own, its members', and those of rafts retired into
-- it): `design-review-NNN.md` and `review-NNN.md`, each path counted once.
function boardview.rounds(paths: { string }): (number, number)
	local seen: { [string]: boolean } = {}
	local design, code = 0, 0
	for _, p in paths do
		if seen[p] then
			continue
		end
		seen[p] = true
		local name = string.match(p, "([^/]+)$") or p
		if string.match(name, "^design%-review%-%d+%.md$") then
			design += 1
		elseif string.match(name, "^review%-%d+%.md$") then
			code += 1
		end
	end
	return design, code
end

-- The range's first instant: `asOf` minus its days, or the earliest of `ats` for all history (nil when empty).
local function start(ats: { number }, asOf: number, days: number?): number?
	if days then
		return asOf - days * DAY
	end
	local lo: number? = nil
	for _, at in ats do
		if lo == nil or at < lo then
			lo = at
		end
	end
	return lo
end

local function within(at: number, from: number, to: number): boolean
	return at >= from and at <= to
end

-- Review rounds by week: each landed raft's design and code rounds in the UTC week it landed, for the rafts that
-- landed between the range's start and `asOf`; every week in the range has a value (0 when nothing landed).
function boardview.roundsByWeek(landed: { Landed }, asOf: number, days: number?): Weekly
	local ats: { number } = {}
	for _, l in landed do
		if l.at <= asOf then
			table.insert(ats, l.at)
		end
	end
	local from = start(ats, asOf, days)
	if from == nil then
		return { labels = {}, weeks = {}, series = {} }
	end
	local ws = weeks(from, asOf)
	local index: { [string]: number } = {}
	local design, code, labels = {}, {}, {}
	for i, w in ws do
		index[w] = i
		design[i] = 0
		code[i] = 0
		labels[i] = label(w)
	end
	for _, l in landed do
		if within(l.at, from, asOf) then
			local i = index[boardview.weekOf(l.at)]
			design[i] += l.design
			code[i] += l.code
		end
	end
	return {
		labels = labels,
		weeks = ws,
		series = {
			{ key = "design", label = "Design reviews", values = design },
			{ key = "code", label = "Code reviews", values = code },
		},
	}
end

-- Tokens by model by week, for spend rows of the design-review and code-review phases with tokens, dated in the range.
-- One series per model id, largest total first (ties by id), at most MAX_MODELS of them, the rest summed as "other
-- models"; a row with no model is the "unrecorded" series, always last.
function boardview.tokensByWeek(rows: { TokenRow }, asOf: number, days: number?): Weekly
	local kept: { TokenRow } = {}
	local ats: { number } = {}
	for _, r in rows do
		if boardview.REVIEW_PHASES[r.phase] and r.tokens > 0 and r.at <= asOf then
			table.insert(kept, r)
			table.insert(ats, r.at)
		end
	end
	local from = start(ats, asOf, days)
	if from == nil then
		return { labels = {}, weeks = {}, series = {} }
	end
	local ws = weeks(from, asOf)
	local index: { [string]: number } = {}
	local labels = {}
	for i, w in ws do
		index[w] = i
		labels[i] = label(w)
	end
	local totals: { [string]: number } = {}
	local perWeek: { [string]: { number } } = {}
	for _, r in kept do
		if within(r.at, from, asOf) then
			local m = r.model or boardview.UNRECORDED
			if not perWeek[m] then
				perWeek[m] = table.create(#ws, 0)
				totals[m] = 0
			end
			local i = index[boardview.weekOf(r.at)]
			perWeek[m][i] += r.tokens
			totals[m] += r.tokens
		end
	end
	local named: { string } = {}
	for m in perWeek do
		if m ~= boardview.UNRECORDED then
			table.insert(named, m)
		end
	end
	table.sort(named, function(a, b)
		if totals[a] ~= totals[b] then
			return totals[a] > totals[b]
		end
		return a < b
	end)
	local series: { Series } = {}
	local other: { number }? = nil
	for i, m in named do
		if i <= boardview.MAX_MODELS then
			table.insert(series, { key = `m{i}`, label = m, values = perWeek[m] })
		else
			local sum = other or table.create(#ws, 0)
			for w, v in perWeek[m] do
				sum[w] += v
			end
			other = sum
		end
	end
	if other then
		table.insert(series, { key = "other", label = "other models", values = other })
	end
	if perWeek[boardview.UNRECORDED] then
		table.insert(
			series,
			{ key = "unrecorded", label = "unrecorded model", values = perWeek[boardview.UNRECORDED] }
		)
	end
	return { labels = labels, weeks = ws, series = series }
end

-- The weekly series scaled so the axis stays short: by 1,000 ("k tokens") when the largest week tops 10,000, by
-- 1,000,000 ("M tokens") when it tops 10,000,000; returns the scaled copy and its unit.
function boardview.scaled(w: Weekly, unit: string): (Weekly, string)
	local top = 0
	for i = 1, #w.labels do
		local sum = 0
		for _, s in w.series do
			sum += s.values[i] or 0
		end
		top = math.max(top, sum)
	end
	local div, prefix = 1, ""
	if top > 10000000 then
		div, prefix = 1000000, "M "
	elseif top > 10000 then
		div, prefix = 1000, "k "
	end
	if div == 1 then
		return w, unit
	end
	local series: { Series } = {}
	for _, s in w.series do
		local values: { number? } = {}
		for i = 1, #w.labels do
			values[i] = math.floor((s.values[i] or 0) / div * 10 + 0.5) / 10
		end
		table.insert(series, { key = s.key, label = s.label, values = values })
	end
	return { labels = w.labels, weeks = w.weeks, series = series }, prefix .. unit
end

-- A spend row's `when` (UTC "YYYY-MM-DD HH:MM", or a bare day) as epoch seconds; nil when it is neither.
function boardview.rowInstant(when: string): number?
	local y, m, d, rest = string.match(when, "^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
	if not y then
		return nil
	end
	local hh, mi = string.match(rest :: string, "^[ T](%d%d):(%d%d)")
	local stamp = `{y}-{m}-{d}T{hh or "00"}:{mi or "00"}:00Z`
	return stats.seconds(stamp)
end

return boardview
