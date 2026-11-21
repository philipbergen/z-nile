--!strict
-- What the tracker commands tell the live layer (f0424, Who emits what): one event per step forward, and one poke per
-- publish. Every call goes through livecall, which never raises, so an event can never fail or change a command. Two
-- rules keep it cheap:
--   - a command spends at most ONE livecall per event it emits (a field it does not know is left out, never read for);
--   - when the layer is unavailable (turned off, no binary, or a call that failed) the process remembers it for a minute, so
--     a command that emits three events pays one failed attempt, not three, and a long-lived process finds a daemon
--     started later.
-- An emit is a write: with no daemon running it starts one (the event log is the point; a cold start costs about 50 ms,
-- once). A poke is not: it wakes waiters, and with no daemon there are none, so it never starts one.
-- main.luau requires this module inside the functions that use it (it has no room for another top-level local).
local livecall = require("./livecall")

local liveemit = {}

-- What this process has learned: the layer cannot be reached at all, or there is no daemon to poke.
local RETRY_AFTER = 60 -- seconds before a failed layer is tried again: a daemon started meanwhile is found
local goneAt: number? = nil
local quietAt: number? = nil

-- The clock, replaceable by a spec.
liveemit.now = os.time :: () -> number

local function failed(at: number?): boolean
	return at ~= nil and liveemit.now() - at < RETRY_AFTER
end

-- Whether an emit would be tried now: the layer is on, a binary exists and no call has failed in the last minute.
function liveemit.available(): boolean
	if failed(goneAt) then
		return false
	end
	goneAt = nil
	if livecall.off() or livecall.binary() == nil then
		goneAt = liveemit.now()
		return false
	end
	return true
end

-- Emits one event. Never raises; returns livecall's code, or 3 when the layer is unavailable (no process started).
function liveemit.emit(kind: string, fields: { [string]: any }?): number
	local ok, code = pcall(function(): number
		if not liveemit.available() then
			return livecall.UNAVAILABLE
		end
		local c = livecall.emit(kind, fields)
		if c == livecall.UNAVAILABLE then
			goneAt = liveemit.now() -- cannot start, or the call failed: not again for a minute
		else
			quietAt = nil -- a daemon answered (maybe the one this call started)
		end
		return c
	end)
	return if ok then code :: number else livecall.UNAVAILABLE
end

-- Wakes the waiters after a publish. Never raises, never starts a daemon.
function liveemit.poke(reason: string?, ref: string?): number
	local ok, code = pcall(function(): number
		if failed(quietAt) or not liveemit.available() then
			return livecall.UNAVAILABLE
		end
		local c = livecall.poke(reason, ref)
		if c == livecall.UNAVAILABLE then
			quietAt = liveemit.now() -- no daemon: the next publishes of this minute do not ask again
		end
		return c
	end)
	return if ok then code :: number else livecall.UNAVAILABLE
end

-- The project a tracker root belongs to (its registry name), or nil: the registry is already loaded by every command.
function liveemit.projectOf(root: string): string?
	local ok, name = pcall(function(): string?
		local projects = require("./projects")
		local p = projects.projectOf(projects.load(), root)
		return if p then p.name else nil
	end)
	return if ok then name :: string? else nil
end

-- The project of an item's path (`<root>/issues/...` or `<root>/rafts/...`), or nil.
function liveemit.projectOfPath(path: string): string?
	local root = string.match(path, "^(.-)/issues/") or string.match(path, "^(.-)/rafts/")
	return if root then liveemit.projectOf(root) else nil
end

-- One `spent` event per row a command wrote: the unit, the activity (the row's phase), the model and the tokens, AI seconds
-- and (when measured apart) wall seconds the row carries (a row with none leaves them out).
function liveemit.spent(
	unit: string,
	activity: string,
	model: string?,
	tokens: number?,
	seconds: number?,
	wall: number?
)
	liveemit.emit("spent", {
		wall = if wall ~= nil and wall > 0 then wall else nil,
		unit = unit,
		activity = activity,
		model = model,
		tokens = if tokens ~= nil and tokens > 0 then tokens else nil,
		seconds = if seconds ~= nil and seconds > 0 then seconds else nil,
	})
end

-- The review and refutation files a commit adds, from the staged names: [{ kind, unit, raft?, activity, round }].
-- One git call to settle that this is no merge conclusion (a merge brings in files others filed) and one for the names,
-- made only when the layer is there to be told (nothing is read for an event nobody hears). A file is `<stem>-NNN.md` in
-- the folder of its unit (an issue's review carries no raft; a raft's own review names the raft), or the stream review of
-- an issue, `stream-review-<id>-NNN.md`, whose unit is that issue.
export type Filed = { kind: string, unit: string, raft: string?, activity: string, round: number }
function liveemit.stagedReviews(): { Filed }
	local out: { Filed } = {}
	if not liveemit.available() then
		return out
	end
	pcall(function()
		local sh = require("../lib/sh")
		if sh.run("git", { "rev-parse", "-q", "--verify", "MERGE_HEAD" }).ok then
			return
		end
		local r = sh.run("git", {
			"diff",
			"--cached",
			"--name-only",
			"--diff-filter=A",
			"--",
			"*review-[0-9][0-9][0-9].md",
			"*refute-[0-9][0-9][0-9].md",
			"*review-[fdc][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9].md",
			"*refute-[fdc][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9].md",
		})
		if not r.ok then
			return
		end
		for path in string.gmatch(r.stdout, "[^\n]+") do
			local dir, stem, n = string.match(path, "([^/]+)/([%w%-]+)%-(%d%d%d)%.md$")
			if dir and stem and n then
				local activity, streamOf = string.match(stem, "^(.-)%-([fdc]%d%d%d%d)$")
				local isRaft = streamOf == nil and string.match(dir, "^R%d%d%d%d$") ~= nil
				table.insert(out, {
					kind = if string.find(stem, "refute", 1, true) then "answer-filed" else "review-filed",
					unit = streamOf or dir,
					raft = if isRaft then dir else nil,
					activity = activity or stem,
					round = tonumber(n) :: number,
				})
			end
		end
	end)
	return out
end

-- Tells each review the commit added (what stagedReviews returned before the commit).
function liveemit.reviewsFiled(filed: { Filed })
	for _, f in filed do
		liveemit.emit(f.kind, { unit = f.unit, raft = f.raft, activity = f.activity, round = f.round })
	end
end

-- The raw state, for the spec: forget what this process learned.
function liveemit.reset()
	goneAt = nil
	quietAt = nil
	liveemit.now = os.time
end

return liveemit
