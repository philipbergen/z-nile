--!strict
-- Git reads for a raft's layers. The shape (names, finished, order) is stack.luau; this module only asks git.
local completion = require("./completion")
local fs = require("@lune/fs")
local process = require("@lune/process")
local sh = require("../lib/sh")
local stack = require("./stack")
local stdio = require("@lune/stdio")
local store = require("./store")

local layergit = {}

local function fail(msg: string): never
	stdio.ewrite(msg .. "\n")
	return process.exit(1)
end

local function hasOrigin(): boolean
	return sh.run("git", { "remote", "get-url", "origin" }).ok
end

function layergit.raftSection(text: string, heading: string): string
	local hay = "\n" .. text
	local mark = "\n## " .. heading
	local s = string.find(hay, mark, 1, true)
	if not s then
		return `(no ## {heading} section)`
	end
	local body = s + #mark
	local nxt = string.find(hay, "\n## ", body, true)
	local chunk = if nxt then string.sub(hay, body, nxt - 1) else string.sub(hay, body)
	return (string.gsub(chunk, "^%s*(.-)%s*$", "%1"))
end

function layergit.orderedMembers(raft: store.Item): { store.Item }
	local members = store.members(raft.id)
	local byId: { [string]: store.Item } = {}
	local specs: { stack.Member } = {}
	for _, m in members do
		byId[m.id] = m
		table.insert(specs, { id = m.id, dependsOn = store.idList(store.readFront(m.doc).depends_on) })
	end
	local ids, err =
		stack.order(raft.id, layergit.raftSection(fs.readFile(raft.doc), "Order & dependencies"), specs)
	if not ids then
		fail(err :: string)
	end
	local out: { store.Item } = {}
	for _, id in ids :: { string } do
		local item = byId[id]
		if item then
			table.insert(out, item)
		end
	end
	return out
end

function layergit.shaOf(ref: string): string?
	local r = sh.run("git", { "rev-parse", "--verify", "--quiet", ref .. "^{commit}" })
	if not r.ok then
		return nil
	end
	return sh.trim(r.stdout)
end

-- origin/main, or a local main, or (a fixture whose clone is not named main) the branch the layer was cut from.
function layergit.mainTip(): string
	local named = layergit.shaOf("origin/main") or layergit.shaOf("main")
	if named then
		return named
	end
	local current = sh.trim(sh.git({ "branch", "--show-current" }))
	if current == "" or not stack.parse(current) then
		return layergit.shaOf("HEAD") or fail("no main branch")
	end
	local listed = sh.run("git", { "for-each-ref", "--format=%(refname:short)", "refs/heads" })
	if listed.ok then
		for line in string.gmatch(listed.stdout .. "\n", "([^\n]*)\n") do
			if line ~= "" and not stack.parse(line) then
				local sha = layergit.shaOf(line)
				if sha and sh.run("git", { "merge-base", "--is-ancestor", sha, "HEAD" }).ok then
					return sha
				end
			end
		end
	end
	return fail("no main branch")
end

function layergit.layersOf(raftId: string): { stack.Layer }
	local listed =
		sh.run("git", { "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes/origin" })
	local byPos: { [number]: stack.Layer } = {}
	if listed.ok then
		for line in string.gmatch(listed.stdout .. "\n", "([^\n]*)\n") do
			local layer = if line == "" then nil else stack.parse(line)
			if layer and layer.raft == raftId then
				byPos[layer.position] = layer
			end
		end
	end
	local out: { stack.Layer } = {}
	for _, layer in byPos do
		table.insert(out, layer)
	end
	table.sort(out, function(a, b)
		return a.position < b.position
	end)
	return out
end

function layergit.layerTip(layer: stack.Layer): string?
	return layergit.shaOf(`origin/{layer.name}`) or layergit.shaOf(layer.name)
end

function layergit.issueTitle(item: store.Item): string
	return store.readFront(item.doc).title or item.id
end

