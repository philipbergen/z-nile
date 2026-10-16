--!strict
-- Pure statistics for the tracker board. Dates are civil days and UTC seconds, never os.date or os.time.
local stats = {}

export type Kind = "feature" | "defect" | "chore"
export type Spell = { state: string, from: string, to: string? }
export type Item = { id: string, type: Kind, opened: string, closed: string?, spells: { Spell } }
export type Spend = { id: string, type: Kind, day: string, added: number, removed: number, minutes: number }
export type Bucket = { start: string, stop: string, label: string }
export type Counts = { all: number, feature: number, defect: number, chore: number }
export type Ratios = { defectCount: number?, defectTime: number?, choreCount: number?, choreTime: number? }
export type Row = {
	bucket: Bucket,
	opened: Counts,
	closed: Counts,
	net: Counts,
	minutes: Counts,
	added: Counts,
	removed: Counts,
	netLines: Counts,
	ratios: Ratios,
}
export type Spread = { n: number, mean: number?, median: number? }
export type ByType = { all: Spread, feature: Spread, defect: Spread, chore: Spread }
export type Stats = {
	today: string,
	history: boolean,
	views: { month: { Row }, quarter: { Row }, year: { Row } },
	periods: { week: Row, month: Row, quarter: Row, year: Row }?,
	durations: { [string]: ByType },
}

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local STATES = { "new", "preparing", "prepared", "active" }

local function div(a: number, b: number): number
	return math.floor(a / b)
end

local function daysFromCivil(y: number, m: number, d: number): number
	local yy = if m <= 2 then y - 1 else y
	local era = div(yy, 400)
	local yoe = yy - era * 400
	local moy = if m > 2 then m - 3 else m + 9
	local doy = div(153 * moy + 2, 5) + d - 1
	local doe = yoe * 365 + div(yoe, 4) - div(yoe, 100) + doy
	return era * 146097 + doe - 719468
end

