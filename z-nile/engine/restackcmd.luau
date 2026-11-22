--!strict
-- d0434: `./zn restack <R-id> [--continue | --abort]`. Rebase each layer of a raft onto the one below. A conflict
-- leaves that rebase in progress in the raft's worktree and says which files; the worker resolves them and runs
-- `--continue`, which finishes the rebase and then walks the stack again from the bottom (every layer already
-- stacked is skipped, so nothing is restarted). The decisions are restackplan's; the git calls are here.
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

local function stateFile(): string
	return `{sh.trim(sh.git({ "rev-parse", "--absolute-git-dir" }))}/zn-restack.state`
end

local function rebaseOn(): boolean
	local dir = sh.trim(sh.git({ "rev-parse", "--absolute-git-dir" }))
	return fs.isDir(`{dir}/rebase-merge`) or fs.isDir(`{dir}/rebase-apply`)
end

local function readState(): restackplan.State?
	local path = stateFile()
	if not fs.isFile(path) then
		return nil
	end
	return restackplan.parseState(fs.readFile(path))
end

local function isAncestor(a: string, b: string): boolean
	return sh.run("git", { "merge-base", "--is-ancestor", a, b }).ok
end

local function unmergedFiles(): { string }
	return restackplan.lines(sh.run("git", { "diff", "--name-only", "--diff-filter=U" }).stdout)
end

local function switchBack(back: string)
	if back ~= "" and sh.git({ "branch", "--show-current" }) ~= back then
		sh.git({ "switch", "--quiet", back })
	end
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

local function subjects(range: string): { string }
	return restackplan.lines(sh.run("git", { "log", "--no-merges", "--format=%s", range }).stdout)
end

-- Origin's own commits of the layer whose subject is on neither the local branch's own commits nor the layer below.
local function foreignOnOrigin(
	layer: stack.Layer,
	raftId: string,
	localSha: string,
	originSha: string,
	onto: string
): { string }
	local theirs = upstreamOf(layer, raftId, originSha, onto)
	if not theirs then
		return {}
	end
	local known = subjects(`{onto}`)
	local mine = upstreamOf(layer, raftId, localSha, onto)
	if mine then
		for _, s in subjects(`{mine}..{localSha}`) do
			table.insert(known, s)
		end
	end
	return restackplan.foreignSubjects(subjects(`{theirs}..{originSha}`), known)
end

local function writeState(state: restackplan.State)
	sh.writeReplacing(stateFile(), restackplan.renderState(state))
end

-- Stops the run on a content conflict: the rebase stays, the marker says where, the exit code is 3.
local function stopOnConflict(raft: string, layer: string, state: restackplan.State): never
	local files = unmergedFiles()
	state.conflict = layer
	writeState(state)
	stdio.ewrite(restackplan.conflictMessage(raft, layer, files) .. "\n")
	return process.exit(CONFLICT_EXIT)
end

local function publish(layer: stack.Layer, raftId: string, deps: Deps, remote: string?)
	if not deps.hasOrigin() then
		return
	end
	if not stack.owns(layer.name, raftId) then
		deps.fail(`{layer.name} is not a layer of {raftId}`)
	end
	if remote then
		sh.git({
			"push",
			"--quiet",
			`--force-with-lease=refs/heads/{layer.name}:{remote}`,
			"origin",
			layer.name,
		})
	else
		sh.git({ "push", "--quiet", "-u", "origin", layer.name })
	end
end

-- f0399: the first layer of a raft built on a raft that has landed has its pull request retargeted to main.
local function retarget(layer: stack.Layer, wasOn: boolean, basePr: string, deps: Deps)
	if not (layer.position == 1 and wasOn and basePr == "main" and deps.hasOrigin()) then
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

