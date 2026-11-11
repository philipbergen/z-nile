--!strict
-- The shape of a raft that is a stack. Pure: texts in, texts out. Git and the pull requests stay in main.luau.
--
-- Contract, which the Python port reads as these bytes:
--   branch:   R0010/1/c0010
--             raft / 1-based position, unpadded / issue. The first layer's base is main.
--   claim:    a commit whose subject is not "<issue>: <title>" (tracker: start …, or any worker commit)
--   finish:   ./zn finish <issue-id>
--             one commit, subject "<issue>: <title>" (tab and newline in the title become a space)
--             git push --force-with-lease of that layer branch only
--   pull request:
--             gh pr create --draft --base <lower branch, or main> --head <branch> --title "<issue>: <title>"
--   restack:  ./zn restack <R-id>
--             rebase each layer onto the tip of the one below, in order; stop at the first conflict or red check.
--             A rewritten lower commit rebases only this layer's own commits (the finish commit, or the
--             commits after `tracker: start`), not the old lower commits still in this layer's history.
--   read:     ./zn stack <R-id>
--             one row per layer, from git: "<position> <branch> <issue> <finished|claimed|missing> <sha>"
--   land:     ./zn done <R-id>
--             The checkout must be the published top-layer commit (the one that is merged).
--             git merge --no-ff of that commit into main. The merge commit's message is
--             "<raft>: bind <id>, <id>\n\nVerdict: <word>\n"
--             <word> is the review file's Verdict line. No review file, and a review with no
--             Verdict line, both refuse: a verdict nobody wrote is not recorded.
--             gh pr view <n> --json baseRefName -q .baseRefName, then gh pr edit <n> --base main,
--             then git push origin HEAD:refs/heads/main. A failed push runs
--             gh pr edit <n> --base <the base just read> so the pull request is left where it was.

local stack = {}

export type Member = { id: string, dependsOn: { string } }
export type Layer = { raft: string, position: number, issue: string, name: string }
export type Row = { position: number, name: string, issue: string, state: string, sha: string }
export type CommitRow = { subject: string, parent: string }

function stack.branch(raftId: string, position: number, issueId: string): string
	return `{raftId}/{position}/{issueId}`
end

-- nil when `ref` is not a layer branch. `origin/R0010/1/c0010` is the same layer as `R0010/1/c0010`.
-- A padded position (`R0010/01/c0010`) is not a layer: the tool writes the position unpadded.
function stack.parse(ref: string): Layer?
	local bare = (string.gsub(ref, "^origin/", ""))
	local raft, pos, issue = string.match(bare, "^(R%d%d%d%d)/(%d+)/([fdc]%d%d%d%d)$")
	if not raft or not pos or not issue then
		return nil
	end
	local n = tonumber(pos)
	if not n or n < 1 or tostring(n) ~= pos then
		return nil
	end
	return { raft = raft, position = n, issue = issue, name = `{raft}/{pos}/{issue}` }
end

function stack.owns(ref: string, raftId: string): boolean
	local layer = stack.parse(ref)
	return layer ~= nil and layer.raft == raftId
end

function stack.finishSubject(issueId: string, title: string): string
	local clean = (string.gsub(title, "[\t\n\r]", " "))
	return `{issueId}: {clean}`
end

-- A finished layer is exactly one commit, on `base`, whose subject is the finish subject.
function stack.finished(
	count: number,
	subject: string,
	parent: string,
	base: string,
	issueId: string,
	title: string
): boolean
	return count == 1 and parent == base and subject == stack.finishSubject(issueId, title)
end

function stack.bindMessage(raftId: string, issueIds: { string }, verdict: string): string
	return `{raftId}: bind {table.concat(issueIds, ", ")}\n\nVerdict: {verdict}\n`
end

function stack.oldShapeMessage(raftId: string, branch: string): string
	return `{raftId} is an active raft in the old single-branch shape ({branch}) and is not migrated. It is being stopped separately.`
end

-- Once git has said whether the lower tip is an ancestor of this layer, the layer needs no rebase.
function stack.alreadyStacked(lowerIsAncestor: boolean): boolean
	return lowerIsAncestor
end