function layergit.isPostFinishPath(path: string, raftId: string, issueId: string?): boolean
	if string.find(path, "/spend%.d/", 1, false) ~= nil then
		return true
	end
	-- c0248: the layer's own review and refute, in its issue's folder
	if issueId ~= nil then
		local owner, name = string.match(path, "/issues/active/([fdc]%d%d%d%d)/([^/]+)$")
		if owner == nil then
			owner, name = string.match(path, "/issues/([fdc]%d%d%d%d)/([^/]+)$")
		end
		if
			owner == issueId
			and name ~= nil
			and (
				string.match(name, "^review%-%d+%.md$") ~= nil
				or string.match(name, "^refute%-%d+%.md$") ~= nil
			)
		then
			return true
		end
	end
	local raftDirPattern = `/rafts/active/{raftId}/([^/]+)$`
	local name = string.match(path, raftDirPattern)
	if name ~= nil then
		if
			name == "trace.md"
			or name == `{raftId}.md`
			or string.match(name, "^review%-%d+%.md$") ~= nil
			or string.match(name, "^refute%-%d+%.md$") ~= nil
			or string.match(name, "^final%-review%-%d+%.md$") ~= nil
			or string.match(name, "^final%-refute%-%d+%.md$") ~= nil
		then
			return true
		end
	end
	local issueDoc = string.match(path, "/issues/active/([fdc]%d%d%d%d)/([fdc]%d%d%d%d)%.md$")
		or string.match(path, "/issues/([fdc]%d%d%d%d)/([fdc]%d%d%d%d)%.md$")
	if issueDoc ~= nil then
		return true
	end
	return false
end

-- Returns the SHA of the layer's "<issue>: <title>" commit on `base` when the layer is finished
-- (either that commit is the tip, or commits above it touch only post-finish review/trace/ruling files).
function layergit.layerFinishSha(layer: stack.Layer, base: string, overrideTip: string?): string?
	local tip = overrideTip or layergit.layerTip(layer)
	if not tip or base == "" then
		return nil
	end
	local count = tonumber(sh.trim(sh.git({ "rev-list", "--count", `{base}..{tip}` }))) or 0
	if count == 0 then
		return nil
	end
	local issue = store.find(layer.issue)
	local title = if issue then layergit.issueTitle(issue) else layer.issue
	if count == 1 then
		local subject = sh.trim(sh.git({ "log", "-1", "--format=%s", tip }))
		local parent = sh.trim(sh.git({ "rev-parse", `{tip}^` }))
		if stack.finished(count, subject, parent, base, layer.issue, title) then
			return tip
		end
		return nil
	end
	local raw = sh.git({ "log", "--reverse", "--format=%H%x09%P%x09%s", `{base}..{tip}` })
	local commits: { { sha: string, parent: string, subject: string } } = {}
	for line in string.gmatch(raw .. "\n", "([^\n]+)\n") do
		local sha, parents, subject = string.match(line, "^(%x+)\t([^\t]*)\t(.*)$")
		if sha then
			local firstParent = string.match(parents or "", "^(%x+)") or ""
			table.insert(commits, { sha = sha, parent = firstParent, subject = subject or "" })
		end
	end
	if #commits == 0 then
		return nil
	end
	local first = commits[1]
	if not stack.finished(1, first.subject, first.parent, base, layer.issue, title) then
		return nil
	end
	for i = 2, #commits do
		local c = commits[i]
		local changed = sh.git({ "diff-tree", "--no-commit-id", "--name-only", "-r", c.sha })
		local fileCount = 0
		for path in string.gmatch(changed .. "\n", "([^\n]+)\n") do
			if path ~= "" then
				fileCount += 1
				if not layergit.isPostFinishPath(path, layer.raft, layer.issue) then
					return nil
				end
			end
		end
		if fileCount == 0 then
			return nil
		end
	end
	return first.sha
end

-- True when the layer has its "<issue>: <title>" commit on `base` (plus optional review/trace commits).
function layergit.layerFinished(layer: stack.Layer, base: string): boolean
	return layergit.layerFinishSha(layer, base) ~= nil
