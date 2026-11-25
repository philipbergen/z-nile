--!strict
-- d0434: `./zn restack <R-id> [--continue | --abort]`. Rebase each layer of a raft onto the one below, and push each
-- layer that moved on its own, as soon as its check.sh has passed and before the next layer is restacked (the owner's
-- ruling of 2026-11-22). A stop (conflict, red check, refused lease) leaves the layers below it pushed and it and the
-- layers above it not. A conflict leaves that rebase in progress in the raft's worktree and says which files; the worker resolves them and
-- runs `--continue`, which finishes the rebase and walks the stack again from the bottom (every layer already stacked
-- is skipped, so nothing is restarted). The marker (restackplan.luau) is written when a run starts and holds what
-- `--abort` and the lease need. The decisions are restackplan's; the git calls are here.
local fs = require("@lune/fs")
local layergit = require("./layergit")
local process = require("@lune/process")
local restackplan = require("./restackplan")
local sh = require("../lib/sh")
local stack = require("./stack")
local stdio = require("@lune/stdio")
local store = require("./store")

local restackcmd = {}

export type Deps = {
	fail: (string) -> never,
	hasOrigin: () -> boolean,
	runCheck: (store.Item) -> boolean,
}

local CONFLICT_EXIT = 3 -- distinct from success (0) and from every other refusal (1)

-- A crash seam for the specs: with ZN_RESTACK_KILL=<point> set, the run exits where a crash would hurt (around a push).
-- Nothing sets it outside the specs.
local function killAt(point: string)
	if process.env.ZN_RESTACK_KILL == point then
		process.exit(137)
	end
end

local function gitDir(): string
	return sh.trim(sh.git({ "rev-parse", "--absolute-git-dir" }))
end

local function stateFile(): string
	return `{gitDir()}/zn-restack.state`
end

local function rebaseOn(): boolean
	local dir = gitDir()
	return fs.isDir(`{dir}/rebase-merge`) or fs.isDir(`{dir}/rebase-apply`)
end

local function readState(): restackplan.State?
	local path = stateFile()
	if not fs.isFile(path) then
		return nil
	end
	return restackplan.parseState(fs.readFile(path))
end

local function writeState(state: restackplan.State)
	sh.writeReplacing(stateFile(), restackplan.renderState(state))
end

local function isAncestor(a: string, b: string): boolean
	return sh.run("git", { "merge-base", "--is-ancestor", a, b }).ok
end

local function unmergedFiles(): { string }
	return restackplan.lines(sh.run("git", { "diff", "--name-only", "--diff-filter=U" }).stdout)
end

local function dirty(): boolean
	return sh.git({ "status", "--porcelain" }) ~= ""
end

-- Back on the branch the run started on (or the commit, when it started detached).
local function switchBack(state: restackplan.State)
	if state.back ~= "" then
		if sh.git({ "branch", "--show-current" }) ~= state.back then
			sh.git({ "switch", "--quiet", state.back })
		end
	elseif state.start ~= "" and sh.trim(sh.git({ "rev-parse", "HEAD" })) ~= state.start then
		sh.git({ "switch", "--quiet", "--detach", state.start })
	end
end

-- The layer a restack's rebase is stopped on: the marker's, or (a marker written before the stop was recorded) the
-- branch git is rebasing.
local function stoppedAt(state: restackplan.State): string
	if state.conflict ~= "" then
		return state.conflict
	end
	local path = `{gitDir()}/rebase-merge/head-name`
	if fs.isFile(path) then
		local name = string.gsub(fs.readFile(path), "%s+$", "")
		return (string.gsub(name, "^refs/heads/", ""))
	end
	return ""
end

local function count(range: string): number
	local r = sh.run("git", { "rev-list", "--count", "--no-merges", range })
	return if r.ok then tonumber(sh.trim(r.stdout)) or 0 else 0
end

