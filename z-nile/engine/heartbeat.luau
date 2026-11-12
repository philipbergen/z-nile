--!strict
-- The work heartbeat's pure rules (c0265): no I/O, no clock. A claim is a lease proved by the branch hb/<claim stamp>.
local reap = require("@znile/engine/reap")

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

-- The clock: ZN_NOW only inside a spec run (`specRun` is the guards' own answer, asked by the engine edge: this module
-- names no guard variable).
function heartbeat.clock(env: { [string]: string? }, real: number, specRun: boolean): number
	local forced = env.ZN_NOW
	if specRun and forced ~= nil and tonumber(forced) ~= nil then
		return tonumber(forced) :: number
	end
	return real
end

-- A tuning setting (ZN_BEAT_EVERY, ZN_NET_SECONDS): honoured only inside a spec run, and only a positive whole number.
function heartbeat.setting(
	env: { [string]: string? },
	name: string,
	default: number,
	specRun: boolean
): number
	local raw = env[name]
	local n = if raw ~= nil then tonumber(raw) else nil
	if specRun and n ~= nil and n >= 1 and n == math.floor(n) then
		return n
	end
	return default
end

-- live | stale | unknown | nobeat, from the newest sign of life: the newest usable beat, else the moment the claim landed.
-- `landed` is the epoch the heartbeat itself landed on main (nil: no such rule): a claim made at or before it that has
-- never beaten is `nobeat`, not stale (the user's "older claims never read lost until they beat once"); every claim made
-- after it is flatlined as before.
function heartbeat.judge(
	claims: { Claim },
	beats: { Beat },
	now: number,
	stale: number?,
	landed: number?
): { Verdict }
	local limit = stale or heartbeat.STALE
	local out: { Verdict } = {}
	for _, c in claims do
		local last: number? = c.since
		local beaten = false
		for _, b in beats do
			if b.stamp == c.stamp and b.epoch <= now + heartbeat.SKEW then
				last = math.max(last or b.epoch, b.epoch)
				beaten = true
			end
		end
		if last == nil then
			-- neither a beat nor a readable landing time: unknown, never lost
			table.insert(out, { id = c.id, state = c.state, stamp = c.stamp, silent = 0, kind = "unknown" })
		else
			local silent = math.max(0, now - last)
			local kind = if silent > limit then "stale" else "live"
			if kind == "stale" and not beaten and landed ~= nil and c.since ~= nil and c.since <= landed then
				kind = "nobeat"
			end
			table.insert(out, { id = c.id, state = c.state, stamp = c.stamp, silent = silent, kind = kind })
		end
	end
	return out
end

-- The git arguments that read the epoch the heartbeat landed on main: the newest commit on main's first-parent line
-- that added this module. A merge-commit PR would otherwise return the time of the PR branch's own commit (before the
-- merge), and claims made while the raft ran would read as made after the landing.
function heartbeat.landingArgs(): { string }
	return {
		"log",
		"--first-parent",
		"--diff-filter=A",
		"--format=%ct",
		"-1",
		"origin/main",
		"--",
		"z-nile/engine/heartbeat.luau",
	}
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

