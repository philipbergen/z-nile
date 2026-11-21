--!strict
-- How the live layer's workers and claims are shown (f0424 step 4): the one place that turns livecall's snapshot into the
-- slim record the board page embeds and into the lines `./zn work status` prints. Pure: it reads nothing and starts nothing.
local liveview = {}

-- What the page embeds: only what it shows (a worker's id, cli, state, capabilities, last-heard time; a claim's unit,
-- activity, worker and since), and the time the snapshot was taken.
export type Worker = {
	id: string,
	cli: string,
	state: string,
	can: { string },
	heard: number?,
	started: number?,
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
				state = text(w.state),
				can = can,
				heard = num(w.heard),
				started = num(w.started),
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

-- Pacific time: "HH:MM PST" or "HH:MM PDT" (US rule: second Sunday of March 2:00 to first Sunday of November 2:00).
function liveview.pacific(epoch: number): string
	local year = (os.date("!*t", math.floor(epoch)) :: any).year :: number
	local dstStart = nthSunday(year, 3, 2) * 86400 + 10 * 3600 -- 2:00 PST is 10:00 UTC
	local dstEnd = nthSunday(year, 11, 1) * 86400 + 9 * 3600 -- 2:00 PDT is 09:00 UTC
	local summer = epoch >= dstStart and epoch < dstEnd
	local local_ = os.date("!*t", math.floor(epoch + (if summer then -7 else -8) * 3600)) :: any
	return string.format("%02d:%02d %s", local_.hour, local_.min, if summer then "PDT" else "PST")
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
	return `can {table.concat(shown, ",")}{more} ({#can} pairs)`
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

-- One line per worker for `./zn work status`: id, cli, state, what it holds (or idle) and since when, when it was last
-- heard from, and what it can deliver.
function liveview.workerLines(live: Live): { string }
	local out: { string } = {}
	for _, w in live.workers do
		local claim = liveview.claimOf(live, w.id)
		local holds = if claim
			then `holds {claim.unit} {claim.activity}{if claim.since
				then ` since {liveview.pacific(claim.since)}`
				else ""}`
			else "idle"
		local heard = if w.heard then `heard {liveview.pacific(w.heard)}` else "heard never"
		table.insert(out, `{w.id} {w.cli} {w.state} {holds} {heard} {liveview.canSummary(w.can)}`)
	end
	return out
end

return liveview
