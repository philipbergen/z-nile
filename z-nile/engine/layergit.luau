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

export type ReadyRecord = { lands: boolean, on: string? }

-- f0399: how a raft was readied, from the trailers of its newest ready commit on origin/main's first-parent
-- history. A raft started the legacy way, stopped since, or readied before trailers existed has none. Nothing in a
-- worktree is read, so no edit on a layer changes the answer.
function layergit.readyRecord(raftId: string): ReadyRecord
	local ref = if layergit.shaOf("origin/main")
		then "origin/main"
		elseif layergit.shaOf("main") then "main"
		else nil
	if not ref then
		return { lands = false }
	end
	local found = sh.run("git", {
		"log",
		"--first-parent",
		"-1",
		"-E",
		`--grep=^tracker: (ready|stop) {raftId} `,
		`--grep=^tracker: start {raftId}`,
		"--format=%B",
		ref,
	})
	if not found.ok then
		return { lands = false }
	end
	local subject = string.match(found.stdout, "^([^\n]*)") or ""
	if string.sub(subject, 1, #`tracker: ready {raftId} `) ~= `tracker: ready {raftId} ` then
		return { lands = false }
	end
	local record: ReadyRecord = { lands = false }
	for line in string.gmatch(found.stdout .. "\n", "([^\n]*)\n") do
		if line == "Lands: approved" then
			record.lands = true
		end
		local on = string.match(line, "^On: (R%d%d%d%d)$")
		if on then
			record.on = on
		end
	end
	return record
end

-- f0399: what a raft's lowest layer sits on, as the tip and the pull-request base. A raft readied `--on <D>` sits
-- on its base commit (the branch <R>/base) until D is done on origin/main; every other raft sits on main.
function layergit.raftBase(raftId: string): (string, string)
	local on = layergit.readyRecord(raftId).on
	if not on then
		return layergit.mainTip(), "main"
	end
	for _, root in store.roots() do
		local doc = `{store.dirFor("raft", "done", on, root)}/{on}.md`
		if sh.run("git", { "cat-file", "-e", `origin/main:{doc}` }).ok then
			return layergit.mainTip(), "main"
		end
	end
	local name = `{raftId}/base`
	local tip = layergit.shaOf(`origin/{name}`) or layergit.shaOf(name)
	if not tip then
		return layergit.mainTip(), "main"
	end
	return tip, name
end

-- f0399: the base commit of a raft readied `--on <D>`, on the branch <R>/base: D's top layer tip as its parent,
-- and a tree that differs from it only in R's own tracker folders, which are as on origin/main (R is active there;
-- D's layers were cut before that). Built in this worktree, which must be clean, and pushed. Nil when the raft is
-- not built on another, or that raft has landed. It is current while its parent is D's top layer tip.
function layergit.buildBase(raft: store.Item): string?
	local on = layergit.readyRecord(raft.id).on
	local _, prBase = layergit.raftBase(raft.id)
	local name = `{raft.id}/base`
	if not on then
		return nil
	end
	local layers = layergit.layersOf(on)
	if #layers == 0 then
		-- no layer of the base raft is left: it landed and its branches are gone
		return nil
	end
	local top = layers[#layers]
	local tip = layergit.layerTip(top) or fail(`{top.name} has no tip`)
	local have = layergit.shaOf(`origin/{name}`) or layergit.shaOf(name)
	if have and prBase ~= name then
		return nil -- the base raft is done: the raft sits on main now
	end
	if have and layergit.shaOf(`{have}^`) == tip then
		return have
	end
	local items: { store.Item } = { raft }
	for _, m in layergit.orderedMembers(raft) do
		table.insert(items, m)
	end
	local mainRef = if layergit.shaOf("origin/main") then "origin/main" else "main"
	local branch = sh.trim(sh.git({ "branch", "--show-current" }))
	local back = if branch ~= "" then branch else sh.trim(sh.git({ "rev-parse", "HEAD" }))
	sh.git({ "switch", "--quiet", "--detach", tip })
	for _, item in items do
		for _, state in { "backlog", "active", "done" } :: { store.State } do
			local dir = store.dirFor(item.kind, state, item.id, item.root)
			if sh.run("git", { "ls-files", "--error-unmatch", "--", dir }).ok then
				sh.git({ "rm", "-r", "--quiet", "--", dir })
			end
		end
		sh.git({ "checkout", mainRef, "--", item.dir })
	end
	sh.git({ "commit", "--quiet", "--allow-empty", "-m", `tracker: base {raft.id} on {on}` })
	local sha = sh.trim(sh.git({ "rev-parse", "HEAD" }))
	if branch ~= "" then
		sh.git({ "switch", "--quiet", back })
	else
		sh.git({ "switch", "--quiet", "--detach", back })
	end
	sh.git({ "branch", "--force", name, sha })
	if hasOrigin() then
		local remote = layergit.shaOf(`origin/{name}`)
		sh.git({
			"push",
			"--quiet",
			if remote then `--force-with-lease=refs/heads/{name}:{remote}` else "--force-with-lease",
			"origin",
			`refs/heads/{name}:refs/heads/{name}`,
		})
		sh.run("git", { "fetch", "--quiet", "origin", name })
	end
	return sha
end

-- The commit layer 1 is judged against (d0331): where `tip` left main, not main's newest commit. Main gaining
-- commits after that is no reason to refuse or to restack; only `restack` moves a layer onto main's tip.
-- With no shared commit it is main's tip, so every caller's own check still refuses.
function layergit.mainFork(tip: string, main: string?): string
	local onto = main or layergit.mainTip()
	local r = sh.run("git", { "merge-base", onto, tip })
	local sha = if r.ok then sh.trim(r.stdout) else ""
	return if sha == "" then onto else sha
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
			or name == "spend.md" -- d0333: every `./zn commit` rewrites the raft's snapshot
			or string.match(name, "^trace%-%d+%.md$") ~= nil
			or name == `{raftId}.md`
			or string.match(name, "^review%-%d+%.md$") ~= nil
			or string.match(name, "^refute%-%d+%.md$") ~= nil
			or string.match(name, "^final%-review%-%d+%.md$") ~= nil
			or string.match(name, "^final%-refute%-%d+%.md$") ~= nil
		then
			return true
		end
	end
	-- f0399: the person's approval, and a guess recorded while answering a review, leave a layer finished
	for _, file in { "approval%.md", "guesses%.md" } do
		if
			string.match(path, `/issues/active/[fdc]%d%d%d%d/{file}$`)
			or string.match(path, `/issues/[fdc]%d%d%d%d/{file}$`)
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
-- (either that commit is the tip, or commits above it touch only post-finish review/trace/ruling files
-- and the raft's own `spend.md`, which every `./zn commit` rewrites).
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
	_raft: store.Item,
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

-- `git patch-id --stable` of a commit: what a clean rebase keeps (the diff, not the parent). "" when it cannot be read.
function layergit.patchId(sha: string): string
	local shown = sh.run("git", { "show", "--format=", "--no-color", sha })
	if not shown.ok or shown.stdout == "" then
		return ""
	end
	local id = sh.run("git", { "patch-id", "--stable" }, shown.stdout)
	return if id.ok then (string.match(id.stdout, "^(%x+)") or "") else ""
end

local function backlogIssue(id: string): boolean
	local item = store.find(id)
	return item ~= nil and item.kind == "issue" and item.state == "backlog"
end

-- The base of one layer of the raft (see baseOf), asked from git: what `finish` squashes onto.
function layergit.baseOfLayer(raft: store.Item, layer: stack.Layer): string?
	local issues = layergit.orderedMembers(raft)
	local have: { [number]: stack.Layer } = {}
	for _, l in layergit.layersOf(raft.id) do
		have[l.position] = l
	end
	local landedAt: { [number]: boolean } = {}
	for i, issue in issues do
		landedAt[i] = layergit.landed(issue.id)
	end
	return layergit.baseFor(have, landedAt, layer.position, raft.id)
end

-- The finish commit of a layer and its patch id, or nil and the reason the layer is not finished.
function layergit.finishStamp(raft: store.Item, layer: stack.Layer): (string?, string?, string?)
	local base = layergit.baseOfLayer(raft, layer)
	local sha = if base then layergit.layerFinishSha(layer, base) else nil
	if not sha then
		return nil, nil, `{layer.issue} is not finished: ./zn finish {layer.issue}`
	end
	return sha, layergit.patchId(sha), nil
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
		patchId = layergit.patchId(finishSha),
		review = review,
		refute = refute,
		doc = doc,
		backlog = backlogIssue,
		reviewName = if num then `review-{num}.md` else nil,
		refuteName = if num then `refute-{num}.md` else nil,
	})
	if reason then
		return `{layer.issue} is not complete: {reason}`
	end
	return nil
end

-- A layer is landed when its issue is in done/ on origin/main (main with no remote), never in this tree: a layer's
-- own tree was cut before the layers below it landed (zz-arch lesson stacked-layer-reads-landing-from-origin), and
-- a tree that moves an issue to done/ by hand has landed nothing. The bind that lands a layer moves it.
function layergit.landed(issueId: string): boolean
	local here = store.find(issueId)
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

-- The commit a layer is judged against. The lowest layer not yet landed (layer 1, or the one above the landed ones)
-- is judged against its fork, where its tip left main (d0331's rule, and its ruling "Any lowest layer": main gaining
-- commits, a landing included, is no reason to restack); `lowest` replaces the fork for a layer 1 whose raft is built
-- on an unlanded raft (f0399). Any other layer is judged against the tip of the layer below it.
function layergit.baseOf(
	position: number,
	belowTip: string?,
	belowLanded: boolean,
	tip: string,
	lowest: string?
): string?
	if position == 1 or belowLanded then
		return lowest or layergit.mainFork(tip)
	end
	return belowTip
end

-- The base of layer i (see baseOf), given the layers that exist and which positions are landed.
function layergit.baseFor(
	have: { [number]: stack.Layer },
	landedAt: { [number]: boolean },
	i: number,
	raftId: string
): string?
	local layer = have[i]
	local tip = if layer then layergit.layerTip(layer) else nil
	if not layer or not tip then
		return nil
	end
	local lowest: string? = nil
	if i == 1 then
		local baseTip, basePr = layergit.raftBase(raftId)
		if basePr ~= "main" then
			lowest = baseTip
		end
	end
	local lower = have[i - 1]
	return layergit.baseOf(
		i,
		if lower then layergit.layerTip(lower) else nil,
		landedAt[i - 1] == true,
		tip,
		lowest
	)
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
			local base = layergit.baseFor(have, landedAt, i, raft.id)
			if base and layergit.layerFinished(layer, base) then
				state = if layergit.marked(raft)
						and layergit.completeReason(raft, layer, base) == nil
					then "complete"
					else "finished"
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
	local baseTip, basePr = layergit.raftBase(raft.id)
	local landedAt: { [number]: boolean } = {}
	for i, issue in issues do
		landedAt[i] = layergit.landed(issue.id)
	end
	local function baseFor(i: number): string?
		return layergit.baseFor(have, landedAt, i, raft.id)
	end
	local current = stack.parse(sh.git({ "branch", "--show-current" }))
	if current and current.raft == raft.id and have[current.position] and not landedAt[current.position] then
		local below = baseFor(current.position)
		if below and not layergit.layerFinished(current, below) then
			local issue = store.get(current.issue)
			local prBase = if current.position == 1
				then basePr
				elseif landedAt[current.position - 1] then "main"
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
				local notComplete = if layergit.marked(raft)
					then layergit.completeReason(raft, below, belowBase :: string)
					else nil
				if notComplete then
					fail(notComplete)
				end
				return issue,
					i,
					stack.branch(raft.id, i, issue.id),
					if layergit.shaOf(`origin/{below.name}`) then `origin/{below.name}` else below.name,
					below.name
			end
			if basePr ~= "main" then
				return issue, 1, stack.branch(raft.id, 1, issue.id), baseTip, basePr
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

-- c0248: a raft readied once layer reviews exist carries `layers: reviewed`; only such a raft has each layer's review
-- in its issue's folder and a final review and trace per landing. An older raft keeps the rule it was readied under.
function layergit.marked(raft: store.Item): boolean
	return store.readFront(raft.doc).layers == "reviewed"
end

-- The numbers of the raft folder's `<prefix>-NNN.md` files: on origin/main, and in this working tree.
function layergit.rounds(raft: store.Item, stem: string): ({ number }, { number })
	local prefix = string.gsub(stem, "%-", "%%-") -- a name with a dash is a pattern with a quantifier
	local onMain: { number } = {}
	local ref = if layergit.shaOf("origin/main")
		then "origin/main"
		elseif layergit.shaOf("main") then "main"
		else nil
	if ref then
		local listed = sh.run("git", { "ls-tree", "--name-only", ref, `{raft.dir}/` })
		if listed.ok then
			for line in string.gmatch(listed.stdout .. "\n", "([^\n]*)\n") do
				local n = tonumber((string.match(line, `/{prefix}%-(%d+)%.md$`)))
				if n then
					table.insert(onMain, n)
				end
			end
		end
	end
	local here: { number } = {}
	if fs.isDir(raft.dir) then
		for _, name in fs.readDir(raft.dir) do
			local n = tonumber((string.match(name, `^{prefix}%-(%d+)%.md$`)))
			if n then
				table.insert(here, n)
			end
		end
	end
	return onMain, here
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

-- c0248: a landing below a block runs the raft's checks for its own members only (`done` sets ZN_BIND_MEMBERS, a
-- comma list). The members `./zn members` and `promote-check` see; an id that is not a member is refused.
function layergit.bindScope(all: { store.Item }): { store.Item }
	local scoped = process.env.ZN_BIND_MEMBERS
	if scoped == nil or scoped == "" then
		return all
	end
	local byId: { [string]: store.Item } = {}
	for _, m in all do
		byId[m.id] = m
	end
	local out: { store.Item } = {}
	for id in string.gmatch(scoped, "[^,%s]+") do
		local m = byId[id]
		if not m then
			fail(`ZN_BIND_MEMBERS names {id}, which is not a member of this raft`)
		end
		table.insert(out, m)
	end
	return out
