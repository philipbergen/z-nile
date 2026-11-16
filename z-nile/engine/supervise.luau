--!strict
-- The worker's supervisor (c0253), pure part. The supervisor is a thin loop over `./zn next` and `./zn dispatch <id>`
-- (the captured Solution): it starts no model, so everything a model step needs (the wrapper, the broker, the agent's
-- credential, the tripwire, the measured row, the gates, the beat) is the dispatcher's. What is decided here: what `next`
-- printed, what a dispatch run's exit code asks the loop to do, the environment the dispatcher child starts in, the
-- refusals at start, the state file, and, for the dispatcher's `--worker` mode, the session record (one CLI session per
-- raft, resumed), the CLI order, the quota wait and the notes. Nothing reads a file, a process or the clock (zz-arch rule 4).
local supervise = {}

supervise.KINDS = { "lost", "raft", "rafting", "draft" } -- the four kinds `./zn next` prints (c0249)
supervise.MAX_TURNS = 1000000 -- the loop is a bounded `for`, never a `while` (zz-arch rule 9)
supervise.IDLE_SECONDS = 60 -- the wait between two polls of origin/main when nothing is claimable (Q6)
supervise.READ_RETRIES = 5 -- a failed `next` is retried this many times in a row, then the worker stops naming the error
supervise.GATE_WAIT_SECONDS = 7200 -- how long a raft's gate (CI, a merge) may stay pending before the worker stops, by the clock
supervise.QUOTA_RECHECK_SECONDS = 300 -- the dispatcher's worker mode tries a CLI again after this long
supervise.QUOTA_WAIT_SECONDS = 600 -- the raft's own CLI is waited for this long when `.models.toml` names none (Q9)

-- The exit codes of `./zn dispatch` (dispatch.EXIT): the loop reads these and never the dispatcher's prose.
supervise.EXIT = { done = 0, failure = 1, user = 3, gate = 4, tripwire = 5, taken = 6 }

export type Pick = { id: string, kind: string, why: string }
export type Read = { kind: string, pick: Pick?, why: string } -- kind: "pick", "none" or "failed"

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function firstLine(s: string): string
	return string.match(s, "[^\n]+") or ""
end