-- One beat: replace the claim's branch; never go backwards or repeat a second; delete the branches of stamps no claim
-- holds once they are older than the limit (a young one may be a claim this checkout has not fetched yet). The lease is
-- one rule (c0275): the sha this checkout last wrote for the stamp (`remembered`, its throttle mark), else the sha seen,
-- else "" (create only if absent). A remembered sha whose branch is gone is rejected, which `rejected` then reads.
function heartbeat.plan(
	stamp: string,
	epoch: number,
	beats: { Beat },
	claimed: { [string]: boolean },
	now: number,
	remembered: string?
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
	-- a branch dated past the skew allowance is not "newer": judge ignores it too, so a beat replaces it
	if existing ~= nil and existing.epoch >= epoch and existing.epoch <= now + heartbeat.SKEW then
		return { write = nil, delete = delete }
	end
	return {
		write = {
			ref = heartbeat.branch(stamp),
			subject = heartbeat.subject(stamp, epoch),
			lease = remembered or (if existing then existing.sha else ""),
		},
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

-- One tick of `beat --watch`: stop when the claim's stamp changed, when it has no place to beat from any more (`gone`: the
-- session that started it ended or the worktree is gone, c0275), or when the next tick would pass the bound.
function heartbeat.watch(
	startStamp: string,
	originStamp: string?,
	now: number,
	deadline: number,
	every: number,
	gone: string?
): string
	if originStamp ~= startStamp then
		return "stop-restamped"
	end
	if gone ~= nil then
		return "stop-gone"
	end
	if now + every >= deadline then
		return "stop-bound"
	end
	return "beat"
end

-- c0274. A takeover of a lost claim: create the taker's branch (create-only: a new stamp has none) and delete the old
-- owner's, each with a lease on the sha seen, in ONE atomic push, so an old owner that beats meanwhile makes the whole
-- push fail (the engine re-reads and repeats once) and one that beats afterwards finds its branch gone.
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

-- Only an explicit lost verdict, judged for the stamp origin still holds at the moment of the publish, allows it
-- (the push is the lock: a claim restamped since the verdict is someone else's now).
function heartbeat.canTakeOver(kind: string, judgedStamp: string, originStamp: string): boolean
	return kind == "lost" and judgedStamp == originStamp
end

-- Why a claim is not taken over, for the refusal that follows `<id> is preparing on origin/main: cannot move to
-- preparing`. `kind` is the verdict (live, stale, parked, nobeat, lost, unknown), `silent` its seconds, `why` what made
-- an unreadable verdict unreadable. A lost claim has no reason: it is taken over.
function heartbeat.takeoverRefusal(id: string, kind: string, silent: number, why: string?): string
	if kind == "live" then
		return `claim alive: last heartbeat {math.floor(silent / 60)}m ago, limit {math.floor(
			heartbeat.STALE / 60
		)}m`
	elseif kind == "parked" then
		return "claim parked (an open pull request or a dispatcher waiting on questions.md names it)"
	elseif kind == "nobeat" then
		return `{id} has never beaten: not lost, no takeover`
	end
	return `no heartbeat verdict: {why or "the claim was made after it was judged, or origin/main could not be read"}`
end

-- Whom a claim stamp belongs to, from the stamp this checkout remembers for the item and the one origin/main shows:
-- "held" (the same), "unheld" (this checkout remembers none), "taken" (origin shows another stamp), "ended" (origin
-- shows no claim). The memory itself is never changed by what this answers.
function heartbeat.holds(remembered: string?, originStamp: string?): string
	if remembered == nil or remembered == "" then
		return "unheld"
	elseif originStamp == nil then
		return "ended"
	elseif originStamp == remembered then
		return "held"
	end
	return "taken"
end

-- The text an old owner is told: its claim was taken over (naming the stamp now on main), or ended.
function heartbeat.lostText(id: string, originStamp: string?): string
	return if originStamp then `{id}'s claim was taken over (now {originStamp})` else `{id}'s claim ended`
end

-- c0274: `stop` records, in its commit subject, the verdict of the claim it gives back: `(claim S)` when the claim was live
-- or parked, `(claim S, lost <n>m)` when it was lost, `(claim S, unjudged)` when no verdict could be read (a never-beaten
-- claim included). It is a record in `git log`; nothing reads it back.
function heartbeat.stopNote(stamp: string, kind: string, silent: number): string
	if kind == "live" or kind == "parked" then
		return `(claim {stamp})`
	elseif kind == "lost" then
		return `(claim {stamp}, lost {math.floor(silent / 60)}m)`
	end
	return `(claim {stamp}, unjudged)`
end

-- ---- c0275: automatic beats ----

-- What a worktree remembers of its last beat for one claim (`.cache/tracker-beats/<id>`, `<stamp> <epoch> <sha>`): the
-- throttle (one beat per interval) and the lease (the sha it wrote). The main checkout holds no work and writes none.
export type Mark = { stamp: string, epoch: number, sha: string }

function heartbeat.markText(m: Mark): string
	return `{m.stamp} {m.epoch} {m.sha}`
end

-- nil for anything that is not a mark: a damaged file is read as no mark (the claim is then due, which only costs a beat)
function heartbeat.markParse(text: string): Mark?
	local stamp, epoch, sha = string.match(text, "^(%S+) (%d+) (%x*)%s*$")
	if stamp == nil or epoch == nil or sha == nil then
		return nil
	end
	return { stamp = stamp, epoch = tonumber(epoch) :: number, sha = sha }
end

-- Whether a beat is due: never made, a full `every` old, or dated past the skew allowance (a clock that went back).
function heartbeat.due(last: number?, now: number, every: number): boolean
	return last == nil or now - last >= every or last > now + heartbeat.SKEW
end

-- The mark after an attempt: a failed attempt advances the epoch too (a hung or offline remote costs one bounded attempt
-- per interval) and keeps the sha it knew; a written beat records the sha it wrote.
function heartbeat.markAfter(stamp: string, now: number, before: Mark?, wrote: string?): Mark
	local sha = wrote or (if before and before.stamp == stamp then before.sha else "")
	return { stamp = stamp, epoch = now, sha = sha }
end

-- The sha to lease on for `stamp`: the mark's, when the mark is for this stamp and records one.
function heartbeat.leaseOf(m: Mark?, stamp: string): string?
	if m ~= nil and m.stamp == stamp and m.sha ~= "" then
		return m.sha
	end
	return nil
end

heartbeat.BEATER_SECONDS = 3600 -- the background beater's bound: `./zn run --time 3600` is the longest a command may run

export type BeaterFacts = {
	dispatched: boolean, -- ZN_DISPATCH: the dispatcher beats for a headless step, which starts no loop
	main: boolean, -- the main checkout holds no work
	guarded: boolean, -- a check protects this repository
	running: boolean, -- a beater of this claim is alive and not past its bound
	held: boolean, -- this worktree still remembers the claim (a beater started elsewhere would be refused at once)
	specRun: boolean,
	forced: boolean, -- a spec asked for the real beater (ZN_BEATER=1; honoured only inside a spec run)
}

-- Whether a claim held in this worktree starts its background beater now: every held claim without a live beater, except
-- where the dispatcher beats, the main checkout, a protected checkout, and (unless a spec asks) a spec run.
function heartbeat.beaterStart(f: BeaterFacts): boolean
	if f.dispatched or f.main or f.guarded or f.running or not f.held then
		return false
	end
	return not f.specRun or f.forced
end

-- The beater's command: `./zn run` is its bound, `beat --watch` its loop, `--session` the process whose end ends it.
function heartbeat.beaterArgv(root: string, id: string, session: number?): { string }
	local argv = {
		`{root}/zn`,
		"run",
		"--time",
		tostring(heartbeat.BEATER_SECONDS),
		"--",
		`{root}/zn`,
		"beat",
		id,
		"--watch",
	}
	if session ~= nil then
		table.insert(argv, "--session")
		table.insert(argv, tostring(session))
	end
	return argv
end

-- `<pid> <deadline>`, the beater's own file; alive means the pid answers and the deadline has not passed.
function heartbeat.beaterRunning(text: string, now: number, alive: boolean): boolean
	local pid, deadline = string.match(text, "^(%d+) (%d+)%s*$")
	return pid ~= nil and deadline ~= nil and alive and tonumber(deadline) :: number > now
end

-- The session a beater is tied to: the nearest ancestor (nearest first) that is `claude`. Another CLI has none, and its
-- beater is bounded by its time and its worktree only.
function heartbeat.sessionPid(chain: { { pid: number, command: string } }): number?
	for _, p in chain do
		if reap.name(p.command) == "claude" then
			return p.pid
		end
	end
	return nil
end

-- Why `beat --watch` has no place to beat from any more, or nil: its session ended, its worktree is gone, or the claim's
-- memory in it ended (a claim-ending command ran there), or it was discarded by a takeover (c0277: its marker is there).
function heartbeat.gone(
	sessionAlive: boolean?,
	worktreeThere: boolean,
	memoryThere: boolean,
	discarded: boolean?
): string?
	if sessionAlive == false then
		return "its session ended"
	elseif not worktreeThere then
		return "its worktree is gone"
	elseif discarded == true then
		return "its worktree was discarded (the claim was taken over)"
	elseif not memoryThere then
		return "its worktree no longer holds the claim"
	end
	return nil
end

-- The dispatcher's stamp for a step's item: the claim its step worktree remembers (a step that made its own claim), else
-- the stamp main showed when the step started.
function heartbeat.dispatchStamp(started: string?, remembered: string?): string?
	if remembered ~= nil and remembered ~= "" then
		return remembered
	end
	return started
end

-- Whether the claim a worktree remembers as `stamp` was taken over ("taken") or ended ("ended") when `main` shows `current`:
-- no claim is ended, and so is an item whose claim changed kind (a prep that ended normally, the item readied later).
function heartbeat.lostKind(stamp: string, current: string?): string
	if current == nil then
		return "ended"
	end
	local before = string.match(stamp, "^(%a+)%-")
	local now = string.match(current, "^(%a+)%-")
	return if before ~= now then "ended" else "taken"
end

-- The claim stamp in a document's status field, nil for anything that is not a live claim (preparing-… or active-…).
function heartbeat.stampIn(status: string?): string?
	local kind = if status then string.match(status, "^(%a+)%-%a+%-%a+%-%a+$") else nil
	return if kind == "preparing" or kind == "active" then status else nil
end

-- What the dispatcher does with the answer of its `zn beat <id> --adopt --stamp <S>` child: "beat" (landed), "lost" (the
-- claim was taken over or ended mid-step: stop beating and say so once), "none" (no claim yet: the step has not made its
-- own: ignored) or "failed" (written once per step to the run's stderr).
function heartbeat.dispatchOutcome(ok: boolean, stderr: string): string
	if ok then
		return "beat"
	elseif
		string.find(stderr, "claim was taken over", 1, true) or string.find(stderr, "claim ended", 1, true)
	then
		return "lost"
	elseif string.find(stderr, "no claim to beat", 1, true) then
		return "none"
	end
	return "failed"
end

-- c0277. A takeover DISCARDS the old worker's worktree (the user, 2026-11-08: "Rename the old worktree and create a copy to
-- continue the work and call it R123-1 R123-2 and so on. That way a process that wakes up knows it has been discarded and
-- can clear and pick up something new. I assume that there is a point in trying to recover the work and not just discarding
-- it"): the old worktree stays at its path with a marker, its branch is renamed, and the taker works in the numbered copy
-- <name>-<n>. Everything below is pure: the engine edge reads the checkout and writes the marker.

-- The marker a takeover leaves in the old worktree, and the file that marks a copy its taker is still starting in (the
-- epoch it was made). Both are relative to a worktree's top.
heartbeat.DISCARDED = ".cache/discarded"
heartbeat.FRESH = ".cache/fresh"

-- n when `name` is `base` (0) or `base-<n>` (n >= 1, digits only), else nil: the worktrees of one family.
function heartbeat.suffixOf(base: string, name: string): number?
	if name == base then
		return 0
	end
	local digits = string.match(name, "^" .. string.gsub(base, "%p", "%%%0") .. "%-(%d+)$")
	local n = if digits then tonumber(digits) else nil
	if n and n >= 1 and tostring(n) == digits then
		return n
	end
	return nil
end

-- The smallest free `<base>-<n>` (n >= 1). `taken` holds names (directories, and branches mapped to the name they stand for).
function heartbeat.nextSuffix(base: string, taken: { string }): string
	local used: { [number]: boolean } = {}
	for _, name in taken do
		local n = heartbeat.suffixOf(base, name)
		if n then
			used[n] = true
		end
	end
	local n = 1
	while used[n] do
		n += 1
	end
	return `{base}-{n}`
end

-- The family's current worktree: the highest suffix among the names not marked discarded; nil when none is left.
function heartbeat.currentOf(base: string, names: { string }, discarded: { [string]: boolean }): string?
	local best: string? = nil
	local bestN = -1
	for _, name in names do
		local n = heartbeat.suffixOf(base, name)
		if n and not discarded[name] and n > bestN then
			best, bestN = name, n
		end
	end
	return best
end

-- The base a worktree stands for: the name its branch had before any discard (a raft layer's branch stands for its raft),
-- else the worktree's own name without a numeric suffix.
function heartbeat.baseOf(branch: string?, dirName: string): string
	local raft = if branch then string.match(branch, "^(R%d%d%d%d)/%d+/[fdc]%d%d%d%d$") else nil
	if raft then
		return raft
	elseif branch and branch ~= "" then
		return branch
	end
	return (string.gsub(dirName, "%-%d+$", ""))
end

-- A taker who is still starting in a copy (`.cache/fresh` holds the epoch it was made) is not discarded until the limit.
function heartbeat.fresh(epoch: number?, now: number, limit: number): boolean
	return epoch ~= nil and now - epoch < limit
end

-- `--item <id>` names a claim for a worktree that remembers none, accepted only for the item's own branch: an issue's
-- `prep-<slug>` or its layer branch, a raft's `raft-<slug>`, its worktree name or one of its layers. The lost verdict is
-- about the item, not about whose worktree this is.
function heartbeat.ownsBranch(branch: string?, id: string, slug: string?): boolean
	if branch == nil or branch == "" then
		return false
	end
	local raft, _, issue = string.match(branch, "^(R%d%d%d%d)/(%d+)/([fdc]%d%d%d%d)$")
	if raft or issue then
		return id == raft or id == issue
	end
	return branch == id or (slug ~= nil and (branch == `prep-{slug}` or branch == `raft-{slug}`))
end

export type ClaimFact = { id: string, remembered: string, current: string?, verdict: Verdict? }

-- Whether every claim a worktree remembers (or the item named for it) may be discarded: lost, or already over (origin
-- shows another stamp or none). nil when it may, else the first refusal, naming the item and why (c0274's wording).
function heartbeat.discardRefusal(facts: { ClaimFact }, why: string?): string?
	if #facts == 0 then
		return "it remembers no claim: name the item with --item <id> (accepted for the item's own branch only)"
	end
	for _, f in facts do
		local held = heartbeat.holds(f.remembered, f.current)
		if f.remembered == "" and f.current == nil then
			return `{f.id} is not a claim on origin/main: nothing to take over`
		elseif held == "held" or held == "unheld" then
			local v = f.verdict
			if not (v and heartbeat.canTakeOver(v.kind, v.stamp, f.current or "")) then
				return `{f.id}: {heartbeat.takeoverRefusal(
					f.id,
					if v then v.kind else "unknown",
					if v then v.silent else 0,
					why
				)}`
			end
		end
	end
	return nil
end

export type Discard = {
	path: string,
	copy: string,
	branch: string,
	base: string,
	items: { string },
	since: number,
	body: string,
}
export type DiscardFacts = {
	path: string,
	copy: string,
	branch: string, -- the renamed branch ("" for a detached worktree)
	base: string, -- the branch name the copy keeps
	items: { string },
	since: number,
	pushedSha: string, -- the pushed tip the copy continues ("" when nothing was pushed)
	pushed: { string },
	unpushed: { string },
	dirty: { string },
}

local LIST_CAP = 20
local function listed(lines: { string }): string
	local out: { string } = {}
	for i, l in lines do
		if i > LIST_CAP then
			table.insert(out, `  ... and {#lines - LIST_CAP} more`)
			break
		end
		table.insert(out, `  {l}`)
	end
	return table.concat(out, "\n")
end

-- The marker's text: a header the engine reads back (`discardParse`, the one reader) and a body every command run in the
-- discarded worktree prints and the taker is shown. Nothing is deleted: this is where the old worker's work is listed.
function heartbeat.discardText(f: DiscardFacts): string
	local first = f.items[1] or "?"
	local more = if #f.items > 1 then ` (and {#f.items - 1} more)` else ""
	local range = if f.pushedSha ~= "" then `origin/{f.base}..{f.branch}` else `origin/main..{f.branch}`
	local out = {
		`discarded worktree: {f.path}`,
		`copy: {f.copy}`,
		`branch: {f.branch}`,
		`base: {f.base}`,
		`items: {table.concat(f.items, " ")}`,
		`since: {f.since}`,
		"",
		`this worktree was discarded: {first}'s claim was taken over{more}. Clear your context and pick up something new. Your work is kept here: {f.path}`,
		`The taker continues in {f.copy}, on {if f.base ~= "" then f.base else "a detached head"}{if f.pushedSha
				~= ""
			then ` at the pushed {string.sub(f.pushedSha, 1, 7)}`
			else " (nothing was pushed)"}.`,
	}
	if #f.pushed > 0 then
		table.insert(out, `pushed commits (the copy has them):\n{listed(f.pushed)}`)
	end
	if #f.unpushed > 0 then
		table.insert(
			out,
			`unpushed commits (kept on {f.branch}; take them with: git -C {f.copy} cherry-pick {range}):\n{listed(
				f.unpushed
			)}`
		)
	end
	if #f.dirty > 0 then
		table.insert(
			out,
			`uncommitted files (kept in {f.path}; copy what you need, for example cp {f.path}/<file> {f.copy}/<file>):\n{listed(
				f.dirty
			)}`
		)
	end
	if #f.pushed == 0 and #f.unpushed == 0 and #f.dirty == 0 then
		table.insert(out, "nothing else was left here")
	end
	return table.concat(out, "\n") .. "\n"
end

-- The marker's header and body, or nil for a damaged file (the engine then refuses with the file's own text: a marker
-- is present or it is not, and a present one is never ignored).
function heartbeat.discardParse(text: string): Discard?
	local head, body = string.match(text, "^(.-)\n\n(.*)$")
	if not head then
		return nil
	end
	local path = string.match(head, "^discarded worktree: ([^\n]+)")
	local copy = string.match(head, "\ncopy: ([^\n]*)")
	local branch = string.match(head, "\nbranch: ([^\n]*)")
	local base = string.match(head, "\nbase: ([^\n]*)")
	local items = string.match(head, "\nitems: ([^\n]*)")
	local since = tonumber(string.match(head, "\nsince: (%d+)") or "")
	if not (path and copy and branch and base and items and since) then
		return nil
	end
	local ids: { string } = {}
	for id in string.gmatch(items, "%S+") do
		table.insert(ids, id)
	end
	return { path = path, copy = copy, branch = branch, base = base, items = ids, since = since, body = body }
end

-- What a command run in a discarded worktree is told (exit 1): the body of the marker.
function heartbeat.discardedText(text: string): string
	local d = heartbeat.discardParse(text)
	if d then
		return d.body
	end
	return "this worktree was discarded. Clear your context and pick up something new. " .. text
end

-- A discarded worktree is finished with when no item it was discarded for is a live claim any more (done, prepared again,
-- new or gone): the raft merged or was stopped, the prep merged or was given back. `live` says, per item, whether
-- origin/main shows it as a claim (preparing or active); an item it says nothing about is not live.
function heartbeat.discardEnded(live: { [string]: boolean }, items: { string }): boolean
	for _, id in items do
		if live[id] == true then
			return false
		end
	end
	return true
end

-- Why a finished discarded worktree is kept anyway, or nil when it may go: it still holds uncommitted files, or commits
-- that exist nowhere else (not reachable from any origin ref). The user's "try to recover the work and not just discard it".
function heartbeat.keepReason(dirty: number, unreachable: number): string?
	if dirty > 0 and unreachable > 0 then
		return `{dirty} uncommitted file(s) and {unreachable} commit(s) exist nowhere else`
	elseif dirty > 0 then
		return `{dirty} uncommitted file(s)`
	elseif unreachable > 0 then
		return `{unreachable} commit(s) exist nowhere else`
	end
	return nil
end

return heartbeat