end

-- c0248: a new review-NNN.md or refute-NNN.md in the folder of the issue whose layer this branch is gets the tool's
-- stamp (`Commit:` the layer's finish commit, `Patch:` its patch id), so the file vouches for exactly what it reviewed.
-- An unfinished layer refuses it. Only a raft readied with layers: reviewed has the rule.
-- c0248: stamps the layer's new review and refute files in its issue folder with the finish commit and its patch id.
-- Every file is checked before any is written. A new file (not in HEAD) may carry no stamp but the tool's own for the
-- finish (`Commit:` and `Patch:` exactly as the tool writes them, so a command run again after a failed commit goes
-- on); a new review must name on its `Inputs:` line the finish, or a commit with its patch. A committed file may be
-- corrected (a refute's answer, a typo), but its stamp is never changed: a stale review is answered or reviewed again,
-- never re-stamped.
function layergit.stampLayerReviews()
	local layer = stack.parse(sh.git({ "branch", "--show-current" }))
	if not layer then
		return
	end
	local raft = store.find(layer.raft)
	if not raft or not layergit.marked(raft) then
		return
	end
	local function ownRound(path: string): string?
		local owner, name = string.match(path, "/issues/active/([fdc]%d%d%d%d)/([^/]+)$")
		if owner == nil then
			owner, name = string.match(path, "/issues/([fdc]%d%d%d%d)/([^/]+)$")
		end
		if
			owner == layer.issue
			and name ~= nil
			and (
				string.match(name, "^review%-%d+%.md$") ~= nil
				or string.match(name, "^refute%-%d+%.md$") ~= nil
			)
		then
			return name
		end
		return nil
	end
	local planned: { { path: string, text: string, name: string } } = {}
	-- raw output: a trimmed one loses the leading space of the first line's status code
	local status = sh.run("git", { "status", "--porcelain", "--untracked-files=all" }).stdout
	for line in string.gmatch(status .. "\n", "([^\n]*)\n") do
		local path = string.match(line, "^.. (.+)$")
		local name = if path then ownRound(path) else nil
		if not path or not name or not fs.isFile(path) then
			continue
		end
		local text = fs.readFile(path)
		local before = sh.run("git", { "show", `HEAD:{path}` })
		if before.ok then
			local c0, p0 = completion.stampsOf(before.stdout)
			local c1, p1 = completion.stampsOf(text)
			if c0 ~= c1 or p0 ~= p1 then
				fail(
					`{name} is committed: its Commit: and Patch: are the tool's and never change; answer it, or review again`
				)
			end
			continue
		end
		table.insert(planned, { path = path, text = text, name = name })
	end
	if #planned == 0 then
		return
	end
	local sha, patch, why = layergit.finishStamp(raft, layer)
	if not sha or not patch or patch == "" then
		fail(`{planned[1].name}: {why or "the layer's patch id cannot be read"}`)
	end
	for _, p in planned do
		local c, pid = completion.stampsOf(p.text)
		if
			(c ~= nil or pid ~= nil)
			and (c ~= string.lower(sha :: string) or pid ~= string.lower(patch :: string))
		then
			fail(
				`{p.name} already carries a Commit: or Patch: line that is not the layer's finish: the tool stamps it; remove the line`
			)
		end
		if string.match(p.name, "^review%-") then
			-- the review vouches for the commit it read: a commit its Inputs: line names is the finish, or has its patch
			local named = false
			for _, read in completion.reviewedShas(p.text) do
				if string.sub(sha :: string, 1, #read) == read then
					named = true
				else
					local full = layergit.shaOf(read)
					named = full ~= nil and layergit.patchId(full :: string) == patch
				end
				if named then
					break
				end
			end
			if not named then
				fail(
					`{p.name} names no commit on its Inputs: line that is the layer's finish {sha} or has its change: commit the review before re-finishing, or review again`
				)
			end
		end
	end
	for _, p in planned do
		fs.writeFile(p.path, completion.stamp(p.text, sha :: string, patch :: string))
	end
end

return layergit
