--!strict
-- Reads git and the tracker into the facts work.luau decides on. The decision is not made here.
--
-- One `ls-tree` of origin/main, one `cat-file --batch` of the files that decision needs, and one
-- `git log` for every ready commit. Done rafts are not read unless one is named. Layer tips are
-- read only for active rafts (the status line and the layer action). A cold `work next` used to
-- take minutes because it built a fact for every raft, done ones included, and each of those ran
-- `git for-each-ref`, `git show` per file and `git log --grep` over all of main. `work status`
-- is that same function, so a later call only looked faster once the page cache was warm.
local approval = require("./approval")
local contract = require("./contract")
local fs = require("@lune/fs")
local idea = require("./idea")
local layergit = require("./layergit")
local process = require("@lune/process")
local projects = require("./projects")
local raftplan = require("./raftplan")
local readycheck = require("./readycheck")
local sessionread = require("./sessionread")
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

local function sideFile(name: string): boolean
	return name == "questions.md"
		or name == "trace.md"
		or string.match(name, "^trace%-%d+%.md$") ~= nil
		or string.match(name, "^review%-%d+%.md$") ~= nil
		or string.match(name, "^final%-review%-%d+%.md$") ~= nil
end

local function verdictOf(text: string): string?
	return string.match("\n" .. text, "\n[Vv]erdict:%s*(%a+)")
end

local function bestNumbered(sides: { [string]: string }, prefix: string): (number, string)
	local best, body = 0, ""
	for name, text in sides do
		local captured = string.match(name, "^" .. prefix .. "(%d+)%.md$")
		local n = if captured then tonumber(captured) else nil
		if n and n > best then
			best = n
			body = text
		end
	end
	return best, body
end

local function reviewState(sides: { [string]: string }, prefix: string, approved: string): string
	local n, text = bestNumbered(sides, prefix)
	if n == 0 then
		return "none"
	end
	if verdictOf(text) == "approve" then
		return approved
	end
	return "open"
end

-- `git cat-file --batch` in request order. A missing object is an empty slot.
local function catBatch(specs: { string }): { string }
	local out: { string } = {}
	if #specs == 0 then
		return out
	end
	local r = sh.run("git", { "cat-file", "--batch" }, table.concat(specs, "\n") .. "\n")
	if not r.ok then
		return out
	end
	local i = 1
	local text = r.stdout
	for _ = 1, #specs do
		local nl = string.find(text, "\n", i, true)
		if not nl then
			table.insert(out, "")
			continue
		end
		local header = string.sub(text, i, nl - 1)
		i = nl + 1
		local size = string.match(header, "^%x+ %w+ (%d+)$")
		if size then
			local n = tonumber(size) :: number
			table.insert(out, string.sub(text, i, i + n - 1))
			i += n + 1
		else
			table.insert(out, "")
		end
	end
	return out
end

type Tip = { name: string, sha: string, position: number, issue: string }

local function tipsFor(raftId: string, refs: { { sha: string, ref: string } }): { [number]: Tip }
	local byPos: { [number]: Tip } = {}
	local localAt: { [number]: boolean } = {}
	for _, row in refs do
		local layer = stack.parse(row.ref)
		if layer and layer.raft == raftId and row.sha ~= "" then
			local origin = string.sub(row.ref, 1, 7) == "origin/"
			if not byPos[layer.position] or (not origin and not localAt[layer.position]) then
				byPos[layer.position] = {
					name = layer.name,
					sha = row.sha,
					position = layer.position,
					issue = layer.issue,
				}
				if not origin then
					localAt[layer.position] = true
				end
			end
		end
	end
	return byPos
end

