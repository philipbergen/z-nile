--!strict
-- Reads git and the tracker into the facts work.luau decides on. The decision is not made here.
local fs = require("@lune/fs")
local layergit = require("./layergit")
local process = require("@lune/process")
local sh = require("../lib/sh")
local stack = require("./stack")
local statusLib = require("./status")
local store = require("./store")
local work = require("./work")

local workread = {}

local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end

local function section(text: string, heading: string): string
	local hay = "\n" .. text
	local mark = "\n## " .. heading
	local s = string.find(hay, mark, 1, true)
	if not s then
		return ""
	end
	local body = s + #mark
	local nxt = string.find(hay, "\n## ", body, true)
	local chunk = if nxt then string.sub(hay, body, nxt - 1) else string.sub(hay, body)
	return (string.gsub(chunk, "^%s*(.-)%s*$", "%1"))
end

local function mainTip(): string
	return layergit.shaOf("origin/main") or layergit.shaOf("main") or ""
end

local function holderOf(id: string): (string, string)
	local r = sh.run("git", {
		"log",
		"-1",
		"--format=%an <%ae>%x09%cI",
		"origin/main",
		`--grep=tracker: ready {id}`,
	})
	if not r.ok then
		return "", ""
	end
	local who, when = string.match(trim(r.stdout), "^(.-)\t(.+)$")
	return who or "", when or ""
end

local originFiles: { string }? = nil

local function originPaths(): { string }
	if originFiles then
		return originFiles
	end
	local found: { string } = {}
	originFiles = found
	if mainTip() == "" then
		return found
	end
	local listed = sh.run("git", { "ls-tree", "-r", "--name-only", "origin/main" })
	if listed.ok then
		for line in string.gmatch(listed.stdout .. "\n", "([^\n]*)\n") do
			if line ~= "" then
				table.insert(found, line)
			end
		end
	end
	return found
end

local function show(ref: string, path: string): string?
	local r = sh.run("git", { "show", `{ref}:{path}` })
	return if r.ok then r.stdout else nil
end

-- A tracker file: the working tree, origin/main, or a layer branch. The shared location of a raft is origin/main.
-- A review or a questions file committed only on the layer is still visible.
local function fileText(raftId: string, dir: string, name: string): string?
	local path = `{dir}/{name}`
	if fs.isFile(path) then
		return fs.readFile(path)
	end
	local onMain = show("origin/main", path)
	if onMain then
		return onMain
	end
	for _, layer in layergit.layersOf(raftId) do
		local tip = layergit.shaOf(layer.name) or layergit.shaOf(`origin/{layer.name}`)
		if tip then
			local text = show(tip, path)
			if text then
				return text
			end
		end
	end
	return nil
end

local function hasQuestions(raftId: string, dir: string): boolean
	return fileText(raftId, dir, "questions.md") ~= nil
end

local function designReady(item: store.Item): boolean
	if store.readFront(item.doc).design ~= "ready" then
		return false
	end
	for _, m in store.members(item.id) do
		if store.readFront(m.doc).design ~= "ready" then
			return false
		end
	end
	return true
end

local function depsMet(item: store.Item, memberIds: { [string]: boolean }): boolean
	for _, m in store.members(item.id) do
		for _, dep in store.idList(store.readFront(m.doc).depends_on) do
			if not memberIds[dep] then
				local found = store.find(dep)
				if not found or found.state ~= "done" then
					return false
				end
			end
		end
	end
	return true
end

local function issueIds(item: store.Item): { string }
	local members = store.members(item.id)
	local specs: { stack.Member } = {}
	for _, m in members do
		table.insert(specs, { id = m.id, dependsOn = store.idList(store.readFront(m.doc).depends_on) })
	end
	local ids = stack.order(item.id, section(fs.readFile(item.doc), "Order & dependencies"), specs)
	if ids and #ids > 0 then
		return ids
	end
	local listed = store.idList(store.readFront(item.doc).issues)
	if #listed > 0 then
		return listed
	end
	local out: { string } = {}
	for _, m in members do
		table.insert(out, m.id)
	end
	table.sort(out)
	return out
end

-- This checkout's branch when it has one, otherwise the copy on origin. The worker decides from the
-- commits it can see; another clone sees origin after a fetch.
local function tipOf(layer: stack.Layer): string?
	return layergit.shaOf(layer.name) or layergit.shaOf(`origin/{layer.name}`)
end

