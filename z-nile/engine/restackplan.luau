--!strict
-- d0434: the pure part of `./zn restack`. Texts and booleans in, texts and decisions out; the git calls are
-- restackcmd.luau's. Three things live here: which tip a layer is restacked from and what to do with it, the
-- marker a conflicted restack leaves in the worktree's git directory, and the readers of git's output that name
-- what is still unresolved.
--
-- Marker (`<worktree git dir>/zn-restack.state`), one line each:
--   raft <R-id>
--   back <branch the restack started on, or ->
--   orig <layer branch> <its local tip before the run, or ->     (one per layer, in order)
--   conflict <layer branch>
-- Nothing else is kept: which layers are done is read again from git by every run.

local restackplan = {}

export type Facts = {
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
	orig: { { name: string, sha: string } }, -- sha "" : the branch had no local copy
	conflict: string,
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
		if source == "local" then
			return { source = source, action = "publish" }
		end
		return { source = source, action = "skip" }
	end
	return { source = source, action = "rebase" }
end

-- Subjects of origin's own commits that are in neither list (the local branch's own commits, the layer below's).
function restackplan.foreignSubjects(originOwn: { string }, known: { string }): { string }
	local seen: { [string]: boolean } = {}
	for _, s in known do
		seen[s] = true
	end
	local out: { string } = {}
	for _, s in originOwn do
		if not seen[s] then
			table.insert(out, s)
		end
	end
	return out
end

function restackplan.renderState(state: State): string
	local lines = { `raft {state.raft}`, `back {if state.back == "" then "-" else state.back}` }
	for _, o in state.orig do
		table.insert(lines, `orig {o.name} {if o.sha == "" then "-" else o.sha}`)
	end
	table.insert(lines, `conflict {state.conflict}`)
	return table.concat(lines, "\n") .. "\n"
end

-- Nil when the text is not a marker this module wrote.
function restackplan.parseState(text: string): State?
	local raft, back, conflict = "", nil, ""
	local orig: { { name: string, sha: string } } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local key, a, b = string.match(line, "^(%a+) (%S+) ?(%S*)$")
		if key == "raft" and a then
			raft = a
		elseif key == "back" and a then
			back = if a == "-" then "" else a
		elseif key == "orig" and a and b ~= "" then
			table.insert(orig, { name = a, sha = if b == "-" then "" else b :: string })
		elseif key == "conflict" and a then
			conflict = a
		end
	end
	if raft == "" or back == nil or conflict == "" then
		return nil
	end
	return { raft = raft, back = back, orig = orig, conflict = conflict }
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
	table.insert(lines, `(or ./zn restack {raft} --abort to put every branch back as it was)`)
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
	return `A restack of {raft} is stopped on a conflict at {layer}. Read both sides of {named} and resolve them keeping both intents, git add them, run the specs they select by name, then run ./zn restack {raft} --continue and ask again. If the two sides changed the same behaviour on purpose and you cannot tell which the owner wants, stop and ask, naming the files and both intents. Never git rebase --skip, never drop a commit, never force-push by hand. ./zn restack {raft} --abort puts every branch back.`
end

return restackplan