end

-- The newest review of a layer's issue, its refute and the issue document, read from the layer's tip tree.
-- Returns review, refute, document, number (nil review when the folder holds none).
function layergit.layerReview(
	raft: store.Item,
	layer: stack.Layer,
	overrideTip: string?
): (string?, string?, string?, string?)
	local tip = overrideTip or layergit.layerTip(layer)
	local issue = store.find(layer.issue)
	if not tip or not issue then
		return nil, nil, nil, nil
	end
	-- the issue's folder as the layer's tree has it (a checkout that has not synced may hold it elsewhere)
	local dir, docPath = issue.dir, issue.doc
	for _, state in { "active", "done", "backlog" } do
		local candidate = store.dirFor("issue", state :: store.State, issue.id, issue.root)
		if sh.run("git", { "cat-file", "-e", `{tip}:{candidate}/{issue.id}.md` }).ok then
			dir, docPath = candidate, `{candidate}/{issue.id}.md`
			break
		end
	end
	local listed = sh.run("git", { "ls-tree", "--name-only", tip, `{dir}/` })
	local newest = 0
	if listed.ok then
		for line in string.gmatch(listed.stdout .. "\n", "([^\n]*)\n") do
			local n = tonumber(string.match(line, "/review%-(%d+)%.md$"))
			if n and n > newest then
				newest = n
			end
		end
	end
	local function show(path: string): string?
		local shown = sh.run("git", { "show", `{tip}:{path}` })
		return if shown.ok then shown.stdout else nil
	end
	local doc = show(docPath)
	if newest == 0 then
		return nil, nil, doc, nil
	end
	local num = string.format("%03d", newest)
	return show(`{dir}/review-{num}.md`), show(`{dir}/refute-{num}.md`), doc, num
end

local function backlogIssue(id: string): boolean
	local item = store.find(id)
	return item ~= nil and item.kind == "issue" and item.state == "backlog"
end

-- nil when the layer is complete: finished on `base`, and its review settled and current (completion.layer).
function layergit.completeReason(
	raft: store.Item,
	layer: stack.Layer,
	base: string,
	overrideTip: string?
): string?
	local finishSha = layergit.layerFinishSha(layer, base, overrideTip)
	if not finishSha then
		return `{layer.issue} is not finished: ./zn finish {layer.issue}`
	end
	local review, refute, doc, num = layergit.layerReview(raft, layer, overrideTip)
	local reason = completion.layer({
		finishSha = finishSha,
		review = review,
		refute = refute,
		openList = doc,
		backlog = backlogIssue,
		reviewName = if num then `review-{num}.md` else nil,
		refuteName = if num then `refute-{num}.md` else nil,
	})
	if reason then
		return `{layer.issue} is not complete: {reason}`
	end
	return nil
end

-- A layer is landed when its issue is in done/ on origin/main (or in this tree). The bind that lands a layer moves it.
function layergit.landed(issueId: string): boolean
	local here = store.find(issueId)
	if here and here.state == "done" then
		return true
	end
	if not here then
		return false
	end
	local ref = layergit.shaOf("origin/main") and "origin/main" or (layergit.shaOf("main") and "main" or nil)
	if not ref then
		return false
	end
	local doneDir = store.dirFor("issue", "done", issueId, here.root)
	return sh.run("git", { "cat-file", "-e", `{ref}:{doneDir}/{issueId}.md` }).ok
end

