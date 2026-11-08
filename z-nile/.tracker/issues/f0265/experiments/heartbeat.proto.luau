-- E5 prototype of engine/heartbeat.luau (prep only; copy it to z-nile/engine/ to replay the mutants)
-- PROTOTYPE (prep only)
local heartbeat = {}
export type Beat = { stamp: string, epoch: number, ref: string }
export type Claim = { id: string, state: string, stamp: string, match: { string } }
export type Verdict = { id: string, state: string, stamp: string, silent: number?, kind: string }
export type Pr = { title: string, head: string }
heartbeat.PREFIX = "refs/zn/hb/"
heartbeat.INTERVAL = 300
heartbeat.STALE = 900
heartbeat.SKEW = 300
function heartbeat.refName(stamp: string, epoch: number): string
	return `{heartbeat.PREFIX}{stamp}/{epoch}`
end
function heartbeat.parse(refs: { string }): ({ Beat }, { string })
	local beats, problems = {}, {}
	for _, ref in refs do
		if string.sub(ref, 1, #heartbeat.PREFIX) == heartbeat.PREFIX then
			local stamp, kind, epoch = string.match(ref, "^refs/zn/hb/((%a+)%-%a+%-%a+%-%a+)/(%d+)$")
			if stamp and (kind == "preparing" or kind == "active") then
				table.insert(beats, { stamp = stamp, epoch = tonumber(epoch) :: number, ref = ref })
			else
				table.insert(problems, `{ref}: not a beat (refs/zn/hb/<preparing|active>-<three words>/<epoch>)`)
			end
		end
	end
	return beats, problems
end
function heartbeat.judge(claims: { Claim }, beats: { Beat }, now: number, stale: number?): { Verdict }
	local limit = stale or heartbeat.STALE
	local out = {}
	for _, c in claims do
		local last: number? = nil
		for _, b in beats do
			if b.stamp == c.stamp and b.epoch <= now + heartbeat.SKEW then
				last = math.max(last or b.epoch, b.epoch)
			end
		end
		local v: Verdict = { id = c.id, state = c.state, stamp = c.stamp, kind = "unbeaten" }
		if last then
			v.silent = math.max(0, now - last)
			v.kind = if (v.silent :: number) > limit then "stale" else "live"
		end
		table.insert(out, v)
	end
	return out
end
function heartbeat.settle(vs: { Verdict }, parked: { [string]: boolean }?): { Verdict }
	local out = {}
	for _, v in vs do
		local c = table.clone(v)
		if v.kind == "stale" and parked then
			c.kind = if parked[v.id] then "parked" else "lost"
		end
		table.insert(out, c)
	end
	return out
end
function heartbeat.parkedBy(prs: { Pr }, claims: { Claim }): { [string]: boolean }
	local out = {}
	for _, c in claims do
		for _, pr in prs do
			for _, id in c.match do
				for _, text in { pr.title, pr.head } do
					local from = 1
					while true do
						local s, e = string.find(text, id, from, true)
						if not s then
							break
						end
						local before = string.sub(text, s - 1, s - 1)
						local after = string.sub(text, e + 1, e + 1)
						if not string.match(before, "%w") and not string.match(after, "%w") then
							out[c.id] = true
						end
						from = e + 1
					end
				end
			end
		end
	end
	return out
end
function heartbeat.order(vs: { Verdict }): { Verdict }
	local out = table.clone(vs)
	local pos = {}
	for i, v in vs do
		pos[v] = i
	end
	table.sort(out, function(a, b)
		local al, bl = a.kind == "lost", b.kind == "lost"
		if al ~= bl then
			return al
		end
		if al and a.silent ~= b.silent then
			return (a.silent :: number) > (b.silent :: number)
		end
		return pos[a] < pos[b]
	end)
	return out
end
function heartbeat.plan(stamp: string, epoch: number, beats: { Beat }, claimed: { [string]: boolean }, now: number): { write: string?, delete: { string } }
	local write: string? = heartbeat.refName(stamp, epoch)
	local delete = {}
	for _, b in beats do
		if b.stamp == stamp and b.epoch == epoch then
			write = nil
		elseif (b.stamp == stamp and b.epoch < epoch) or (not claimed[b.stamp] and b.epoch < now - heartbeat.STALE) then
			table.insert(delete, b.ref)
		end
	end
	return { write = write, delete = delete }
end
return heartbeat