-- The upstream of `git rebase --onto <new lower> <upstream> <layer>`. Nil means the merge-base.
-- `rows` are the commits after that merge-base, oldest first.
function stack.rebaseUpstream(
	issue: string,
	raftId: string,
	tipSubject: string,
	tipParent: string,
	parentInLower: boolean,
	rows: { CommitRow }
): string?
	if string.sub(tipSubject, 1, #issue + 2) == `{issue}: ` and not parentInLower then
		return tipParent
	end
	local mark = `tracker: start {raftId}`
	for _, row in rows do
		if string.sub(row.subject, 1, #mark) == mark then
			return row.parent
		end
	end
	return nil
end

function stack.render(raftId: string, rows: { Row }): string
	local lines = { raftId }
	for _, row in rows do
		table.insert(lines, `{row.position} {row.name} {row.issue} {row.state} {row.sha}`)
	end
	return table.concat(lines, "\n")
end

local function memberSet(members: { Member }): { [string]: Member }
	local set: { [string]: Member } = {}
	for _, m in members do
		set[m.id] = m
	end
	return set
end

local function inRaftDeps(m: Member, set: { [string]: Member }): { string }
	local out: { string } = {}
	for _, id in m.dependsOn do
		if set[id] then
			table.insert(out, id)
		end
	end
	return out
end

-- Ids named in the Order section, in the order written. A section that names none is the fallback.
local function namedIds(section: string): { string }
	local out: { string } = {}
	for id in string.gmatch(section, "[fdc]%d%d%d%d") do
		table.insert(out, id)
	end
	return out
end

local function topo(
	remaining: { string },
	depsOf: (string) -> { string },
	placed: { [string]: boolean }
): ({ string }?, string?)
	local left: { string } = {}
	for _, id in remaining do
		table.insert(left, id)
	end
	local out: { string } = {}
	while #left > 0 do
		local ready: { string } = {}
		for _, id in left do
			local ok = true
			for _, dep in depsOf(id) do
				if not placed[dep] then
					ok = false
					break
				end
			end
			if ok then
				table.insert(ready, id)
			end
		end
		if #ready == 0 then
			table.sort(left)
			return nil, `dependency cycle among: {table.concat(left, ", ")}`
		end
		table.sort(ready)
		local pick = ready[1]
		placed[pick] = true
		local nextLeft: { string } = {}
		for _, id in left do
			if id ~= pick then
				table.insert(nextLeft, id)
			end
		end
		left = nextLeft
		table.insert(out, pick)
	end
	return out, nil
end

-- The raft's Order: ids the section names, in the order written, then the members it does not name,
-- topological by in-raft depends_on, ties by lowest id. A section that names no id is that fallback
-- for every member. A named order that puts a dependent before its depends_on is refused.
function stack.order(raftId: string, section: string, members: { Member }): ({ string }?, string?)
	local set = memberSet(members)
	local function depsOf(id: string): { string }
		local m = set[id]
		return if m then inRaftDeps(m, set) else {}
	end
	local named = namedIds(section)
	local seen: { [string]: boolean } = {}
	for _, id in named do
		if seen[id] then
			return nil, `{id} is listed twice in {raftId}'s Order`
		end
		seen[id] = true
		if not set[id] then
			return nil, `{id} is in {raftId}'s Order and is not a member`
		end
	end
	local index: { [string]: number } = {}
	for i, id in named do
		index[id] = i
	end
	for _, id in named do
		for _, dep in depsOf(id) do
			local at = index[dep]
			if not at or at > (index[id] :: number) then
				return nil, `{id} is listed before {dep}, which it depends on`
			end
		end
	end
	local placed: { [string]: boolean } = {}
	for _, id in named do
		placed[id] = true
	end
	local rest: { string } = {}
	for _, m in members do
		if not seen[m.id] then
			table.insert(rest, m.id)
		end
	end
	local suffix, err = topo(rest, depsOf, placed)
	if not suffix then
		return nil, err
	end
	local out: { string } = {}
	for _, id in named do
		table.insert(out, id)
	end
	for _, id in suffix do
		table.insert(out, id)
	end
	return out, nil
end

return stack