-- The commit a layer is built on. The layer below's tip while that branch exists and is under this layer; for the
-- lowest unlanded layer whose lower branch is gone (GitHub deletes a merged branch), the parent of its oldest commit
-- that main lacks, which is reachable from origin/main by construction.
function layergit.baseOf(position: number, belowTip: string?, belowLanded: boolean, tip: string): string?
	if position == 1 then
		return layergit.mainTip()
	end
	if
		belowTip and (not belowLanded or sh.run("git", { "merge-base", "--is-ancestor", belowTip, tip }).ok)
	then
		return belowTip
	end
	if not belowLanded then
		return nil
	end
	local main = layergit.mainTip()
	local oldest = sh.trim(sh.git({ "rev-list", "--reverse", "--first-parent", `{main}..{tip}` }))
	local first = string.match(oldest, "^(%x+)")
	if not first then
		return nil
	end
	local parent = layergit.shaOf(`{first}^`)
	if parent and sh.run("git", { "merge-base", "--is-ancestor", parent, main }).ok then
		return parent
	end
	return nil
end

-- The base of layer i (see baseOf), given the layers that exist and which positions are landed.
function layergit.baseFor(
	have: { [number]: stack.Layer },
	landedAt: { [number]: boolean },
	i: number
): string?
	local layer = have[i]
	local tip = if layer then layergit.layerTip(layer) else nil
	if not layer or not tip then
		return nil
	end
	local lower = have[i - 1]
	return layergit.baseOf(i, if lower then layergit.layerTip(lower) else nil, landedAt[i - 1] == true, tip)
end

-- One row per member in the raft's Order, from git: landed, complete, finished, claimed or missing.
function layergit.rows(raft: store.Item): { stack.Row }
	local issues = layergit.orderedMembers(raft)
	local have: { [number]: stack.Layer } = {}
	for _, layer in layergit.layersOf(raft.id) do
		have[layer.position] = layer
	end
	local landedAt: { [number]: boolean } = {}
	for i, issue in issues do
		landedAt[i] = layergit.landed(issue.id)
	end
	local rows: { stack.Row } = {}
	for i, issue in issues do
		local layer = have[i]
		local tip = if layer then layergit.layerTip(layer) else nil
		local state = "missing"
		if landedAt[i] then
			state = "landed"
		elseif layer and tip then
			local base = layergit.baseFor(have, landedAt, i)
			if base and layergit.layerFinished(layer, base) then
				state = if layergit.completeReason(raft, layer, base) == nil then "complete" else "finished"
			else
				state = "claimed"
			end
		elseif layer then
			state = "claimed"
		end
		table.insert(rows, {
			position = i,
			name = stack.branch(raft.id, i, issue.id),
			issue = issue.id,
			state = state,
			sha = if tip then string.sub(tip, 1, 12) else "-",
		})
	end
	return rows
end

-- origin carries the old single branch, and that branch is not merely the worktree branch sitting at main.
function layergit.oldShapeRefusal(raft: store.Item): string?
	if #layergit.layersOf(raft.id) > 0 then
		return nil
	end
	local old = `{raft.id}-{raft.slug}`
	local sha = layergit.shaOf(`origin/{old}`)
	local base = layergit.shaOf("origin/main")
	if not sha or not base or sha == base then
		return nil
	end
	local log = sh.git({ "log", "--format=%s", `{base}..{sha}` })
	if string.find(log, `tracker: start {raft.id}`, 1, true) then
		return stack.oldShapeMessage(raft.id, old)
	end
	return nil
end

