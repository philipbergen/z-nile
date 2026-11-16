--!strict
-- Workers on several hosts (c0254), pure part. Hosts share only origin/main and the branches on origin, so what one worker
-- must know about another is decided here from facts the edge reads: who a worker is (host, CLI, model), whether a claim
-- attempt was lost to another worker, whether a branch may be pushed after a commit, and who holds what. Nothing reads a
-- file, a process or the clock (zz-arch rule 4). The claim itself is not decided here: it is the publisher's lease push
-- (publish.commit), which refuses a second claim on the same item.
local xhost = {}

export type Identity = { host: string, cli: string, model: string } -- cli "unknown" and model "" when nothing says

-- A host name as a file name and a spend cell: lower case, letters, digits, '.', '_' and '-'. costrow.writer names its
-- file with this too, so the file name and the row agree.
function xhost.hostPart(raw: string?): string
	local name = string.match(raw or "", "%S+") or "host"
	return (string.gsub(string.lower(name), "[^%w._%-]", "-"))
end

local CLI_MARKERS: { { var: string, cli: string } } = {
	{ var = "CLAUDECODE", cli = "claude" },
	{ var = "CLAUDE_CODE_SESSION_ID", cli = "claude" },
	{ var = "KIMI_SESSION_ID", cli = "kimi" },
	{ var = "KIMI_CODE_SESSION_ID", cli = "kimi" },
}

-- Who is working: the host, the CLI and the model. `ZN_CLI` and `ZN_MODEL` are what the dispatcher sets for each attempt
-- (recorded); a person's own session has the CLI's markers (detected); otherwise the CLI is "unknown" and the model "".
function xhost.identity(env: { [string]: string? }, rawHost: string?): Identity
	local cli = env.ZN_CLI
	if cli == nil or not string.match(cli, "^[%a][%w%-]*$") then
		cli = nil
		for _, m in CLI_MARKERS do
			local v = env[m.var]
			if v ~= nil and v ~= "" then
				cli = m.cli
				break
			end
		end
	end
	local model = env.ZN_MODEL
	if model == nil or not string.match(model, "^[%w][%w%._%-]*$") then
		model = ""
	end
	return { host = xhost.hostPart(rawHost), cli = cli or "unknown", model = model :: string }
end

-- ===== the claim race =====

export type Seen = { state: string, status: string, stamp: string } -- an item on origin/main: its folder state, effective status, raw stamp

-- Whether a worker's own claim attempt lost to another worker. `code` is the claim step's exit code. `before` is what the
-- worker saw when it picked the item, `after` what origin/main shows once the step failed (nil: it could not be read),
-- `mine` the stamp this worker's checkout remembers for the item ("" for none), `ours` whether the claim commit that set
-- origin's current stamp carries this attempt's own token (the push landed and the step failed after it). Only a verdict read
-- from origin/main after the failure counts.
-- "won": the step succeeded. "ours": it failed after its claim landed, so the claim is the worker's and the chain goes on
-- (it is adopted, never abandoned). "lost": the item left the state the worker picked it in under a stamp that is not its own.
-- "failed": anything else, handled by the loop's own rules, never taken for a lost race.
function xhost.claimOutcome(code: number, before: Seen, after: Seen?, mine: string, ours: boolean): string
	if code == 0 then
		return "won"
	end
	if after == nil then
		return "failed"
	end
	if after.stamp ~= "" and ((mine ~= "" and after.stamp == mine) or ours) then
		return "ours"
	end
	if after.state == before.state and after.status == before.status then
		return "failed" -- nothing moved: a refusal that is not a lost race
	end
	return "lost"
end

-- A claim stamp is `<state>-<three words>`; a claim is a `preparing-` or `active-` stamp.
function xhost.isClaim(stamp: string): boolean
	return string.match(stamp, "^preparing%-") ~= nil or string.match(stamp, "^active%-") ~= nil
end

export type RaftedBy = { id: string, stamp: string } -- a raft on origin/main that is being rafted (preparing) and lists the issue

