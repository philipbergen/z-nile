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

-- What `--abort` refuses to move: a branch at none of the tips the run could have left it at. That is where the run
-- found it (`orig`), where it last left it (`left`), and for a layer it pushed the tip it pushed: a pushed layer put
-- back by hand to its tip from before the run is taken forward to the pushed tip, which loses nothing.
function restackplan.abortRefuses(current: string, orig: string, left: string, pushed: string?): boolean
	return restackplan.movedSince(current, orig, left) and (pushed == nil or current ~= pushed)
end

-- d0434 (design review 001 F5, code review 001 F3, F4): the one undo `--continue` refuses. A layer the run moved
-- (`left` is not `orig`) whose branch is back at its tip from before the run (`orig`): what an older engine, an abort by
-- hand or a reset leaves, and walking on would rebuild it from that old tip and replace what the run left. Whatever
-- refs/zn/pushed holds: before a run pushes a layer that ref is the old tip too. Every other tip, a hand rebase, an
-- amend, a fix on top or a finished layer, is the worker's change and goes through the walk; a deleted branch too (the
-- walk takes the layer from origin).
function restackplan.strayed(now: string, orig: string, left: string): boolean
	return now ~= "" and left ~= "" and left ~= orig and now == orig
end

export type Stray = {
	layer: string,
	leftSha: string, -- the tip the run left
	left: string, -- `<sha> <subject> (<date>)` of it
	now: string, -- the same for the branch's tip now (its tip from before the run)
	log: string, -- `git log --oneline <left>..<now>`
	here: boolean, -- the layer is the branch checked out in this worktree
}

-- What `--continue` says when a layer is back at its old tip: both commits, what is on the branch that the run did not
-- leave, and for each layer its own way on. First, put the branch back on the tip the run left and continue, which keeps
-- a resolution staged in the rebase; `git branch -f` works while a rebase is in progress, because the layer is not the
-- branch being rebased. Second, `--abort` and a plain restack, which discards an unfinished resolution. Never a reset.
function restackplan.strayedMessage(raft: string, strays: { Stray }): string
	local lines = {
		`restack of {raft} cannot continue: a layer this restack moved is back at its tip from before the run (what an older zn, an abort by hand or a branch moved back by hand leaves). Going on would rebuild it from that old tip and replace what the restack left. Nothing was changed.`,
	}
	for _, s in strays do
		table.insert(lines, `{s.layer}:`)
		table.insert(lines, `  the restack left it at: {s.left}`)
		table.insert(lines, `  it is now at:           {s.now}`)
		table.insert(lines, `  on it now and not on what the restack left (git log --oneline <left>..<now>):`)
		local log: { string } = if s.log == "" then { "(none)" } else restackplan.lines(s.log)
		for _, l in log do
			table.insert(lines, `    {l}`)
		end
		local move = if s.here
			then `git switch --detach && git branch -f {s.layer} {s.leftSha} && git switch {s.layer}`
			else `git branch -f {s.layer} {s.leftSha}`
		table.insert(lines, `  to put it back on the tip the restack left: {move}`)
	end
	table.insert(
		lines,
		`To go on, keeping what you resolved: run the command above for each layer, then ./zn restack {raft} --continue.`
	)
	table.insert(
		lines,
		`Or drop this restack: ./zn restack {raft} --abort, then ./zn restack {raft}. The abort discards a resolution you have not continued yet (the rebase in progress and what is staged), puts each layer it pushed on the tip it pushed, and leaves the others where it found them.`
	)
	return table.concat(lines, "\n")
end

-- A refused push: the run stops, and the way on is an abort (which keeps what was pushed) and a plain restack, which
-- fetches; `--continue` never does.
function restackplan.refusedPushMessage(
	raft: string,
	layer: string,
	published: { string },
	why: string
): string
	local below = if #published > 0
		then `Already pushed, and left as pushed: {table.concat(published, ", ")}.`
		else "No layer was pushed."
	return `the push of {layer} was refused: origin's branch changed since this restack started, or the push failed. {layer} and the layers above it were not pushed. {below} --continue does not fetch, so it cannot build on what origin holds now. To go on: ./zn restack {raft} --abort (it keeps the layers already pushed and puts the others back), then ./zn restack {raft}, which fetches and builds on origin's tip.\n{why}`
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

export type Move = { name: string, from: string, to: string } -- "" : no branch (before, or after: deleted)

-- What `--abort` says: what it kept, and every branch it moved with the tip it was on and the tip it is on now, so a
-- tip it moved off can be found again (code review 001 F2).
function restackplan.abortMessage(raft: string, published: { string }, moves: { Move }?): string
	local names = table.concat(published, ", ")
	local head = if #published == 0
		then `restack of {raft} aborted: every layer branch and the worktree are back as before the run; nothing had been pushed`
		else `restack of {raft} aborted: every layer that was not yet pushed and the worktree are back as before the run; {names} stay as pushed (an abort never moves origin back). A plain ./zn restack {raft} goes on from them.`
	local lines = { head }
	if moves and #moves > 0 then
		table.insert(lines, "moved (the tip it was on -> the tip it is on now):")
		for _, m in moves do
			local from = if m.from == "" then "(no branch)" else m.from
			local to = if m.to == "" then "(deleted)" else m.to
			table.insert(lines, `  {m.name}: {from} -> {to}`)
		end
	end
	return table.concat(lines, "\n")
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
