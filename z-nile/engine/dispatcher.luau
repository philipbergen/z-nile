--!strict
-- `./zn dispatch` (c0117): runs script steps itself and model steps on .models.toml's CLIs, headless and unattended,
-- and chains them from an item's tracker state up to the run's pull request. The rules are dispatch.luau's (pure);
-- this module reads the state, starts the processes (runner.luau), keeps the run state and records the spend.
--
-- The boundary (the user's "Bot token, no bypass"): a model step runs with the agent's own GitHub credential
-- (the credential module), which can't merge or bypass main's protection; the tracker's pushes of tracker state from inside
-- a step go through the dispatcher's publish broker (broker.luau), which checks them and pushes with the user's
-- credential; only the dispatcher merges; and after every step a tripwire checks that main and the main checkout moved
-- only as the dispatcher moved them.
--
-- Run state (ignored, in the main checkout): .cache/dispatch/<id>/state.json, lock, questions.md (a step that needs the
-- user), pending.json rows in state.json, stop (the stop marker), pid, stdin, gh/ (the step's empty gh configuration),
-- and <step>-<mode>-<n>/ for a step a step dispatched (a review), with its own state; .cache/dispatch/broker/.
local adapters = require("./adapters")
local audit = require("./audit")
local broker = require("./broker")
local buffer = require("./buffer")
local costrow = require("./costrow")
local cred = require("./credential")
local dispatch = require("./dispatch")
local fs = require("@lune/fs")
local heartbeat = require("./heartbeat")
local models = require("./models")
local modelstep = require("./modelstep")
local openlist = require("./openlist")
local process = require("@lune/process")
local projects = require("./projects")
local raftcheck = require("./raftcheck")
local runner = require("./runner")
local serde = require("@lune/serde")
local sh = require("../lib/sh")
local stdio = require("@lune/stdio")
local store = require("./store")
local task = require("@lune/task")
local trackerstate = require("./trackerstate")

local dispatcher = {}

export type OriginItem = { path: string, front: { [string]: string }, state: string, status: string }
export type Ctx = {
	fail: (string) -> never,
	mainRoot: () -> string,
	onGitHub: () -> boolean,
	checking: () -> boolean, -- inside a guarded run (a spec or a check.sh): only a CLI under .cache may start
	origin: (id: string) -> OriginItem?,
	originIssueIds: () -> { string },
	prView: (branch: string) -> string?, -- `gh pr view <branch> --json …`'s output, or nil
	prMerged: (sha: string) -> boolean, -- `sha` is a pull request's merge commit on GitHub
	memoryIn: ((dir: string, id: string) -> string)?, -- c0275: the claim stamp the checkout at `dir` remembers for `id`, "" for none
}
export type Attempt = {
	step: string,
	cli: string,
	runtime: string,
	model: string,
	outcome: string, -- runner.Outcome, "tripwire", or "failed" for a CLI that never started
	detail: string,
	tokens: number,
	minutes: number,
	wall: number?,
	cpu: number?,
}
export type Row = {
	id: string,
	phase: string,
	tokens: number,
	model: string,
	minutes: number,
	note: string,
	wall: number?,
	cpu: number?,
}
export type State = {
	id: string,
	dir: string, -- the folder this state lives in
	mode: string, -- "chain" or "step"
	step: string?,
	reviewMode: string?,
	cli: string?,
	runtime: string?,
	model: string?,
	run: runner.Identity?, -- the running step's group: its id, leader start time and command
	worktree: string?,
	startedAt: string?,
	tokens: number?,
	outcome: string?,
	detail: string?,
	follows: string?, -- the raft an issue's chain moved on to
	merged: { number }, -- the PRs the dispatcher merged
	pushed: { string }, -- the commits its publish broker pushed to main
	history: { Attempt },
	pending: { Row },
}

local HOME = ".cache/dispatch"
-- the state folder of a step that another step dispatched (a review from its author), set once in `main`
local nested: string? = nil

local function now(): string
	return os.date("!%Y-%m-%dT%H:%M:%SZ") :: string
end

local function trim(s: string): string
	return sh.trim(s)
end

function dispatcher.home(ctx: Ctx): string
	return `{ctx.mainRoot()}/{HOME}`
end

-- Whether the dispatcher's run state for `id` under the main checkout `root` holds a questions.md: a step waits on the
-- user, so a claim on `id` is parked, not lost (c0265).
function dispatcher.waitsOnUser(root: string, id: string): boolean
	return fs.isFile(`{root}/{HOME}/{id}/questions.md`)
end

local function dirOf(ctx: Ctx, id: string): string
	return nested or `{dispatcher.home(ctx)}/{id}`
end

local function blank(id: string, dir: string): State
	return { id = id, dir = dir, mode = "chain", history = {}, pending = {}, merged = {}, pushed = {} }
end

local function loadAt(id: string, dir: string): State
	local path = `{dir}/state.json`
	if fs.isFile(path) then
		local text = fs.readFile(path)
		local ok, s = pcall(function()
			return serde.decode("json", text)
		end)
		if ok and type(s) == "table" then
			local st = s :: any
			st.history = st.history or {}
			st.pending = st.pending or {}
			st.merged = st.merged or {}
			st.pushed = st.pushed or {}
			st.dir = dir
			return st :: State
		end
	end
	return blank(id, dir)
end

local function load(ctx: Ctx, id: string): State
	return loadAt(id, dirOf(ctx, id))
end

-- see pinOrigin and vetMain
local guard: { origin: broker.Origin?, config: string?, mark: string?, fresh: string? } = {}

local function save(st: State)
	fs.writeDir(st.dir)
	sh.writeReplacing(`{st.dir}/state.json`, serde.encode("json", st, true) .. "\n")
end

-- `<dir>/zn <args>`; returns success and captured stdout and stderr.
local function zn(dir: string, args: { string }, quiet: boolean?): (boolean, string, string)
	local r = process.exec(`{dir}/zn`, args, {
		cwd = dir,
		stdio = if quiet then "default" else { stdout = "default", stderr = "forward" },
	})
	return r.ok, trim(r.stdout), trim(r.stderr)
end

local function git(dir: string, args: { string }): (boolean, string)
	local r = process.exec("git", args, { cwd = dir })
	return r.ok, trim(r.stdout)
end

-- This process's own fetch refs (review 005 F1): a dispatcher, its broker and its gates fetch into
-- `refs/zn-dispatch/run-<id>/<name>`, never a ref another run shares (git compares and swaps a ref, so two fetches into
-- one ref fail with "cannot lock ref", and a late one can set it back). The id's lock file
-- (`<git common dir>/zn-dispatch-runs/<id>.lock`, held by a helper for the process's life) says the run is alive;
-- `sweepRefs` deletes the refs of runs nobody holds, and `dropRefs` this run's own at its end.
local runId: string? = nil
local runLock: any = nil

local function commonDir(dir: string): string
	local _, common = git(dir, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
	return common
end

local function runRef(dir: string, name: string): string
	if not runId then
		runId = string.lower(trim(process.exec("uuidgen", {}).stdout))
		local locks = `{commonDir(dir)}/zn-dispatch-runs`
		fs.writeDir(locks)
		runLock = runner.holdLock(`{locks}/{runId}.lock`)
	end
	return `refs/zn-dispatch/run-{runId}/{name}`
end
dispatcher.runRef = runRef

-- A fetch into `ref`, retried three times with back-off (a lock another process holds on it: as publish.commit does);
-- returns the fetched sha, or nil when it still fails (a network fault, said as such by the callers).
local function fetchInto(dir: string, url: string, from: string, ref: string): string?
	for attempt = 1, 4 do
		if git(dir, { "fetch", "-q", url, `+{from}:{ref}` }) then
			local ok, sha = git(dir, { "rev-parse", ref })
			if ok and string.match(sha, "^%x+$") then
				return sha
			end
		end
		if attempt < 4 then
			task.wait(0.2 * attempt)
		end
	end
	return nil
end

-- Deletes the fetch refs of runs whose lock nobody holds (a lost run's leftovers), never this run's own.
function dispatcher.sweepRefs(dir: string)
	local locks = `{commonDir(dir)}/zn-dispatch-runs`
	local _, refs = git(dir, { "for-each-ref", "--format=%(refname)", "refs/zn-dispatch/" })
	for ref in string.gmatch(refs, "[^\n]+") do
		local id = string.match(ref, "^refs/zn%-dispatch/run%-([%w%-]+)/")
		if id and id ~= runId and not runner.held(`{locks}/{id}.lock`) then
			git(dir, { "update-ref", "-d", ref })
			pcall(fs.removeFile, `{locks}/{id}.lock`)
		end
	end
end

local function dropRefs(dir: string)
	if not runId then
		return
	end
	local _, refs = git(dir, { "for-each-ref", "--format=%(refname)", `refs/zn-dispatch/run-{runId}/` })
	for ref in string.gmatch(refs, "[^\n]+") do
		git(dir, { "update-ref", "-d", ref })
	end
	if runLock then
		runLock.stdin:close()
	end
	pcall(fs.removeFile, `{commonDir(dir)}/zn-dispatch-runs/{runId}.lock`)
end

-- The worktree named `name`, made (or reused) from the main checkout.
local function worktree(ctx: Ctx, name: string): string
	local ok, out, err = zn(ctx.mainRoot(), { "worktree", name }, true)
	if not ok then
		error(`./zn worktree {name}: {err}{out}`, 0)
	end
	local lines = string.split(out, "\n")
	return lines[#lines]
end

-- The caller's PATH without any z-nile/bin (a folder beside an engine with wrap.luau): the real tools resolve there,
-- never the shims, whatever the environment says (c0117 review 001 F5).
function dispatcher.realPath(): string
	local out: { string } = {}
	for _, entry in string.split(process.env.PATH or "/usr/bin:/bin", ":") do
		if entry ~= "" and not fs.isFile(`{entry}/../engine/wrap.luau`) then
			table.insert(out, entry)
		end
	end
	return table.concat(out, ":")
end

-- The physical path of the program `name` on `path`, or nil.
local function resolveBin(name: string, path: string): string?
	local r = process.exec("sh", { "-c", 'command -v "$1"', "_", name }, { env = { PATH = path } })
	if not r.ok or trim(r.stdout) == "" then
		return nil
	end
	local real = process.exec("perl", { "-MCwd", "-e", "print Cwd::realpath($ARGV[0])", trim(r.stdout) })
	return if real.ok and real.stdout ~= "" then real.stdout else trim(r.stdout)
end

-- Where a CLI that may start inside a check lives, physically.
local function physicalCache(): string
	-- the outermost .cache this checkout lies in (a spec's fixture is a checkout under the real one's .cache, beside
	-- the spec's fakes), else this checkout's own
	local here = trim(process.exec("pwd", { "-P" }).stdout) .. "/"
	local at = string.find(here, "/.cache/", 1, true)
	return if at then string.sub(here, 1, at + 7) else here .. ".cache/"
end

-- The run locks this process holds (flock holders that let go when it ends or dies), by folder.
local holders: { [string]: any } = {}

-- Takes the run lock of a dispatch on `dir`: an flock held by a helper that lives as long as this process, so a dead
-- dispatcher's lock is free at once. Refuses while another live dispatcher holds it. Returns the refusal, or nil.
local function lock(dir: string, _takeOver: boolean): string?
	fs.writeDir(dir)
	if holders[dir] then
		return nil
	end
	local h = runner.holdLock(`{dir}/lock`)
	if not h then
		return `{dir} is being dispatched by another live ./zn dispatch: wait for it, or ./zn dispatch stop`
	end
	holders[dir] = h
	return nil
end

local function unlock(dir: string)
	local h = holders[dir]
	if h then
		h.stdin:close()
		holders[dir] = nil
	end
end

-- The commit settings, caps and models are read at: main, fetched once per run (review 002 F5).
local pinned: string? = nil

-- origin's fetch URL for a process that has pinned none (a nested step, a dry run), set below once pinOrigin exists
local unpinnedOrigin: () -> string

local function walk(dir: string): { models.Layer }
	if not pinned then
		-- the run's own fresh main when it has one, else fetched from the pinned URL (code review 001 F7): never
		-- `origin` by name and never the tracking ref a step can rewrite; no main, no walk
		if guard.fresh then
			pinned = guard.fresh
		else
			local here = process.cwd
			local url = if guard.origin then (guard.origin :: broker.Origin).fetch else unpinnedOrigin()
			pinned = fetchInto(here, url, "refs/heads/main", runRef(here, "models"))
			if not pinned then
				error(`could not fetch main from {url} to read .models.toml: no walk without it`, 0)
			end
		end
	end
	return models.walkAt(dir, function(path: string): string?
		local shown = process.exec("git", { "show", `{pinned}:{path}` })
		return if shown.ok then shown.stdout else nil
	end, function(path: string): boolean
		return fs.isFile(path)
	end)
end

-- The walk of `skill` for an item: an issue's own folder; a raft's members, strongest per CLI, ordered by the
-- raft's own walk; z-ticket's, its project's home.
function dispatcher.resolve(skill: string, id: string, project: string?, mode: string?): models.Resolved
	if id == "" then
		local reg = projects.load(".")
		local p = if project then projects.named(reg, project) else reg.projects[1]
		if not p then
			error(`no project {tostring(project)} in {projects.FILE}`, 0)
		end
		return models.resolve(walk((p :: projects.Project).home), skill, mode)
	end
	local item = store.get(id)
	if item.kind == "issue" then
		return models.resolve(walk(item.dir), skill, mode)
	end
	local own = models.resolve(walk(item.dir), skill, mode)
	if own.fromRoles then
		return own
	end
	local members: { models.Resolved } = {}
	for _, m in store.members(id) do
		table.insert(members, models.resolve(walk(m.dir), skill))
	end
	return models.forRaft(own, members)
end

-- The dispatcher's settings for an item, from its own walk; any error means no auto-merge (fail closed).
function dispatcher.settings(id: string): (models.Settings, string?)
	local ok, r = pcall(function(): models.Settings
		local item = if id ~= "" then store.find(id) else nil
		return models.settings(walk(if item then item.dir else "."))
	end)
	if ok then
		return r :: models.Settings, nil
	end
	return { autoMerge = {}, stallSeconds = models.STALL_SECONDS, toolSeconds = models.TOOL_SECONDS },
		tostring(r)
end

local function minutesSince(t0: number): number
	return math.floor((os.time() - t0) / 6 + 0.5) / 10
end

-- Records the rows the step's attempts spent: on the item now when its spend may be written (backlog), else kept in
-- pending for the next legal point (a run's rows after its merge). Minutes (the user's G13, 2026-10-25, "Dispatcher row
-- 0 min", read with "Yes, reviewers keep minutes"): an author step's rows record 0, since its skill records its own;
-- a review's rows record the attempt's wall minutes, since no skill records a reviewer's. A code or stream review's
-- spend is one printed `record:` line for the author's `./zn commit`, and one line in the author's measure
-- buffer (the author's commit folds it). Tokens are the attempts summed, under the model of the attempt that
-- did the review (the last that spent tokens). The dispatch branch is not given this row.
local function rowLine(root: string, row: Row): buffer.Line
	local branch, head = costrow.branchOf(root)
	local flags: { string } = {}
	if not row.wall then
		table.insert(flags, "wall")
		table.insert(flags, "ai")
	end
	if not row.cpu then
		table.insert(flags, "cpu")
	end
	if row.tokens == 0 then
		table.insert(flags, "tokens")
	end
	return {
		ms = 0,
		kind = "row",
		phase = row.phase,
		subject = row.note,
		wall = row.wall,
		cpu = row.cpu,
		ai = row.wall,
		tokens = row.tokens,
		model = if row.model ~= "" then row.model else nil,
		unmeasured = if #flags > 0 then table.concat(flags, ",") else nil,
		id = row.id,
		branch = branch,
		head = head,
	}
end

-- Folds the measured row into the dispatcher's branch and commits that file alone.
local function publishMeasured(ctx: Ctx, row: Row): (boolean, string, string)
	local wt = worktree(ctx, "zn-dispatch")
	zn(wt, { "sync" }, true)
	local dir = costrow.locate(wt, row.id)
	if not dir then
		return false, "", `no folder for {row.id}`
	end
	if not costrow.append(wt, rowLine(wt, row)) then
		return false, "", "could not buffer the row"
	end
	local homes: { [string]: string } = {}
	homes[row.id] = dir
	local planned = costrow.plan(wt, homes, nil, false)
	local paths = costrow.writeFiles(planned)
	if #paths == 0 then
		return false, "", "no row"
	end
	local out = paths[1]
	local added = git(wt, { "add", "--", out })
	if not added then
		costrow.restore(planned)
		return false, out, "could not stage the row"
	end
	local committed, cerr = git(wt, {
		"commit",
		"-q",
		"--only",
		"-m",
		`tracker: spend {row.id} {row.phase}`,
		"--",
		out,
	})
	if not committed then
		costrow.restore(planned)
		return false, out, cerr
	end
	costrow.writeBuffer(wt, planned)
	return true, out, ""
end

local function record(
	ctx: Ctx,
	st: State,
	id: string,
	phase: string,
	attempts: { Attempt },
	note: string,
	reviewer: boolean,
	stream: boolean,
	cwd: string
)
	if phase == "code-review" then
		local model = nil :: string?
		local tokens = 0
		local wall, cpu = 0, 0
		local sawWall, sawCpu = false, false
		for _, a in attempts do
			tokens += a.tokens
			if a.tokens > 0 then
				model = a.model
			end
			if a.wall then
				wall += a.wall
				sawWall = true
			end
			if a.cpu then
				cpu += a.cpu
				sawCpu = true
			end
		end
		if model then
			print(
				`record: ./zn commit -m "{id}: {note}" --phase code-review --model {model}{if stream
					then ` --issue {id}`
					else ""}`
			)
			local flags: { string } = {}
			if not sawWall then
				table.insert(flags, "wall")
				table.insert(flags, "ai")
			end
			if not sawCpu then
				table.insert(flags, "cpu")
			end
			-- In the author's measure buffer. Their commit folds it. The dispatch branch is left alone.
			local branch, head = costrow.branchOf(cwd)
			costrow.append(cwd, {
				ms = 0,
				kind = "row",
				phase = phase,
				subject = note,
				tokens = tokens,
				model = model,
				wall = if sawWall then wall else nil,
				cpu = if sawCpu then cpu else nil,
				ai = if sawWall then wall else nil,
				unmeasured = if #flags > 0 then table.concat(flags, ",") else nil,
				id = id,
				branch = branch,
				head = head,
			})
		end
		return
	end
	for _, a in attempts do
		if a.tokens > 0 then
			local row: Row = {
				id = id,
				phase = phase,
				tokens = a.tokens,
				model = a.model,
				minutes = if reviewer then a.minutes else 0,
				note = note,
				wall = a.wall,
				cpu = a.cpu,
			}
			local origin = ctx.origin(id)
			if phase == "deliver" or (origin and origin.state ~= "backlog") then
				table.insert(st.pending, row)
			else
				local ok, out, err = publishMeasured(ctx, row)
				if ok then
					print(`spend: {id} {phase} {a.tokens} tokens {a.model}`)
				else
					stdio.ewrite(
						`dispatch: could not record {id}'s {phase} row ({err}{out}): kept as pending\n`
					)
					table.insert(st.pending, row)
				end
			end
		end
	end
end

-- Writes the pending rows whose item may now take them (a done raft takes its run's row as deliver).
local function flush(ctx: Ctx, st: State)
	-- every pending row its item may take now (code review 001 F6): a run's `deliver` row once the raft is done, any
	-- other row while its item is in the backlog (a row `record` couldn't publish); a row that fails again is kept and
	-- reported, never dropped silently
	local keep: { Row } = {}
	for _, row in st.pending do
		local origin = ctx.origin(row.id)
		local ready = origin
			and (
				(row.phase == "deliver" and origin.state == "done")
				or (row.phase ~= "deliver" and origin.state == "backlog")
			)
		if ready then
			local ok, out, err = publishMeasured(ctx, row)
			if ok then
				print(`spend: {row.id} {row.phase} {row.tokens} tokens {row.model} (pending, now written)`)
			else
				stdio.ewrite(
					`dispatch: {row.id}'s pending {row.phase} row still can't be written ({err}{out})\n`
				)
				table.insert(keep, row)
			end
		else
			table.insert(keep, row)
		end
	end
	st.pending = keep
end

-- Every dispatched review lands through the dispatcher (design review 008 F1, 009 F1: one mechanism, no folder
-- scan): its reviewer writes `review.md` in its own state folder, and the dispatcher numbers it into the mode's folder.
-- The highest round in `dir` of the files named `<prefix>NNN.md` (a plain prefix match, so another issue's or another
-- mode's file never counts), and that file's name.
local function lastRound(dir: string, prefix: string): (number, string?)
	local best, name = 0, nil :: string?
	if fs.isDir(dir) then
		for _, f in fs.readDir(dir) do
			if string.sub(f, 1, #prefix) == prefix then
				local n = tonumber(string.match(string.sub(f, #prefix + 1), "^(%d+)%.md$"))
				if n and n > best then
					best, name = n, f
				end
			end
		end
	end
	return best, name
end

-- What this dispatcher pinned at its start, held in memory for this process (review 003 F2, F3): origin's fetch and
-- push URLs, the configuration that resolves them, and the commit of main the process started from. A step can rewrite
-- the repository's configuration; it can't reach this memory. A rewrite during the run is detected. Between runs
-- nothing is remembered: the next process accepts main and origin as git reports them.

local function originConfig(root: string): string
	local _, out = git(root, { "config", "--get-regexp", "^(remote\\.origin\\.|url\\.)" })
	return out
end

local function pinOrigin(ctx: Ctx): broker.Origin
	if not guard.origin then
		local root = ctx.mainRoot()
		local _, fetchUrl = git(root, { "ls-remote", "--get-url", "origin" })
		local _, pushUrl = git(root, { "remote", "get-url", "--push", "origin" })
		guard.origin = { fetch = fetchUrl, push = pushUrl }
		guard.config = originConfig(root)
	end
	return guard.origin :: broker.Origin
end
dispatcher.pinOrigin = pinOrigin

-- origin's main, freshly fetched from the pinned URL into a ref of the dispatcher's own (never the tracking ref an agent
-- can rewrite, never `origin` as the configuration says later).
local function freshMain(ctx: Ctx): string?
	local root = ctx.mainRoot()
	local origin = pinOrigin(ctx)
	local sha = fetchInto(root, origin.fetch, "refs/heads/main", runRef(root, "main"))
	if sha then
		guard.fresh = sha
	end
	return sha
end
dispatcher.freshMain = freshMain

-- The project roots of the registry at `ref` (lesson zz-arch/guards-trust-only-origin), or nil.
local function rootsAt(ctx: Ctx, ref: string): { string }?
	local reg = projects.at(ref, ctx.mainRoot())
	return if reg then projects.roots(reg :: projects.Registry) else nil
end

local function isAncestor(root: string, a: string, b: string): boolean
	return process.exec("git", { "merge-base", "--is-ancestor", a, b }, { cwd = root }).ok
end

-- A nested step never runs guardStart (code review 002 F3). It reads .models.toml from git's current origin URL.
-- During a run the tripwire still stops if origin's configuration changes after the run pinned it.
unpinnedOrigin = function(): string
	local ctx = ({
		mainRoot = function(): string
			return process.cwd
		end,
	} :: any) :: Ctx
	local origin = pinOrigin(ctx)
	if origin.fetch == "" then
		error("origin has no fetch URL, so .models.toml is not read from it", 0)
	end
	return origin.fetch
end

-- During this process, main may only move forward by tracker state or a pull request's merge into main. The first
-- call remembers the fetched tip in memory and accepts it: a fresh clone, a second machine and a cleaned home folder
-- all start. A later call in the same process walks the commits since that tip (trackerstate.checkEach, the broker's
-- own rule). Nothing is written outside the repository. Returns why the run stops, or nil.
function dispatcher.vetMain(ctx: Ctx): string?
	local root = ctx.mainRoot()
	local fresh = freshMain(ctx)
	if not fresh then
		return "origin's main could not be fetched (after retries: the network?); ./zn dispatch retry once it is back"
	end
	local mark = guard.mark
	if not mark then
		guard.mark = fresh
		return nil
	end
	if mark == fresh then
		return nil
	end
	if not isAncestor(root, mark, fresh :: string) then
		return `origin's main was rewritten during this run: {mark} is no longer in it`
	end
	local why = trackerstate.checkEach(
		function(a: { string }): (boolean, string)
			return git(root, a)
		end,
		mark,
		fresh :: string,
		function(ref: string): { string }?
			return rootsAt(ctx, ref)
		end,
		true,
		ctx.prMerged
	)
	if why then
		return `main has {why}, which arrived during this run and is not tracker state or a pull request's merge into main`
	end
	guard.mark = fresh
	return nil
end

-- At the start of a top-level run: sweep leftover refs, pin origin's URLs for this process, and accept main as it is.
-- Returns why the run stops, or nil.
function dispatcher.guardStart(ctx: Ctx, _st: State): string?
	dispatcher.sweepRefs(ctx.mainRoot())
	pinOrigin(ctx)
	return dispatcher.vetMain(ctx)
end

export type Snapshot = { head: string, status: string, diff: string }

local function snapshot(ctx: Ctx): Snapshot
	local root = ctx.mainRoot()
	local _, head = git(root, { "rev-parse", "HEAD" })
	local _, status = git(root, { "status", "--porcelain", "--untracked-files=all" })
	local _, diff = git(root, { "diff", "HEAD" })
	return { head = head, status = status, diff = diff }
end

-- The tripwire, after a step's group is gone: main is judged since the commit this process started from (every
-- interval, not only the step's: review 002 F4), origin's configuration is the one this run pinned, and the main
-- checkout's tracked and untracked files did not change (its HEAD may only move forward along main, as ./zn
-- fast-forwards it). Returns what tripped it, or nil.
function dispatcher.tripwire(ctx: Ctx, _st: State, before: Snapshot): string?
	local root = ctx.mainRoot()
	local after = snapshot(ctx)
	if after.status ~= before.status or after.diff ~= before.diff then
		return `the main checkout changed during the step: {after.status}`
	end
	-- origin's URLs and what resolves them, as this run pinned them (review 003 F3)
	if guard.config and originConfig(root) ~= guard.config then
		return `origin's configuration changed during the step (remote.origin.* or url.*): {originConfig(root)}`
	end
	local unvetted = dispatcher.vetMain(ctx)
	if unvetted then
		return unvetted
	end
	if after.head ~= before.head then
		local onMain = process.exec(
			"git",
			{ "merge-base", "--is-ancestor", after.head, guard.fresh or "HEAD" },
			{ cwd = root }
		).ok
		local forward =
			process.exec("git", { "merge-base", "--is-ancestor", before.head, after.head }, { cwd = root }).ok
		if not (onMain and forward) then
			return `the main checkout's HEAD moved from {before.head} to {after.head}, off origin's main`
		end
	end
	return nil
end

-- Runs one model step: each CLI of the order in turn, moving down only when one fails on quota. Returns the outcome.
-- A nested step beats for its whole process, not only while its CLI runs (code review 002, the stall cases: a review
-- whose CLI was done still had its review to land and its spend to record, and its author stalled at the silence).
-- The runner enforces the CLI's own limits; outside it the beat lasts NESTED_BEAT seconds from the process's start and
-- again from the runner's return, so a hung post-step still stops beating and its author stalls.
local NESTED_BEAT = 300
local beatUntil = 0
local function holdBeat()
	beatUntil = os.time() + NESTED_BEAT
end
dispatcher.holdBeat = holdBeat
local function keepBeating(dir: string): () -> ()
	local running, n = true, 0
	holdBeat()
	task.spawn(function()
		while running do
			if os.time() < beatUntil then
				n += 1
				pcall(fs.writeFile, `{dir}/beat`, `{os.time()} process {n}`)
			end
			task.wait(1)
		end
	end)
	return function()
		running = false
	end
end

-- c0275: while a model step works an item, the dispatcher beats for it, so a claim whose model thinks for minutes between
-- two `./zn` commands never reads lost. Every INTERVAL one child (`zn beat <id> --adopt --stamp <S>` under `./zn run
-- --time 60`, one at a time; a hung remote cannot stall the supervising loop because the child runs in a task of its own)
-- beats the claim `S` the step's worktree remembers, else the one main showed when the step started. A claim restamped
-- mid-step is refused by the child: the dispatcher stops beating and says so once. Returns the function that stops it.
function dispatcher.claimBeat(ctx: Ctx, id: string, cwd: string, started: string?): () -> ()
	local running = true
	if id == "" then
		return function() end
	end
	task.spawn(function()
		local every = heartbeat.setting(process.env, "ZN_BEAT_EVERY", heartbeat.INTERVAL, ctx.checking())
		local last: number? = nil
		local said = false
		while running do
			local at = os.time()
			if not fs.isDir(cwd) or fs.isFile(`{cwd}/{heartbeat.DISCARDED}`) then
				-- c0277: a takeover discarded this step's worktree (renamed: its path is gone). Nothing beats from it, and
				-- an empty memory would only make the beat fall back to the stamp the step started with
				stdio.ewrite(
					`dispatch: {id}: the step's worktree was discarded (the claim was taken over): not beating\n`
				)
				return
			end
			if heartbeat.due(last, at, every) then
				last = at
				local remembered = if ctx.memoryIn then ctx.memoryIn(cwd, id) else ""
				local s = heartbeat.dispatchStamp(started, remembered)
				if s then
					local root = ctx.mainRoot()
					-- ZN_MEASURED: a beat is not measured work of the claim (`./zn run` would add a line to the main checkout's buffer each time)
					local r = process.exec(
						`{root}/zn`,
						{ "run", "--time", "60", "--", `{root}/zn`, "beat", id, "--adopt", "--stamp", s },
						{
							cwd = root,
							env = { ZN_MEASURED = "1" },
						}
					)
					local ok, err = r.ok, trim(r.stderr)
					local outcome = heartbeat.dispatchOutcome(ok, err)
					if outcome == "lost" then
						stdio.ewrite(`dispatch: {err}: not beating {id} any more\n`)
						return
					elseif outcome == "failed" and not said then
						said = true
						stdio.ewrite(`dispatch: beat {id}: {err}\n`)
					end
				end
			end
			task.wait(1)
		end
	end)
	return function()
		running = false
	end
end

function dispatcher.modelStep(
	ctx: Ctx,
	st: State,
	step: string,
	id: string,
	opts: { [string]: { string } }
): string
	local mode = opts["--mode"] and opts["--mode"][1]
	local project = opts["--project"] and opts["--project"][1]
	local resolved = dispatcher.resolve(step, id, project, mode)
	local tries = models.tries(resolved)
	local stateDir = st.dir
	local cwd: string
	if step == "zz-review" then
		-- the author's worktree: the checkout ./zn ran in (zn passes ZN_TOP, and ZN_CWD relative to it, since c0114)
		local topDir = process.env.ZN_TOP
		cwd = if topDir and topDir ~= "" then topDir else process.cwd
		if trim(cwd) == trim(ctx.mainRoot()) then
			error("zz-review runs in its author's worktree, not the main checkout", 0)
		end
	elseif step == "z-ticket" then
		cwd = worktree(ctx, `capture-zn-{os.time()}`)
	elseif step == "z-design" then
		cwd = worktree(ctx, `prep-{store.get(id).slug}`)
	elseif step == "z-raft" then
		cwd = worktree(ctx, `raft-{opts["--for"] and opts["--for"][1] or string.lower(id)}`)
	else
		cwd = worktree(ctx, id)
	end
	local skillPath = `z-nile/skills/{step}/SKILL.md`
	local promptPath: string? = nil
	if step == "z-run" then
		local ok, out = zn(ctx.mainRoot(), { "prompt", id, "--path" }, true)
		if not ok then
			error(`{id} has no readied prompt: ./zn ready {id} first`, 0)
		end
		promptPath = out
	end
	-- a stream review's raft folder (repository-relative). One round: a second file is refused where the review lands.
	local streamDir: string? = nil
	if step == "zz-review" and mode == "stream" and id ~= "" then
		local raftId = store.readFront(store.get(id).doc).raft
		if not raftId or raftId == "" then
			error(`{id} has no raft: a stream review lands in its raft's folder`, 0)
		end
		streamDir = store.get(raftId).dir
	end
	local prompt = dispatch.prompt({
		step = step,
		id = id,
		mode = mode,
		skillPath = skillPath,
		worktree = cwd,
		stateDir = stateDir,
		promptPath = promptPath,
		streamWorktree = if streamDir then `{ctx.mainRoot()}/.worktree/ws-{id}` else nil,
		description = opts["--description"] and opts["--description"][1],
		project = project,
	})
	local attempts: { Attempt } = {}
	local function refused(spec: models.Spec, why: string)
		table.insert(attempts, {
			step = step,
			cli = spec.cli,
			runtime = spec.runtime,
			model = models.id(spec),
			outcome = "failed",
			detail = why,
			tokens = 0,
			minutes = 0,
		})
		stdio.ewrite(`dispatch: {why}\n`)
	end
	local function skipped(spec: models.Spec, why: string)
		table.insert(attempts, {
			step = step,
			cli = spec.cli,
			runtime = spec.runtime,
			model = models.id(spec),
			outcome = "missing",
			detail = why,
			tokens = 0,
			minutes = 0,
		})
		stdio.ewrite(`dispatch: {why}\n`)
	end
	local basePath = dispatcher.realPath()
	local repo = trim(process.exec("pwd", { "-P" }).stdout)
	local token, where = cred.token()
	-- the top dispatcher of a run serves a broker folder of its own, bound by a run token; a nested step (a review its
	-- author started) uses the one it inherited (review 002 F7)
	local serving = process.env.ZN_PUBLISH_BROKER == nil or process.env.ZN_PUBLISH_BROKER == ""
	local brokerDir = if serving then `{stateDir}/broker` else process.env.ZN_PUBLISH_BROKER :: string
	local brokerToken = if serving
		then string.lower(trim(process.exec("uuidgen", {}).stdout))
		else (process.env.ZN_PUBLISH_TOKEN or "")
	local env: { [string]: string } = {
		PATH = `{repo}/z-nile/bin:{basePath}`,
		ZN_DISPATCH = "1",
		ZN_HEADLESS = "1",
		ZN_DISPATCH_DIR = stateDir,
		ZN_DISPATCH_HOME = dispatcher.home(ctx),
		ZN_REAL_GIT = resolveBin("git", basePath) or "",
		ZN_REAL_GH = resolveBin("gh", basePath) or "",
		ZN_PUBLISH_BROKER = brokerDir,
		ZN_PUBLISH_TOKEN = brokerToken,
		-- this dispatcher's pid (the step's lifeline is the supervisor's stdin; this only names it)
		ZN_DISPATCHER_PID = trim(process.exec("sh", { "-c", "echo $PPID" }).stdout),
	}
	if token then
		for k, v in cred.agentEnv(process.env, token :: string, `{stateDir}/gh`) do
			env[k] = v
		end
	end
	-- where a dispatched review lands: the mode's folder (the item's; a stream review's raft's) and file name
	type Landing = { dir: string, prefix: string, note: string }
	local land: Landing? = nil
	if step == "zz-review" and id ~= "" then
		if streamDir then
			land = { dir = streamDir, prefix = `stream-review-{id}-`, note = "stream-review-" }
		else
			local prefix = if mode == "code"
				then "review-"
				elseif mode == "final" then "final-review-"
				else "design-review-"
			land = { dir = store.get(id).dir, prefix = prefix, note = prefix }
		end
	end
	local outcome = "failed"
	fs.writeDir(stateDir)
	local landing = `{stateDir}/review.md`
	if land then
		pcall(fs.removeFile, landing) -- a stale one from an earlier run is never this run's review
	end
	for _, spec in tries do
		local adapter = adapters.get(spec.runtime)
		local argv = adapter.argv({
			prompt = prompt,
			model = spec.model,
			effort = spec.effort,
			cwd = cwd,
			session = string.lower(trim(process.exec("uuidgen", {}).stdout)),
		})
		local bin = resolveBin(argv[1], basePath)
		if not token then
			outcome = "failed"
			refused(spec, where)
			break
		end
		if not bin then
			-- skipped like quota, named on stderr (the user's G11, 2026-10-25: "Skip missing CLIs")
			skipped(spec, `{argv[1]} is not installed (the {spec.cli} CLI): skipped`)
			continue
		end
		if ctx.checking() and string.sub(bin :: string, 1, #physicalCache()) ~= physicalCache() then
			outcome = "failed"
			refused(
				spec,
				`refusing to start {argv[1]}: inside a check run only a CLI under this checkout's .cache may start (found {bin})`
			)
			break
		end
		-- main is judged since the commit this process started from, before every step
		local unvetted = if serving then dispatcher.vetMain(ctx) else nil
		if unvetted then
			outcome = "tripwire"
			table.insert(attempts, {
				step = step,
				cli = spec.cli,
				runtime = spec.runtime,
				model = models.id(spec),
				outcome = "tripwire",
				detail = unvetted :: string,
				tokens = 0,
				minutes = 0,
			})
			stdio.ewrite(`dispatch: TRIPWIRE: {unvetted}\n`)
			break
		end
		argv[1] = bin :: string
		local extra: { [string]: string } = adapters.STEP_ENV[spec.runtime] or {}
		for k, v in extra do
			env[k] = v
		end
		local t0 = os.time()
		print(
			`dispatch: {step} {id} on {spec.cli} ({spec.runtime}, {models.id(spec)}, max_tokens {spec.maxTokens})`
		)
		st.step, st.cli, st.runtime, st.model = step, spec.cli, spec.runtime, models.id(spec)
		st.worktree, st.startedAt, st.outcome, st.reviewMode = cwd, now(), "running", mode
		-- a stale stop marker goes before the state says running, never after (review 002 F10)
		pcall(fs.removeFile, `{stateDir}/{runner.STOP}`)
		save(st)
		local shot = if serving then snapshot(ctx) else nil
		local function push(sha: string): (boolean, string)
			local ok, said = broker.push(ctx.mainRoot(), sha, function(ref: string): { string }?
				return rootsAt(ctx, ref)
			end, pinOrigin(ctx), runRef(ctx.mainRoot(), "broker"))
			if ok then
				table.insert(st.pushed, sha)
			end
			return ok, said
		end
		local startedStamp: string? = nil
		if id ~= "" then
			local found = pcall(function()
				startedStamp = heartbeat.stampIn(store.readFront(store.get(id).doc).status)
			end)
			if not found then
				startedStamp = nil
			end
		end
		local stopClaimBeat = dispatcher.claimBeat(ctx, id, cwd, startedStamp)
		local result = modelstep.launch({
			argv = argv,
			cwd = cwd,
			env = env,
			stdin = nil, -- every runtime takes its prompt on the command line
			adapter = adapter,
			cap = spec.maxTokens,
			maxCalls = if adapter.callCapped then spec.maxCalls else nil,
			maxSeconds = if adapter.callCapped and spec.maxMinutes
				then (spec.maxMinutes :: number) * 60
				else nil,
			stallSeconds = resolved.settings.stallSeconds,
			toolSeconds = resolved.settings.toolSeconds,
			stateDir = stateDir,
			beatFile = if serving then nil else `{stateDir}/beat`,
			onStart = function(identity: runner.Identity)
				st.run = identity
				save(st)
			end,
			onTick = if serving
				then function()
					broker.serve(brokerDir, brokerToken, push)
				end
				else nil,
		})
		stopClaimBeat()
		holdBeat() -- the review still lands and the spend is recorded: beat through it
		local outcomeNow: string = result.outcome
		local detail = result.detail
		if shot then
			broker.serve(brokerDir, brokerToken, push)
			local tripped = dispatcher.tripwire(ctx, st, shot :: Snapshot)
			if tripped then
				outcomeNow, detail = "tripwire", tripped
				stdio.ewrite(`dispatch: TRIPWIRE: {tripped}\n`)
			end
		end
		table.insert(attempts, {
			step = step,
			cli = spec.cli,
			runtime = spec.runtime,
			model = models.id(spec),
			outcome = outcomeNow,
			detail = detail,
			tokens = result.tokens,
			minutes = minutesSince(t0),
			wall = result.wall,
			cpu = result.cpu,
		})
		print(`dispatch: {step} on {spec.cli}: {outcomeNow} ({detail}), {result.tokens} tokens`)
		outcome = outcomeNow
		-- a failed attempt's review is moved aside, so only the attempt that ends the step can land one
		if land and outcomeNow ~= "ok" and fs.isFile(landing) then
			local aside = `{stateDir}/review-attempt-{#attempts}.md`
			pcall(fs.removeFile, aside)
			fs.move(landing, aside)
		end
		-- a role's list moves on when the call fails, the CLI is missing, or the quota is gone
		if outcomeNow ~= "quota" and not (resolved.fromRoles and outcomeNow == "failed") then
			break
		end
	end
	-- when every CLI of the order was tried and none could run, say why for each kind (review 006 F5)
	local onQuota, notInstalled = {}, {}
	for _, a in attempts do
		if a.outcome == "quota" then
			table.insert(onQuota, a.cli)
		elseif a.outcome == "missing" then
			table.insert(notInstalled, a.cli)
		end
	end
	if #attempts > 0 and #onQuota + #notInstalled == #attempts then
		if #notInstalled == 0 then
			stdio.ewrite(`dispatch: every CLI in the order failed on quota\n`)
		elseif #onQuota == 0 then
			stdio.ewrite(`dispatch: no CLI in the order is installed\n`)
		else
			stdio.ewrite(
				`dispatch: no CLI in the order could run: {table.concat(onQuota, ", ")} on quota; {table.concat(
					notInstalled,
					", "
				)} not installed\n`
			)
		end
	end
	for _, a in attempts do
		table.insert(st.history, a)
	end
	-- the item z-ticket made: the one new issue on origin/main
	local target = id
	if step == "z-ticket" and outcome == "ok" then
		local made: { string } = {}
		local had: { [string]: boolean } = {}
		local earlier: { string } = opts["--before"] or {}
		for _, i in earlier do
			had[i] = true
		end
		for _, i in ctx.originIssueIds() do
			if not had[i] then
				table.insert(made, i)
			end
		end
		if #made ~= 1 then
			outcome = "failed"
			local why: Attempt = {
				step = step :: string,
				cli = "",
				runtime = "",
				model = "",
				outcome = "failed",
				detail = `z-ticket made {#made} issues on origin/main, not one`,
				tokens = 0,
				minutes = 0,
			}
			table.insert(attempts, why)
		else
			target = made[1]
			st.id = target
			st.dir = `{dispatcher.home(ctx)}/{target}`
		end
	end
	-- the dispatcher lands a dispatched review: exactly the one review.md, numbered after the last round of its kind in
	-- the mode's folder; a step that spent tokens and left none failed (its spend is still recorded below)
	local reviewNote: string? = nil
	if land and outcome == "ok" then
		local l = land :: Landing
		if fs.isFile(landing) then
			local last = lastRound(`{cwd}/{l.dir}`, l.prefix)
			if last >= 1 then
				-- one round. Historical files stay where they are; a new one is not added.
				outcome = "failed"
				pcall(fs.removeFile, landing)
				local why: Attempt = {
					step = step :: string,
					cli = "",
					runtime = "",
					model = "",
					outcome = "failed",
					detail = `{l.dir} already has {l.prefix}{string.format("%03d", last)}.md: one round, then the author answers it; there is no second round`,
					tokens = 0,
					minutes = 0,
				}
				table.insert(attempts, why)
				table.insert(st.history, why)
				stdio.ewrite(`dispatch: {why.detail}\n`)
			else
				local name = string.format("%s%03d.md", l.prefix, last + 1)
				fs.move(landing, `{cwd}/{l.dir}/{name}`)
				reviewNote = string.format("%s%03d", l.note, last + 1)
				print(`dispatch: the review is {l.dir}/{name}`)
			end
		else
			outcome = "failed"
			local why: Attempt = {
				step = step :: string,
				cli = "",
				runtime = "",
				model = "",
				outcome = "failed",
				detail = `the reviewer wrote no review ({landing})`,
				tokens = 0,
				minutes = 0,
			}
			table.insert(attempts, why)
			table.insert(st.history, why)
			stdio.ewrite(`dispatch: {why.detail}\n`)
		end
	end
	local note = reviewNote or `dispatch {step}`
	if target ~= "" then
		record(
			ctx,
			st,
			target,
			dispatch.phaseOf(step, mode),
			attempts,
			note,
			step == "zz-review",
			mode == "stream",
			cwd
		)
	end
	-- a step that refuses before any CLI is tried (no credential) still has to name itself, or the chain
	-- reads no last step and runs it again
	st.step = step
	st.outcome = outcome
	st.detail = attempts[#attempts] and attempts[#attempts].detail or ""
	st.tokens = 0
	for _, a in attempts do
		st.tokens = (st.tokens :: number) + a.tokens
	end
	st.run = nil
	save(st)
	return outcome
end

-- Runs a script step: `./zn <command>` in the main checkout or the step's worktree, never a model.
function dispatcher.scriptStep(ctx: Ctx, st: State, step: string, id: string, extra: { string }?): string
	local argv = dispatch.scriptArgv(step, id, extra)
	local where = dispatch.step(step).where
	local dir = if where == "main" then ctx.mainRoot() else worktree(ctx, `raft-{id}`)
	print(`dispatch: {step} {id}: {table.concat(argv, " ")} (in {dir})`)
	local args = table.move(argv, 2, #argv, 1, {})
	local r =
		process.exec(`{dir}/zn`, args, { cwd = dir, stdio = { stdout = "forward", stderr = "forward" } })
	local outcome = if r.ok then "ok" else "failed"
	st.step, st.cli, st.runtime, st.model, st.worktree, st.outcome = step, nil, nil, nil, dir, outcome
	st.detail = if r.ok then "done" else `exit {r.code}`
	table.insert(st.history, {
		step = step,
		cli = "",
		runtime = "script",
		model = "",
		outcome = outcome,
		detail = st.detail :: string,
		tokens = 0,
		minutes = 0,
	})
	save(st)
	return outcome
end

-- `gh pr view`'s JSON as the chain's Pr, or nil.
function dispatcher.parsePr(text: string?): dispatch.Pr?
	if not text then
		return nil
	end
	local okj, j = pcall(function()
		return serde.decode("json", text :: string)
	end)
	if not okj or type(j) ~= "table" or type(j.number) ~= "number" then
		return nil
	end
	local checks = j.statusCheckRollup
	local green = type(checks) == "table" and #checks > 0
	for _, c in (checks or {}) :: { any } do
		local v = c.conclusion or c.state
		if v ~= "SUCCESS" and v ~= "NEUTRAL" and v ~= "SKIPPED" then
			green = false
		end
	end
	return {
		number = j.number,
		state = tostring(j.state),
		draft = j.isDraft == true,
		green = green,
		mergeable = j.mergeable == "MERGEABLE",
		head = if type(j.headRefOid) == "string" then j.headRefOid else "",
	}
end

-- Whether a gate may merge PR `pr` (review 003 F5): its head, fetched from the pinned URL into a private ref, must be
-- the head gh reports, and `merge-base(main, head)..head` must be tracker state by the one function, sequestered, with
-- the gate's own narrower rule: a prep PR only its issue's folder (whose sequestered files it may change) and skill
-- lessons; a rafting PR each item's change judged by its shape against the base, never by what the PR says (code
-- review 002 F1, 003 F1, F2): an existing backlog issue only its document's `raft:` line, between empty and a raft the
-- PR carries; an existing backlog raft any non-sequestered file; a new raft its backlog folder, its check.sh the rendered
-- template's RC0 lines then only RCn checks and `finish`; never anything of an active, done or retired item. Returns
-- why not, or nil.
function dispatcher.judgePr(ctx: Ctx, gateName: string, id: string, pr: dispatch.Pr, folder: string): string?
	local root = ctx.mainRoot()
	local origin = pinOrigin(ctx)
	local ref = runRef(root, `pr-{pr.number}`)
	if pr.head == "" then
		return "its head commit is unknown"
	end
	if not freshMain(ctx) then
		return "origin's main could not be fetched"
	end
	local got = fetchInto(root, origin.fetch, `refs/pull/{pr.number}/head`, ref)
	if not got then
		return "its head could not be fetched"
	end
	if got ~= pr.head then
		return `its fetched head {got} is not the head GitHub reports ({pr.head})`
	end
	local main = guard.fresh :: string
	pr.judgedMain = main
	pr.itemIds = if folder ~= "" then { id } else {}
	local okBase, base = git(root, { "merge-base", main, ref })
	local roots = rootsAt(ctx, main)
	if not roots then
		return "the registry could not be read"
	end
	local function gitFn(a: { string }): (boolean, string)
		return git(root, a)
	end
	-- `own` are the items whose sequestered files this PR may change (code review 001 F1, 002 F1): the issue being
	-- prepared at the prep gate, and none at the rafting gate (a new raft's own files pass as a new item, its check.sh
	-- judged against the template below; an existing item's reviewed check.sh and acceptance specs are never a rafting
	-- PR's to change)
	local own: { [string]: boolean } = if gateName == "prep" then { [id] = true } else {}
	local only: (path: string) -> string?
	local carriedRafts: { string } = {}
	if gateName == "prep" then
		only = function(path: string): string?
			if
				(folder ~= "" and string.sub(path, 1, #folder + 1) == folder .. "/")
				or dispatch.isLesson(path)
			then
				return nil
			end
			return `it carries {path}, outside the issue's own folder and the skill lessons`
		end
	else
		-- the rafting gate judges each item's change by its shape against the base (code review 003 F1, F2), never by
		-- what the PR says: an existing issue only its document's `raft:` line, in the backlog, between empty and a raft
		-- this PR carries; an existing backlog raft any non-sequestered file; a new raft its own backlog folder, its
		-- check.sh the rendered template's RC0 lines then only RCn checks; `z-nile/next`; nothing else
		local from = if okBase then base else trackerstate.EMPTY_TREE
		local function atBase(path: string): boolean
			return okBase and (git(root, { "cat-file", "-e", `{base}:{path}` })) or false
		end
		local function show(rev: string, path: string): string?
			local ok, text = git(root, { "show", `{rev}:{path}` })
			return if ok then text else nil
		end
		local LIVES = { "", "active/", "done/", "retired/" }
		-- where an item's folder is on the base ("" for the backlog), or nil when it has none: every lifecycle
		-- folder trackerstate.itemOf knows
		local function lifeOnBase(r: string, kind: string, xid: string): string?
			for _, life in LIVES do
				if atBase(`{r}/{kind}/{life}{xid}/{xid}.md`) then
					return life
				end
			end
			return nil
		end
		local function rootOf(path: string): string?
			for _, r in roots :: { string } do
				if string.sub(path, 1, #r + 1) == r .. "/" then
					return r
				end
			end
			return nil
		end
		if not okBase then
			return "it shares no history with origin's main"
		end
		local _, names = git(root, { "diff", "--name-only", "--no-renames", from, ref })
		local paths: { string } = {}
		for path in string.gmatch(names, "[^\n]+") do
			table.insert(paths, path)
		end
		-- code review 005 F1: the merge lands on today's main, not on the base, so every rule below that reads an item
		-- "at the base" is only true while main left that item alone. An item (any root, any lifecycle folder) that
		-- main changed since the base is refused, whatever the PR does to it: the rafting PR is rebased first
		local okMoved, moved = git(root, { "diff", "--name-only", "--no-renames", from, main })
		if not okMoved then
			return "what origin's main changed since this PR was cut could not be read"
		end
		local movedIds: { [string]: string } = {}
		for path in string.gmatch(moved, "[^\n]+") do
			local mid = trackerstate.itemOf(path, roots :: { string })
			if mid then
				movedIds[mid :: string] = path
			end
		end
		pr.judgedMain = main
		local carriedIds: { [string]: boolean } = {}
		for _, path in paths do
			local pid = trackerstate.itemOf(path, roots :: { string })
			if pid then
				carriedIds[pid :: string] = true
			end
		end
		local idList: { string } = {}
		for cid in carriedIds do
			table.insert(idList, cid)
		end
		pr.itemIds = idList
		for _, path in paths do
			local pid = trackerstate.itemOf(path, roots :: { string })
			if pid and movedIds[pid :: string] then
				return `it carries {path}, but origin's main changed {movedIds[pid :: string]} since this PR was cut: rebase it onto main`
			end
		end
		-- the rafts this PR carries, keyed by root and id (code review 004 F2: an id is per root, and an issue may
		-- name only a raft of its own root): new, or in the backlog on the base, and in the backlog folder at the head
		-- too (F1: a carried raft moved to active/, done/ or retired/ is not the PR's to move; a retire waits for a human)
		local rafts: { [string]: string } = {} -- "<root>/<id>" -> "new" or "backlog"
		local live: { string } = {}
		local newIn: { [string]: string } = {} -- a new raft's id -> the one root it appears in
		for _, path in paths do
			local rid, dirOfItem = trackerstate.itemOf(path, roots :: { string })
			if rid and store.isRaftId(rid :: string) then
				local r = rootOf(path) :: string
				local life = lifeOnBase(r, "rafts", rid :: string)
				-- the id on the base in any other root: not this root's raft, and not a new one either
				for _, other in roots :: { string } do
					if other ~= r and lifeOnBase(other, "rafts", rid :: string) ~= nil then
						return `it carries {path}, but raft {rid} belongs to {other}`
					end
				end
				if life == nil then
					if dirOfItem ~= `{r}/rafts/{rid}` then
						return `it adds raft {rid} outside the backlog folder ({path})`
					end
					local prev = newIn[rid :: string]
					if prev ~= nil and prev ~= r then
						return `it adds raft {rid} in two roots ({prev} and {r})`
					end
					newIn[rid :: string] = r
					rafts[`{r}/{rid}`] = "new"
				elseif life == "" then
					if dirOfItem ~= `{r}/rafts/{rid}` then
						return `it moves raft {rid} out of the backlog folder ({path}): a rafting PR leaves a backlog raft where it is`
					end
					rafts[`{r}/{rid}`] = "backlog"
				else
					table.insert(live, `{path} (raft {rid} is {string.sub(life, 1, -2)})`)
				end
			end
		end
		if #live > 0 then
			return `it changes an active, done or retired raft: {table.concat(live, ", ")}`
		end
		-- code review 005 F2: a carried raft keeps the file that makes it a raft: `<id>.md` at the head, its `id:` the
		-- folder's name (a deleted, renamed or missing document strands its members and breaks find and audit)
		for key, _ in rafts do
			local r, rid = string.match(key, "^(.*)/(R%d+)$")
			table.insert(carriedRafts, rid :: string)
			local docPath = `{r}/rafts/{rid}/{rid}.md`
			local text = show(ref, docPath)
			local front = if text then string.match(text :: string, "^%-%-%-\n(.-\n)%-%-%-") else nil
			local docId = if front then string.match("\n" .. front, "\nid:[ \t]*([^\n]-)[ \t]*\n") else nil
			if docId ~= rid then
				return `it carries raft {rid} without a valid {docPath} (the file must exist, with id: {rid})`
			end
		end
		local function raftLine(text: string): string?
			local front = string.match(text, "^%-%-%-\n(.-\n)%-%-%-")
			return if front then string.match("\n" .. front, "\nraft:[ \t]*([^\n]-)[ \t]*\n") else nil
		end
		local fresh = guard.fresh :: string
		-- why each path may not be carried (nil: it may); the `only` rule reports it, after the judge's own rules
		-- (configuration, links, sequestered names) have had their say
		local function shapeOf(path: string): string?
			local pid, _, rel = trackerstate.itemOf(path, roots :: { string })
			if pid and store.isRaftId(pid :: string) then
				if rafts[`{rootOf(path) :: string}/{pid}`] == "new" and rel == "check.sh" then
					local r = rootOf(path) :: string
					local reg = projects.at(fresh, root)
					local p = if reg then projects.projectOf(reg :: projects.Registry, r) else nil
					local template = show(fresh, "z-nile/templates/raft/check.sh")
					local text = show(ref, path)
					if not template or not text then
						return `it carries {path}, which could not be judged against the raft template`
					end
					local why = raftcheck.judge(
						text :: string,
						raftcheck.render(
							template :: string,
							{ ID = pid :: string, PROJECT = if p then (p :: projects.Project).name else r }
						)
					)
					if why then
						return `it carries {path}: {why}`
					end
				end
				return nil
			elseif pid then
				local r = rootOf(path) :: string
				local life = lifeOnBase(r, "issues", pid :: string)
				local doc = `{r}/issues/{pid}/{pid}.md`
				if life == nil then
					return `it adds issue {pid} ({path}): a rafting PR adds no issue`
				elseif life ~= "" then
					return `it changes {path}, an issue in {string.sub(life, 1, -2)}/: a rafting PR changes only a backlog issue's raft: line`
				elseif path ~= doc then
					return `it changes {path}: a rafting PR changes only a backlog issue's raft: line`
				end
				local before, after = show(base, path), show(ref, path)
				local was = if before then raftLine(before :: string) else nil
				local became = if after then raftLine(after :: string) else nil
				if not before or not after or was == nil or became == nil then
					return `it changes {path}: no raft: line to judge`
				end
				-- the PR's document with the base's raft: line put back must be the base's document
				local baseLine = string.match(before :: string, "\nraft:[^\n]*") :: string
				if
					string.gsub(after :: string, "\nraft:[^\n]*", function()
						return baseLine
					end, 1) ~= before
				then
					return `it changes {path} beyond its raft: line`
				end
				for _, v in { was, became } do
					if v ~= "" and not rafts[`{r}/{v}`] then
						return `it moves {pid}'s raft: line from {if was == "" then "empty" else was} to {if became
								== ""
							then "empty"
							else became}: only between empty and a raft this PR carries`
					end
				end
				return nil
			end
			return `it carries {path}, which is not one of the raft's own items`
		end
		local reasons: { [string]: string } = {}
		local carried: { [string]: boolean } = {}
		for _, path in paths do
			local why = shapeOf(path)
			if why then
				reasons[path] = why
			else
				carried[path] = true
			end
		end
		only = function(path: string): string?
			if path == trackerstate.COUNTER then
				-- code review 005 F4: `./zn new` reserves ids on origin by its own push, so a rafting PR has no reason to
				-- carry the counter, and a bad one stops every capture
				return `it carries {path}: a rafting PR never carries the id counter`
			end
			if carried[path] then
				return nil
			end
			return reasons[path] or `it carries {path}, which is not one of the raft's own items`
		end
	end
	local why = trackerstate.check(
		gitFn,
		if okBase then base else trackerstate.EMPTY_TREE,
		ref,
		roots :: { string },
		{
			sequestered = true,
			own = own,
			allow = if gateName == "prep" then dispatch.isLesson else nil,
			only = only,
		}
	)
	if why then
		return why
	end
	-- code review 007 F2: the prep gate auto-merges too, so it is judged by the tracker's readers the same way (its
	-- issue's `raft:` line, if any, is held to the raft's own list)
	return dispatcher.backstop(
		ctx,
		pr.number,
		main,
		ref,
		roots :: { string },
		carriedRafts,
		if gateName == "prep" and folder ~= "" then `{folder}/{id}.md` else nil
	)
end

-- Code review 005 F2, 006 F1: the rafting gate's last word is the tracker's own readers on what the merge would make:
-- `git merge-tree` of today's main and the head (a conflict refuses: GitHub would not merge it either), then `audit`
-- over that tree and over main, and the rule `./zn ready` applies to each carried raft. A PR whose merged tree has an
-- audit error main does not, or a carried raft whose `issues:` and members disagree, is refused, whatever its shape.
function dispatcher.backstop(
	ctx: Ctx,
	number: number,
	main: string,
	ref: string,
	roots: { string },
	carriedRafts: { string },
	issueDoc: string?
): string?
	local root = ctx.mainRoot()
	local ok, out = git(root, { "merge-tree", "--write-tree", main, ref })
	if not ok then
		return "its merge with origin's main conflicts or could not be made"
	end
	local tree = string.match(out, "^(%x+)")
	if not tree then
		return "its merge with origin's main made no tree"
	end
	local paths = { projects.FILE, trackerstate.COUNTER }
	for _, r in roots do
		table.insert(paths, r)
	end
	-- a folder of this judgement alone (code review 007 F4), inside this checkout's dispatcher state, removed whole
	local base = `{root}/{HOME}/judge-{number}-{os.time()}-{math.random(1, 1000000000)}`
	local function cleanup()
		if fs.isDir(base) then
			pcall(fs.removeDir, base)
		end
	end
	local function audited(label: string, rev: string): ({ [string]: boolean }, string?, string?)
		local dir = `{base}/{label}`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		local tar = `{base}/{label}.tar`
		local here: { string } = {}
		for _, path in paths do
			if git(root, { "cat-file", "-e", `{rev}:{path}` }) then
				table.insert(here, path)
			end
		end
		local okA = #here > 0
			and git(root, { "archive", "--format=tar", "-o", tar, rev, "--", table.unpack(here) })
		local x = if okA then process.exec("tar", { "-xf", tar, "-C", dir }) else nil
		if not okA or not x or not x.ok then
			return {}, nil, `the {label} tree could not be exported for the audit`
		end
		local init = process.exec("git", { "init", "-q" }, { cwd = dir })
		if not init.ok or not fs.isDir(`{dir}/.git`) then
			return {}, nil, `the {label} tree could not be prepared for the audit`
		end
		local added = process.exec("git", { "add", "-A" }, { cwd = dir })
		if not added.ok then
			return {}, nil, `the {label} tree could not be prepared for the audit`
		end
		local okRun, problems = pcall(audit.run, dir)
		if not okRun then
			return {}, dir, `the audit of the {label} tree failed: {problems}`
		end
		local errs: { [string]: boolean } = {}
		for _, p in problems :: { audit.Problem } do
			if p.level == "error" then
				errs[audit.format(p)] = true
			end
		end
		return errs, dir, nil
	end
	local mainErrs, _, why = audited("main", main)
	local mergedErrs, mergedDir, why2 = audited("merged", tree)
	local result: string? = why or why2
	if not result then
		for line in mergedErrs do
			if not mainErrs[line] then
				result = `its merge would add an audit error: {line}`
				break
			end
		end
	end
	local rafts: { string } = table.clone(carriedRafts)
	if not result and mergedDir and issueDoc and fs.isFile(`{mergedDir}/{issueDoc}`) then
		local named = audit.front(fs.readFile(`{mergedDir}/{issueDoc}`)).raft
		if named and named ~= "" then
			table.insert(rafts, named)
		end
	end
	if not result and mergedDir then
		local okM, bad = pcall(audit.membership, mergedDir, rafts)
		if not okM then
			result = `the merged tree's raft membership could not be read: {bad}`
		elseif #(bad :: { string }) > 0 then
			result = `its merge would leave a carried raft inconsistent: {(bad :: { string })[1]}`
		end
	end
	cleanup()
	return result
end

-- What the chain sees of `id` now.
function dispatcher.facts(ctx: Ctx, st: State, id: string, description: string?): dispatch.Facts
	local o = if id ~= "" then ctx.origin(id) else nil
	local kind = if not o then "none" elseif store.isRaftId(id) then "raft" else "issue"
	local front: { [string]: string } = if o then o.front else {}
	local own = false
	for _, a in st.history do
		if a.step == "z-design" then
			own = true
		end
	end
	local localRaft = ""
	local rafting = `{ctx.mainRoot()}/.worktree/raft-{id}`
	if o and kind == "issue" and fs.isFile(`{rafting}/{o.path}`) then
		localRaft = store.readFront(`{rafting}/{o.path}`).raft or ""
	end
	local last = if st.outcome
			and st.step
			and st.outcome ~= "running"
		then { step = st.step :: string, outcome = st.outcome :: string }
		else nil
	local uncovered: { string } = {}
	if last and last.outcome == "ok" and st.worktree and id ~= "" then
		local ok, out = zn(st.worktree :: string, { "lessons", "--uncovered", id }, true)
		if not ok then
			for line in string.gmatch(out, "[^\n]+") do
				table.insert(uncovered, line)
			end
		end
	end
	local openHuman: { string } = {}
	if st.worktree and o and fs.isFile(`{st.worktree}/{o.path}`) then
		openHuman = openlist.pending(fs.readFile(`{st.worktree}/{o.path}`))
	end
	local pr: dispatch.Pr? = nil
	if o then
		local branch: string? = nil
		if kind == "issue" and o.status == "preparing" then
			branch = `prep-{front.slug or ""}`
		elseif kind == "issue" and o.status == "prepared" and (front.raft or "") == "" then
			branch = `raft-{id}`
		elseif kind == "raft" and o.state == "active" then
			branch = `{id}-{front.slug or ""}`
		end
		if branch then
			pr = dispatcher.parsePr(ctx.prView(branch :: string))
		end
	end
	local settings = dispatcher.settings(id)
	local folder = if o then (string.match(o.path, "^(.*)/[^/]+$") or "") else ""
	if pr and pr.state == "OPEN" and o and o.status ~= "active" and kind == "issue" then
		local gateName = if o.status == "preparing" then "prep" else "raft"
		local p = pr :: dispatch.Pr
		p.judged = dispatcher.judgePr(ctx, gateName, id, p, folder)
	end
	local root = ""
	if o then
		local known: { string } = rootsAt(ctx, guard.fresh or "origin/main") or {}
		for _, r in known do
			if string.sub(o.path, 1, #r + 1) == r .. "/" then
				root = r
			end
		end
	end
	return {
		folder = folder,
		root = root,
		id = id,
		kind = kind :: any,
		where = if o then o.state else "none",
		status = if o then o.status else "none",
		design = front.design or "",
		raft = front.raft or "",
		ownClaim = own,
		localRaft = localRaft,
		pr = pr,
		questions = fs.isFile(`{st.dir}/questions.md`),
		openHuman = openHuman,
		last = last,
		uncovered = uncovered,
		autoMerge = settings.autoMerge,
		description = description,
	}
end

local function describeAction(a: dispatch.Action): string
	if a.kind == "step" then
		return `next: {a.step} {a.target or ""}`
	elseif a.kind == "merge" then
		return `next: merge the {a.gate} PR #{a.pr}`
	end
	return `stop: {a.why}`
end

-- Merges a gate's PR itself, with the real gh and the user's credential (an agent never merges).
local function merge(ctx: Ctx, st: State, pr: number, head: string): boolean
	local gh = resolveBin("gh", dispatcher.realPath()) or "gh"
	-- pinned to the head the gate checked: a push to the branch since voids the merge (review 002 F6)
	local r = process.exec(
		gh,
		{ "pr", "merge", tostring(pr), "--squash", "--match-head-commit", head },
		{ stdio = "forward" }
	)
	if r.ok then
		table.insert(st.merged, pr)
		save(st)
		zn(ctx.mainRoot(), { "sync" }, true)
		-- the net repairs main after the landing; it returns at once and does not decide this merge
		zn(ctx.mainRoot(), { "watch-kick" }, true)
	end
	return r.ok
end

-- After a gate merge: the merge commit's first parent is the main the gate judged, or main moved over an item the PR
-- carries in between (a state the judgement never saw): why not, or nil. The merge is not undone; a human looks.
function dispatcher.afterMerge(ctx: Ctx, number: number, pr: dispatch.Pr?, id: string): string?
	if not pr or not pr.judgedMain then
		return nil
	end
	local root = ctx.mainRoot()
	-- the merge commit is what GitHub says it is, never a search of main's subjects (code review 008 F1); a failure to
	-- read it is a stop, because nothing was compared
	local gh = resolveBin("gh", dispatcher.realPath()) or "gh"
	local view = process.exec(gh, { "pr", "view", tostring(number), "--json", "mergeCommit" })
	local commit = ""
	if view.ok then
		local okj, j = pcall(function()
			return serde.decode("json", view.stdout)
		end)
		local mc = if okj and type(j) == "table" then (j :: any).mergeCommit else nil
		if type(mc) == "table" and type(mc.oid) == "string" and string.match(mc.oid, "^%x+$") then
			commit = mc.oid
		end
	end
	if commit == "" then
		return `PR #{number}: GitHub names no merge commit for it (a merge queue, a delay, or gh failing), so nothing was compared with the main it was judged against: look at main, then run ./zn dispatch retry {id}`
	end
	if not freshMain(ctx) or not (git(root, { "cat-file", "-e", `{commit}^\{commit\}` })) then
		return `PR #{number} merged as {commit}, which could not be fetched from origin, so nothing was compared with the main it was judged against: look at main, then run ./zn dispatch retry {id}`
	end
	local okP, parent = git(root, { "rev-parse", `{commit}^1` })
	if not okP then
		return `PR #{number} merged as {commit}, whose parent could not be read: look at main, then run ./zn dispatch retry {id}`
	end
	if parent == pr.judgedMain then
		return nil
	end
	local okD, names = git(root, { "diff", "--name-only", "--no-renames", pr.judgedMain :: string, parent })
	if not okD then
		return `PR #{number} merged as {commit} onto {parent}, not the main it was judged against ({pr.judgedMain}), and the difference could not be read: look at it, then run ./zn dispatch retry {id}`
	end
	local roots = rootsAt(ctx, parent) or {}
	local mine: { [string]: boolean } = {}
	local ids: { string } = pr.itemIds or {}
	for _, cid in ids do
		mine[cid] = true
	end
	for path in string.gmatch(names, "[^\n]+") do
		local pid = trackerstate.itemOf(path, roots)
		if pid and mine[pid :: string] then
			return `PR #{number} merged as {commit} onto {parent}, not the main it was judged against ({pr.judgedMain}), and main changed {path}, an item the PR carries: look at it, then run ./zn dispatch retry {id}`
		end
	end
	return nil
end

-- The chain on `id` (or a new issue from `description`), until a gate, questions.md, a failure or done.
function dispatcher.chain(ctx: Ctx, id: string, opts: { [string]: { string } }, given: State?): number
	local description: string? = opts["--description"] and opts["--description"][1]
	local st = given or load(ctx, if id == "" then "new" else id)
	if st.mode ~= "chain" and st.outcome ~= "tripwire" and st.outcome ~= "lost" then
		-- a one-step run's outcome is not the chain's: the chain reads its own steps only (a tripped wire or a lost
		-- step stops every run on the item until a human retries it)
		st.outcome = nil
	end
	st.mode = "chain"
	for _ = 1, dispatch.MAX_ACTIONS do
		local f = dispatcher.facts(ctx, st, id, description)
		local action = dispatch.next(f)
		print(describeAction(action))
		if opts["--dry-run"] then
			if action.kind == "step" and action.step and dispatch.STEPS[action.step] then
				local s = dispatch.STEPS[action.step :: string]
				if s.kind == "model" then
					local okr, r = pcall(dispatcher.resolve, action.step :: string, action.target or "", nil)
					if okr then
						for _, line in dispatch.describe(r :: models.Resolved) do
							print(line)
						end
					else
						print(`error: {r}`)
					end
				end
			end
			return 0
		end
		if action.kind == "stop" then
			if action.step == "flush" then
				flush(ctx, st)
			end
			save(st)
			return action.code or 1
		elseif action.kind == "merge" then
			if not merge(ctx, st, action.pr :: number, action.head or "") then
				print(`stop: the {action.gate} PR #{action.pr} did not merge`)
				return dispatch.EXIT.failure
			end
			-- code review 006 F2, 007 F3: GitHub merges into whatever main is by then, so what landed is compared with
			-- what was judged: a merge commit whose parent is another main, over items the PR carries, stops the run
			local moved = dispatcher.afterMerge(ctx, action.pr :: number, f.pr, id)
			if moved then
				-- recorded as an attempt of its own (code review 008 F2), so the next run reads a step and a detail and
				-- holds, whatever the item's earlier steps were
				table.insert(st.history, {
					step = "merge-check",
					cli = "",
					runtime = "",
					model = "",
					outcome = "tripwire",
					detail = moved,
					tokens = 0,
					minutes = 0,
				})
				st.step = "merge-check"
				st.outcome = "tripwire"
				st.detail = moved
				save(st)
				print(`stop: {moved}`)
				return dispatch.EXIT.tripwire
			end
		elseif action.step == "follow" then
			st.follows = action.target
			save(st)
			unlock(st.dir)
			id = action.target :: string
			local nextState = load(ctx, id)
			local refusal = lock(nextState.dir, false)
			if refusal then
				print(`stop: {refusal}`)
				return dispatch.EXIT.failure
			end
			nextState.mode = "chain"
			for _, a in st.history do
				table.insert(nextState.history, a)
			end
			st = nextState
		else
			local step = action.step :: string
			local target = action.target or ""
			local kind = dispatch.step(step).kind
			if kind == "script" then
				dispatcher.scriptStep(ctx, st, step, if step == "raft-plan" then id else target)
			else
				local o2 = table.clone(opts)
				if step == "z-ticket" then
					o2["--before"] = ctx.originIssueIds()
				elseif step == "z-raft" then
					o2["--for"] = { id }
				end
				local oldDir = st.dir
				dispatcher.modelStep(ctx, st, step, target, o2)
				if step == "z-ticket" and st.outcome == "ok" then
					id = st.id
					description = nil
					unlock(oldDir)
					lock(st.dir, true)
					save(st)
				end
			end
			zn(ctx.mainRoot(), { "sync" }, true)
		end
	end
	print(`stop: the chain ran {dispatch.MAX_ACTIONS} actions without reaching a gate`)
	return dispatch.EXIT.failure
end

-- Every state folder of `dir` and of the steps its steps dispatched, deepest last.
local function runsUnder(dir: string): { string }
	local out = { dir }
	if fs.isDir(dir) then
		for _, name in fs.readDir(dir) do
			if fs.isDir(`{dir}/{name}`) and fs.isFile(`{dir}/{name}/state.json`) then
				for _, d in runsUnder(`{dir}/{name}`) do
					table.insert(out, d)
				end
			end
		end
	end
	return out
end

-- Stops the step of `dir` (and every step it dispatched): the stop marker, then the group, only when it is still the
-- same run (its supervisor still holds the run's lock); otherwise it is marked lost and nothing is signalled.
local function stopAt(id: string, dir: string): string
	fs.writeDir(dir)
	sh.writeReplacing(`{dir}/{runner.STOP}`, now() .. "\n")
	local st = loadAt(id, dir)
	local said: string
	if st.run and runner.sameRun(st.run :: runner.Identity) then
		runner.killGroup((st.run :: runner.Identity).pgid)
		st.outcome, st.detail = "stopped", "stopped by ./zn dispatch stop"
		said = "stopped"
	elseif st.outcome == "running" and runner.held(`{dir}/lock`) then
		-- its dispatcher is alive and the step is starting: the marker stops it before the CLI starts (review 002 F10)
		return "stop requested (the step is starting)"
	elseif st.outcome == "running" then
		st.outcome, st.detail =
			"lost", "its process group is gone or is no longer this run's: nothing was signalled"
		said = "lost"
	else
		said = "not running"
	end
	st.run = nil
	save(st)
	return said
end

-- `./zn dispatch …`
local mainInner: (ctx: Ctx, pos: { string }, opts: { [string]: { string } }) -> number

-- `./zn dispatch …`; its own fetch refs go at its end, whatever happened (review 005 F1)
function dispatcher.main(ctx: Ctx, pos: { string }, opts: { [string]: { string } }): number
	local ok, code = pcall(mainInner, ctx, pos, opts)
	pcall(dropRefs, ctx.mainRoot())
	if not ok then
		error(code, 0)
	end
	return code :: number
end

function mainInner(ctx: Ctx, pos: { string }, opts: { [string]: { string } }): number
	local first = pos[1]
	if not first then
		ctx.fail(
			'usage: ./zn dispatch <id> | new "<description>" | <step> <id> [--mode design|code|raft|stream] | stop|retry|status <id>'
		)
	end
	if first == "vet" then
		ctx.fail(
			"dispatch vet is gone: a run accepts main as it is when it starts; ./zn dispatch retry <id> continues an item a tripwire stopped"
		)
	elseif first == "status" then
		local id = pos[2] or ctx.fail("usage: ./zn dispatch status <id>")
		for _, dir in runsUnder(dirOf(ctx, id)) do
			print(serde.encode("json", loadAt(id, dir), true))
		end
		return 0
	elseif first == "stop" then
		local id = pos[2] or ctx.fail("usage: ./zn dispatch stop <id>")
		local runs = runsUnder(dirOf(ctx, id))
		for i = #runs, 1, -1 do
			print(`dispatch: {id} ({runs[i]}): {stopAt(id, runs[i])}`)
		end
		return 0
	elseif first == "retry" then
		local id = pos[2] or ctx.fail("usage: ./zn dispatch retry <id>")
		local dir = dirOf(ctx, id)
		local refusal = lock(dir, true)
		if refusal then
			print(`stop: {refusal}`)
			return dispatch.EXIT.failure
		end
		local st = load(ctx, id)
		-- every run that starts a step starts through the same guards (code review 001 F2): pin origin, then
		-- accept main as it is; `top` (`<id>`, `new`, `<step> <id>`) and `retry` are the only two entry points
		-- that run steps (`status` and `stop` start none)
		local unvetted = dispatcher.guardStart(ctx, st)
		if unvetted then
			st.outcome, st.detail = "tripwire", unvetted
			save(st)
			unlock(dir)
			print(`stop: {unvetted}`)
			return dispatch.EXIT.tripwire
		end
		flush(ctx, st)
		local q = `{dir}/questions.md`
		if fs.isFile(q) then
			local n = 1
			while fs.isFile(`{dir}/answered-{n}.md`) do
				n += 1
			end
			fs.move(q, `{dir}/answered-{n}.md`)
		end
		local step, mode = st.step, st.mode
		st.outcome, st.detail = nil, nil
		save(st)
		local code: number
		if mode == "step" and step then
			local o2 = table.clone(opts)
			if st.reviewMode then
				o2["--mode"] = { st.reviewMode :: string }
			end
			code = dispatcher.oneStep(ctx, step :: string, id, o2, st)
		else
			code = dispatcher.chain(ctx, id, opts, st)
		end
		unlock(dir)
		return code
	elseif first == "new" then
		local words = pos[2] or ctx.fail('usage: ./zn dispatch new "<description>" [--project <name>]')
		local o2 = table.clone(opts)
		o2["--description"] = { words }
		return dispatcher.top(ctx, "", o2, function(st: State): number
			return dispatcher.chain(ctx, "", o2, st)
		end)
	elseif
		dispatch.STEPS[first]
		or dispatch.READ_INSIDE[first]
		or string.match(first, "^[a-z][a-z0-9]*%-")
	then
		local id = pos[2] or ctx.fail(`usage: ./zn dispatch {first} <id>`)
		return dispatcher.oneStep(ctx, first, id, opts)
	end
	return dispatcher.top(ctx, first, opts, function(st: State): number
		return dispatcher.chain(ctx, first, opts, st)
	end)
end

-- A top-level run: --dry-run takes no lock and writes nothing; any other takes the item's run lock.
function dispatcher.top(ctx: Ctx, id: string, opts: { [string]: { string } }, body: (State) -> number): number
	local key = if id == "" then "new" else id
	if opts["--dry-run"] then
		return body(blank(key, dirOf(ctx, key)))
	end
	local dir = dirOf(ctx, key)
	local refusal = lock(dir, false)
	if refusal then
		print(`stop: {refusal}`)
		return dispatch.EXIT.failure
	end
	local st = load(ctx, key)
	if st.outcome == "running" then
		-- the run lock is free, so the dispatcher that left this running is gone: its step is lost, never resumed
		st.outcome, st.detail, st.run = "lost", "its dispatcher died mid-step", nil
		save(st)
		unlock(dir)
		print(`stop: {key}'s last step was lost (its dispatcher died): ./zn dispatch retry {key}`)
		return dispatch.EXIT.failure
	end
	-- main is accepted as it is at the start of every run; during the run, vetMain judges commits since that tip
	local unvetted = dispatcher.guardStart(ctx, st)
	if unvetted then
		st.outcome, st.detail = "tripwire", unvetted
		save(st)
		unlock(dir)
		print(`stop: {unvetted}`)
		return dispatch.EXIT.tripwire
	end
	flush(ctx, st)
	save(st)
	local ok, code = pcall(body, st)
	unlock(dir)
	if not ok then
		error(code, 0)
	end
	return code :: number
end

-- One step on one item (`./zn dispatch <step> <id>`); --dry-run prints its plan and starts nothing. A step started
-- from inside a dispatched step (a review from its author) gets a state folder of its own under the author's.
function dispatcher.oneStep(
	ctx: Ctx,
	step: string,
	id: string,
	opts: { [string]: { string } },
	given: State?
): number
	local s = dispatch.step(step)
	local mode = opts["--mode"] and opts["--mode"][1]
	if step == "zz-review" then
		dispatch.lessonsOf(step, mode)
	end
	if opts["--dry-run"] then
		print(`step={step} id={id} kind={s.kind}`)
		if s.kind == "script" then
			print(`run={table.concat(dispatch.scriptArgv(step, id), " ")}`)
		else
			for _, line in dispatch.describe(dispatcher.resolve(step, id, nil, mode)) do
				print(line)
			end
		end
		return 0
	end
	local parent = process.env.ZN_DISPATCH_DIR
	if not given and parent and parent ~= "" then
		-- claimed atomically: a plain mkdir (no -p) fails when another nested step took the name first (review 002 F11)
		local n = 1
		while true do
			local name = `{parent}/{step}-{mode or "step"}-{id}-{n}`
			if process.exec("mkdir", { name }).ok then
				nested = name
				break
			end
			n += 1
			if n > 1000 then
				error(`could not claim a state folder under {parent}`, 0)
			end
		end
	end
	local function body(st: State): number
		st.mode = "step"
		local outcome = if s.kind == "script"
			then dispatcher.scriptStep(ctx, st, step, id)
			else dispatcher.modelStep(ctx, st, step, id, opts)
		if fs.isFile(`{st.dir}/questions.md`) then
			print(`stop: needs the user: answer {st.dir}/questions.md, then ./zn dispatch retry {id}`)
			return dispatch.EXIT.user
		end
		if outcome == "tripwire" then
			return dispatch.EXIT.tripwire
		end
		return if outcome == "ok" then 0 else dispatch.EXIT.failure
	end
	if given then
		return body(given)
	end
	if nested then
		local stop = keepBeating(nested :: string)
		local ok, code = pcall(body, load(ctx, id))
		stop()
		if not ok then
			error(code, 0)
		end
		return code
	end
	return dispatcher.top(ctx, id, opts, body)
end

return dispatcher