-- Whether the item a worker was handed (`pick` is what `./zn next` called it) is still the worker's to take, read from
-- origin/main before any step runs. `seen` is the item on origin (nil: gone), `mine` the claim stamp the run recorded ("" for
-- none), `raftedBy` for a rafting pick the preparing raft that lists the issue. "ok" or "taken". A lost pick is "ok" here: its
-- takeover is a lease push that decides (c0274 refuses a claim restamped since the verdict).
function xhost.pickHeld(pick: string, seen: Seen?, mine: string, raftedBy: RaftedBy?): string
	if seen == nil then
		return "taken"
	end
	if pick == "draft" then
		if seen.state == "backlog" and seen.status == "new" then
			return "ok"
		end
		return if mine ~= "" and seen.stamp == mine then "ok" else "taken"
	elseif pick == "raft" then
		if seen.state == "backlog" and seen.status == "prepared" then
			return "ok"
		end
		return if mine ~= "" and seen.stamp == mine then "ok" else "taken"
	elseif pick == "rafting" then
		if seen.state ~= "backlog" or seen.status ~= "prepared" then
			return "taken"
		end
		if raftedBy == nil or (mine ~= "" and raftedBy.stamp == mine) then
			return "ok"
		end
		return "taken"
	end
	return "ok"
end

-- Once a run holds a claim (`claim` is the stamp it recorded when its claim step landed), the claim is still its own while
-- origin shows that stamp; a different claim stamp is another worker's. A stamp that is not a claim (the item went on to
-- prepared or done through this run's own steps) is not a takeover.
function xhost.stillMine(seen: Seen?, claim: string): boolean
	if seen == nil then
		return false
	end
	if not xhost.isClaim(seen.stamp) then
		return true
	end
	return seen.stamp == claim
end

-- ===== every commit is pushed =====

export type PushFacts = {
	publishing: boolean, -- the checkout has an origin it may push to
	branch: string?, -- the current branch (nil: detached)
	hasUpstream: boolean,
	originHas: boolean, -- origin has a branch of this name
	behind: number?, -- commits on origin/<branch> this checkout lacks (nil: could not be counted)
	claim: string, -- heartbeat.holds (c0265) for the claim of the branch's item: held, unheld, taken or ended
	owner: string?, -- the item whose claim it is (the raft of a layer, the issue of a prep)
	originStamp: string?, -- the claim stamp origin/main shows for it now
	copy: boolean?, -- this worktree is a numbered copy a takeover made (the fresh marker c0277 leaves) or is marked discarded, and holds no claim
}
export type PushDecision = { action: string, why: string } -- action: push, push-new, skip or refuse

-- What kind of work branch this is: a raft's layer (`R0010/1/c0248`), an issue's prep (`prep-<slug>`), or other.
function xhost.branchKind(branch: string?): string
	if branch == nil then
		return "other"
	elseif string.match(branch, "^R%d%d%d%d/%d+/[fdc]%d%d%d%d$") then
		return "layer"
	elseif string.match(branch, "^prep%-[%w%-]+$") then
		return "prep"
	end
	return "other"
end

-- The raft or issue a work branch's claim belongs to is the edge's to look up; this says which kind of key to look for.
function xhost.raftOfLayer(branch: string): string?
	return string.match(branch, "^(R%d%d%d%d)/%d+/[fdc]%d%d%d%d$")
end

-- The text an old owner is told, c0274's own words (heartbeat.lostText plus its stop line): the lost worker stops; it never
-- continues on the taker's branch.
function xhost.lostText(id: string, originStamp: string?): string
	local head = if originStamp
		then `{id}'s claim was taken over (now {originStamp})`
		else `{id}'s claim ended`
	return `{head}: this checkout's work is no longer the claim's; stop here (./zn lost lists lost work to pick up)`
end