local function layersOf(raftId: string, issues: { string }): { work.LayerFact }
	local byPos: { [number]: stack.Layer } = {}
	for _, layer in layergit.layersOf(raftId) do
		byPos[layer.position] = layer
	end
	local base = mainTip()
	local out: { work.LayerFact } = {}
	for i, issue in issues do
		local layer = byPos[i]
		if layer and layer.issue == issue and base ~= "" then
			local tip = tipOf(layer)
			local commits = 0
			local subject = ""
			if tip then
				commits = tonumber(trim(sh.git({ "rev-list", "--count", `{base}..{tip}` }))) or 0
				if commits > 0 then
					subject = trim(sh.git({ "log", "-1", "--format=%s", tip }))
				end
			end
			local finished = if tip then layergit.layerFinishSha(layer, base, tip) ~= nil else false
			table.insert(out, {
				position = i,
				issue = issue,
				name = layer.name,
				commits = commits,
				onlyStart = commits == 1 and string.sub(subject, 1, 14) == "tracker: start",
				finished = finished,
			})
			if tip then
				base = tip
			end
		end
	end
	return out
end

local function stacked(raftId: string, issues: { string }, layers: { work.LayerFact }): boolean
	if #layers < #issues then
		return false
	end
	local onto = mainTip()
	if onto == "" then
		return false
	end
	for i, issue in issues do
		local layer: work.LayerFact? = nil
		for _, candidate in layers do
			if candidate.position == i and candidate.issue == issue then
				layer = candidate
			end
		end
		if not layer then
			return false
		end
		local tip = tipOf({
			raft = raftId,
			position = (layer :: work.LayerFact).position,
			issue = issue,
			name = (layer :: work.LayerFact).name,
		})
		if not tip or not sh.run("git", { "merge-base", "--is-ancestor", onto, tip }).ok then
			return false
		end
		onto = tip
	end
	return true
end

