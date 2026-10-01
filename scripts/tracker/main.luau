--!strict
-- Tracker CLI. Run through scripts/tracker.sh. See .claude/skills/tracker/SKILL.md.
local board = require("./board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local sh = require("../lib/sh")
local spend = require("./spend")
local stdio = require("@lune/stdio")
local store = require("./store")

local USAGE = [[
usage: scripts/tracker.sh <command> ...
  new issue <f|d|c> <slug> [--raft R0010]     create an issue (emergent if the raft is active)
  new raft <feature|defect|chore> <slug> <issue>... [--single]
  find <id>                                     print the item's current directory
  list [backlog|active|done]                    list items
  members <R-id>                                print directories of every issue in the raft
  check <id>                                    run an item's check.sh (a raft runs its own)
  renumber <old> <new>                          step an id (conflict resolution)
  migrate                                       rename legacy-named documents to <ID>.md (adds slug: to the frontmatter)
  start <R-id>                                  branch, move to active, commit, push, draft PR
  focus <issue-id>                              attribute following commits to this issue
  commit -m <msg> [--issue <id>]... [--time <minutes>]   stage all, record spend, commit, push
  done <R-id>                                   verify checks + review resolution, move to done, ready PR
  worktree <R-id|name>                          create or reuse .worktree/<R-id|name> from origin/main; print its path
  worktree-prune                                remove worktrees of rafts that are done on main
  launch <R-id|name> [-- cmd...]                run a command (default claude) in the target's worktree (scripts/tracker.sh)
  workstreams <R-id>                            plan parallel workstreams (waves) for a raft
  promote-check <R-id>                          dry-run: would promoted acceptance specs pass type check + meta?
  prompt <R-id|issue-id> [--stdout]             render the execution prompt to the clipboard
  metrics [--include-active]                    cost per issue and rework %
  board [--out PATH] [--open]                   write the tracker as one HTML page (default .cache/board.html)]]

local FOCUS_FILE = ".cache/tracker-focus"

local function fail(msg: string): never
	stdio.ewrite(msg .. "\n")
	return process.exit(1)
end

local function title(slug: string): string
	local s = string.gsub(slug, "%-", " ")
	return (string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2))
end

local function render(path: string, vars: { [string]: string }): string
	local text = fs.readFile(path)
	return (
		string.gsub(text, "{{([%w_]+)}}", function(k: string): string
			return vars[k] or "{{" .. k .. "}}"
		end)
	)
end

local function today(): string
	return os.date("%Y-%m-%d") :: string
end

local function hasUpstream(): boolean
	return sh.run("git", { "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" }).ok
end

local function push()
	if hasUpstream() then
		sh.git({ "push", "--quiet" })
	end
end

local function move(item: store.Item, state: store.State): store.Item
	local dest = store.dirFor(item.kind, state, item.id)
	sh.git({ "mv", item.dir, dest })
	return store.get(item.id)
end

local function raftBranch(raft: store.Item): string
	return `{raft.id}-{raft.slug}`
end

local function hasOrigin(): boolean
	return sh.run("git", { "remote", "get-url", "origin" }).ok
end

-- Only a GitHub origin gets draft PRs: anything else (a local bare remote in a spec) has no `gh`.
local function onGitHub(): boolean
	local r = sh.run("git", { "remote", "get-url", "origin" })
	return r.ok and string.find(r.stdout, "github.com", 1, true) ~= nil
end

-- One entry per worktree of this repository: its path and, unless detached, its branch.
local function worktrees(): { { path: string, branch: string? } }
	local out = {}
	local cur: { path: string, branch: string? } = { path = "", branch = nil }
	for line in string.gmatch(sh.git({ "worktree", "list", "--porcelain" }), "[^\n]+") do
		local p = string.match(line, "^worktree (.+)$")
		if p then
			cur = { path = p, branch = nil }
			table.insert(out, cur)
		else
			local b = string.match(line, "^branch refs/heads/(.+)$")
			if b then
				cur.branch = b
			end
		end
	end
	return out
end

-- The main checkout's root: git lists it first, even when asked from a linked worktree.
local function mainRoot(): string
	return worktrees()[1].path
end

-- Tracker commands that change the tree refuse to run in the main checkout of a repo with an origin:
-- every change is made in a worktree (tracker skill, "Worktrees").
local function refuseInMainCheckout(what: string)
	if hasOrigin() and sh.git({ "rev-parse", "--show-toplevel" }) == mainRoot() then
		fail(`{what} must run inside a worktree: cd "$(scripts/tracker.sh worktree <target>)"`)
	end
end

local function activeRaft(): store.Item
	local rafts = {}
	for _, r in store.all("raft") do
		if r.state == "active" then
			table.insert(rafts, r)
		end
	end
	if #rafts ~= 1 then
		fail(`expected exactly one active raft on this branch, found {#rafts}`)
	end
	return rafts[1]
end

local function flags(args: { string }): ({ string }, { [string]: { string } })
	local pos: { string } = {}
	local opts: { [string]: { string } } = {}
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--single" or a == "--stdout" or a == "--include-active" or a == "--open" then
			opts[a] = { "true" }
		elseif string.sub(a, 1, 1) == "-" then
			opts[a] = opts[a] or {}
			table.insert(opts[a], args[i + 1] or "")
			i += 1
		elseif a ~= "--" then
			table.insert(pos, a)
		end
		i += 1
	end
	return pos, opts