-- After a commit on a layer or prep branch: push it, so a taker on any host continues from every commit (Q3, Q5). A branch
-- with no upstream gets one (`push -u`). A worker whose claim was taken over or ended never pushes (its branch is the
-- taker's now), and nothing is ever pushed over commits origin has and this checkout lacks, or when that cannot be counted.
-- Any other branch keeps today's rule: pushed only with an upstream.
function xhost.pushDecision(f: PushFacts): PushDecision
	if not f.publishing or f.branch == nil or f.branch == "" or f.branch == "main" then
		return { action = "skip", why = "no branch to push, or no origin" }
	end
	local kind = xhost.branchKind(f.branch)
	if kind == "other" then
		if f.hasUpstream then
			return { action = "push", why = "the branch has an upstream" }
		end
		return { action = "skip", why = "not a layer or prep branch, and no upstream" }
	end
	local owner = f.owner or "this item"
	if f.claim == "taken" then
		return { action = "refuse", why = xhost.lostText(owner, f.originStamp) }
	elseif f.claim == "ended" then
		return { action = "refuse", why = xhost.lostText(owner, nil) }
	elseif
		f.claim == "unheld"
		and f.copy == true
		and f.originStamp ~= nil
		and xhost.isClaim(f.originStamp)
	then
		-- a numbered copy that remembers no claim (what c0277's takeover leaves) never pushes an item that is under a live claim;
		-- a person's own worktree that never claimed it is not a copy and pushes as it always did
		return {
			action = "refuse",
			why = `{owner} is claimed on origin/main ({f.originStamp}) and this checkout holds no claim on it: not pushing {f.branch}; stop here (./zn lost lists lost work to pick up)`,
		}
	end
	if f.originHas and (f.behind == nil or f.behind > 0) then
		return {
			action = "refuse",
			why = `origin/{f.branch} {if f.behind == nil
				then "could not be compared with this checkout"
				else `has {f.behind} commit(s) this checkout lacks`}: not pushing {f.branch} (never over another worker's commits; git fetch, then decide)`,
		}
	end
	if f.hasUpstream then
		return { action = "push", why = "every commit is pushed" }
	end
	return { action = "push-new", why = "the first push of the branch sets its upstream" }
end

-- ===== who holds what =====

-- The trailer a claim commit carries: `Worker: <id> <stamp> host=<h> cli=<c> model=<m> [attempt=<token>]` ("-" for no model).
-- `attempt` is the dispatcher's token for the claim step that made the commit: a step that fails after its push finds its own
-- claim by it.
function xhost.trailer(id: string, stamp: string, w: Identity, attempt: string?): string
	local base =
		`Worker: {id} {stamp} host={w.host} cli={w.cli} model={if w.model == "" then "-" else w.model}`
	return if attempt ~= nil and attempt ~= "" then `{base} attempt={attempt}` else base
end

export type Holder = {
	id: string,
	stamp: string,
	host: string,
	cli: string,
	model: string,
	attempt: string,
}

function xhost.parseTrailer(line: string): Holder?
	local id, stamp, host, cli, model, rest =
		string.match(line, "^Worker: (%S+) (%S+) host=(%S+) cli=(%S+) model=(%S+)(.*)$")
	if not id or not stamp or not host or not cli or not model then
		return nil
	end
	local attempt = string.match(rest or "", "^ attempt=(%S+)$")
	if (rest or "") ~= "" and attempt == nil then
		return nil
	end
	return {
		id = id,
		stamp = stamp,
		host = host,
		cli = cli,
		model = if model == "-" then "" else model,
		attempt = attempt or "",
	}
end

-- The attempt token of the newest trailer that names `id` at `stamp`, or nil (none, or none with a token).
function xhost.attemptOf(lines: { string }, id: string, stamp: string): string?
	for _, line in lines do
		local h = xhost.parseTrailer(line)
		if h and h.id == id and h.stamp == stamp then
			return if h.attempt ~= "" then h.attempt else nil
		end
	end
	return nil
end

-- The holder of each claimed item: `lines` are the Worker trailers of origin/main's commits, newest first; `stamps` the
-- claim stamp each item carries on origin/main now. An item is held by the newest trailer that names its current stamp: a
-- trailer for an older stamp (a claim since taken over, given back or finished) names nobody.
function xhost.holders(lines: { string }, stamps: { [string]: string }): { [string]: Holder }
	local out: { [string]: Holder } = {}
	for _, line in lines do
		local h = xhost.parseTrailer(line)
		if h and stamps[h.id] == h.stamp and out[h.id] == nil then
			out[h.id] = h
		end
	end
	return out
end

-- The words the board and `./zn work status` show.
function xhost.holderText(h: Holder): string
	local what = if h.model ~= "" then `{h.cli}, {h.model}` else h.cli
	return `{h.host} ({what})`
end

return xhost