-- Walks the stack from the bottom. `state` is what an abort needs; `continued` says a conflict was just resolved.
local function walk(raft: store.Item, deps: Deps, state: restackplan.State, continued: boolean)
	local layers = layergit.layersOf(raft.id)
	if #layers == 0 then
		deps.fail(`{raft.id} has no layers`)
	end
	layergit.buildBase(raft)
	local baseTip, basePr = layergit.raftBase(raft.id)
	local wasOn = layergit.readyRecord(raft.id).on ~= nil
	local below = baseTip
	local moved = continued
	for _, layer in layers do
		local onto = if layer.position == 1 then baseTip else below
		local localSha = layergit.shaOf(`refs/heads/{layer.name}`)
		local originSha = layergit.shaOf(`refs/remotes/origin/{layer.name}`)
		local facts: restackplan.Facts = {
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
			switchBack(state.back)
			deps.fail(`{layer.name} has no tip`)
		end
		facts.ontoInTip = isAncestor(onto, tip :: string)
		if from == "local" and facts.originExtra then
			facts.foreign = #foreignOnOrigin(
					layer,
					raft.id,
					localSha :: string,
					originSha :: string,
					onto
				) > 0
		end
		local plan = restackplan.decide(facts)
		if plan.action == "foreign" then
			switchBack(state.back)
			local named = table.concat(
				foreignOnOrigin(layer, raft.id, localSha :: string, originSha :: string, onto),
				"; "
			)
			deps.fail(
				`restack stopped at {layer.name}: origin's branch holds a commit that is on neither your local branch nor the layer below ({named}). Nothing was changed for this layer or any after it. Merge or drop that commit by hand, then run ./zn restack {raft.id} again.`
			)
		end
		local before = tip :: string
		if plan.action == "skip" then
			below = before
			continue
		end
		layergit.checkoutLayer(layer)
		if plan.action == "rebase" then
			-- the branch holds no commit that origin's lacks when it is taken from origin: moving it is safe
			if sh.trim(sh.git({ "rev-parse", "HEAD" })) ~= before then
				sh.git({ "reset", "--hard", before })
			end
			local upstream = upstreamOf(layer, raft.id, before, onto)
			if not upstream then
				switchBack(state.back)
				deps.fail(`restack stopped at {layer.name}: no common base`)
			end
			local rebasing = sh.run("git", { "rebase", "--onto", onto, upstream :: string, layer.name })
			if not rebasing.ok then
				if #unmergedFiles() == 0 then
					sh.run("git", { "rebase", "--abort" })
					switchBack(state.back)
					deps.fail(`restack stopped at {layer.name}: the rebase failed\n{rebasing.stderr}`)
				end
				stopOnConflict(raft.id, layer.name, state)
			end
		end
		local issue = store.find(layer.issue)
		if not issue or not deps.runCheck(issue) then
			if plan.action == "rebase" then
				sh.git({ "reset", "--hard", before })
			end
			switchBack(state.back)
			deps.fail(`restack stopped at {layer.name}: {layer.issue} check.sh failed`)
		end
		publish(layer, raft.id, deps, originSha)
		below = sh.trim(sh.git({ "rev-parse", "HEAD" }))
		moved = true
		retarget(layer, wasOn, basePr, deps)
	end
	if fs.isFile(stateFile()) then
		fs.removeFile(stateFile())
	end
	switchBack(state.back)
	if moved then
		require("./liveemit").emit(
			"restacked",
			{ raft = raft.id, project = require("./liveemit").projectOf(raft.root) }
		)
		print(`restacked {raft.id}`)
	else
		print(`{raft.id} is already stacked`)
	end
end

local function start(raft: store.Item, deps: Deps)
	if rebaseOn() then
		local state = readState()
		if state then
			deps.fail(restackplan.inProgressMessage(state.raft, state.conflict))
		end
		deps.fail(
			`a git rebase is in progress in this worktree and it is not a restack's: finish it (git rebase --continue) or git rebase --abort, then run ./zn restack {raft.id} again`
		)
	end
	if fs.isFile(stateFile()) then
		fs.removeFile(stateFile()) -- a marker with no rebase behind it: the run that wrote it is over
	end
	if sh.git({ "status", "--porcelain" }) ~= "" then
		deps.fail("working tree is not clean")
	end
	if deps.hasOrigin() then
		sh.git({ "fetch", "--quiet", "origin" })
	end
	local why = layergit.oldShapeRefusal(raft)
	if why then
		deps.fail(why)
	end
	local orig: { { name: string, sha: string } } = {}
	for _, layer in layergit.layersOf(raft.id) do
		table.insert(orig, { name = layer.name, sha = layergit.shaOf(`refs/heads/{layer.name}`) or "" })
	end
	local back = sh.git({ "branch", "--show-current" })
	walk(raft, deps, { raft = raft.id, back = back, orig = orig, conflict = "" }, false)
end

local function continueRun(raft: store.Item, deps: Deps)
	local state = readState()
	if not state or state.raft ~= raft.id then
		deps.fail(
			`no restack of {raft.id} is in progress: nothing to continue (./zn restack {raft.id} starts one)`
		)
	end
	local st = state :: restackplan.State
	if rebaseOn() then
		local unmerged = unmergedFiles()
		local checked = sh.run("git", { "diff", "--check", "HEAD" })
		local marked = restackplan.markers(checked.stdout .. "\n" .. checked.stderr)
		if #unmerged > 0 or #marked > 0 then
			deps.fail(restackplan.unresolvedMessage(raft.id, unmerged, marked))
		end
		local went = sh.run("git", { "-c", "core.editor=true", "rebase", "--continue" })
		if not went.ok then
			if #unmergedFiles() > 0 then
				stopOnConflict(raft.id, st.conflict, st)
			end
			deps.fail(`restack of {raft.id} could not continue the rebase:\n{went.stderr}{went.stdout}`)
		end
	end
	walk(raft, deps, st, true)
end

local function abortRun(raft: store.Item, deps: Deps)
	local state = readState()
	if not state or state.raft ~= raft.id then
		deps.fail(`no restack of {raft.id} is in progress: nothing to abort`)
	end
	local st = state :: restackplan.State
	if rebaseOn() then
		sh.git({ "rebase", "--abort" })
	end
	sh.git({ "reset", "--hard", "--quiet" })
	if st.back == "" then
		sh.git({ "switch", "--quiet", "--detach" })
	else
		sh.git({ "switch", "--quiet", st.back })
	end
	local current = sh.git({ "branch", "--show-current" })
	for _, o in st.orig do
		if o.sha == "" then
			sh.run("git", { "update-ref", "-d", `refs/heads/{o.name}` })
		elseif o.name == current then
			sh.git({ "reset", "--hard", "--quiet", o.sha })
		else
			sh.git({ "update-ref", `refs/heads/{o.name}`, o.sha })
		end
	end
	fs.removeFile(stateFile())
	print(`restack of {raft.id} aborted: every branch is back as it was before the run`)
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