local function civilFromDays(z: number): (number, number, number)
	z += 719468
	local era = div(z, 146097)
	local doe = z - era * 146097
	local yoe = div(doe - div(doe, 1460) + div(doe, 36524) - div(doe, 146096), 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + div(yoe, 4) - div(yoe, 100))
	local mp = div(5 * doy + 2, 153)
	local d = doy - div(153 * mp + 2, 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	if m <= 2 then
		y += 1
	end
	return y, m, d
end

local function parseDay(day: string): (number?, number?, number?)
	local y, m, d = string.match(day, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y then
		return nil, nil, nil
	end
	return tonumber(y), tonumber(m), tonumber(d)
end

local function fmtDay(y: number, m: number, d: number): string
	return string.format("%04d-%02d-%02d", y, m, d)
end

local function toDays(day: string): number?
	local y, m, d = parseDay(day)
	if not y or not m or not d then
		return nil
	end
	return daysFromCivil(y, m, d)
end

local function fromDays(days: number): string
	local y, m, d = civilFromDays(days)
	return fmtDay(y, m, d)
end

local function leap(y: number): boolean
	return y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
end

local function monthLength(y: number, m: number): number
	local lens = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	if m == 2 and leap(y) then
		return 29
	end
	return lens[m]
end

-- n months from a civil date, clamping the day to the target month's length.
local function addMonths(y: number, m: number, d: number, n: number): (number, number, number)
	local idx = m - 1 + n
	local y2 = y + div(idx, 12)
	local m0 = idx % 12
	if m0 < 0 then
		m0 += 12
		y2 -= 1
	end
	local m2 = m0 + 1
	return y2, m2, math.min(d, monthLength(y2, m2))
end

local function dayLabel(day: string): string
	local _, m, d = parseDay(day)
	return `{MONTHS[m :: number]} {d}`
end

local function monthLabel(day: string): string
	local y, m = parseDay(day)
	return string.format("%s %02d", MONTHS[m :: number], (y :: number) % 100)
end

local function isoWeek(day: string): number
	local days = toDays(day) :: number
	local monday = days - (days + 3) % 7
	local thursday = monday + 3
	local y = civilFromDays(thursday)
	local jan4 = daysFromCivil(y, 1, 4)
	local week1 = jan4 - (jan4 + 3) % 7
	return div(monday - week1, 7) + 1
end

function stats.floor(day: string, unit: "week" | "month" | "quarter" | "year"): string
	local y, m, d = parseDay(day)
	assert(y and m and d, `not a day: {day}`)
	if unit == "week" then
		local days = daysFromCivil(y, m, d)
		return fromDays(days - (days + 3) % 7)
	elseif unit == "month" then
		return fmtDay(y, m, 1)
	elseif unit == "quarter" then
		local qm = m - (m - 1) % 3
		return fmtDay(y, qm, 1)
	end
	return fmtDay(y, 1, 1)
end

function stats.buckets(view: "month" | "quarter" | "year", today: string): { Bucket }
	local y, m, d = parseDay(today)
	assert(y and m and d, `not a day: {today}`)
	local out: { Bucket } = {}
	if view == "month" then
		local y0, m0, d0 = addMonths(y, m, d, -1)
		local start = daysFromCivil(y0, m0, d0)
		local stop = daysFromCivil(y, m, d)
		for n = start, stop do
			local day = fromDays(n)
			table.insert(out, { start = day, stop = fromDays(n + 1), label = dayLabel(day) })
		end
	elseif view == "quarter" then
		local y0, m0, d0 = addMonths(y, m, d, -3)
		local start = stats.floor(fmtDay(y0, m0, d0), "week")
		local last = stats.floor(today, "week")
		local n = toDays(start) :: number
		local endN = toDays(last) :: number
		while n <= endN do
			local day = fromDays(n)
			table.insert(out, { start = day, stop = fromDays(n + 7), label = `W{isoWeek(day)}` })
			n += 7
		end
	else
		local y0, m0 = addMonths(y, m, d, -12)
		local yy, mm = y0, m0
		local lastY, lastM = y, m
		while yy < lastY or (yy == lastY and mm <= lastM) do
			local start = fmtDay(yy, mm, 1)
			local ny, nm = addMonths(yy, mm, 1, 1)
			table.insert(out, { start = start, stop = fmtDay(ny, nm, 1), label = monthLabel(start) })
			yy, mm = ny, nm
		end
	end
	return out
end

function stats.periods(today: string): { week: Bucket, month: Bucket, quarter: Bucket, year: Bucket }
	local nextDay = fromDays((toDays(today) :: number) + 1)
	local function span(unit: "week" | "month" | "quarter" | "year", label: string): Bucket
		return { start = stats.floor(today, unit), stop = nextDay, label = label }
	end
	return {
		week = span("week", "This week"),
		month = span("month", "This month"),
		quarter = span("quarter", "This quarter"),
		year = span("year", "This year"),
	}
end

local function zero(): Counts
	return { all = 0, feature = 0, defect = 0, chore = 0 }
end

local function add(counts: Counts, kind: Kind, n: number)
	counts.all += n
	if kind == "feature" then
		counts.feature += n
	elseif kind == "defect" then
		counts.defect += n
	else
		counts.chore += n
	end
end

local function sub(a: Counts, b: Counts): Counts
	return {
		all = a.all - b.all,
		feature = a.feature - b.feature,
		defect = a.defect - b.defect,
		chore = a.chore - b.chore,
	}
end

local function inside(day: string?, bucket: Bucket): boolean
	return day ~= nil and day ~= "" and day >= bucket.start and day < bucket.stop
end

local function roundTo(n: number, places: number): number
	local scale = 10 ^ places
	local sign = if n < 0 then -1 else 1
	return sign * math.floor(math.abs(n) * scale + 0.5) / scale
end

local function percent(part: number, whole: number): number?
	if whole == 0 then
		return nil
	end
	return roundTo(100 * part / whole, 1)
end

function stats.row(items: { Item }, spends: { Spend }, bucket: Bucket): Row
	local opened, closed, minutes, added, removed = zero(), zero(), zero(), zero(), zero()
	for _, item in items do
		if inside(item.opened, bucket) then
			add(opened, item.type, 1)
		end
		if inside(item.closed, bucket) then
			add(closed, item.type, 1)
		end
	end
	for _, spend in spends do
		if inside(spend.day, bucket) then
			add(minutes, spend.type, spend.minutes)
			add(added, spend.type, spend.added)
			add(removed, spend.type, spend.removed)
		end
	end
	return {
		bucket = bucket,
		opened = opened,
		closed = closed,
		net = sub(opened, closed),
		minutes = minutes,
		added = added,
		removed = removed,
		netLines = sub(added, removed),
		ratios = {
			defectCount = percent(closed.defect, closed.defect + closed.feature),
			defectTime = percent(minutes.defect, minutes.defect + minutes.feature),
			choreCount = percent(closed.chore, closed.all),
			choreTime = percent(minutes.chore, minutes.all),
		},
	}
end

-- Absolute seconds of an ISO timestamp, using the offset written on it.
function stats.seconds(ts: string): number
	local y, mo, d, hh, mi, ss, rest =
		string.match(ts, "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$")
	assert(y, `not a timestamp: {ts}`)
	local frac, sign, oh, om = string.match(rest :: string, "^(%.%d*)([%+%-])(%d%d):(%d%d)$")
	local offset = 0
	if sign then
		offset = ((tonumber(oh) :: number) * 60 + (tonumber(om) :: number)) * 60
		if sign == "-" then
			offset = -offset
		end
	elseif rest ~= "Z" and rest ~= "z" and rest ~= "" then
		local sign2, oh2, om2 = string.match(rest :: string, "^([%+%-])(%d%d):(%d%d)$")
		if sign2 then
			offset = ((tonumber(oh2) :: number) * 60 + (tonumber(om2) :: number)) * 60
			if sign2 == "-" then
				offset = -offset
			end
		end
	end
	local fraction = if frac then tonumber(frac) or 0 else 0
	local days = daysFromCivil(tonumber(y) :: number, tonumber(mo) :: number, tonumber(d) :: number)
	return days * 86400
		+ (tonumber(hh) :: number) * 3600
		+ (tonumber(mi) :: number) * 60
		+ (tonumber(ss) :: number)
		+ fraction
		- offset
end

local function spread(values: { number }): Spread
	local n = #values
	if n == 0 then
		return { n = 0 }
	end
	table.sort(values)
	local sum = 0
	for _, v in values do
		sum += v
	end
	local median = if n % 2 == 1 then values[(n + 1) / 2] else (values[n / 2] + values[n / 2 + 1]) / 2
	return { n = n, mean = roundTo(sum / n, 2), median = roundTo(median, 2) }
end

function stats.durations(items: { Item }): { [string]: ByType }
	local buckets: { [string]: { [string]: { number } } } = {}
	for _, state in STATES do
		buckets[state] = { all = {}, feature = {}, defect = {}, chore = {} }
	end
	for _, item in items do
		for _, spell in item.spells do
			local bag = buckets[spell.state]
			if bag and spell.to then
				local days = roundTo((stats.seconds(spell.to) - stats.seconds(spell.from)) / 86400, 2)
				table.insert(bag.all, days)
				table.insert(bag[item.type], days)
			end
		end
	end
	local out: { [string]: ByType } = {}
	for _, state in STATES do
		local bag = buckets[state]
		out[state] = {
			all = spread(bag.all),
			feature = spread(bag.feature),
			defect = spread(bag.defect),
			chore = spread(bag.chore),
		}
	end
	return out
end

function stats.compute(items: { Item }, spends: { Spend }, today: string, history: boolean): Stats
	if today == "" then
		return {
			today = "",
			history = history,
			views = { month = {}, quarter = {}, year = {} },
			periods = nil,
			durations = {},
		}
	end
	local function rows(view: "month" | "quarter" | "year"): { Row }
		local out: { Row } = {}
		for _, bucket in stats.buckets(view, today) do
			table.insert(out, stats.row(items, spends, bucket))
		end
		return out
	end
	local periods = stats.periods(today)
	return {
		today = today,
		history = history,
		views = { month = rows("month"), quarter = rows("quarter"), year = rows("year") },
		periods = {
			week = stats.row(items, spends, periods.week),
			month = stats.row(items, spends, periods.month),
			quarter = stats.row(items, spends, periods.quarter),
			year = stats.row(items, spends, periods.year),
		},
		durations = stats.durations(items),
	}
end

return stats
