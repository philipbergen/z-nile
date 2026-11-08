--!strict
-- E5 prototype of engine/heartbeat.luau (prep only; copy it to z-nile/engine/ to replay the mutants). Not committed
-- to engine/ by prep: the executor writes the real one (this one type-checks under promote-check).
local heartbeat = {}
export type Beat = { stamp: string, epoch: number, ref: string, sha: string }
export type Entry = { ref: string, sha: string, subject: string } -- one per branch under the prefix, as the single read returns it
export type Claim = { id: string, state: string, stamp: string, since: number?, match: { string } }
export type Verdict = { id: string, state: string, stamp: string, silent: number, kind: string }
export type Pr = { title: string, head: string }
heartbeat.PREFIX = "refs/heads/hb/"
heartbeat.INTERVAL = 300
heartbeat.STALE = 900
heartbeat.SKEW = 300

-- The heartbeat branch of a claim: one per claim stamp, shared by a raft and its members.
function heartbeat.branch(stamp: string): string
	return `{heartbeat.PREFIX}{stamp}`
end

-- The subject of the one beat commit (its parent is origin/main's tip and its tree is main's tree, so ./zn busy never
-- sees a change): the epoch is read from here, not from a clock the reader trusts.
function heartbeat.subject(stamp: string, epoch: number): string
	return `hb {stamp} {epoch}`
end

-- Entries (one per branch under the prefix) to beats, and a problem naming each branch that is not a beat.
function heartbeat.parse(entries: { Entry }): ({ Beat }, { string })
	local beats: { Beat }, problems: { string } = {}, {}
	for _, e in entries do
		if string.sub(e.ref, 1, #heartbeat.PREFIX) == heartbeat.PREFIX then
			local stamp = string.sub(e.ref, #heartbeat.PREFIX + 1)
			local kind = string.match(stamp, "^(%a+)%-%a+%-%a+%-%a+$")
			local sStamp, epoch = string.match(e.subject, "^hb (%S+) (%d+)$")
			if kind and (kind == "preparing" or kind == "active") and sStamp == stamp and epoch then
				table.insert(
					beats,
					{ stamp = stamp, epoch = tonumber(epoch) :: number, ref = e.ref, sha = e.sha }
				)
			else
				table.insert(
					problems,
					`{e.ref}: not a beat (a branch hb/<preparing|active>-<three words> whose commit subject is "hb <stamp> <epoch>"); clear it with git push origin :{e.ref}`
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

-- live | stale | unknown, from the newest sign of life: the newest usable beat, else the moment the claim landed.
function heartbeat.judge(claims: { Claim }, beats: { Beat }, now: number, stale: number?): { Verdict }
	local limit = stale or heartbeat.STALE
	local out: { Verdict } = {}
	for _, c in claims do
		local last: number? = c.since
		for _, b in beats do
			if b.stamp == c.stamp and b.epoch <= now + heartbeat.SKEW then
				last = math.max(last or b.epoch, b.epoch)
			end
		end
		if last == nil then
			-- neither a beat nor a readable landing time: unknown, never lost
			table.insert(out, { id = c.id, state = c.state, stamp = c.stamp, silent = 0, kind = "unknown" })
		else
			local silent = math.max(0, now - last)
			table.insert(out, {
				id = c.id,
				state = c.state,
				stamp = c.stamp,
				silent = silent,
				kind = if silent > limit then "stale" else "live",
			})
		end
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

export type Push = {
	write: { ref: string, subject: string, lease: string }?,
	delete: { { ref: string, lease: string } },
}

-- One beat: replace the claim's branch (the lease is the sha seen, or "" to create only if absent); never go backwards
-- or repeat a second; delete the branches of stamps no claim holds once they are older than the limit (a young one may
-- be a claim this checkout has not fetched yet).
function heartbeat.plan(
	stamp: string,
	epoch: number,
	beats: { Beat },
	claimed: { [string]: boolean },
	now: number
): Push
	local existing: Beat? = nil
	local delete: { { ref: string, lease: string } } = {}
	for _, b in beats do
		if b.stamp == stamp then
			existing = b
		elseif not claimed[b.stamp] and b.epoch < now - heartbeat.STALE then
			table.insert(delete, { ref = b.ref, lease = b.sha })
		end
	end
	if existing ~= nil and existing.epoch >= epoch then
		return { write = nil, delete = delete }
	end
	return {
		write = {
			ref = heartbeat.branch(stamp),
			subject = heartbeat.subject(stamp, epoch),
			lease = if existing then existing.sha else "",
		},
		delete = delete,
	}
end

-- A takeover, in one atomic push: create the taker's branch (create-only) and delete the old owner's with a lease on
-- the sha seen, so the old owner's next beat finds its branch gone and its lease rejected.
function heartbeat.takeoverPlan(oldStamp: string, newStamp: string, epoch: number, beats: { Beat }): Push
	local delete: { { ref: string, lease: string } } = {}
	for _, b in beats do
		if b.stamp == oldStamp then
			table.insert(delete, { ref = b.ref, lease = b.sha })
		end
	end
	return {
		write = { ref = heartbeat.branch(newStamp), subject = heartbeat.subject(newStamp, epoch), lease = "" },
		delete = delete,
	}
end

-- What a beat does when its push was rejected (the lease was stale): re-read, then retry on the branch that is there,
-- create it if this claim still stands but its branch is gone, or learn that the claim was lost.
function heartbeat.rejected(
	stamp: string,
	originStamp: string?,
	beats: { Beat }
): { action: string, lease: string?, why: string? }
	if originStamp == nil then
		return { action = "lost", why = "ended" }
	elseif originStamp ~= stamp then
		return { action = "lost", why = `taken over (now {originStamp})` }
	end
	for _, b in beats do
		if b.stamp == stamp then
			return { action = "retry", lease = b.sha }
		end
	end
	return { action = "create", lease = "" }
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
