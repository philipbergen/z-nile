--!strict
-- How the live layer's workers and claims are shown (f0424 step 4): the one place that turns livecall's snapshot into the
-- slim record the board page embeds and into the lines `./zn work status` prints. Pure: it reads nothing and starts nothing.
local liveview = {}

-- What the page embeds: only what it shows (a worker's id, cli, state, capabilities, last-heard time; a claim's unit,
-- activity, worker and since), and the time the snapshot was taken.
export type Worker = {
	id: string,
	cli: string,
	account: string?,
	state: string,
	can: { string },
	heard: number?,
	started: number?,
	quiet: number?, -- when the daemon found it quiet (its process lives, nothing was heard): the daemon calls that state `lost`
}
export type Claim = { unit: string, activity: string, worker: string, raft: string?, since: number? }
export type Live = { at: number, workers: { Worker }, claims: { Claim } }

local function text(v: any): string
	return if type(v) == "string" then v else ""
end

local function num(v: any): number?
	return if type(v) == "number" then v else nil
end

-- The slim record of livecall.snapshot()'s answer, or nil when the layer did not answer.
function liveview.slim(snap: { ok: boolean, at: number?, workers: { any }?, claims: { any }? }): Live?
	if not snap.ok or snap.workers == nil or snap.claims == nil or snap.at == nil then
		return nil
	end
	local workers: { Worker } = {}
	for _, w in snap.workers :: { any } do
		if type(w) == "table" and text(w.id) ~= "" then
			local can: { string } = {}
			if type(w.can) == "table" then
				for _, c in w.can do
					if type(c) == "string" then
						table.insert(can, c)
					end
				end
			end
			table.insert(workers, {
				id = text(w.id),
				cli = text(w.cli),
				account = if text(w.account) ~= "" then text(w.account) else nil,
				state = text(w.state),
				can = can,
				heard = num(w.heard),
				started = num(w.started),
				quiet = num(w.lost_since),
			})
		end
	end
	table.sort(workers, function(a, b)
		return a.id < b.id
	end)
	local claims: { Claim } = {}
	for _, c in snap.claims :: { any } do
		if type(c) == "table" and text(c.unit) ~= "" then
			table.insert(claims, {
				unit = text(c.unit),
				activity = text(c.activity),
				worker = text(c.worker),
				raft = if text(c.raft) ~= "" then text(c.raft) else nil,
				since = num(c.since),
			})
		end
	end
	table.sort(claims, function(a, b)
		return a.unit < b.unit
	end)
	return { at = snap.at :: number, workers = workers, claims = claims }
end

local function daysFromCivil(y: number, m: number, d: number): number
	y -= if m <= 2 then 1 else 0
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (m + (if m > 2 then -3 else 9)) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- The Nth Sunday (1-based) of month m of year y, as a day number.
local function nthSunday(y: number, m: number, n: number): number
	local first = daysFromCivil(y, m, 1)
	local wday = (first + 4) % 7 -- 1970-01-01 was a Thursday: 0 = Sunday
	local firstSunday = first + (7 - wday) % 7
	return firstSunday + 7 * (n - 1)
end

-- The Pacific offset in force at `epoch` (seconds): -7 hours in daylight time, else -8. US rule: second Sunday of March 2:00
-- to first Sunday of November 2:00.
local function offsetAt(epoch: number): (number, boolean)
	local year = (os.date("!*t", math.floor(epoch)) :: any).year :: number
	local dstStart = nthSunday(year, 3, 2) * 86400 + 10 * 3600 -- 2:00 PST is 10:00 UTC
	local dstEnd = nthSunday(year, 11, 1) * 86400 + 9 * 3600 -- 2:00 PDT is 09:00 UTC
	local summer = epoch >= dstStart and epoch < dstEnd
	return (if summer then -7 else -8) * 3600, summer
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- Pacific time: "HH:MM PST" or "HH:MM PDT"; with the date ("Nov 20 HH:MM PST") when `epoch` is not on the same Pacific
-- day as `now` (default: the present), so a since-time from yesterday is never read as today's.
function liveview.pacific(epoch: number, now: number?): string
	local offset, summer = offsetAt(epoch)
	local at = os.date("!*t", math.floor(epoch + offset)) :: any
	local nowOffset = offsetAt(now or os.time())
	local today = os.date("!*t", math.floor((now or os.time()) + nowOffset)) :: any
	local time = string.format("%02d:%02d %s", at.hour, at.min, if summer then "PDT" else "PST")
	if at.year == today.year and at.month == today.month and at.day == today.day then
		return time
	end
	return `{MONTHS[at.month]} {at.day} {time}`
