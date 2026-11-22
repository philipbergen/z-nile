--!strict
-- d0434: the pure part of `./zn restack`. Texts and booleans in, texts and decisions out; the git calls are
-- restackcmd.luau's. Three things live here: which tip a layer is restacked from and what to do with it, the
-- marker a conflicted restack leaves in the worktree's git directory, and the readers of git's output that name
-- what is still unresolved.
--
-- Marker (`<worktree git dir>/zn-restack.state`), written when a run starts, rewritten as it moves branches and
-- removed when it ends; one line each:
--   raft <R-id>
--   back <branch the restack started on, or ->
--   start <commit the worktree started at>
--   orig <layer branch> <its local tip before the run, or ->
--   judged <layer branch> <origin's tip the run judged after its fetch, or ->     (every push is leased against it)
--   left <layer branch> <the tip the run last left it at>
--   conflict <layer branch> <how many own commits it had>      (only while stopped on a conflict)
--   file <conflicted path>
-- Which layers are done is read again from git by every run.

local restackplan = {}

export type Facts = {
	hasRemote: boolean, -- the repository has an origin to publish to
	hasLocal: boolean,
	hasOrigin: boolean,
	localExtra: boolean, -- the local branch holds a commit origin's branch lacks
	originExtra: boolean, -- origin's branch holds a commit the local branch lacks
	foreign: boolean, -- origin's extra commits include one whose change is on neither the local branch nor the layer below
	ontoInTip: boolean, -- the layer below is an ancestor of the tip taken
}

export type Plan = {
	source: string, -- "local" or "origin": where the tip is taken from
	action: string, -- "none" (no tip), "foreign", "skip", "publish" (check, push) or "rebase"
}

export type State = {
	raft: string,
	back: string,
	start: string,
	orig: { { name: string, sha: string } }, -- "" : no local copy
	judged: { [string]: string },
	left: { [string]: string },
	conflict: string, -- "" : not stopped on a conflict
	own: number,
	files: { string },
}

-- A layer's tip is the local branch's whenever it holds a commit origin's lacks, and origin's otherwise. Never the
-- other way round: taking origin's tip over a local hand rebase is the R0138 reset.
function restackplan.source(facts: Facts): string
	if facts.hasLocal and (not facts.hasOrigin or facts.localExtra) then
		return "local"
	end
	return "origin"
end

function restackplan.decide(facts: Facts): Plan
	if not facts.hasLocal and not facts.hasOrigin then
		return { source = "origin", action = "none" }
	end
	local source = restackplan.source(facts)
	if source == "local" and facts.hasOrigin and facts.originExtra and facts.foreign then
		return { source = source, action = "foreign" }
	end
	if facts.ontoInTip then
		-- stacked, but not yet on origin: check and push it before the next layer
		if source == "local" and facts.hasRemote and (not facts.hasOrigin or facts.localExtra) then
			return { source = source, action = "publish" }
		end
		return { source = source, action = "skip" }
	end
	return { source = source, action = "rebase" }
end

-- A diverged origin tip is a rewrite of the local branch only when this clone pushed it itself: `pushed` is the tip
-- zn recorded in refs/zn/pushed/<layer> when its own push succeeded. A fetch, a reset or a reflog entry says nothing
-- about who wrote a commit.
function restackplan.trusted(originSha: string, pushed: string): boolean
	return pushed ~= "" and pushed == originSha
end

-- A resolution (or a clean rebase) that left fewer own commits than the layer had emptied one.
function restackplan.emptied(expected: number, now: number): boolean
	return expected > 0 and now < expected
end

-- A branch moved since the run left it when it is neither where it started nor where the run left it.
function restackplan.movedSince(current: string, orig: string, left: string): boolean
	return current ~= orig and current ~= left
end

local function dash(s: string): string
	return if s == "" then "-" else s
end

local function undash(s: string): string
	return if s == "-" then "" else s
end

function restackplan.renderState(state: State): string
	local lines = { `raft {state.raft}`, `back {dash(state.back)}`, `start {dash(state.start)}` }
	for _, o in state.orig do
		table.insert(lines, `orig {o.name} {dash(o.sha)}`)
	end
	local names: { string } = {}
	for name in state.left do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		table.insert(lines, `left {name} {state.left[name]}`)
	end
	local judged: { string } = {}
	for name in state.judged do
		table.insert(judged, name)
	end
	table.sort(judged)
	for _, name in judged do
		table.insert(lines, `judged {name} {dash(state.judged[name])}`)
	end
	if state.conflict ~= "" then
		table.insert(lines, `conflict {state.conflict} {state.own}`)
		for _, f in state.files do
			table.insert(lines, `file {f}`)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Nil when the text is not a marker this module wrote.