-- The commit `git rebase --onto <below> <upstream> <layer>` starts after: the layer's own commits only. Nil when the
-- tip and the layer below share no commit.
local function upstreamOf(layer: stack.Layer, raftId: string, tip: string, onto: string): string?
	local fork = sh.run("git", { "merge-base", tip, onto })
	if not fork.ok then
		return nil
	end
	local forkSha = sh.trim(fork.stdout)
	local tipSubject = sh.trim(sh.git({ "log", "-1", "--format=%s", tip }))
	local tipParent = sh.trim(sh.git({ "rev-parse", `{tip}^` }))
	local parentInLower = isAncestor(tipParent, onto)
	local raw = sh.git({ "log", "--reverse", "--format=%s%x00%P", `{forkSha}..{tip}` })
	local rows: { stack.CommitRow } = {}
	for subject, parents in string.gmatch(raw .. "\n", "(.-)%z(.-)\n") do
		local text = if type(parents) == "string" then parents else ""
		local matched = string.match(text, "%S+")
		table.insert(rows, {
			subject = if type(subject) == "string" then subject else "",
			parent = if type(matched) == "string" then matched else "",
		})
	end
	return stack.rebaseUpstream(layer.issue, raftId, tipSubject, tipParent, parentInLower, rows) or forkSha
end

-- Stops the run on a content conflict: the rebase stays, the marker says where, the exit code is 3.
local function stopOnConflict(raft: string, layer: string, own: number, state: restackplan.State): never
	local files = unmergedFiles()
	state.conflict = layer
	state.red = ""
	state.redSha = ""
	state.own = own
	state.files = files
	writeState(state)
	stdio.ewrite(restackplan.conflictMessage(raft, layer, files, restackplan.published(state)) .. "\n")
	return process.exit(CONFLICT_EXIT)
end

-- f0399: the first layer of a raft built on a raft that has landed has its pull request retargeted to main.
local function retarget(layer: stack.Layer, wasOn: boolean, basePr: string)
	if not (layer.position == 1 and wasOn and basePr == "main") then
		return
	end
	local listed = sh.run("gh", {
		"pr",
		"list",
		"--head",
		layer.name,
		"--state",
		"open",
		"--json",
		"number",
		"-q",
		".[0].number",
	})
	local number = if listed.ok then sh.trim(listed.stdout) else ""
	if number ~= "" and number ~= "null" then
		if not sh.run("gh", { "pr", "edit", number, "--base", "main" }).ok then
			stdio.ewrite(
				`warning: could not retarget the pull request for {layer.name} to main: gh pr edit {number} --base main\n`
			)
		end
	end
end

-- One layer, on its own, against the tip origin had when this run judged it (after its fetch).
local function pushLayer(layer: stack.Layer, lease: string, raftId: string, published: { string }): string?
	if not stack.owns(layer.name, raftId) then
		return `{layer.name} is not a layer of {raftId}`
	end
	local pushed = sh.run("git", {
		"push",
		"--quiet",
		`--force-with-lease=refs/heads/{layer.name}:{lease}`,
		"origin",
		layer.name,
	})
	if not pushed.ok then
		local why = restackplan.pushReason(pushed.stderr) -- never git's own words: they carry the remote's address
		return restackplan.refusedPushMessage(raftId, layer.name, published, why)
	end
	return nil
end

local function remoteTip(layer: string): string
	local r = sh.run("git", { "ls-remote", "origin", `refs/heads/{layer}` })
	return if r.ok then string.match(r.stdout, "^(%x+)") or "" else ""
end