local function layerFacts(
	raftId: string,
	issues: { string },
	tips: { [number]: Tip },
	mainSha: string,
	landed: { [string]: boolean },
	marked: boolean
): { work.LayerFact }
	local base = if tips[1] then layergit.mainFork(tips[1].sha, mainSha) else mainSha
	local out: { work.LayerFact } = {}
	local raftItem = if marked then store.find(raftId) else nil
	for i, issue in issues do
		local tip = tips[i]
		if landed[issue] then
			-- c0248: landed by an earlier bind; the layer above it is judged against its fork with main, like layer 1
			table.insert(out, {
				position = i,
				issue = issue,
				name = if tip then tip.name else stack.branch(raftId, i, issue),
				commits = 0,
				onlyStart = false,
				finished = true,
				landed = true,
			})
			local above = tips[i + 1]
			base = if above then layergit.mainFork(above.sha, mainSha) else mainSha
		elseif tip and tip.issue == issue and base ~= "" then
			local count = 0
			local subject = ""
			local counted = sh.run("git", { "rev-list", "--count", `{base}..{tip.sha}` })
			if counted.ok then
				count = tonumber(trim(counted.stdout)) or 0
			end
			if count > 0 then
				local logged = sh.run("git", { "log", "-1", "--format=%s", tip.sha })
				if logged.ok then
					subject = trim(logged.stdout)
				end
			end
			local finished = false
			local ok, finish = pcall(layergit.layerFinishSha, {
				raft = raftId,
				position = i,
				issue = issue,
				name = tip.name,
			}, base, tip.sha)
			finished = ok and finish ~= nil
			local fact: work.LayerFact = {
				position = i,
				issue = issue,
				name = tip.name,
				commits = count,
				onlyStart = count == 1 and string.sub(subject, 1, 14) == "tracker: start",
				finished = finished,
			}
			if raftItem and finished then
				-- c0248: the rule start and done apply, read from the layer's own tree
				local layer: stack.Layer = { raft = raftId, position = i, issue = issue, name = tip.name }
				local okReason, reason = pcall(layergit.completeReason, raftItem, layer, base, tip.sha)
				fact.reviewReason = if okReason then (reason or "") else `{issue}: {tostring(reason)}`
			end
			table.insert(out, fact)
			base = tip.sha
		end
	end
	return out
end

local function stacked(
	issues: { string },
	layers: { work.LayerFact },
	tips: { [number]: Tip },
	mainSha: string,
	landed: { [string]: boolean }
): boolean
	if #layers < #issues or mainSha == "" then
		return false
	end
	local onto: string? = nil
	for i, issue in issues do
		local tip = tips[i]
		if landed[issue] then
			onto = nil -- c0248: the next layer is the lowest unlanded one, judged against its fork with main
			continue
		end
		if not tip or tip.issue ~= issue then
			return false
		end
		if onto == nil then
			onto = layergit.mainFork(tip.sha, mainSha)
		end
		if not sh.run("git", { "merge-base", "--is-ancestor", onto :: string, tip.sha }).ok then
			return false
		end
		onto = tip.sha
	end
	return true
end

type Holder = { who: string, when: string, lands: boolean, on: string? }

-- The newest ready commit of each raft: who holds it, since when, and its trailers (f0399: `Lands: approved`,
-- `On: <R>`), from the one log.
local function holdersOf(): { [string]: Holder }
	local out: { [string]: Holder } = {}
	local r = sh.run("git", {
		"log",
		"origin/main",
		"--format=%x1e%s%x09%an <%ae>%x09%cI%x0a%b",
		"--grep=^tracker: ready",
	})
	if not r.ok then
		return out
	end
	for record in string.gmatch(r.stdout, "\30([^\30]*)") do
		local line = string.match(record, "^([^\n]*)") or ""
		local subject, who, when = string.match(line, "^(.-)\t(.-)\t(.+)$")
		local id = if subject then string.match(subject, "^tracker: ready (R%d%d%d%d)") else nil
		if id and who and when and not out[id] then
			local body = "\n" .. record .. "\n"
			out[id] = {
				who = who,
				when = when,
				lands = string.find(body, "\nLands: approved\n", 1, true) ~= nil,
				on = string.match(body, "\nOn: (R%d%d%d%d)\n"),
			}
		end
	end
	return out
end