end

-- What a worker can deliver, in a few words: its distinct activities (the part before the `/level`), at most four, then
-- how many activity/level pairs there are in all.
function liveview.canSummary(can: { string }): string
	if #can == 0 then
		return "can: nothing recorded"
	end
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	for _, c in can do
		local a = string.match(c, "^([^/]+)") or c
		if not seen[a] then
			seen[a] = true
			table.insert(names, a)
		end
	end
	table.sort(names)
	local shown: { string } = {}
	for i = 1, math.min(4, #names) do
		table.insert(shown, names[i])
	end
	local more = if #names > 4 then `, +{#names - 4} more` else ""
	return `can {table.concat(shown, ",")}{more} ({#can} {if #can == 1 then "pair" else "pairs"})`
end

-- The claim a worker holds, or nil.
function liveview.claimOf(live: Live, worker: string): Claim?
	for _, c in live.claims do
		if c.worker == worker then
			return c
		end
	end
	return nil
end

-- f0437: who holds each unit now, by unit id: a claim names its unit and, when it has one, its raft, and both are held by
-- the worker ("<cli> <worker id>", never an account). Each unit's labels are unique and sorted. nil live: nobody known.
function liveview.holders(live: Live?): { [string]: { string } }
	local out: { [string]: { string } } = {}
	if not live then
		return out
	end
	local cliOf: { [string]: string } = {}
	for _, w in live.workers do
		cliOf[w.id] = w.cli
	end
	for _, c in live.claims do
		local label = `{cliOf[c.worker] or "worker"} {c.worker}`
		for _, id in { c.unit, c.raft or "" } do
			if id ~= "" then
				local list = out[id] or {}
				out[id] = list
				if not table.find(list, label) then
					table.insert(list, label)
					table.sort(list)
				end
			end
		end
	end
	return out
end

-- When a quiet worker went quiet: the daemon's own time, else when it was last heard.
local function quietAt(w: Worker): number?
	return w.quiet or w.heard
end

-- One line per worker for `./zn work status`: id, cli, one state word (what it holds says "working"; an idle worker says
-- so), what it holds and since when, when it was last heard from, and what it can deliver. The daemon calls a worker whose
-- process lives but who has said nothing for a while `lost`; nobody is lost while its process lives, so such a worker is
-- "working, quiet since <time>" when it holds a claim (a long build) and "quiet since <time>" when it holds none.
function liveview.workerLines(live: Live): { string }
	local out: { string } = {}
	for _, w in live.workers do
		local claim = liveview.claimOf(live, w.id)
		local since = ""
		if claim and claim.since then
			since = ` since {liveview.pacific(claim.since, live.at)}`
		end
		local state = w.state
		local what = if claim then ` {claim.unit} {claim.activity}{since}` else ""
		if w.state == "lost" then
			local at = quietAt(w)
			local when = if at then ` since {liveview.pacific(at, live.at)}` else ""
			state = if claim then `working, quiet{when}` else `quiet{when}`
			what = if claim then ` on {claim.unit} {claim.activity}{since}` else ""
		elseif claim then
			state = "holds"
		end
		local label = if w.account then ` (account {w.account})` else ""
		local heard = if w.heard then `heard {liveview.pacific(w.heard, live.at)}` else "heard never"
		table.insert(out, `{w.id} {w.cli}{label} {state}{what} {heard} {liveview.canSummary(w.can)}`)
	end
	return out
end

-- The units workers hold, one line each: `<unit> is held by <worker>`; a quiet holder's line says since when and names the
-- manual release. `me`: a worker whose own claims are left out. `onlyQuiet`: just the quiet holders' units.
function liveview.heldLines(live: Live, me: string?, onlyQuiet: boolean): { string }
	local out: { string } = {}
	for _, c in live.claims do
		if c.worker ~= me then
			local holder: Worker? = nil
			for _, w in live.workers do
				if w.id == c.worker then
					holder = w
				end
			end
			local quiet = holder ~= nil and holder.state == "lost"
			if quiet or not onlyQuiet then
				local line = `{c.unit} is held by {c.worker}`
				if quiet and holder then
					local at = quietAt(holder)
					line ..= `, quiet{if at then " since " .. liveview.pacific(at, live.at) else ""}: if that worker is gone, free it with ./zn live release --worker {c.worker}`
				end
				table.insert(out, line)
			end
		end
	end
	return out
end

return liveview