end

local cmd = {}

function cmd.new(pos: { string }, opts: { [string]: { string } })
	refuseInMainCheckout("new")
	local what = pos[1]
	if what == "issue" then
		local prefix, slug = pos[2], pos[3]
		if not (prefix and store.TYPES[prefix] and slug) then
			fail("usage: new issue <f|d|c> <slug> [--raft R0010]")
		end
		if not string.match(slug, "^[a-z][a-z0-9%-]*$") then
			fail(`invalid slug: {slug} (lowercase words joined by hyphens)`)
		end
		local id = store.formatId(prefix, store.nextNumber("issue"))
		local raftId = opts["--raft"] and opts["--raft"][1]
		local raft = raftId and store.get(raftId)
		local state: store.State = if raft and raft.state == "active" then "active" else "backlog"
		local dir = store.dirFor("issue", state, id)
		fs.writeDir(dir)
		local vars = {
			ID = id,
			TYPE = store.TYPES[prefix],
			TITLE = title(slug),
			SLUG = slug,
			RAFT = raftId or "",
			EMERGENT = if state == "active" then "true" else "false",
			DATE = today(),
		}
		fs.writeFile(`{dir}/{id}.md`, render("tracker/templates/issue/doc.md", vars))
		fs.writeFile(`{dir}/check.sh`, render("tracker/templates/issue/check.sh", vars))
		sh.must("chmod", { "+x", `{dir}/check.sh` })
		print(`{dir}/{id}.md`)
	elseif what == "raft" then
		local rtype, slug = pos[2], pos[3]
		if not (rtype and store.PREFIX[rtype] and slug) then
			fail("usage: new raft <feature|defect|chore> <slug> <issue>... [--single]")
		end
		if not string.match(slug, "^[a-z][a-z0-9%-]*$") then
			fail(`invalid slug: {slug} (lowercase words joined by hyphens)`)
		end
		local members: { store.Item } = {}
		for i = 4, #pos do
			local issue = store.get(pos[i])
			if store.typeOf(issue) ~= rtype then
				fail(`{issue.id} is a {store.typeOf(issue)}; a {rtype} raft cannot contain it`)
			end
			local current = store.readFront(issue.doc).raft
			if current and current ~= "" then
				fail(`{issue.id} already belongs to {current}`)
			end
			table.insert(members, issue)
		end
		if #members == 0 then
			fail("a raft needs at least one issue")
		end
		local id = store.formatId("R", store.nextNumber("raft"))
		local dir = store.dirFor("raft", "backlog", id)
		fs.writeDir(dir)
		local ids: { string } = {}
		for _, m in members do
			table.insert(ids, m.id)
			store.setFront(m.doc, "raft", id)
		end
		local vars = {
			ID = id,
			TYPE = rtype,
			TITLE = title(slug),
			SLUG = slug,
			SINGLE = if opts["--single"] then "true" else "false",
			ISSUES = table.concat(ids, ", "),
			DATE = today(),
		}
		fs.writeFile(`{dir}/{id}.md`, render("tracker/templates/raft/doc.md", vars))
		fs.writeFile(`{dir}/check.sh`, render("tracker/templates/raft/check.sh", vars))
		sh.must("chmod", { "+x", `{dir}/check.sh` })
		print(`{dir}/{id}.md`)
	else
		fail(USAGE)
	end
end

function cmd.find(pos: { string })
	print(store.get(pos[1] or fail("usage: find <id>")).dir)
end

function cmd.members(pos: { string })
	for _, m in store.members(pos[1] or fail("usage: members <R-id>")) do
		print(m.dir)
	end
end

function cmd.list(pos: { string })
	for _, kind in { "raft", "issue" } do
		for _, item in store.all(kind) do
			if not pos[1] or pos[1] == item.state then
				local f = store.readFront(item.doc)
				print(
					string.format(
						"%-6s %-8s %-8s %-7s %s",
						item.id,
						item.state,
						store.typeOf(item),
						f.raft or "",
						f.title or item.slug
					)
				)
			end
		end
	end
	-- f0420 and c0420 share a number (issues have one number space): harmless, but worth a warning
	local byNumber: { [string]: { string } } = {}
	for _, issue in store.all("issue") do
		local n = string.sub(issue.id, 2)
		byNumber[n] = byNumber[n] or {}
		table.insert(byNumber[n], issue.id)
	end
	local shared: { string } = {}
	for n, ids in byNumber do
		if #ids > 1 then
			table.insert(shared, n)
		end
	end
	table.sort(shared)
	for _, n in shared do
		stdio.ewrite(`warning: number {n} is used by {table.concat(byNumber[n], ", ")}\n`)
	end
end

-- Runs check.sh for an item. A raft's check.sh is responsible for running its members' checks.
local function runCheck(item: store.Item): boolean
	print(`\n=== {item.id} check.sh`)
	return sh.stream("bash", { `{item.dir}/check.sh` })
end