local function build(
	id: string,
	at: At,
	text: string,
	byId: { [string]: At },
	docs: { [string]: string },
	sides: { [string]: string },
	holder: Holder?,
	tips: { [number]: Tip },
	mainSha: string
): work.RaftFact
	local front = frontText(text)
	local listed = store.idList(front.issues)
	local specs: { stack.Member } = {}
	local memberFront: { [string]: { [string]: string } } = {}
	for _, mid in listed do
		local found = byId[mid]
		local raw = if found then docs[found.path] else nil
		if (not raw or raw == "") and found and fs.isFile(found.path) then
			raw = fs.readFile(found.path)
		end
		local mf: { [string]: string } = if raw and raw ~= "" then frontText(raw) else {}
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
	local outside: { string } = {}
	for _, mid in issues do
		local mf: { [string]: string } = memberFront[mid] or {}
		if mf.design ~= "ready" then
			ready = false
		end
		for _, dep in store.idList(mf.depends_on) do
			if not memberIds[dep] then
				if not table.find(outside, dep) then
					table.insert(outside, dep)
				end
				local depAt = byId[dep]
				if not depAt or depAt.state ~= "done" then
					deps = false
				end
			end
		end
	end
	-- c0248: a raft readied with `layers: reviewed`; its landed members are in done/ on origin/main
	local marked = front.layers == "reviewed"
	local landed: { [string]: boolean } = {}
	for _, mid in issues do
		local mAt = byId[mid]
		landed[mid] = mAt ~= nil and mAt.state == "done"
	end
	local layers: { work.LayerFact } = if at.state == "active"
		then layerFacts(id, issues, tips, mainSha, landed, marked)
		else {}
	local final = reviewState(sides, "final%-review%-", "approved")
	local trace = sides["trace.md"] ~= nil
	local traceName: string? = nil
	if marked then
		-- this landing's final review and trace: one more than the last landing's on origin/main
		local onMain: { number } = {}
		for path in docs do
			local dir, num = string.match(path, "^(.*)/final%-review%-(%d+)%.md$")
			if dir == at.dir and num then
				table.insert(onMain, tonumber(num) :: number)
			end
		end
		local here: { number } = {}
		for name in sides do
			local n = tonumber((string.match(name, "^final%-review%-(%d+)%.md$")))
			if n then
				table.insert(here, n)
			end
		end
		local nnn = string.format("%03d", stack.nextRound(onMain, here))
		local landing = sides[`final-review-{nnn}.md`]
		final = if not landing then "none" elseif verdictOf(landing) == "approve" then "approved" else "open"
		local name = `trace-{nnn}.md`
		traceName = name
		trace = sides[name] ~= nil
	end
	return {
		id = id,
		title = front.title or id,
		where = at.state,
		status = statusLib.effective(front, at.state),
		designReady = ready,
		depsMet = deps,
		questions = sides["questions.md"] ~= nil,
		issues = issues,
		layers = layers,
		holder = if holder then holder.who else "",
		since = if holder then holder.when else "",
		stacked = if at.state == "active" then stacked(issues, layers, tips, mainSha, landed) else false,
		codeReview = reviewState(sides, "review%-", "resolved"),
		finalReview = final,
		trace = trace,
		traceOk = trace and final == "approved",
		marked = if marked then true else nil,
		traceName = traceName,
		root = string.match(at.dir, "^(.*%.tracker)/") or "",
		lands = if holder then holder.lands else false,
		on = if holder then holder.on else nil,
		onLanded = if holder and holder.on
			then byId[holder.on] ~= nil and byId[holder.on].state == "done"
			else nil,
		outside = outside,
	}
end

function workread.author(): string
	local named = sh.run("git", { "config", "--get", "user.name" })
	local mailed = sh.run("git", { "config", "--get", "user.email" })
	local name = if named.ok then trim(named.stdout) else ""
	local email = if mailed.ok then trim(mailed.stdout) else ""
	if name == "" or email == "" then
		return ""
	end
	return `{name} <{email}>`
