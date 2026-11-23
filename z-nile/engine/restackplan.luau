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
--   pushed <layer branch> <the tip this run pushed for it>     (a layer is pushed once its check.sh passed; --abort leaves it)
--   pushing <layer branch> <the tip about to be pushed>        (written BEFORE the push, cleared after it; a run killed
--                                                               around the push finds out from origin whether it landed)
--   red <layer branch> <its restacked tip>      (its check.sh failed; the tip stays on the branch, unpushed, to be fixed)
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
	pushed: { [string]: string }, -- layers this run pushed, and the tip each went at
	pushing: { [string]: string }, -- a push started and not yet recorded: the tip it carries
	red: string, -- "" : no layer stopped on a red check; else the layer whose restacked tip is kept for a fix
	redSha: string,
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

-- The layers this run has pushed, in the order the run walked them.
function restackplan.published(state: State): { string }
	local out: { string } = {}
	for _, o in state.orig do
		if state.pushed[o.name] ~= nil then
			table.insert(out, o.name)
		end
	end
	return out
end

-- Where `--abort` puts a layer's branch: where the run found it (`orig`, "" meaning it had no branch: delete it) unless
-- the run pushed it, and then the tip it pushed, because origin is never moved back and the branch the run created and
-- pushed is kept.
function restackplan.restoreTo(state: State, name: string, orig: string): string
	return state.pushed[name] or orig
end

-- Of git's words about a refused push, only the reason lines (` ! [rejected] a -> a (stale info)`): the rest names the
-- remote's address, which zn never prints.
function restackplan.pushReason(stderr: string): string
	local out: { string } = {}
	for line in string.gmatch(stderr .. "\n", "([^\n]*)\n") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") or ""
		if string.sub(trimmed, 1, 3) == "! [" then
			table.insert(out, trimmed)
		end
	end
	return table.concat(out, "\n")
end

-- A red check.sh on a restacked layer: the restacked tip stays on the branch, not pushed, for the worker to fix.
function restackplan.redMessage(raft: string, layer: string, issue: string, published: { string }): string
	local below = if #published > 0
		then `Already pushed, and left as pushed: {table.concat(published, ", ")}.`
		else "No layer was pushed."
	return `restack stopped at {layer}: {issue} check.sh failed on the restacked tip. {layer} and the layers above it are not pushed. {below} The restacked tip stays on the branch {layer}, not pushed: fix the layer on that tip, ./zn finish {issue}, then run ./zn restack {raft} (it trusts that tip as your own work). ./zn restack {raft} --abort puts the layers not yet pushed back as before the run.`
end

function restackplan.redNote(raft: string, layer: string, issue: string): string
	return `A restack of {raft} stopped at {layer}: {issue}'s check.sh is red on the restacked tip. That tip is on the branch {layer} and not pushed (the layers below it that passed already are). Fix the layer on that tip (run ./zn check {issue}), run ./zn finish {issue}, then ./zn restack {raft} and ask again. If the failure is not yours to fix, or the fix is not clear, stop and ask the owner (write questions.md, as z-work says), naming the layer and the failing check. Never force-push by hand. ./zn restack {raft} --abort puts the layers not yet pushed back as before the run.`
end

function restackplan.abortMessage(raft: string, published: { string }): string
	if #published == 0 then
		return `restack of {raft} aborted: every layer branch and the worktree are back as before the run; nothing had been pushed`
	end
	local names = table.concat(published, ", ")
	return `restack of {raft} aborted: every layer that was not yet pushed and the worktree are back as before the run; {names} stay as pushed (an abort never moves origin back). A plain ./zn restack {raft} goes on from them.`
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
	local pushingNames: { string } = {}
	for name in state.pushing do
		table.insert(pushingNames, name)
	end
	table.sort(pushingNames)
	for _, name in pushingNames do
		table.insert(lines, `pushing {name} {state.pushing[name]}`)
	end
	if state.red ~= "" then
		table.insert(lines, `red {state.red} {state.redSha}`)
	end
	local pushedNames: { string } = {}
	for name in state.pushed do
		table.insert(pushedNames, name)
	end
	table.sort(pushedNames)
	for _, name in pushedNames do
		table.insert(lines, `pushed {name} {state.pushed[name]}`)
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
		pushed = {},
		pushing = {},
		red = "",
		redSha = "",
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
			elseif key == "pushed" and #words == 2 then
				state.pushed[words[1]] = words[2]
			elseif key == "pushing" and #words == 2 then
				state.pushing[words[1]] = words[2]
			elseif key == "red" and #words == 2 then
				state.red = words[1]
				state.redSha = words[2]
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
function restackplan.conflictMessage(
	raft: string,
	layer: string,
	files: { string },
	published: { string }
): string
	local lines = {
		`restack stopped at {layer}: conflict in {#files} file(s) of {raft}, the rebase is left in progress:`,
	}
	for _, f in files do
		table.insert(lines, `  {f}`)
	end
	table.insert(lines, `resolve them, git add them, then run ./zn restack {raft} --continue`)
	table.insert(
		lines,
		`(or ./zn restack {raft} --abort: it puts the layers not yet pushed and the worktree back as before the run, and leaves the pushed ones)`
	)
	if #published > 0 then
		local names = table.concat(published, ", ")
		table.insert(
			lines,
			`already pushed: {names} (each passed its check.sh); this layer and the ones above are not`
		)
	end
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
	return `A restack of {raft} is stopped on a conflict at {layer}. Read both sides of {named} and resolve them keeping both intents, git add them, run the specs they select by name (lune run z-nile/affected -- <the files> lists them), then run ./zn restack {raft} --continue and ask again; a later layer may stop again, then repeat. If the check goes red after the continue, that layer and the ones above it are not pushed (the layers below it that passed already are) and your resolution stays on the layer locally: fix the layer, ./zn finish its issue, then run a plain ./zn restack {raft}. If the resolution empties a commit (its change is already below), stop and ask; never git rebase --skip and never --allow-empty without the owner's answer. If the two sides changed the same behaviour on purpose and you cannot tell which the owner wants, stop and ask (write questions.md, as z-work says), naming the files and both intents. Never drop a commit, never force-push by hand. ./zn restack {raft} --abort puts the layers not yet pushed and the worktree back and leaves the pushed ones (it never moves origin back); a plain ./zn restack {raft} then goes on from them.`
end

return restackplan