-- A push the run wrote down before it started (`pushing`) and did not record: origin says whether it landed. When it
-- did, the layer counts as pushed (refs/zn/pushed, the marker's `pushed` line, the remote-tracking ref); either way the
-- entry is done with.
local function reconcile(state: restackplan.State)
	local changed = false
	for name, sha in state.pushing do
		if remoteTip(name) == sha then
			layergit.notePushed(name, sha)
			state.pushed[name] = sha
			sh.run("git", { "update-ref", `refs/remotes/origin/{name}`, sha })
		end
		state.pushing[name] = nil
		changed = true
	end
	if changed then
		writeState(state)
	end
end

-- Walks the stack from the bottom. `state` is what `--abort` and the lease need; `continued` says a conflict was just
-- resolved.
local function walkBody(raft: store.Item, deps: Deps, state: restackplan.State, continued: boolean)
	local function bail(msg: string): never
		switchBack(state)
		return deps.fail(msg)
	end
	local layers = layergit.layersOf(raft.id)
	if #layers == 0 then
		bail(`{raft.id} has no layers`)
	end
	layergit.buildBase(raft)
	local baseTip, basePr = layergit.raftBase(raft.id)
	local wasOn = layergit.readyRecord(raft.id).on ~= nil
	local hasRemote = deps.hasOrigin()
	state.red = ""
	state.redSha = ""
	local below = baseTip
	local rebased = continued
	local pushedAny = false
	local function left(name: string, sha: string)
		if state.left[name] ~= sha then
			state.left[name] = sha
			writeState(state)
		end
	end
	-- where the run leaves a branch it did not move is where `--abort` finds it
	local function noteLeft(layer: stack.Layer)
		local now = layergit.shaOf(`refs/heads/{layer.name}`)
		if now then
			left(layer.name, now)
		end
	end
	for _, layer in layers do
		local onto = if layer.position == 1 then baseTip else below
		local localSha = layergit.shaOf(`refs/heads/{layer.name}`)
		local originSha = layergit.shaOf(`refs/remotes/origin/{layer.name}`)
		local facts: restackplan.Facts = {
			hasRemote = hasRemote,
			hasLocal = localSha ~= nil,
			hasOrigin = originSha ~= nil,
			localExtra = localSha ~= nil and originSha ~= nil and not isAncestor(localSha, originSha),
			originExtra = localSha ~= nil and originSha ~= nil and not isAncestor(originSha, localSha),
			foreign = false,
			ontoInTip = false,
		}
		local from = restackplan.source(facts)
		local tip = if from == "local" then localSha else originSha
		if tip == nil then
			bail(`{layer.name} has no tip`)
		end
		facts.ontoInTip = isAncestor(onto, tip :: string)
		if from == "local" and facts.originExtra then
			-- both sides hold commits the other lacks: the local branch is only a rewrite of origin's when this clone
			-- pushed origin's tip itself (refs/zn/pushed)
			facts.foreign = not restackplan.trusted(originSha :: string, layergit.pushedTip(layer.name))
		end
		local plan = restackplan.decide(facts)
		if plan.action == "foreign" then
			bail(
				`restack stopped at {layer.name}: origin's branch ({originSha}) holds a commit that your local branch ({localSha}) was never based on, so it is someone else's work. Nothing was changed for this layer or any after it. To go on: git fetch, rebuild your commits on origin's tip ({originSha}) (rebase {layer.name} onto origin/{layer.name}), then run ./zn restack {raft.id} again; or ask whoever pushed it.`
			)
		end
		local before = tip :: string
		if state.conflict == layer.name and plan.action ~= "rebase" and state.own > 0 then
			if restackplan.emptied(state.own, count(`{onto}..{before}`)) then
				bail(
					`restack stopped at {layer.name}: the resolution emptied a commit of {layer.issue}: its change is already below; stop and ask the owner. Do not git rebase --skip and do not commit it empty. ./zn restack {raft.id} --abort puts every branch back.`
				)
			end
		end
		if plan.action == "skip" then
			noteLeft(layer)
			below = before
			continue
		end
		layergit.checkoutLayer(layer)
		local ownBefore = 0
		if plan.action == "rebase" then
			-- the branch holds no commit that origin's lacks when it is taken from origin: moving it is safe
			if sh.trim(sh.git({ "rev-parse", "HEAD" })) ~= before then
				sh.git({ "reset", "--hard", before })
			end
			left(layer.name, before)
			local upstream = upstreamOf(layer, raft.id, before, onto)
			if not upstream then
				bail(`restack stopped at {layer.name}: no common base`)
			end
			ownBefore = count(`{upstream :: string}..{before}`)
			local rebasing = sh.run(
				"git",
				{ "-c", "rerere.enabled=false", "rebase", "--onto", onto, upstream :: string, layer.name }
			)
			if not rebasing.ok then
				if rebaseOn() then
					stopOnConflict(raft.id, layer.name, ownBefore, state)
				end
				bail(`restack stopped at {layer.name}: the rebase failed\n{rebasing.stderr}`)
			end
			if restackplan.emptied(ownBefore, count(`{onto}..HEAD`)) then
				sh.git({ "reset", "--hard", before })
				bail(
					`restack stopped at {layer.name}: the rebase emptied a commit of {layer.issue}: its change is already below; stop and ask the owner. Do not git rebase --skip and do not commit it empty. {layer.name} and the layers above it were not pushed.`
				)
			end
			rebased = true
			left(layer.name, sh.trim(sh.git({ "rev-parse", "HEAD" })))
		end
		local issue = store.find(layer.issue)
		if not issue or not deps.runCheck(issue) then
			if sh.lastCode == sh.NOT_STARTED then
				-- the machine-wide gate queue was busy: the check never ran, so nothing is red. The restacked tip stays
				-- on the branch (as for a red check) and the marker keeps `left` for it, with no `red` line: the next
				-- plain restack, or --continue, finds the layer local-ahead and trusted (refs/zn/pushed) and runs the
				-- check again. The worktree goes back to the starting branch like any stop.
				state.red = ""
				state.redSha = ""
				writeState(state)
				switchBack(state)
				stdio.ewrite(
					`restack stopped at {layer.name}: the check of {layer.issue} did not start, so nothing is red and nothing was pushed for {layer.name} or the layers above it. Run ./zn restack {raft.id} again (or ./zn restack {raft.id} --continue).\n`
				)
				sh.exitIfNotStarted()
			end
			-- the restacked tip stays on the branch, unpushed: it is the worker's to fix, and the next run trusts it
			state.red = layer.name
			state.redSha = sh.trim(sh.git({ "rev-parse", "HEAD" }))
			writeState(state)
			bail(restackplan.redMessage(raft.id, layer.name, layer.issue, restackplan.published(state)))
		end
		local now = sh.trim(sh.git({ "rev-parse", "HEAD" }))
		noteLeft(layer)
		if hasRemote and (originSha == nil or now ~= originSha) then
			-- passed: pushed now, before the next layer is restacked
			-- leased on the tip this run itself pushed for the layer, when it did (a second pass over a layer it already
			-- pushed), else on the origin tip judged after the run's fetch ("" : the layer must not exist there)
			local lease = state.pushed[layer.name] or state.judged[layer.name] or ""
			state.pushing[layer.name] = now
			writeState(state)
			killAt("before-push")
			local problem = pushLayer(layer, lease, raft.id, restackplan.published(state))
			if problem then
				state.pushing[layer.name] = nil
				writeState(state)
				bail(problem)
			end
			killAt("after-push")
			layergit.notePushed(layer.name, now) -- only now that the push succeeded
			killAt("after-note")
			state.pushed[layer.name] = now
			state.pushing[layer.name] = nil
			writeState(state)
			pushedAny = true
			retarget(layer, wasOn, basePr)
		end
		below = now
	end
	if fs.isFile(stateFile()) then
		fs.removeFile(stateFile())
	end
	switchBack(state)
	if rebased or pushedAny then
		require("./liveemit").emit(
			"restacked",
			{ raft = raft.id, project = require("./liveemit").projectOf(raft.root) }
		)
		print(`restacked {raft.id}`)
	else
		print(`{raft.id} is already stacked`)
	end
end

-- Any error mid-walk leaves the worktree on the branch the run started on.
local function walk(raft: store.Item, deps: Deps, state: restackplan.State, continued: boolean)
	local ok, err = pcall(function()
		walkBody(raft, deps, state, continued)
	end)
	if not ok then
		pcall(switchBack, state)
		error(err, 0)
	end
end

local function start(raft: store.Item, deps: Deps)
	if rebaseOn() then
		local state = readState()
		if state and state.raft == raft.id then
			deps.fail(restackplan.inProgressMessage(state.raft, stoppedAt(state)))
		end
		deps.fail(
			`a git rebase is in progress in this worktree and it is not a restack's: finish it (git rebase --continue) or git rebase --abort, then run ./zn restack {raft.id} again`
		)
	end
	-- refused before any marker is read or removed: a refusal changes nothing
	if dirty() then
		deps.fail("working tree is not clean")
	end
	local old: restackplan.State? = nil
	if fs.isFile(stateFile()) then
		-- a marker with no rebase behind it: the run that wrote it stopped. A push it left unrecorded is noted first, and
		-- its record is kept below for the branches it still describes (review 001 F6)
		old = readState()
		if old and old.raft ~= raft.id then
			old = nil
		end
		if old and deps.hasOrigin() then
			reconcile(old)
		end
		fs.removeFile(stateFile())
	end
	if deps.hasOrigin() then
		sh.git({ "fetch", "--quiet", "origin" })
	end
	local why = layergit.oldShapeRefusal(raft)
	if why then
		deps.fail(why)
	end
	local orig: { { name: string, sha: string } } = {}
	local judged: { [string]: string } = {}
	local left: { [string]: string } = {}
	local pushed: { [string]: string } = {}
	for _, layer in layergit.layersOf(raft.id) do
		local now = layergit.shaOf(`refs/heads/{layer.name}`) or ""
		-- the origin tip this run judges (after its fetch): every push of the run, and of its --continue, is leased on it
		judged[layer.name] = layergit.shaOf(`refs/remotes/origin/{layer.name}`) or ""
		local keptOrig, keptPushed = restackplan.carried(old, layer.name, now, judged[layer.name])
		table.insert(orig, { name = layer.name, sha = keptOrig or now })
		if now ~= "" then
			left[layer.name] = now -- where this run finds it
		end
		if keptPushed then
			pushed[layer.name] = keptPushed
		end
	end
	local state: restackplan.State = {
		raft = raft.id,
		back = sh.git({ "branch", "--show-current" }),
		start = sh.trim(sh.git({ "rev-parse", "HEAD" })),
		orig = orig,
		judged = judged,
		left = left,
		pushed = pushed,
		pushing = {},
		red = "",
		redSha = "",
		conflict = "",
		own = 0,
		files = {},
	}
	writeState(state)
	walk(raft, deps, state, false)
end

-- `<sha> <subject> (<date>)` of a commit, for a refusal that names it.
local function described(sha: string): string
	local r = sh.run("git", { "log", "-1", "--date=iso", "--format=%H %s (%cd)", sha })
	return if r.ok then sh.trim(r.stdout) else sha
end

-- The layers the run moved or pushed that are no longer where it left them, nor built on it (review 001 F5).
local function straysOf(state: restackplan.State): { restackplan.Stray }
	local out: { restackplan.Stray } = {}
	for _, o in state.orig do
		local now = layergit.shaOf(`refs/heads/{o.name}`) or ""
		local left = state.left[o.name] or ""
		local onLeft = now ~= "" and left ~= "" and isAncestor(left, now)
		if
			restackplan.strayed(now, o.sha, left, state.pushed[o.name], layergit.pushedTip(o.name), onLeft)
		then
			local fork = sh.run("git", { "merge-base", left, now })
			local log = sh.run("git", { "log", "--oneline", `{left}..{now}` })
			table.insert(out, {
				layer = o.name,
				atOrig = now == o.sha,
				left = described(left),
				now = described(now),
				log = if log.ok then sh.trim(log.stdout) else "",
				base = if fork.ok then sh.trim(fork.stdout) else left,
			})
		end
	end
	return out
end

local function continueRun(raft: store.Item, deps: Deps)
	local state = readState()
	if not state or state.raft ~= raft.id then
		deps.fail(
			`no restack of {raft.id} is in progress: nothing to continue (./zn restack {raft.id} starts one)`
		)
	end
	local st = state :: restackplan.State
	if deps.hasOrigin() then
		reconcile(st)
	end
	local strays = straysOf(st)
	if #strays > 0 then
		deps.fail(restackplan.strayedMessage(raft.id, strays))
	end
	if rebaseOn() then
		local unmerged = unmergedFiles()
		local marked: { string } = {}
		st.conflict = stoppedAt(st)
		local files: { string } = if #st.files > 0 then st.files else unmerged
		if #files > 0 then
			local args = { "diff", "--check", "HEAD", "--" }
			for _, f in files do
				table.insert(args, f)
			end
			local checked = sh.run("git", args)
			marked = restackplan.markers(checked.stdout .. "\n" .. checked.stderr)
		end
		if #unmerged > 0 or #marked > 0 then
			deps.fail(restackplan.unresolvedMessage(raft.id, unmerged, marked))
		end
		local went = process.exec(
			"git",
			{ "-c", "core.editor=true", "-c", "rerere.enabled=false", "rebase", "--continue" },
			{ env = { GIT_EDITOR = "true" } }
		)
		if not went.ok then
			if rebaseOn() then
				stopOnConflict(raft.id, st.conflict, st.own, st)
			end
			deps.fail(`restack of {raft.id} could not continue the rebase:\n{went.stderr}{went.stdout}`)
		end
		-- the resolved layer is where the run now leaves it: an abort that follows must find it there
		local resolvedTip = layergit.shaOf(`refs/heads/{st.conflict}`)
		if resolvedTip then
			st.left[st.conflict] = resolvedTip
			writeState(st)
		end
	elseif dirty() then
		deps.fail(
			`restack of {raft.id} cannot continue: the worktree has uncommitted changes and no rebase is in progress. Commit or discard them first.`
		)
	end
	walk(raft, deps, st, true)
end

local function abortRun(raft: store.Item, deps: Deps)
	local state = readState()
	if not state or state.raft ~= raft.id then
		deps.fail(`no restack of {raft.id} is in progress: nothing to abort`)
	end
	local st = state :: restackplan.State
	if deps.hasOrigin() then
		reconcile(st) -- a push the run was killed around counts when origin has it
	end
	local rebasing = rebaseOn()
	if not rebasing and dirty() then
		deps.fail(
			`restack of {raft.id} cannot be aborted: the worktree has uncommitted changes and no rebase is in progress. Commit or discard them first.`
		)
	end
	-- a branch somebody moved since the run left it is not the run's to move back, or to delete
	local moved: { string } = {}
	for _, o in st.orig do
		local current = layergit.shaOf(`refs/heads/{o.name}`) or ""
		-- where the run found it, where it left it, or for a pushed layer the tip it pushed
		if restackplan.abortRefuses(current, o.sha, st.left[o.name] or "", st.pushed[o.name]) then
			table.insert(moved, o.name)
		end
	end
	if #moved > 0 then
		deps.fail(
			`restack of {raft.id} cannot be aborted: {table.concat(moved, ", ")} moved since the restack left it. Nothing was changed. Put the branch back (or decide it is yours) and run ./zn restack {raft.id} --abort again.`
		)
	end
	if rebasing then
		sh.git({ "rebase", "--abort" })
	end
	sh.git({ "reset", "--hard", "--quiet" })
	if st.back == "" then
		sh.git({ "switch", "--quiet", "--detach", if st.start ~= "" then st.start else "HEAD" })
	else
		sh.git({ "switch", "--quiet", st.back })
	end
	local current = sh.git({ "branch", "--show-current" })
	for _, o in st.orig do
		local now = layergit.shaOf(`refs/heads/{o.name}`) or ""
		-- where the run found it, or the tip it pushed: origin is never moved back, and a branch the run created and
		-- pushed is kept
		local target = restackplan.restoreTo(st, o.name, o.sha)
		if now == target then
			continue
		elseif target == "" then
			sh.git({ "update-ref", "-d", `refs/heads/{o.name}` })
		elseif o.name == current then
			sh.git({ "reset", "--hard", "--quiet", target })
		else
			sh.git({ "update-ref", `refs/heads/{o.name}`, target })
		end
	end
	fs.removeFile(stateFile())
	print(restackplan.abortMessage(raft.id, restackplan.published(st)))
end

function restackcmd.run(raft: store.Item, mode: string, deps: Deps)
	if mode == "continue" then
		continueRun(raft, deps)
	elseif mode == "abort" then
		abortRun(raft, deps)
	else
		start(raft, deps)
	end
end

return restackcmd
