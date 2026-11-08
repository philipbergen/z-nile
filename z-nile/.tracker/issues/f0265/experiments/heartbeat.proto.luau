--!strict
-- E5 prototype of engine/heartbeat.luau (prep only; copy it to z-nile/engine/ to replay the mutants). Not committed
-- to engine/ by prep: the executor writes the real one (this one type-checks under promote-check).
local heartbeat = {}
export type Beat = { stamp: string, epoch: number, ref: string }
export type Claim = { id: string, state: string, stamp: string, since: number, match: { string } }
export type Verdict = { id: string, state: string, stamp: string, silent: number, kind: string }
export type Pr = { title: string, head: string }
heartbeat.PREFIX = "refs/zn/hb/"
heartbeat.INTERVAL = 300
heartbeat.STALE = 900
heartbeat.SKEW = 300

function heartbeat.refName(stamp: string, epoch: number): string
	return `{heartbeat.PREFIX}{stamp}/{epoch}`
end

function heartbeat.parse(refs: { string }): ({ Beat }, { string })
	local beats: { Beat }, problems: { string } = {}, {}
	for _, ref in refs do
		if string.sub(ref, 1, #heartbeat.PREFIX) == heartbeat.PREFIX then
			local stamp, kind, epoch = string.match(ref, "^refs/zn/hb/((%a+)%-%a+%-%a+%-%a+)/(%d+)$")
			if stamp and (kind == "preparing" or kind == "active") then
				table.insert(beats, { stamp = stamp, epoch = tonumber(epoch) :: number, ref = ref })
			else
				table.insert(
					problems,
					`{ref}: not a beat (refs/zn/hb/<preparing|active>-<three words>/<epoch>)`
				)
			end
		end
	end
	return beats, problems
end

-- The clock: ZN_NOW only inside a spec run (the runner's marker is "1").
function heartbeat.clock(env: { [string]: string? }, real: number): number
	local forced = env.ZN_NOW
	if env.PICKMAN_FENCE_SPECS == "1" and forced ~= nil and tonumber(forced) ~= nil then
		return tonumber(forced) :: number
	end
	return real
end

-- A tuning setting (ZN_BEAT_EVERY, ZN_NET_SECONDS): honoured only inside a spec run, and only a positive whole number.
function heartbeat.setting(env: { [string]: string? }, name: string, default: number): number
	local raw = env[name]
	local n = if raw ~= nil then tonumber(raw) else nil
	if env.PICKMAN_FENCE_SPECS == "1" and n ~= nil and n >= 1 and n == math.floor(n) then
		return n
	end
	return default
end

-- live | stale, from the newest sign of life: the newest usable beat, else the moment the claim landed.
function heartbeat.judge(claims: { Claim }, beats: { Beat }, now: number, stale: number?): { Verdict }
	local limit = stale or heartbeat.STALE
	local out: { Verdict } = {}
	for _, c in claims do
		local last = c.since
		for _, b in beats do
			if b.stamp == c.stamp and b.epoch <= now + heartbeat.SKEW then
				last = math.max(last, b.epoch)
			end
		end
		local silent = math.max(0, now - last)
		table.insert(out, {
			id = c.id,
			state = c.state,
			stamp = c.stamp,
			silent = silent,
			kind = if silent > limit then "stale" else "live",
		})
	end
	return out
end

function heartbeat.settle(vs: { Verdict }, parked: { [string]: boolean }?): { Verdict }
	local out: { Verdict } = {}
	for _, v in vs do
		local c = table.clone(v)
		if v.kind == "stale" and parked then
			c.kind = if parked[v.id] then "parked" else "lost"
		end
		table.insert(out, c)
	end
	return out
end

local function names(text: string, id: string): boolean
	local from = 1
	while true do
		local s, e = string.find(text, id, from, true)
		if not s or not e then
			return false
		end
		local before = string.sub(text, s - 1, s - 1)
		local after = string.sub(text, e + 1, e + 1)
		if not string.match(before, "%w") and not string.match(after, "%w") then
			return true
		end
		from = e + 1
	end
end

-- A lease is per stamp: a PR naming any item that holds a stamp parks every item holding it.
function heartbeat.parkedBy(
	prs: { Pr },
	claims: { Claim },
	local_: { [string]: boolean }?
): { [string]: boolean }
	local stamps: { [string]: boolean } = {}
	for _, c in claims do
		for _, id in c.match do
			for _, pr in prs do
				if names(pr.title, id) or names(pr.head, id) then
					stamps[c.stamp] = true
				end
			end
			if local_ and local_[id] then
				stamps[c.stamp] = true
			end
		end
	end
	local out: { [string]: boolean } = {}
	for _, c in claims do
		if stamps[c.stamp] then
			out[c.id] = true
		end
	end
	return out
end

function heartbeat.order(vs: { Verdict }): { Verdict }
	local out = table.clone(vs)
	local pos: { [Verdict]: number } = {}
	for i, v in vs do
		pos[v] = i
	end
	table.sort(out, function(a, b)
		local al, bl = a.kind == "lost", b.kind == "lost"
		if al ~= bl then
			return al
		end
		if al and a.silent ~= b.silent then
			return a.silent > b.silent
		end
		return pos[a] < pos[b]
	end)
	return out
end

function heartbeat.plan(
	stamp: string,
	epoch: number,
	beats: { Beat },
	claimed: { [string]: boolean },
	now: number
): { write: string?, delete: { string } }
	local write: string? = heartbeat.refName(stamp, epoch)
	local delete: { string } = {}
	for _, b in beats do
		if b.stamp == stamp and b.epoch == epoch then
			write = nil
		elseif
			(b.stamp == stamp and b.epoch < epoch)
			or (not claimed[b.stamp] and b.epoch < now - heartbeat.STALE)
		then
			table.insert(delete, b.ref)
		end
	end
	return { write = write, delete = delete }
end

-- A takeover needs an explicit lost verdict judged for the stamp origin still holds.
function heartbeat.canTakeOver(kind: string, judgedStamp: string, originStamp: string): boolean
	return kind == "lost" and judgedStamp == originStamp
end

-- One tick of `beat --watch`: stop when the claim's stamp changed, or when the next tick would pass the bound.
function heartbeat.watch(
	startStamp: string,
	originStamp: string?,
	now: number,
	deadline: number,
	every: number
): string
	if originStamp ~= startStamp then
		return "stop-restamped"
	end
	if now + every >= deadline then
		return "stop-bound"
	end
	return "beat"
end

return heartbeat