-- The next layer to open, or the current unfinished layer to resume (startAt == "").
-- Returns issue, position, branch, startPoint, pull-request base.
function layergit.startLayer(raft: store.Item): (store.Item, number, string, string, string)
	if hasOrigin() then
		-- a fetch URL this sandbox cannot reach (a test that only wants the GitHub-shaped name) is not a reason
		-- to refuse the start; the push still uses the push URL. done and restack do fail when their fetch fails.
		sh.run("git", { "fetch", "--quiet", "origin" })
	end
	local why = layergit.oldShapeRefusal(raft)
	if why then
		fail(why)
	end
	local issues = layergit.orderedMembers(raft)
	if #issues == 0 then
		fail(`{raft.id} has no issues`)
	end
	local have: { [number]: stack.Layer } = {}
	for _, layer in layergit.layersOf(raft.id) do
		have[layer.position] = layer
	end
	local landedAt: { [number]: boolean } = {}
	for i, issue in issues do
		landedAt[i] = layergit.landed(issue.id)
	end
	local function baseFor(i: number): string?
		return layergit.baseFor(have, landedAt, i)
	end
	local current = stack.parse(sh.git({ "branch", "--show-current" }))
	if current and current.raft == raft.id and have[current.position] and not landedAt[current.position] then
		local below = baseFor(current.position)
		if below and not layergit.layerFinished(current, below) then
			local issue = store.get(current.issue)
			local prBase = if current.position == 1 or landedAt[current.position - 1]
				then "main"
				else stack.branch(raft.id, current.position - 1, issues[current.position - 1].id)
			return issue, current.position, current.name, "", prBase
		end
	end
	for i, issue in issues do
		if landedAt[i] then
			continue
		end
		if not have[i] then
			if i > 1 and landedAt[i - 1] then
				-- the layer below landed: this one is cut from main, which holds it
				return issue,
					i,
					stack.branch(raft.id, i, issue.id),
					if layergit.shaOf("origin/main")
						then "origin/main"
						elseif layergit.shaOf("main") then "main"
						else layergit.mainTip(),
					"main"
			elseif i > 1 then
				local below = have[i - 1]
				if not below then
					fail(`{raft.id} is missing layer {i - 1}`)
				end
				if not layergit.layerTip(below) then
					fail(`{below.name} has no tip`)
				end
				local belowBase = baseFor(i - 1)
				if not belowBase or not layergit.layerFinished(below, belowBase) then
					fail(`{below.issue} is not finished: ./zn finish {below.issue}`)
				end
				-- c0248: the layer below is complete (finished, green, reviewed) before the next one starts
				local notComplete = layergit.completeReason(raft, below, belowBase :: string)
				if notComplete then
					fail(notComplete)
				end
				return issue,
					i,
					stack.branch(raft.id, i, issue.id),
					if layergit.shaOf(`origin/{below.name}`) then `origin/{below.name}` else below.name,
					below.name
			end
			return issue,
				1,
				stack.branch(raft.id, 1, issue.id),
				if layergit.shaOf("origin/main")
					then "origin/main"
					elseif layergit.shaOf("main") then "main"
					else layergit.mainTip(),
				"main"
		end
	end
	fail(`{raft.id} is already active`)
	return issues[1] :: store.Item, 1, "", "", ""
end

function layergit.diffPaths(base: string): { string }
	local names = sh.git({ "diff", "--name-only", base, "HEAD" })
	local out: { string } = {}
	for path in string.gmatch(names .. "\n", "([^\n]*)\n") do
		if path ~= "" then
			table.insert(out, path)
		end
	end
	return out
end

function layergit.checkoutLayer(layer: stack.Layer)
	if layergit.shaOf(`refs/heads/{layer.name}`) then
		sh.git({ "switch", "--quiet", layer.name })
	else
		local remote = layergit.shaOf(`origin/{layer.name}`) or fail(`{layer.name} is not on origin`)
		sh.git({ "switch", "--quiet", "-c", layer.name, remote })
	end
end

function layergit.latestReview(raft: store.Item): (string, string, number)
	local finalLatest = 0
	if fs.isDir(raft.dir) then
		for _, name in fs.readDir(raft.dir) do
			local fn = tonumber(string.match(name, "^final%-review%-(%d+)%.md$"))
			if fn and fn > finalLatest then
				finalLatest = fn
			end
		end
	end
	return "final-review", "final-refute", finalLatest
end

-- The final review file's Verdict word, or nil when nobody wrote one. Never a default of approve.
function layergit.reviewVerdict(raft: store.Item): string?
	local reviewPrefix, _, latest = layergit.latestReview(raft)
	if latest == 0 then
		return nil
	end
	local review = "\n" .. fs.readFile(`{raft.dir}/{reviewPrefix}-{string.format("%03d", latest)}.md`)
	return string.match(review, "\n[Vv]erdict:%s*(%a+)")
end

return layergit