-- What `./zn next` printed. c0249's contract: exit 0 and exactly one `<id> lost|raft|rafting|draft <why>` line is a pick;
-- exit 1 with `next: nothing to take: <why>` first on stderr is "nothing claimable"; every other outcome (a fetch that
-- failed, a Lune trace, a crash, a line of another shape) is a failed read, never a pick and never "nothing" (a Lune error
-- exits 1 too, so the exit code alone cannot tell them apart).
function supervise.parseNext(stdout: string, stderr: string, code: number): Read
	if code == 1 and string.sub(trim(stderr), 1, #"next: nothing to take") == "next: nothing to take" then
		return { kind = "none", pick = nil, why = firstLine(trim(stderr)) }
	end
	if code ~= 0 then
		return { kind = "failed", pick = nil, why = `./zn next exited {code}: {firstLine(trim(stderr))}` }
	end
	local text = trim(stdout)
	if text == "" or string.find(text, "\n", 1, true) then
		return {
			kind = "failed",
			pick = nil,
			why = `./zn next printed {if text == "" then "nothing" else "more than one line"} with exit 0`,
		}
	end
	local id, kind, why = string.match(text, "^([cfdR]%d%d%d%d) (%a+) (.+)$")
	if not id or not kind or not why then
		return {
			kind = "failed",
			pick = nil,
			why = `./zn next printed "{text}": expected "<id> lost|raft|rafting|draft <why>"`,
		}
	end
	if not table.find(supervise.KINDS, kind) then
		return {
			kind = "failed",
			pick = nil,
			why = `./zn next printed the kind "{kind}": expected one of {table.concat(supervise.KINDS, ", ")}`,
		}
	end
	return { kind = "pick", pick = { id = id, kind = kind, why = why }, why = "" }
end

export type DispatchOpts = { cli: string?, noRun: boolean, retry: boolean }

-- The `./zn` arguments that run one pick through the dispatcher's chain. `--worker` turns on the three things the
-- worker needs of it (Q3 one session per raft, Q9 the quota wait, the CLI the person started); `--no-run` keeps the
-- `run` gate (the landing) off on a host the person marked as one that does not land (G1).
function supervise.dispatchArgs(pick: Pick, o: DispatchOpts): { string }
	local args = { "dispatch" }
	if o.retry then
		table.insert(args, "retry")
	end
	table.insert(args, pick.id)
	table.insert(args, "--worker")
	if o.cli and o.cli ~= "" then
		table.insert(args, "--cli")
		table.insert(args, o.cli)
	end
	if o.noRun then
		table.insert(args, "--no-run")
	end
	return args
end

export type Move = { kind: string, why: string }

-- What a dispatch run's exit code asks of the loop. `tries` is how many times this pick already failed (exit 1).
-- done: the chain reached the end (merged, landed). blocked: the item is blocked (c0250) and the worker goes on to the
-- next. park: a draft waits for the person's approval, which is not the loop's to wait for. wait: a raft's gate (CI, a
-- merge) is pending: wait and dispatch again, up to GATE_WAIT_SECONDS by the clock. retry: a failure is retried once.
-- stop: the worker stops, naming the item (a tripwire, a second failure, a code it does not know).
function supervise.afterDispatch(kind: string, code: number, tries: number): Move
	if code == supervise.EXIT.done then
		return { kind = "done", why = "the chain ended" }
	elseif code == supervise.EXIT.taken then
		return { kind = "taken", why = "another worker claimed it first" }
	elseif code == supervise.EXIT.user then
		return { kind = "blocked", why = "the item is blocked or needs the user" }
	elseif code == supervise.EXIT.gate then
		if kind == "draft" then
			return { kind = "park", why = "the prep PR waits for the person's ./zn approve" }
		end
		return { kind = "wait", why = "a gate is pending" }
	elseif code == supervise.EXIT.tripwire then
		return { kind = "stop", why = "the tripwire stopped the chain: look, then ./zn dispatch retry" }
	elseif code == supervise.EXIT.failure then
		if tries < 1 then
			return { kind = "retry", why = "the chain failed: retried once" }
		end
		return { kind = "stop", why = "the chain failed twice: ./zn dispatch status shows why" }
	end
	return { kind = "stop", why = `./zn dispatch exited {code}, which the worker does not know` }
end

-- The variables a person's CLI session (or an earlier run) puts in the environment that must not reach the dispatcher's
-- steps: the agent markers, the session ids a finish or a block would record, and the dispatcher's own state (lesson
-- zz-test/terminal-fixtures-clear-the-agent-session, plus the dispatcher's).
supervise.CLEAR = {
	"AI_AGENT",
	"CLAUDECODE",
	"CLAUDE_CODE_SESSION_ID",
	"KIMI_CODE_SESSION_ID",
	"KIMI_SESSION_ID",
	"ZN_DISPATCH",
	"ZN_DISPATCH_DIR",
	"ZN_DISPATCH_HOME",
	"ZN_DISPATCHER_PID",
	"ZN_HEADLESS",
	"ZN_MODEL",
	"ZN_PUBLISH_BROKER",
	"ZN_PUBLISH_TOKEN",
}

-- `env -u NAME … <zn> <args>`: the argv that starts a ./zn command without the starter's markers. Names are sorted, and only
-- the ones `base` holds are listed.
function supervise.cleanArgv(base: { [string]: string? }, zn: string, args: { string }): { string }
	local names: { string } = {}
	for _, name in supervise.CLEAR do
		if base[name] ~= nil then
			table.insert(names, name)
		end
	end
	table.sort(names)
	local argv = { "env" }
	for _, name in names do
		table.insert(argv, "-u")
		table.insert(argv, name)
	end
	table.insert(argv, zn)
	for _, a in args do
		table.insert(argv, a)
	end
	return argv
end

-- The CLI a person's session runs in, from the markers it sets (the supervisor runs the same CLI, Q8). nil when unknown.
function supervise.starterCli(env: { [string]: string? }): string?
	if env.CLAUDECODE == "1" or (env.CLAUDE_CODE_SESSION_ID or "") ~= "" then
		return "claude"
	elseif (env.KIMI_SESSION_ID or "") ~= "" or (env.KIMI_CODE_SESSION_ID or "") ~= "" then
		return "kimi"
	end
	return nil