function cmd.check(pos: { string })
	if not runCheck(store.get(pos[1] or fail("usage: check <id>"))) then
		process.exit(1)
	end
end

function cmd.renumber(pos: { string })
	refuseInMainCheckout("renumber")
	local old, new = pos[1], pos[2]
	if not old or not new or string.sub(old, 1, 1) ~= string.sub(new, 1, 1) then
		fail("usage: renumber <old> <new> (same type prefix)")
	end
	if store.find(new) then
		fail(`{new} already exists`)
	end
	local item = store.get(old)
	local dest = store.dirFor(item.kind, item.state, new)
	local tracked = sh.run("git", { "ls-files", "--error-unmatch", item.doc }).ok
	if tracked then
		sh.git({ "mv", item.dir, dest })
		sh.git({ "mv", `{dest}/{old}.md`, `{dest}/{new}.md` })
	else
		fs.move(item.dir, dest)
		fs.move(`{dest}/{old}.md`, `{dest}/{new}.md`)
	end
	-- rewrite references everywhere in the tracker
	local function walk(dir: string)
		for _, name in fs.readDir(dir) do
			local p = `{dir}/{name}`
			if fs.isDir(p) then
				walk(p)
			elseif string.match(name, "%.md$") or string.match(name, "%.sh$") then
				local text = fs.readFile(p)
				local replaced, n = string.gsub(text, `%f[%w]{old}%f[^%w]`, new)
				if n > 0 then
					fs.writeFile(p, replaced)
				end
			end
		end
	end
	walk(store.ROOT)
	print(`{old} -> {new}`)
end

-- Converts documents that still carry their slug in the filename (legacy layout) to `<ID>.md` with
-- `slug:` in the frontmatter. It scans directories itself and never goes through `store.find`,
-- which rejects the legacy layout, so it runs against either version of the store.
function cmd.migrate()
	refuseInMainCheckout("migrate")
	local ambiguous = false
	for _, kind in { "issues", "rafts" } do
		for _, state in { "", "active/", "done/" } do
			local base = `{store.ROOT}/{kind}/{state}`
			if fs.isDir(base) then
				local names = fs.readDir(base)
				table.sort(names)
				for _, id in names do
					local isId = if kind == "rafts" then store.isRaftId(id) else store.isIssueId(id)
					local dir = base .. id
					if isId and fs.isDir(dir) then
						local files: { string } = {}
						local hasNew = false
						for _, name in fs.readDir(dir) do
							if name == `{id}.md` then
								hasNew = true
							elseif string.match(name, `^{id}%-.+%.md$`) then
								table.insert(files, name)
							end
						end
						if #files > 0 and (hasNew or #files > 1) then
							stdio.ewrite(`{dir}: ambiguous documents: {table.concat(files, ", ")}\n`)
							ambiguous = true
						elseif #files == 1 then
							local old, new = `{dir}/{files[1]}`, `{dir}/{id}.md`
							local slug = string.match(files[1], `^{id}%-(.+)%.md$`) :: string
							if not string.match(fs.readFile(old), "^%-%-%-\n") then
								-- nothing to add the slug to: report it and leave the document alone
								stdio.ewrite(`{old}: no frontmatter; add one (id, title, slug) by hand\n`)
								ambiguous = true
								continue
							end
							if sh.run("git", { "ls-files", "--error-unmatch", old }).ok then
								sh.git({ "mv", old, new })
							else
								fs.move(old, new)
							end
							local current = store.readFront(new).slug
							if not current or current == "" then
								store.setFront(new, "slug", slug)
							end
							print(`{old} -> {new}`)
						end
					end
				end
			end
		end
	end
	if ambiguous then
		process.exit(1)
	end
end

function cmd.start(pos: { string })
	local raft = store.get(pos[1] or fail("usage: start <R-id>"))
	if raft.kind ~= "raft" then
		fail("only rafts are started; make a `--single` raft with `new raft ... --single` (ticket-prep)")
	end
	if raft.state ~= "backlog" then
		fail(`{raft.id} is already {raft.state}`)
	end
	if sh.git({ "status", "--porcelain" }) ~= "" then
		fail("working tree is not clean")
	end
	local members = store.members(raft.id)
	for _, m in members do
		if store.readFront(m.doc).design ~= "ready" then
			fail(`{m.id} is not design: ready (run ticket-prep first)`)
		end
	end
	local branch = raftBranch(raft)
	if sh.git({ "branch", "--show-current" }) ~= branch then
		refuseInMainCheckout("start")
		sh.git({ "switch", "-c", branch })
	end
	raft = move(raft, "active")
	for _, m in members do
		move(m, "active")
	end
	local ftitle = store.readFront(raft.doc).title or raft.slug
	sh.git({ "commit", "--quiet", "-m", `tracker: start {raft.id} {ftitle}` })
	print(`on branch {branch}; {raft.id} and {#members} issue(s) are active`)
	if hasOrigin() then
		sh.git({ "push", "--quiet", "-u", "origin", branch })
		if not onGitHub() then
			print("origin is not GitHub: skipped draft PR")
			return
		end
		local body = `Raft **{raft.id}**: {ftitle}\n\nIssues: `
		local ids = {}
		for _, m in members do
			table.insert(ids, m.id)
		end
		body ..= table.concat(ids, ", ")
		body ..= `\n\nDocuments: \`{raft.dir}/\`. Draft until all code is written, every check.sh passes, and the adversarial review is resolved.\n`
		local url =
			sh.must("gh", { "pr", "create", "--draft", "--title", `{raft.id}: {ftitle}`, "--body", body })
		print(`draft PR: {url}`)
	else
		print("no origin remote: skipped push and draft PR")
	end