function restackplan.parseState(text: string): State?
	local state: State = {
		raft = "",
		back = "",
		start = "",
		orig = {},
		judged = {},
		left = {},
		conflict = "",
		own = 0,
		files = {},
	}
	local seenBack = false
	for line in string.gmatch(text, "[^\n]+") do
		local key, rest = string.match(line, "^(%a+) (.+)$")
		if key == "file" and rest then
			table.insert(state.files, rest)
		elseif key and rest then
			local words: { string } = {}
			for w in string.gmatch(rest, "%S+") do
				table.insert(words, w)
			end
			if key == "raft" then
				state.raft = words[1] or ""
			elseif key == "back" then
				seenBack = true
				state.back = undash(words[1] or "-")
			elseif key == "start" then
				state.start = undash(words[1] or "-")
			elseif key == "orig" and #words == 2 then
				table.insert(state.orig, { name = words[1], sha = undash(words[2]) })
			elseif key == "judged" and #words == 2 then
				state.judged[words[1]] = undash(words[2])
			elseif key == "left" and #words == 2 then
				state.left[words[1]] = words[2]
			elseif key == "conflict" then
				state.conflict = words[1] or ""
				state.own = tonumber(words[2] or "0") or 0
			end
		end
	end
	if state.raft == "" or not seenBack then
		return nil
	end
	return state
end

-- Paths from `git diff --name-only --diff-filter=U`: one per line.
function restackplan.lines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if line ~= "" then
			table.insert(out, line)
		end
	end
	return out
end

-- `file:line` of every leftover conflict marker in the output of `git diff --check`.
function restackplan.markers(checkOutput: string): { string }
	local out: { string } = {}
	for line in string.gmatch(checkOutput .. "\n", "([^\n]*)\n") do
		local where = string.match(line, "^(.-): leftover conflict marker")
		if where then
			table.insert(out, where)
		end
	end
	return out
end

-- The message a conflicted layer stops with, and what a refused --continue says.
function restackplan.conflictMessage(raft: string, layer: string, files: { string }): string
	local lines = {
		`restack stopped at {layer}: conflict in {#files} file(s) of {raft}, the rebase is left in progress:`,
	}
	for _, f in files do
		table.insert(lines, `  {f}`)
	end
	table.insert(lines, `resolve them, git add them, then run ./zn restack {raft} --continue`)
	table.insert(
		lines,
		`(or ./zn restack {raft} --abort: it puts every layer branch and the worktree back as before the run; nothing is pushed until the whole stack is restacked)`
	)
	return table.concat(lines, "\n")
end

function restackplan.inProgressMessage(raft: string, layer: string): string
	return `a restack of {raft} is in progress, stopped at {layer}: ./zn restack {raft} --continue after resolving, or ./zn restack {raft} --abort`
end

function restackplan.unresolvedMessage(raft: string, unmerged: { string }, marked: { string }): string
	local lines = { `restack of {raft} cannot continue: the conflict is not resolved` }
	for _, f in unmerged do
		table.insert(lines, `  unmerged: {f} (resolve it, then git add it)`)
	end
	for _, m in marked do
		table.insert(lines, `  conflict marker: {m}`)
	end
	return table.concat(lines, "\n")
end

-- What `./zn work next` tells the worker while a restack is stopped on a conflict.
function restackplan.workNote(raft: string, layer: string, files: { string }): string
	local named = if #files == 0 then "the conflicted files" else table.concat(files, ", ")
	return `A restack of {raft} is stopped on a conflict at {layer}. Read both sides of {named} and resolve them keeping both intents, git add them, run the specs they select by name (lune run z-nile/affected -- <the files> lists them), then run ./zn restack {raft} --continue and ask again; a later layer may stop again, then repeat. If the check goes red after the continue, nothing was pushed and your resolution stays on the layer locally: fix the layer, ./zn finish its issue, then run a plain ./zn restack {raft}. If the resolution empties a commit (its change is already below), stop and ask; never git rebase --skip and never --allow-empty without the owner's answer. If the two sides changed the same behaviour on purpose and you cannot tell which the owner wants, stop and ask (write questions.md, as z-work says), naming the files and both intents. Never drop a commit, never force-push by hand. ./zn restack {raft} --abort puts every layer branch and the worktree back; nothing was pushed.`
end

return restackplan