end

-- Why `--cli` cannot be used: it must be among the tries (primary and fallbacks) of every role the worker runs. `roles`
-- maps a role to its CLIs in order.
function supervise.cliProblem(cli: string, roles: { [string]: { string } }): string?
	local names: { string } = {}
	for role in roles do
		table.insert(names, role)
	end
	table.sort(names)
	for _, role in names do
		if not table.find(roles[role], cli) then
			return `--cli {cli} is not among role {role}'s tries ({table.concat(roles[role], ", ")}): name a CLI every role of .models.toml has`
		end
	end
	return nil
end

export type Start = {
	headless: string?,
	dispatch: string?,
	checking: boolean,
	detach: boolean,
	here: string, -- the checkout this runs in
	main: string, -- the main checkout (git worktree list's first entry)
}

-- Why a supervisor may not start here, or nil. It runs only in the main checkout (its lock, state, land requests and the
-- dispatcher's run state live there), never inside a headless or dispatched session (a nested supervisor would hold the
-- agent's credential and take more rafts), and a detached one never inside a check (a process that outlives it).
function supervise.refusal(s: Start): string?
	if (s.headless or "") ~= "" or (s.dispatch or "") ~= "" then
		return "the supervisor does not start inside a headless or dispatched session (ZN_HEADLESS or ZN_DISPATCH is set)"
	elseif s.detach and s.checking then
		return "--detach does not start inside a check run (a detached process would outlive it)"
	elseif s.here ~= s.main then
		return `the supervisor runs in the main checkout: {s.main}`
	end
	return nil
end

-- The merge gates a dispatch run may pass itself: `auto_merge` as the files name it, less `run` (the landing) on a host that
-- does not land (G1).
function supervise.gates(autoMerge: { string }, noRun: boolean): { string }
	local out: { string } = {}
	for _, gate in autoMerge do
		if not (noRun and gate == "run") then
			table.insert(out, gate)
		end
	end
	return out
end

-- The user's own host settings (outside the repository, `~/.config/zn/host.toml`): `[work] land = false` marks a host
-- whose credential must not land (a bot host). Text in, settings out; an unreadable value fails closed to "does not land".
function supervise.hostLand(text: string?): boolean
	if text == nil then
		return true
	end
	local value = string.match(text, "\n?land%s*=%s*([%a]+)")
	return value ~= "false" and (value == "true" or value == nil)
end

-- ===== state, status, detach, summary =====

export type State = {
	pid: number,
	state: string, -- idle, working, waiting, stopped
	item: string,
	cli: string,
	since: string,
	moved: number,
	blocked: number,
	held: string, -- the item this supervisor holds mid-chain ("" for none): a restart resumes it before it asks `next`
}

function supervise.stateText(s: State): string
	return table.concat({
		`pid: {s.pid}`,
		`state: {s.state}`,
		`item: {s.item}`,
		`cli: {s.cli}`,
		`since: {s.since}`,
		`moved: {s.moved}`,
		`blocked: {s.blocked}`,
		`held: {s.held}`,
	}, "\n") .. "\n"
end

function supervise.parseState(text: string): State?
	local function field(k: string): string?
		return string.match(text, "\n?" .. k .. ": ([^\n]*)")
	end
	local pid, moved, blocked = tonumber(field("pid")), tonumber(field("moved")), tonumber(field("blocked"))
	local state = field("state")
	if not pid or not moved or not blocked or not state then
		return nil
	end
	return {
		pid = pid,
		state = state,
		item = field("item") or "",
		cli = field("cli") or "",
		since = field("since") or "",
		moved = moved,
		blocked = blocked,
		held = field("held") or "",
	}
end

-- The one line `./zn work status` prints. `ended` says whether the log holds the summary a graceful end prints.
function supervise.statusLine(s: State, alive: boolean, ended: boolean): string
	local live: string
	if s.state == "stopped" then
		live = "stopped"
	elseif alive then
		live = s.state
	elseif ended then
		live = "ended (see the log)"
	else
		live = "ended without a summary (see the log: it was killed or died)"
	end
	local on = if s.item ~= "" then ` on {s.item}` else ""
	local using = if s.cli ~= "" then ` using {s.cli}` else ""
	local holds = if s.held ~= "" and live ~= "stopped"
		then `; holds {s.held}: ./zn work run resumes it`
		elseif s.held ~= "" then `; {s.held} stays held: ./zn work run resumes it`
		else ""
	return `supervisor pid {s.pid}: {live}{on}{using} since {s.since}; moved {s.moved}, blocked {s.blocked}{holds}`
end

-- The command that starts the supervisor apart from the caller (Q12): a perl that forks, leaves its session and execs
-- `<zn> work run <args>` with its output appended to the log. `args` are the command's own arguments in the order typed,
-- `work` and `--detach` dropped. `base` is the starter's environment, whose markers are cleared (`env -u`).
function supervise.detachArgv(
	zn: string,
	raw: { string },
	log: string,
	base: { [string]: string? }
): { string }
	local forwarded: { string } = { "work", "run" }
	for _, a in raw do
		if a ~= "--detach" and a ~= "work" and a ~= "run" then
			table.insert(forwarded, a)
		end
	end
	local argv = {
		"perl",
		"-e",
		'use POSIX (); my ($log, @cmd) = @ARGV; defined(my $p = fork()) or die "fork: $!"; exit 0 if $p; '
			.. 'POSIX::setsid(); open(STDIN, "<", "/dev/null"); open(STDOUT, ">>", $log); open(STDERR, ">&", \\*STDOUT); '
			.. 'exec { $cmd[0] } @cmd or die "exec: $!"',
		log,
	}
	for _, a in supervise.cleanArgv(base, zn, forwarded) do
		table.insert(argv, a)
	end
	return argv
end

export type Summary = { moved: { string }, blocked: { string }, stopped: string, lost: { string }? } -- lost (c0254): items another worker claimed first

function supervise.summary(s: Summary): string
	local lines = {
		`worker stopped: {s.stopped}`,
		`moved: {if #s.moved == 0 then "nothing" else table.concat(s.moved, ", ")}`,
		`blocked: {if #s.blocked == 0 then "nothing" else table.concat(s.blocked, ", ")}`,
	}
	-- c0254: a line only when a race was lost, so a run on one host reads as before
	if s.lost ~= nil and #s.lost > 0 then
		table.insert(lines, `claimed by another worker first: {table.concat(s.lost, ", ")}`)
	end
	return table.concat(lines, "\n")
end

-- ===== the dispatcher's worker mode (`./zn dispatch … --worker`) =====

-- One CLI session per raft (Q3): the dispatcher keeps, in the item's run state, the CLI and id of the session its z-run step
-- last ran, and a rerun of the step resumes it on the same CLI. The resume flag of each supported CLI (probed 2026-11-16,
-- Unknowns E1); a CLI with no row is refused by name, so a new CLI (c0175) must add one.
supervise.RESUME = {
	claude = { new = "--session-id", resume = "--resume" },
	grok = { new = "-s", resume = "-s" },
	kimi = { new = "", resume = "-S" },
	agent = { new = "", resume = "--resume" },
	agy = { new = "", resume = "--conversation" },
	opencode = { new = "", resume = "-s" },
} :: { [string]: { new: string, resume: string } }

-- The CLI's argv for a session: a new session keeps `argv` as the adapter built it; a resumed one swaps the new-session
-- flag for the resume flag (claude, grok), or appends the resume flag and the id (a CLI whose adapter names no session).
function supervise.withSession(
	argv: { string },
	cli: string,
	session: string,
	resumed: boolean
): ({ string }?, string?)
	local row = supervise.RESUME[cli]
	if not row then
		return nil, `no resume row for the CLI {cli} (supervise.RESUME)`
	end
	local out = table.clone(argv)
	if not resumed then
		return out, nil
	end
	local at = if row.new ~= "" then table.find(out, row.new) else nil
	if at and out[at + 1] ~= nil then
		out[at] = row.resume
		out[at + 1] = session
		return out, nil
	end
	table.insert(out, row.resume)
	table.insert(out, session)
	return out, nil
end

export type Record = { cli: string, id: string }

-- How a z-run attempt on `cli` starts, given the session the item's run state records: "new" (none), "resume" (the same
-- CLI), "switched" (another CLI: a new session that reads the raft's notes, Q9).
function supervise.sessionMode(record: Record?, cli: string): string
	if record == nil or record.id == "" then
		return "new"
	elseif record.cli == cli then
		return "resume"
	end
	return "switched"
end

-- The lines the dispatcher adds to a z-run prompt in worker mode. Every prompt names the skill and the raft (the base prompt
-- does); a resumed one says it has read the skill; a switched one says it has not, and both name the notes.
function supervise.sessionPrompt(
	mode: string,
	id: string,
	skillPath: string,
	notes: string,
	was: string
): string
	if mode == "resume" then
		return `This is a resumed session for {id}: you have read \`{skillPath}\`. Continue where you stopped, and keep \`{notes}\` current.\n`
	elseif mode == "switched" then
		return `This is a new session for {id}, taken over from a session on {was} (its CLI ran out of quota). You have not read \`{skillPath}\`: read it now, then read \`{notes}\` and the layers' commits, and carry on from there. Keep \`{notes}\` current.\n`
	end
	return `Keep \`{notes}\` current as you go (where you are, what you learned, what is open): a session on another CLI, or a taker, continues from it.\n`
end

-- The raft's notes: a file in the raft's folder, committed on the layer with `./zn commit`. The z-run session writes it at
-- each layer boundary and before it ends; a switched session and a taker (c0274) read it.
function supervise.notesPath(raftFolder: string): string
	return `{raftFolder}/notes.md`
end

-- The CLIs of a step in the order to try them, with the quota wait (Q9): `preferred` (the CLI the person started) first,
-- then the rest in the role's order; with a wait set for the first, the first appears twice, the second time after the
-- wait. Each entry says whether it is that second try. `cliOf` reads a try's CLI.
export type Slot<T> = { spec: T, afterWait: boolean }

function supervise.order<T>(
	specs: { T },
	cliOf: (T) -> string,
	preferred: string?,
	waits: { [string]: number }
): { Slot<T> }
	local first: { T } = {}
	local rest: { T } = {}
	for _, spec in specs do
		if preferred ~= nil and preferred ~= "" and cliOf(spec) == preferred then
			table.insert(first, spec)
		else
			table.insert(rest, spec)
		end
	end
	local ordered: { T } = {}
	for _, spec in first do
		table.insert(ordered, spec)
	end
	for _, spec in rest do
		table.insert(ordered, spec)
	end
	local out: { Slot<T> } = {}
	for i, spec in ordered do
		table.insert(out, { spec = spec, afterWait = false })
		if i == 1 and (waits[cliOf(spec)] or 0) > 0 then
			table.insert(out, { spec = spec, afterWait = true })
		end
	end
	return out
end

-- The quota wait of a step whose every CLI is out (Q9, c0250): wait the recheck time and try the whole order again, until
-- the outage has lasted the cap; `since` is when this outage began (nil: now), cleared by the caller when a session ends ok.
function supervise.allOut(since: number?, now: number, capSeconds: number?): { kind: string, since: number }
	local began = since or now
	if capSeconds ~= nil and now - began >= capSeconds then
		return { kind = "block", since = began }
	end
	return { kind = "wait", since = began }
end

-- The escalation.md the worker files when every CLI stayed out past the cap (the four sections c0250 checks, exactly one
-- recommended option), written from this pure function the way c0252's landcheck writes its notes.
function supervise.quotaEscalation(id: string, clis: { string }, outFor: number): string
	local hours = math.floor(outFor / 3600)
	local list = table.concat(clis, ", ")
	return table.concat({
		"## Question",
		`Every CLI of the role stayed out of quota for {hours} hours or more while the worker held {id}. Run it again now, or stop the raft?`,
		"",
		"## What was tried",
		`The worker waited for {id}'s own CLI up to its limit, then continued on the others ({list}) in a new session each, and then waited with no model running until the outage passed quota_cap_hours (.models.toml).`,
		"",
		"## Open findings or error",
		`- quota: every CLI of the role ({list}) said quota; the outage began {hours} hours ago`,
		"",
		"## Options",
		"- retry: run the worker again when a CLI has quota (recommended)",
		"- abort: stop the raft",
		"",
	}, "\n")
end

return supervise