-- The highest `<prefix>NNN.md` in the working tree, on origin/main, or on a layer. Local text wins a tie.
local function numbered(raftId: string, dir: string, prefix: string): (number, string)
	local best, body = 0, ""
	local function consider(name: string, text: string?)
		local captured = string.match(name, "^" .. prefix .. "(%d+)%.md$")
		local n = if captured then tonumber(captured) else nil
		if n and text and n > best then
			best = n
			body = text
		end
	end
	if fs.isDir(dir) then
		for _, name in fs.readDir(dir) do
			if fs.isFile(`{dir}/{name}`) then
				consider(name, fs.readFile(`{dir}/{name}`))
			end
		end
	end
	for _, path in originPaths() do
		if string.sub(path, 1, #dir + 1) == `{dir}/` and not fs.isFile(path) then
			local name = string.sub(path, #dir + 2)
			if not string.find(name, "/", 1, true) then
				consider(name, show("origin/main", path))
			end
		end
	end
	for _, layer in layergit.layersOf(raftId) do
		local tip = layergit.shaOf(layer.name) or layergit.shaOf(`origin/{layer.name}`)
		if tip then
			local listed = sh.run("git", { "ls-tree", "-r", "--name-only", tip, "--", dir })
			if listed.ok then
				for path in string.gmatch(listed.stdout .. "\n", "([^\n]*)\n") do
					if path ~= "" and not fs.isFile(path) then
						consider(string.match(path, "([^/]+)$") or "", show(tip, path))
					end
				end
			end
		end
	end
	return best, body
end

local function verdictOf(text: string): string?
	return string.match("\n" .. text, "\n[Vv]erdict:%s*(%a+)")
end

local function codeReview(raftId: string, dir: string): string
	local n, text = numbered(raftId, dir, "review%-")
	if n == 0 then
		return "none"
	end
	if verdictOf(text) == "approve" then
		return "resolved"
	end
	return "open"
end

local function finalReview(raftId: string, dir: string): string
	local n, text = numbered(raftId, dir, "final%-review%-")
	if n == 0 then
		return "none"
	end
	if verdictOf(text) == "approve" then
		return "approved"
	end
	return "open"
end

local function one(item: store.Item): work.RaftFact
	local front = store.readFront(item.doc)
	local issues = issueIds(item)
	local memberIds: { [string]: boolean } = {}
	for _, id in issues do
		memberIds[id] = true
	end
	local layers = layersOf(item.id, issues)
	local who, when = holderOf(item.id)
	local trace = fileText(item.id, item.dir, "trace.md") ~= nil
	local final = finalReview(item.id, item.dir)
	return {
		id = item.id,
		title = front.title or item.slug,
		where = item.state,
		status = statusLib.effective(front, item.state),
		designReady = designReady(item),
		depsMet = depsMet(item, memberIds),
		questions = hasQuestions(item.id, item.dir),
		issues = issues,
		layers = layers,
		holder = who,
		since = when,
		stacked = stacked(item.id, issues, layers),
		codeReview = codeReview(item.id, item.dir),
		finalReview = final,
		trace = trace,
		traceOk = trace and final == "approved",
	}
end

local function frontText(text: string): { [string]: string }
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-")
	local out: { [string]: string } = {}
	if block then
		for line in string.gmatch(block, "[^\n]+") do
			local k, v = string.match(line, "^([%w_]+):%s*(.-)%s*$")
			if k and v then
				out[k] = v
			end
		end
	end
	return out
end

-- state, directory, id, from a document path on origin/main. Retired rafts are not a place a worker reads.
local function slot(path: string): (string?, string?, string?)
	local root, id, file = string.match(path, "^(.*)/rafts/active/(R%d%d%d%d)/(R%d%d%d%d)%.md$")
	if root and id == file then
		return "active", `{root}/rafts/active/{id}`, id
	end
	root, id, file = string.match(path, "^(.*)/rafts/done/(R%d%d%d%d)/(R%d%d%d%d)%.md$")
	if root and id == file then
		return "done", `{root}/rafts/done/{id}`, id
	end
	root, id, file = string.match(path, "^(.*)/rafts/(R%d%d%d%d)/(R%d%d%d%d)%.md$")
	if root and id == file then
		return "backlog", `{root}/rafts/{id}`, id
	end
	root, id, file = string.match(path, "^(.*)/issues/active/([fdc]%d%d%d%d)/([fdc]%d%d%d%d)%.md$")
	if root and id == file then
		return "active", `{root}/issues/active/{id}`, id
	end
	root, id, file = string.match(path, "^(.*)/issues/done/([fdc]%d%d%d%d)/([fdc]%d%d%d%d)%.md$")
	if root and id == file then
		return "done", `{root}/issues/done/{id}`, id
	end
	root, id, file = string.match(path, "^(.*)/issues/([fdc]%d%d%d%d)/([fdc]%d%d%d%d)%.md$")
	if root and id == file then
		return "backlog", `{root}/issues/{id}`, id
	end
	return nil, nil, nil
end

type At = { path: string, state: string, dir: string }

local function factFrom(id: string, at: At, text: string, byId: { [string]: At }): work.RaftFact
	local front = frontText(text)
	local listed = store.idList(front.issues)
	local specs: { stack.Member } = {}
	local memberFront: { [string]: { [string]: string } } = {}
	for _, mid in listed do
		local found = byId[mid]
		local raw = if found then show("origin/main", found.path) else nil
		local mf: { [string]: string } = if raw then frontText(raw) else {}
		memberFront[mid] = mf
		table.insert(specs, { id = mid, dependsOn = store.idList(mf.depends_on) })
	end
	local ordered = stack.order(id, section(text, "Order & dependencies"), specs)
	local issues: { string } = if ordered and #ordered > 0 then ordered else listed
	local memberIds: { [string]: boolean } = {}
	for _, mid in issues do
		memberIds[mid] = true
	end
	local ready = front.design == "ready"
	local deps = true
	for _, mid in issues do
		local mf: { [string]: string } = memberFront[mid] or {}
		if mf.design ~= "ready" then
			ready = false
		end
		for _, dep in store.idList(mf.depends_on) do
			if not memberIds[dep] then
				local depAt = byId[dep]
				if not depAt or depAt.state ~= "done" then
					deps = false
				end
			end
		end
	end
	local layers = layersOf(id, issues)
	local who, when = holderOf(id)
	local final = finalReview(id, at.dir)
	local trace = fileText(id, at.dir, "trace.md") ~= nil
	return {
		id = id,
		title = front.title or id,
		where = at.state,
		status = statusLib.effective(front, at.state),
		designReady = ready,
		depsMet = deps,
		questions = hasQuestions(id, at.dir),
		issues = issues,
		layers = layers,
		holder = who,
		since = when,
		stacked = stacked(id, issues, layers),
		codeReview = codeReview(id, at.dir),
		finalReview = final,
		trace = trace,
		traceOk = trace and final == "approved",
	}
end

-- Rafts as origin/main has them. This checkout's working tree can be another branch; the shared state is the commit.
local function fromOrigin(): { work.RaftFact }
	local byId: { [string]: At } = {}
	for _, path in originPaths() do
		local state, dir, id = slot(path)
		if state and dir and id then
			byId[id] = { path = path, state = state, dir = dir }
		end
	end
	local out: { work.RaftFact } = {}
	for id, at in byId do
		if store.isRaftId(id) then
			local text = show("origin/main", at.path)
			if text then
				table.insert(out, factFrom(id, at, text, byId))
			end
		end
	end
	return out
end

function workread.held(): string?
	local branch = trim(sh.run("git", { "branch", "--show-current" }).stdout)
	local layer = stack.parse(branch)
	if layer then
		return layer.raft
	end
	local cwd = (string.gsub(process.cwd, "/+$", ""))
	return string.match(cwd, "/%.worktree/(R%d%d%d%d)$")
end

function workread.collect(asked: string?): work.Input
	local rafts: { work.RaftFact } = {}
	local seen: { [string]: boolean } = {}
	if layergit.shaOf("origin/main") then
		for _, fact in fromOrigin() do
			seen[fact.id] = true
			table.insert(rafts, fact)
		end
	end
	for _, item in store.all("raft") do
		if not seen[item.id] then
			table.insert(rafts, one(item))
		end
	end
	return { asked = asked, held = workread.held(), rafts = rafts }
end

return workread