end

local function filesUnder(
	dir: string,
	under: { [string]: { string } },
	docs: { [string]: string },
	id: string,
	take: (string, string) -> boolean
): { [string]: string }
	local out: { [string]: string } = {}
	local listed = under[dir]
	if not listed then
		return out
	end
	for _, path in listed do
		local rel = string.sub(path, #dir + 2)
		local body = docs[path]
		if body and body ~= "" and take(rel, id) then
			out[rel] = body
		end
	end
	return out
end

local function blockFor(
	id: string,
	at: At,
	text: string,
	byId: { [string]: At },
	docs: { [string]: string },
	under: { [string]: { string } },
	promoted: { [string]: { [string]: string } },
	onMembers: { string }?
): string
	local front = frontText(text)
	local status = statusLib.effective(front, at.state)
	if at.state ~= "backlog" or status ~= "prepared" then
		local why = readycheck.reason({
			id = id,
			where = at.state,
			status = status,
			dir = at.dir,
			design = front.design or "",
			doc = text,
			grouped = front.grouped,
			questions = docs[`{at.dir}/questions.md`] ~= nil,
			listed = {},
			members = {},
			files = {},
			loaded = false,
		})
		return why or ""
	end
	-- c0248: a member an earlier bind landed is in done/: it stays listed and is not readied again
	local listed: { string } = {}
	for _, mid in store.idList(front.issues) do
		local mAt = byId[mid]
		if not (mAt and mAt.state == "done") then
			table.insert(listed, mid)
		end
	end
	local members: { readycheck.Member } = {}
	local isMember: { [string]: boolean } = {}
	for mid, mat in byId do
		if store.isIssueId(mid) then
			local raw = docs[mat.path]
			if raw and raw ~= "" and frontText(raw).raft == id then
				isMember[mid] = true
			end
		end
	end
	for mid in isMember do
		local mat = byId[mid]
		local raw = if mat then docs[mat.path] else nil
		local mf: { [string]: string } = if raw and raw ~= "" then frontText(raw) else {}
		local folder = if mat
			then filesUnder(mat.dir, under, docs, mid, function(rel: string, issue: string): boolean
				return raftplan.isDesignFile(rel, issue) or rel == "approval.md" or rel == "guesses.md"
			end)
			else {}
		local specs = readycheck.specs(folder, if mat then promoted[mat.dir] or {} else {})
		table.insert(members, {
			id = mid,
			design = mf.design or "",
			doc = raw or "",
			deps = readycheck.deps(mf.depends_on, function(dep: string): string
				if isMember[dep] then
					return "member"
				end
				local depAt = byId[dep]
				return if depAt then depAt.state else "missing"
			end),
			files = folder,
			specs = specs,
			approval = folder["approval.md"],
			approvalFile = if mat then `{mat.dir}/approval.md` else `{mid}/approval.md`,
		})
	end
	local raftFiles = filesUnder(at.dir, under, docs, id, function(rel: string, _issue: string): boolean
		return rel == "check.sh"
			or string.match(rel, "^design%-review%-%d+%.md$") ~= nil
			or string.match(rel, "^design%-refute%-%d+%.md$") ~= nil
	end)
	-- d0298: the record first, as `./zn ready` judges it, on origin/main's tracked files (not the working tree): a member
	-- redesigned since z-raft grouped it is named for what z-raft must redo, ahead of its stale approval, and
	-- work.fixable then treats the raft as it treats any record refusal.
	local recordWhy = readycheck.record(id, front.grouped, members, raftFiles)
	if recordWhy then
		return recordWhy
	end
	local why = readycheck.reason({
		id = id,
		where = at.state,
		status = status,
		dir = at.dir,
		design = front.design or "",
		doc = text,
		grouped = front.grouped,
		questions = docs[`{at.dir}/questions.md`] ~= nil,
		listed = listed,
		members = members,
		files = raftFiles,
		loaded = true,
		onMembers = onMembers,
	})
	return why or ""
end

-- f0399: "<id> (<why>)" for each member whose approval does not hold in the top layer's tree.
local function unapprovedOf(fact: work.RaftFact, tips: { [number]: Tip }, reg: projects.Registry): { string }
	local top: Tip? = nil
	for _, tip in tips do
		if not top or tip.position > (top :: Tip).position then
			top = tip
		end
	end
	local out: { string } = {}
	if not top then
		return out
	end
	local sha = (top :: Tip).sha
	for _, mid in fact.issues do
		local dir = `{fact.root}/issues/active/{mid}`
		local home = string.match(fact.root, "^(.*)/.tracker$") or "."
		local dest = projects.promotedDir(reg, home, mid)
		local listed = sh.run("git", { "ls-tree", "-r", "--name-only", sha, "--", dir, dest })
		local paths: { string } = {}
		if listed.ok then
			for path in string.gmatch(listed.stdout .. "\n", "([^\n]*)\n") do
				if path ~= "" then
					table.insert(paths, path)
				end
			end
		end
		local specs: { string } = {}
		for _, path in paths do
			table.insert(specs, `{sha}:{path}`)
		end
		local blobs = catBatch(specs)
		local folder: { [string]: string } = {}
		local promoted: { [string]: string } = {}
		for i, path in paths do
			if string.sub(path, 1, #dir + 1) == dir .. "/" then
				folder[string.sub(path, #dir + 2)] = blobs[i] or ""
			elseif string.match(path, "%.spec%.luau$") then
				promoted[string.sub(path, #dest + 2)] = blobs[i] or ""
			end
		end
		local why: string? = nil
		local parts, err = contract.build(
			folder[`{mid}.md`] or "",
			folder["check.sh"] or "",
			readycheck.specs(folder, promoted),
			folder["guesses.md"]
		)
		if not parts then
			why = err
		else
			why = approval.shortOf(parts, folder["approval.md"])
		end
		if why then
			table.insert(out, `{mid} ({why})`)
		end
	end
	return out
end

-- The main checkout (the first worktree), or "" when git cannot say.
function workread.mainCheckout(): string
	local listed = sh.run("git", { "worktree", "list", "--porcelain" })
	return if listed.ok then string.match(listed.stdout, "^worktree ([^\n]+)") or "" else ""
end

function workread.carriersPath(mainCheckout: string): string
	return `{mainCheckout}/.cache/work/carriers.tsv`
end

-- f0399: who last asked `work next` for each item, and how many seconds ago. One line `<id>\t<session>\t<epoch>`.
function workread.carriers(mainCheckout: string): { [string]: work.Carrier }
	local out: { [string]: work.Carrier } = {}
	local path = workread.carriersPath(mainCheckout)
	if mainCheckout == "" or not fs.isFile(path) then
		return out
	end
	local now = os.time()
	for line in string.gmatch(fs.readFile(path), "[^\n]+") do
		local id, session, at = string.match(line, "^([^\t]+)\t([^\t]+)\t(%d+)$")
		if id and session and at then
			out[id] = { session = session, age = now - (tonumber(at) :: number) }
		end
	end
	return out
end

-- Writes `id`'s line for `session` (now), or removes it when `session` is nil. Other lines stay, sorted by id.
function workread.carry(mainCheckout: string, id: string, session: string?)
	if mainCheckout == "" then
		return
	end
	local path = workread.carriersPath(mainCheckout)
	local rows: { [string]: string } = {}
	if fs.isFile(path) then
		for line in string.gmatch(fs.readFile(path), "[^\n]+") do
			local was = string.match(line, "^([^\t]+)\t[^\t]+\t%d+$")
			if was then
				rows[was] = line
			end
		end
	end
	if session == nil and rows[id] == nil then
		return
	end
	rows[id] = if session then `{id}\t{session}\t{os.time()}` else nil :: any
	local ids: { string } = {}
	for was in rows do
		table.insert(ids, was)
	end
	table.sort(ids)
	local lines: { string } = {}
	for _, was in ids do
		table.insert(lines, rows[was])
	end
	fs.writeDir(`{mainCheckout}/.cache/work`)
	fs.writeFile(path, if #lines == 0 then "" else table.concat(lines, "\n") .. "\n")
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
	local main = trim(sh.run("git", { "rev-parse", "--verify", "--quiet", "origin/main" }).stdout)
	if main == "" then
		return { asked = asked, held = workread.held(), author = workread.author(), rafts = rafts }
	end
	local listed = sh.run("git", { "ls-tree", "-r", "--name-only", "origin/main" })
	local names: { string } = {}
	if listed.ok then
		for line in string.gmatch(listed.stdout .. "\n", "([^\n]*)\n") do
			if line ~= "" then
				table.insert(names, line)
			end
		end
	end
	local byId: { [string]: At } = {}
	for _, path in names do
		local state, dir, id = slot(path)
		if state and dir and id then
			byId[id] = { path = path, state = state, dir = dir }
		end
	end
	local keep: { [string]: At } = {}
	for id, at in byId do
		if store.isRaftId(id) and (at.state ~= "done" or id == asked) then
			keep[id] = at
		end
	end
	local want: { string } = {}
	local seenPath: { [string]: boolean } = {}
	local function add(path: string)
		if not seenPath[path] then
			seenPath[path] = true
			table.insert(want, path)
		end
	end
	for _, at in keep do
		add(at.path)
	end
	for id, at in byId do
		if store.isIssueId(id) and at.state ~= "done" then
			add(at.path)
		end
	end
	for _, path in names do
		local slash = string.match(path, "^(.*)/([^/]+)$")
		local base = string.match(path, "([^/]+)$")
		if slash and base and sideFile(base) then
			for _, at in keep do
				if slash == at.dir then
					add(path)
				end
			end
		end
	end
	local refText = sh.run("git", {
		"for-each-ref",
		"--format=%(objectname)%09%(refname:short)",
		"refs/heads",
		"refs/remotes/origin",
	})
	local refs: { { sha: string, ref: string } } = {}
	if refText.ok then
		for line in string.gmatch(refText.stdout .. "\n", "([^\n]*)\n") do
			local sha, ref = string.match(line, "^(%x+)\t(.+)$")
			if sha and ref then
				table.insert(refs, { sha = sha, ref = ref })
			end
		end
	end
	local activeTips: { [string]: { [number]: Tip } } = {}
	local specs: { string } = {}
	for _, path in want do
		table.insert(specs, `origin/main:{path}`)
	end
	local layerKeys: { string } = {}
	for id, at in keep do
		if at.state == "active" then
			local tips = tipsFor(id, refs)
			activeTips[id] = tips
			local ordered: { Tip } = {}
			for _, tip in tips do
				table.insert(ordered, tip)
			end
			table.sort(ordered, function(a, b)
				return a.position < b.position
			end)
			for _, tip in ordered do
				local tree = sh.run("git", { "ls-tree", "-r", "--name-only", tip.sha, "--", at.dir })
				if tree.ok then
					for path in string.gmatch(tree.stdout .. "\n", "([^\n]*)\n") do
						local base = string.match(path, "([^/]+)$")
						if path ~= "" and base and sideFile(base) then
							table.insert(specs, `{tip.sha}:{path}`)
							table.insert(layerKeys, `{id}\t{base}\t{tip.position}`)
						end
					end
				end
			end
		end
	end
	local blobs = catBatch(specs)
	local docs: { [string]: string } = {}
	for i, path in want do
		docs[path] = blobs[i] or ""
	end
	local layerBlobs: { [string]: { [string]: string } } = {}
	local layerPos: { [string]: { [string]: number } } = {}
	for n, key in layerKeys do
		local id, base, pos = string.match(key, "^(R%d%d%d%d)\t([^\t]+)\t(%d+)$")
		local position = if pos then tonumber(pos) else nil
		if id and base and position then
			local bag: { [string]: string } = layerBlobs[id] or {}
			local at: { [string]: number } = layerPos[id] or {}
			layerBlobs[id] = bag
			layerPos[id] = at
			local body = blobs[#want + n]
			if body and body ~= "" and (at[base] == nil or position >= at[base]) then
				bag[base] = body
				at[base] = position
			end
		end
	end
	local dirs: { [string]: boolean } = {}
	for _, at in keep do
		if at.state == "backlog" then
			dirs[at.dir] = true
			local body = docs[at.path]
			if body then
				for _, mid in store.idList(frontText(body).issues) do
					local m = byId[mid]
					if m then
						dirs[m.dir] = true
					end
				end
			end
		end
	end
	local under: { [string]: { string } } = {}
	for dir in dirs do
		under[dir] = {}
	end
	for _, path in names do
		for dir in dirs do
			if string.sub(path, 1, #dir + 1) == dir .. "/" then
				table.insert(under[dir], path)
			end
		end
	end
	local more: { string } = {}
	for dir in dirs do
		for _, path in under[dir] do
			if not docs[path] then
				local rel = string.sub(path, #dir + 2)
				local base = string.match(dir, "([fdcR]%d%d%d%d)$")
				if
					base
					and (
						raftplan.isDesignFile(rel, base)
						or rel == "approval.md"
						or rel == "guesses.md"
						or rel == "check.sh"
					)
				then
					table.insert(more, path)
				end
			end
		end
	end
	-- f0399: the idea review of each new issue in no raft, for z-design's claim gate
	local inTree: { [string]: boolean } = {}
	for _, path in names do
		inTree[path] = true
	end
	for id, at in byId do
		if store.isIssueId(id) and at.state == "backlog" then
			local body = docs[at.path] or ""
			local front = frontText(body)
			local review = `{at.dir}/idea-review-001.md`
			if
				statusLib.effective(front, at.state) == "new"
				and (front.raft or "") == ""
				and inTree[review]
				and not docs[review]
			then
				table.insert(more, review)
			end
		end
	end
	if #more > 0 then
		local extraSpecs: { string } = {}
		for _, path in more do
			table.insert(extraSpecs, `origin/main:{path}`)
		end
		local extra = catBatch(extraSpecs)
		for i, path in more do
			docs[path] = extra[i] or ""
		end
	end
	local promoted: { [string]: { [string]: string } } = {}
	local reg = projects.load(".")
	local promotePaths: { string } = {}
	local promoteOf: { [string]: { string } } = {}
	for dir in dirs do
		local issue = string.match(dir, "([fdc]%d%d%d%d)$")
		if issue then
			local any = false
			for name in
				filesUnder(dir, under, docs, issue, function(rel: string, item: string): boolean
					return raftplan.isDesignFile(rel, item)
				end)
			do
				if string.match(name, "^acceptance/.+%.spec%.luau$") then
					any = true
				end
			end
			if not any then
				local root = string.match(dir, "^(.*)/.tracker/") or ""
				local dest = projects.promotedDir(reg, if root == "" then "." else root, issue)
				local prefix = dest .. "/"
				local paths: { string } = {}
				for _, path in names do
					if string.sub(path, 1, #prefix) == prefix and string.match(path, "%.spec%.luau$") then
						table.insert(paths, path)
						if docs[path] == nil then
							table.insert(promotePaths, path)
						end
					end
				end
				promoteOf[dir] = paths
			end
		end
	end
	if #promotePaths > 0 then
		local specList: { string } = {}
		for _, path in promotePaths do
			table.insert(specList, `origin/main:{path}`)
		end
		local extra = catBatch(specList)
		for i, path in promotePaths do
			docs[path] = extra[i] or ""
		end
	end
	for dir, paths in promoteOf do
		local root = string.match(dir, "^(.*)/.tracker/") or ""
		local issue = string.match(dir, "([fdc]%d%d%d%d)$") or ""
		local dest = projects.promotedDir(reg, if root == "" then "." else root, issue)
		local bag: { [string]: string } = {}
		for _, path in paths do
			local body = docs[path]
			if body and body ~= "" then
				bag[string.sub(path, #dest + 2)] = body
			end
		end
		promoted[dir] = bag
	end
	local holders = holdersOf()
	local ats: { [string]: At } = {}
	for id, at in keep do
		local text = docs[at.path]
		if text and text ~= "" then
			local sides: { [string]: string } = {}
			for _, path in want do
				if string.match(path, "^(.*)/[^/]+$") == at.dir then
					local base = string.match(path, "([^/]+)$")
					local body = docs[path]
					if base and body and body ~= "" and sideFile(base) then
						sides[base] = body
					end
				end
			end
			local fromLayer = layerBlobs[id]
			if fromLayer then
				for name, body in fromLayer do
					sides[name] = body
				end
			end
			if fs.isDir(at.dir) then
				for _, name in fs.readDir(at.dir) do
					if sideFile(name) and fs.isFile(`{at.dir}/{name}`) then
						sides[name] = fs.readFile(`{at.dir}/{name}`)
					end
				end
			end
			-- f0399: a raft built on an unlanded raft sits on its base commit, not on main
			local base = main
			local holder = holders[id]
			if at.state == "active" and holder and holder.on then
				local onAt = byId[holder.on]
				if not (onAt and onAt.state == "done") then
					for _, row in refs do
						if row.ref == `{id}/base` or (row.ref == `origin/{id}/base` and base == main) then
							base = row.sha
						end
					end
				end
			end
			local fact = build(id, at, text, byId, docs, sides, holder, activeTips[id] or {}, base)
			if at.state ~= "done" then
				fact.block = blockFor(id, at, text, byId, docs, under, promoted)
			end
			table.insert(rafts, fact)
			ats[id] = at
		end
	end
	local mainCheckout = workread.mainCheckout()
	local issues: { work.IssueFact } = {}
	for id, at in byId do
		local body = if store.isIssueId(id) and at.state ~= "done" then docs[at.path] else nil
		if body and body ~= "" then
			local front = frontText(body)
			local status = statusLib.effective(front, at.state)
			local raftId = front.raft or ""
			local block = ""
			if status == "new" and raftId == "" then
				block = idea.designRefusal(body, docs[`{at.dir}/idea-review-001.md`], id) or ""
			end
			table.insert(issues, {
				id = id,
				root = string.match(at.dir, "^(.*%.tracker)/") or "",
				status = status,
				raft = raftId,
				designReady = front.design == "ready",
				sized = raftplan.parseSize(front.size) ~= nil,
				deps = store.idList(front.depends_on),
				draftBlock = block,
				added = front.waits ~= nil,
				mine = status == "preparing" and mainCheckout ~= "" and fs.isDir(
					`{mainCheckout}/.worktree/prep-{front.slug or ""}`
				),
			})
		end
	end
	table.sort(issues, function(a, b)
		return a.id < b.id
	end)
	for _, fact in rafts do
		local at = ats[fact.id]
		-- what ready --on would say: only for a prepared backlog raft that waits on issues outside it
		if at and fact.where == "backlog" and fact.status == "prepared" and not fact.depsMet then
			local on = work.baseFor(fact, rafts, issues)
			if on then
				for _, other in rafts do
					if other.id == on then
						fact.blockOn =
							blockFor(fact.id, at, docs[at.path], byId, docs, under, promoted, other.issues)
					end
				end
			end
		end
		-- whose approval does not hold in the tree that would land: read only once the final review is approved
		if at and fact.where == "active" and fact.lands and fact.finalReview == "approved" then
			fact.unapproved = unapprovedOf(fact, activeTips[fact.id] or {}, reg)
		end
	end
	return {
		asked = asked,
		held = workread.held(),
		author = workread.author(),
		rafts = rafts,
		issues = issues,
		session = sessionread.id(),
		carriers = workread.carriers(mainCheckout),
	}
end

return workread