end

-- The backticked paths on the bulleted lines of an issue's "### Touched modules" section, or nil when
-- it has none (a draft issue has only the template comment).
local function touchedModules(item: store.Item): { string }?
	local text = fs.readFile(item.doc)
	local section = string.match(text, "\n### Touched modules\n(.-)\n##")
	if not section then
		return nil
	end
	local out: { string } = {}
	for path in string.gmatch("\n" .. section, "\n%-%s+`([^`]+)`") do
		table.insert(out, (string.gsub(path, "/+$", "")))
	end
	if #out == 0 then
		return nil
	end
	return out
end

-- Two paths overlap when they are equal or one is a parent directory of the other, by whole components.
local function overlaps(a: string, b: string): boolean
	return a == b or string.sub(a, 1, #b + 1) == b .. "/" or string.sub(b, 1, #a + 1) == a .. "/"
end

-- The plan text for a raft, its warnings, and an error when it can't be built. Issues are placed in
-- waves: one more than the latest wave they must follow (in-raft `depends_on`, and any issue already
-- placed whose Touched modules overlap; an issue with none overlaps everything). Deterministic: the
-- lowest-id ready issue is placed first.
local function workstreamPlan(raft: store.Item): (string, { string }, string?)
	local members = store.members(raft.id)
	local isMember: { [string]: boolean } = {}
	for _, m in members do
		isMember[m.id] = true
	end
	local deps: { [string]: { string } } = {}
	local touched: { [string]: { string }? } = {}
	local warnings: { string } = {}
	for _, m in members do
		local d: { string } = {}
		for _, id in store.idList(store.readFront(m.doc).depends_on) do
			if isMember[id] then
				table.insert(d, id)
			end
		end
		deps[m.id] = d
		touched[m.id] = touchedModules(m)
		if not touched[m.id] then
			table.insert(warnings, `warning: {m.id} has no Touched modules; serialized`)
		end
	end
	local wave: { [string]: number } = {}
	local after: { [string]: { string } } = {}
	local why: { [string]: { [string]: string } } = {}
	local assigned: { string } = {}
	local remaining: { string } = {}
	for _, m in members do
		table.insert(remaining, m.id)
	end
	while #remaining > 0 do
		local pick = 0
		for i, id in remaining do
			local ready = true
			for _, d in deps[id] do
				if not wave[d] then
					ready = false
				end
			end
			if ready then
				pick = i
				break
			end
		end
		if pick == 0 then
			return "", warnings, `dependency cycle among: {table.concat(remaining, ", ")}`
		end
		local id = table.remove(remaining, pick) :: string
		local reasons: { [string]: string } = {}
		for _, d in deps[id] do
			reasons[d] = "depends_on"
		end
		for _, other in assigned do
			if not reasons[other] then
				local a, b = touched[id], touched[other]
				if not a or not b then
					reasons[other] = "no touched modules"
				else
					for _, x in a do
						for _, y in b do
							if overlaps(x, y) then
								reasons[other] = "overlap"
							end
						end
					end
				end
			end
		end
		local list: { string } = {}
		local w = 0
		for other in reasons do
			table.insert(list, other)
		end
		table.sort(list)
		for _, other in list do
			w = math.max(w, wave[other])
		end
		wave[id], after[id], why[id] = w + 1, list, reasons
		table.insert(assigned, id)
	end
	local lines = { `raft {raft.id}: {#members} issue{if #members == 1 then "" else "s"}` }
	local byWave: { [number]: { string } } = {}
	for _, m in members do
		local line = `{m.id} wave {wave[m.id]}`
		if #after[m.id] > 0 then
			local parts: { string } = {}
			for _, other in after[m.id] do
				table.insert(parts, `{other} ({why[m.id][other]})`)
			end
			line ..= ` after {table.concat(parts, ", ")}`
		end
		table.insert(lines, line)
		byWave[wave[m.id]] = byWave[wave[m.id]] or {}
		table.insert(byWave[wave[m.id]], m.id)
	end
	local parallel = "parallel: no"
	for k = 1, #members do
		if byWave[k] and #byWave[k] >= 2 then
			parallel = `parallel: yes (wave {k}: {table.concat(byWave[k], " ")})`
			break
		end
	end
	table.insert(lines, parallel)
	return table.concat(lines, "\n"), warnings, nil
end

function cmd.workstreams(pos: { string })
	local raft = store.get(pos[1] or fail("usage: workstreams <R-id>"))
	if raft.kind ~= "raft" then
		fail(`{raft.id} is not a raft`)
	end
	local text, warnings, planError = workstreamPlan(raft)
	if planError then
		fail(planError)
	end
	for _, w in warnings do
		stdio.ewrite(w .. "\n")
	end
	print(text)
end

function cmd.worktree(pos: { string }, opts: { [string]: { string } })
	local target = pos[1] or fail("usage: worktree <R-id|name>")
	local branch: string
	local dirName: string
	if string.match(target, "^R%d%d%d%d$") then
		local missing =
			`{target} is not in this tree; if it was just merged, run git -C {mainRoot()} pull --ff-only`
		local raft = store.find(target) or fail(missing)
		if raft.state == "done" then
			fail(`{target} is done`)
		end
		branch, dirName = raftBranch(raft), target
	elseif string.match(target, "^[fdc]%d%d%d%d$") then
		fail("give a raft id or a name")
	elseif #target <= 60 and string.match(target, "^[a-z][a-z0-9%-]*$") then
		branch, dirName = target, target
	else
		fail(`invalid worktree name: {target}`)
	end
	local from = opts["--from"] and opts["--from"][1]
	if from then
		if string.match(target, "^R%d%d%d%d$") then
			fail("--from is for named worktrees")
		end
		if not sh.run("git", { "rev-parse", "--verify", "--quiet", from .. "^{commit}" }).ok then
			fail(`unknown ref {from}`)
		end
	end
	local root = mainRoot()
	local path = `{root}/.worktree/{dirName}`
	sh.run("git", { "worktree", "prune" }) -- forget worktrees whose directory was deleted
	if hasOrigin() then
		sh.run("git", { "fetch", "--quiet", "--prune", "origin" })
	end
	for _, w in worktrees() do
		if w.path == path then
			print(path)
			return
		elseif w.branch == branch then
			fail(`{branch} is already used by worktree at {w.path}`)
		end
	end
	if sh.run("git", { "show-ref", "--verify", "--quiet", `refs/heads/{branch}` }).ok then
		local track = sh.git({ "for-each-ref", "--format=%(upstream:track)", `refs/heads/{branch}` })
		if track == "[gone]" then
			stdio.ewrite(
				`warning: the upstream of {branch} is gone (merged?); resuming it anyway: git branch -D {branch} gives a fresh start\n`
			)
		end
		sh.git({ "worktree", "add", path, branch })
	elseif sh.run("git", { "show-ref", "--verify", "--quiet", `refs/remotes/origin/{branch}` }).ok then
		sh.git({ "branch", "--track", branch, `origin/{branch}` })
		sh.git({ "worktree", "add", path, branch })
	else
		local base = from
			or if sh.run("git", { "show-ref", "--verify", "--quiet", "refs/remotes/origin/main" }).ok
				then "origin/main"
				else "main"
		-- --no-track: a bare `git push` must not target origin/main before start or landing sets the upstream
		sh.git({ "worktree", "add", "--no-track", "-b", branch, path, base })
	end
	print(path)
end

cmd["worktree-prune"] = function()
	local root = mainRoot()
	sh.run("git", { "worktree", "prune" })
	if hasOrigin() then
		sh.run("git", { "fetch", "--quiet", "--prune", "origin" })
	end
	local base = if sh.run("git", { "show-ref", "--verify", "--quiet", "refs/remotes/origin/main" }).ok
		then "origin/main"
		else "main"
	local here = sh.git({ "rev-parse", "--show-toplevel" })
	local prefix = root .. "/.worktree/"
	local failed = false
	for _, w in worktrees() do
		local name = if string.sub(w.path, 1, #prefix) == prefix then string.sub(w.path, #prefix + 1) else nil
		if name and not string.find(name, "/", 1, true) then
			if not string.match(name, "^R%d%d%d%d$") then
				print(`kept {w.path} (named worktree: remove it when its PR has merged)`)
			elseif sh.git({ "-C", root, "ls-tree", "-d", base, `tracker/rafts/done/{name}` }) ~= "" then
				-- finished: the raft is in done/ on the base branch, whatever merge strategy landed it
				if w.path == here then
					print(`skipped {w.path} (it is the current directory)`)
				else
					local r = sh.run("git", { "-C", root, "worktree", "remove", w.path })
					if r.ok then
						if w.branch then
							sh.git({ "-C", root, "branch", "-D", w.branch })
						end
						print(`removed {w.path}`)
					else
						stdio.ewrite(`kept {w.path}: {sh.trim(r.stderr)}\n`)
						failed = true
					end
				end
			end
		end
	end
	-- worktrees belong under .worktree/: flag (never move or remove) any other than the main checkout
	for _, w in worktrees() do
		if w.path ~= root and string.sub(w.path, 1, #prefix) ~= prefix then
			stdio.ewrite(
				`warning: {w.path} is outside .worktree/: move it with git worktree move, or remove it\n`
			)
		end
	end
	if failed then
		process.exit(1)
	end
end

function cmd.focus(pos: { string })
	local issue = store.get(pos[1] or fail("usage: focus <issue-id>"))
	fs.writeDir(".cache")
	fs.writeFile(FOCUS_FILE, issue.id)
	print(`focus: {issue.id}`)
end

local function recordAndCommit(
	raft: store.Item,
	message: string,
	issueIds: { string },
	explicitMinutes: number?,
	isDone: boolean?
)
	-- a conflicted `git merge --squash` leaves unmerged paths; `git add -A` would commit their markers
	if sh.git({ "ls-files", "-u" }) ~= "" then
		fail("unmerged paths: resolve the merge first")
	end
	sh.git({ "add", "-A" })
	local issues: { store.Item } = {}
	local how: string
	if #issueIds > 0 then
		how = "explicit"
		for _, id in issueIds do
			table.insert(issues, store.get(id))
		end
	elseif fs.isFile(FOCUS_FILE) and store.find(sh.trim(fs.readFile(FOCUS_FILE))) then
		how = "focus"
		table.insert(issues, store.get(sh.trim(fs.readFile(FOCUS_FILE))))
	else
		how = "raft"
		issues = store.members(raft.id)
	end
	local minutes = explicitMinutes or spend.elapsedMinutes()
	local shares = spend.attribute(issues, spend.stagedStats(isDone), minutes, how)
	local trailers: { string } = {}
	for _, share in shares do
		if share.added + share.removed == 0 and share.minutes < 0.1 then
			continue -- nothing to record (e.g. a pure tracker move)
		end
		spend.appendRow(store.get(share.id), share, message)
		table.insert(
			trailers,
			string.format("Issue: %s +%d/-%d %.1fm", share.id, share.added, share.removed, share.minutes)
		)
	end
	spend.writeRaft(raft)
	sh.git({ "add", "-A", store.ROOT })
	sh.git({ "commit", "--quiet", "-m", message, "-m", table.concat(trailers, "\n") })
	print(`committed: {message}\n  {table.concat(trailers, "\n  ")}`)
	push()
end

function cmd.commit(_pos: { string }, opts: { [string]: { string } })
	local message = opts["-m"] and opts["-m"][1]
	if not message or message == "" then
		fail("usage: commit -m <msg> [--issue <id>]... [--time <minutes>]")
	end
	local t = opts["--time"] and tonumber((string.gsub(opts["--time"][1], "m$", "")))
	recordAndCommit(activeRaft(), message, opts["--issue"] or {}, t)
end

-- Copy each member's acceptance specs into tests/acceptance/<id>, run `check`, then remove the
-- copies. Returns check's result. Used by `done` (for real) and `promote-check` (dry run).
local function withPromotedCopies(raft: store.Item, check: ({ string }) -> boolean): boolean
	local copied: { string } = {}
	for _, m in store.members(raft.id) do
		local acc = `{m.dir}/acceptance`
		local dest = `tests/acceptance/{m.id}`
		if fs.isDir(acc) and not fs.isDir(dest) then
			fs.writeDir(dest)
			for _, name in fs.readDir(acc) do
				fs.writeFile(`{dest}/{name}`, fs.readFile(`{acc}/{name}`))
				if string.match(name, "%.spec%.luau$") then
					table.insert(copied, `{dest}/{name}`)
				end
			end
		end
	end
	local pok, result = pcall(check, copied)
	local ok = pok and result == true
	for _, m in store.members(raft.id) do
		local dest = `tests/acceptance/{m.id}`
		if fs.isDir(dest) and not sh.run("git", { "ls-files", "--error-unmatch", dest }).ok then
			fs.removeDir(dest)
		end
	end
	if not pok then
		error(result, 0)
	end
	return ok
end

-- Structural checks promoted acceptance specs must pass in tests/: type check + meta spec
-- (+ the specs themselves when `runSpecs`).
local function promotedChecks(specs: { string }, runSpecs: boolean): boolean
	local ok = sh.stream("luau-lsp", { "analyze", "--base-luaurc=.luaurc", "--platform=standard", "tests" })
	local args = { "run", "tests/run", "--", "tests/meta/architecture.spec.luau" }
	if runSpecs then
		for _, p in specs do
			table.insert(args, p)
		end
	end
	return sh.stream("lune", args) and ok
end

cmd["promote-check"] = function(pos: { string })
	local raft = store.get(pos[1] or fail("usage: promote-check <R-id>"))
	print(`=== {raft.id}: dry-run promotion of acceptance specs (type check + meta)`)
	if not withPromotedCopies(raft, function(specs)
		return promotedChecks(specs, false)
	end) then
		fail("promoted acceptance specs would break tests/ (see above)")
	end
	print("promote-check OK")
end

-- Latest review round must be resolved: verdict approve, or a same-numbered refute file that
-- answers every finding id with "fixed" or "refuted".
local function reviewProblem(raft: store.Item): string?
	local latest = 0
	for _, name in fs.readDir(raft.dir) do
		local n = tonumber(string.match(name, "^review%-(%d+)%.md$"))
		if n and n > latest then
			latest = n
		end
	end
	if latest == 0 then
		return "no review-NNN.md: run the adversarial code review first"
	end
	local num = string.format("%03d", latest)
	local review = "\n" .. fs.readFile(`{raft.dir}/review-{num}.md`)
	local verdict = string.match(review, "\n[Vv]erdict:%s*(%a+)")
	if verdict == "approve" then
		return nil
	end
	local refutePath = `{raft.dir}/refute-{num}.md`
	local refute = "\n" .. (if fs.isFile(refutePath) then fs.readFile(refutePath) else "")
	local missing = {}
	for id in string.gmatch(review, "\n###%s+(F%d+)") do
		local line = string.match(refute, `\n%-%s+{id}:%s*([^\n]*)`)
		if not line or not (string.find(line, "^fixed") or string.find(line, "^refuted")) then
			table.insert(missing, id)
		end
	end
	if #missing > 0 then
		return `review-{num}.md findings not answered in refute-{num}.md: {table.concat(missing, ", ")}`
	end
	return nil
end

function cmd.done(pos: { string })
	local raft = store.get(pos[1] or fail("usage: done <R-id>"))
	if raft.kind ~= "raft" or raft.state ~= "active" then
		fail(`{raft.id} must be an active raft`)
	end
	if sh.git({ "status", "--porcelain" }) ~= "" then
		fail("commit everything first (scripts/tracker.sh commit); done needs a clean tree")
	end
	local problem = reviewProblem(raft)
	if problem then
		fail(problem)
	end
	if not runCheck(raft) then
		fail(`{raft.id} check.sh failed; not done`)
	end
	-- Promote sequestered acceptance specs into the permanent suite, then prove they still pass
	-- there (type check + structural meta spec + the specs themselves). Roll back on failure.
	local promoted: { string } = {}
	for _, m in store.members(raft.id) do
		local acc = `{m.dir}/acceptance`
		if fs.isDir(acc) and #fs.readDir(acc) > 0 then
			fs.writeDir("tests/acceptance")
			sh.git({ "mv", acc, `tests/acceptance/{m.id}` })
			for _, name in fs.readDir(`tests/acceptance/{m.id}`) do
				if string.match(name, "%.spec%.luau$") then
					table.insert(promoted, `tests/acceptance/{m.id}/{name}`)
				end
			end
		end
	end
	if #promoted > 0 then
		print("\n=== promoted acceptance specs: type check + meta + run")
		if not promotedChecks(promoted, true) then
			sh.git({ "reset", "-q", "--hard", "HEAD" })
			fail("promoted acceptance specs fail in tests/acceptance (rolled back); fix and retry done")
		end
	end
	-- Mark the PR ready before the final push: CI skips drafts, so the push below is what gets tested.
	if hasUpstream() and onGitHub() then
		-- pcall: process.exec throws when gh can't be spawned at all (not on PATH)
		local ok, r = pcall(sh.run, "gh", { "pr", "ready" })
		if not (ok and r.ok) then
			sh.git({ "reset", "-q", "--hard", "HEAD" })
			fail("could not mark the PR ready (rolled back); fix gh and retry done")
		end
	end
	for _, m in store.members(raft.id) do
		move(m, "done")
	end
	raft = move(raft, "done")
	if fs.isFile(FOCUS_FILE) then
		fs.removeFile(FOCUS_FILE)
	end
	recordAndCommit(raft, `tracker: done {raft.id}`, {}, nil, true)
	if hasUpstream() and onGitHub() then
		local summary = fs.readFile(`{raft.dir}/spend.md`)
		local body = sh.must("gh", { "pr", "view", "--json", "body", "-q", ".body" })
		sh.must("gh", { "pr", "edit", "--body", body .. "\n\n" .. summary })
		print("PR marked ready for review")
	end
end

local SKILLS_INLINED = { "execute-raft", "tracker", "architecture", "testing", "review" }

function cmd.prompt(pos: { string }, opts: { [string]: { string } })
	local target = store.get(pos[1] or fail("usage: prompt <R-id|issue-id> [--stdout]"))
	local raft = target
	if target.kind == "issue" then
		local raftId = store.readFront(target.doc).raft
		if raftId and raftId ~= "" then
			raft = store.get(raftId)
		else
			cmd.new({ "raft", store.typeOf(target), target.slug, target.id }, { ["--single"] = { "true" } })
			raft = store.get(store.readFront(target.doc).raft)
			stdio.ewrite(
				`created placeholder raft {raft.id}; land it (tracker skill, Landing a change) before handing out the prompt\n`
			)
		end
	end
	local function section(path: string): string
		return `\n<file path="{path}">\n{fs.readFile(path)}\n</file>\n`
	end
	local items = section(raft.doc) .. section(`{raft.dir}/check.sh`)
	local ids = {}
	for _, m in store.members(raft.id) do
		table.insert(ids, m.id)
		items ..= section(m.doc) .. section(`{m.dir}/check.sh`)
		-- the sequestered acceptance specs are the executor's contract; inline them verbatim
		local acc = `{m.dir}/acceptance`
		if fs.isDir(acc) then
			local names = fs.readDir(acc)
			table.sort(names)
			for _, name in names do
				items ..= section(`{acc}/{name}`)
			end
		end
	end
	local skills = ""
	for _, s in SKILLS_INLINED do
		skills ..= section(`.claude/skills/{s}/SKILL.md`)
	end
	local plan, _, planError = workstreamPlan(raft)
	local planText = if planError then `plan unavailable: {planError}\nparallel: no` else plan
	local text = render("tracker/templates/prompt.md", {
		RAFT_ID = raft.id,
		RAFT_TITLE = store.readFront(raft.doc).title or raft.slug,
		RAFT_TYPE = store.typeOf(raft),
		ISSUE_IDS = table.concat(ids, ", "),
		ITEMS = items,
		SKILLS = skills,
		ARCHITECTURE = fs.readFile("tracker/architecture.md"),
		WORKSTREAMS = planText,
	})
	for _, m in store.members(raft.id) do
		if store.readFront(m.doc).design ~= "ready" then
			stdio.ewrite(`warning: {m.id} is not design: ready\n`)
		end
	end
	if opts["--stdout"] then
		print(text)
	else
		local r = sh.run("pbcopy", {}, text)
		if not r.ok then
			fail("pbcopy failed; use --stdout")
		end
		print(`prompt for {raft.id} ({table.concat(ids, ", ")}) copied: {#text} chars`)
	end
end

function cmd.metrics(_pos: { string }, opts: { [string]: { string } })
	type Row = { id: string, type: string, raft: string, added: number, removed: number, minutes: number }
	local rows: { Row } = {}
	local byType: { [string]: { added: number, minutes: number, count: number } } = {}
	for _, issue in store.all("issue") do
		if issue.state == "done" or (issue.state == "active" and opts["--include-active"]) then
			local t = spend.readTotals(issue.dir)
			local ty = store.typeOf(issue)
			table.insert(rows, {
				id = issue.id,
				type = ty,
				raft = store.readFront(issue.doc).raft or "",
				added = t.added,
				removed = t.removed,
				minutes = t.minutes,
			})
			local b = byType[ty] or { added = 0, minutes = 0, count = 0 }
			b.added += t.added
			b.minutes += t.minutes
			b.count += 1
			byType[ty] = b
		end
	end
	print("| issue | type | raft | +lines | -lines | agent-minutes |\n|---|---|---|---|---|---|")
	for _, r in rows do
		print(
			string.format(
				"| %s | %s | %s | %d | %d | %.1f |",
				r.id,
				r.type,
				r.raft,
				r.added,
				r.removed,
				r.minutes
			)
		)
	end
	print("\n| type | issues | +lines | agent-minutes | minutes/issue |\n|---|---|---|---|---|")
	for _, ty in { "feature", "defect", "chore" } do
		local b = byType[ty] or { added = 0, minutes = 0, count = 0 }
		local per = if b.count > 0 then b.minutes / b.count else 0
		print(string.format("| %s | %d | %d | %.1f | %.1f |", ty, b.count, b.added, b.minutes, per))
	end
	local f = byType.feature or { added = 0, minutes = 0, count = 0 }
	local d = byType.defect or { added = 0, minutes = 0, count = 0 }
	local function pct(def: number, feat: number): string
		if def + feat == 0 then
			return "n/a"
		end
		local p = 100 * def / (def + feat)
		return string.format("%.1f%%%s", p, if p > 20 then " (OVER 20% TARGET)" else "")
	end
	print("\nReview rounds per raft (design-review-NNN.md and review-NNN.md files).")
	print("| raft | design rounds | code rounds | format |\n|---|---|---|---|")
	for _, raft in store.all("raft") do
		local design, code = 0, 0
		for _, name in fs.readDir(raft.dir) do
			if string.match(name, "^design%-review%-%d+%.md$") then
				design += 1
			elseif string.match(name, "^review%-%d+%.md$") then
				code += 1
			end
		end
		local first = `{raft.dir}/design-review-001.md`
		local format = "none"
		if fs.isFile(first) then
			format = if string.find("\n" .. fs.readFile(first), "\nConsequences:", 1, true)
				then "second-order"
				else "classic"
		end
		print(string.format("| %s | %d | %d | %s |", raft.id, design, code, format))
	end
	print("\nRework = defect / (defect + feature). Target: under 20%.")
	print(`  by lines added:  {pct(d.added, f.added)}`)
	print(`  by issues:       {pct(d.count, f.count)}`)
	print(`  by agent time:   {pct(d.minutes, f.minutes)}`)
end

function cmd.board(pos: { string }, opts: { [string]: { string } })
	local given = opts["--out"] and opts["--out"][1]
	if #pos > 0 or (given and (given == "" or string.sub(given, 1, 1) == "-")) then
		fail(
			"usage: board [--out PATH] [--open]  (an --out path can't start with -; write ./-x for such a file)"
		)
	end
	local out = given or ".cache/board.html"
	local dir = string.match(out, "^(.*)/[^/]*$")
	if dir and dir ~= "" then
		fs.writeDir(dir)
	end
	fs.writeFile(out, board.build())
	-- tracker.sh runs from the repo root, so say where a relative path really is
	if string.sub(out, 1, 1) ~= "/" then
		out = process.cwd .. out
	end
	print(out)
	if opts["--open"] then
		local opener = if process.os == "macos" then "open" else "xdg-open"
		local ok, r = pcall(sh.run, opener, { out })
		if not ok or not r.ok then
			stdio.ewrite(`warning: could not open {out} with {opener}; the page is written\n`)
		end
	end
end

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end
local name = args[1]
local handler = name and (cmd :: any)[name]
if not handler then
	print(USAGE)
	process.exit(if name then 1 else 0)
end
local rest = table.move(args, 2, #args, 1, {})
local pos, opts = flags(rest)
local ok, err = pcall(handler, pos, opts)
if not ok then
	fail(`tracker {name}: {err}`)
end
