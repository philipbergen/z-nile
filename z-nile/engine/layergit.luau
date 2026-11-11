--!strict
-- Git reads for a raft's layers. The shape (names, finished, order) is stack.luau; this module only asks git.
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

local function raftSection(text: string, heading: string): string
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
	local ids, err = stack.order(raft.id, raftSection(fs.readFile(raft.doc), "Order & dependencies"), specs)
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

-- True when the layer tip is exactly one "<issue>: <title>" commit whose parent is `base`.
function layergit.layerFinished(layer: stack.Layer, base: string): boolean
	local tip = layergit.layerTip(layer)
	if not tip or base == "" then
		return false
	end
	local count = tonumber(sh.trim(sh.git({ "rev-list", "--count", `{base}..{tip}` }))) or 0
	local subject = sh.trim(sh.git({ "log", "-1", "--format=%s", tip }))
	local parent = sh.trim(sh.git({ "rev-parse", `{tip}^` }))
	local issue = store.find(layer.issue)
	local title = if issue then layergit.issueTitle(issue) else layer.issue
	return stack.finished(count, subject, parent, base, layer.issue, title)
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
	local baseTip = layergit.mainTip()
	local current = stack.parse(sh.git({ "branch", "--show-current" }))
	if current and current.raft == raft.id and have[current.position] then
		local below = if current.position == 1
			then baseTip
			else layergit.layerTip(have[current.position - 1] :: stack.Layer)
		if below and not layergit.layerFinished(current, below) then
			local issue = store.get(current.issue)
			local prBase = if current.position == 1
				then "main"
				else stack.branch(raft.id, current.position - 1, issues[current.position - 1].id)
			return issue, current.position, current.name, "", prBase
		end
	end
	for i, issue in issues do
		if not have[i] then
			if i > 1 then
				local below = have[i - 1]
				if not below then
					fail(`{raft.id} is missing layer {i - 1}`)
				end
				if not layergit.layerTip(below) then
					fail(`{below.name} has no tip`)
				end
				local belowBase = if i == 2 then baseTip else layergit.layerTip(have[i - 2] :: stack.Layer)
				if not belowBase or not layergit.layerFinished(below, belowBase) then
					fail(`{below.issue} is not finished: ./zn finish {below.issue}`)
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

function layergit.reviewVerdict(raft: store.Item): string
	local latest = 0
	for _, name in fs.readDir(raft.dir) do
		local n = tonumber(string.match(name, "^review%-(%d+)%.md$"))
		if n and n > latest then
			latest = n
		end
	end
	if latest == 0 then
		return "approve"
	end
	local review = "\n" .. fs.readFile(`{raft.dir}/review-{string.format("%03d", latest)}.md`)
	return string.match(review, "\n[Vv]erdict:%s*(%a+)") or "approve"
end

return layergit
