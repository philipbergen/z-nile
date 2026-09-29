--!strict
-- Tracker CLI. Run through scripts/tracker.sh. See .claude/skills/tracker/SKILL.md.
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
  start <R-id>                                  branch, move to active, commit, push, draft PR
  focus <issue-id>                              attribute following commits to this issue
  commit -m <msg> [--issue <id>]... [--time <minutes>]   stage all, record spend, commit, push
  done <R-id>                                   verify checks + review resolution, move to done, ready PR
  promote-check <R-id>                          dry-run: would promoted acceptance specs pass type check + meta?
  prompt <R-id|issue-id> [--stdout]             render the execution prompt to the clipboard
  metrics [--include-active]                    cost per issue and rework %]]

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
		if a == "--single" or a == "--stdout" or a == "--include-active" then
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
	local what = pos[1]
	if what == "issue" then
		local prefix, slug = pos[2], pos[3]
		if not (prefix and store.TYPES[prefix] and slug) then
			fail("usage: new issue <f|d|c> <slug> [--raft R0010]")
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
			RAFT = raftId or "",
			EMERGENT = if state == "active" then "true" else "false",
			DATE = today(),
		}
		fs.writeFile(`{dir}/{id}-{slug}.md`, render("tracker/templates/issue/doc.md", vars))
		fs.writeFile(`{dir}/check.sh`, render("tracker/templates/issue/check.sh", vars))
		sh.must("chmod", { "+x", `{dir}/check.sh` })
		print(`{dir}/{id}-{slug}.md`)
	elseif what == "raft" then
		local rtype, slug = pos[2], pos[3]
		if not (rtype and store.PREFIX[rtype] and slug) then
			fail("usage: new raft <feature|defect|chore> <slug> <issue>... [--single]")
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
			SINGLE = if opts["--single"] then "true" else "false",
			ISSUES = table.concat(ids, ", "),
			DATE = today(),
		}
		fs.writeFile(`{dir}/{id}-{slug}.md`, render("tracker/templates/raft/doc.md", vars))
		fs.writeFile(`{dir}/check.sh`, render("tracker/templates/raft/check.sh", vars))
		sh.must("chmod", { "+x", `{dir}/check.sh` })
		print(`{dir}/{id}-{slug}.md`)
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
		sh.git({ "mv", `{dest}/{old}-{item.slug}.md`, `{dest}/{new}-{item.slug}.md` })
	else
		fs.move(item.dir, dest)
		fs.move(`{dest}/{old}-{item.slug}.md`, `{dest}/{new}-{item.slug}.md`)
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

function cmd.start(pos: { string })
	local raft = store.get(pos[1] or fail("usage: start <R-id>"))
	if raft.kind ~= "raft" then
		fail("only rafts are started; wrap a single issue with `prompt <issue>` or `new raft ... --single`")
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
	local branch = `{raft.id}-{raft.slug}`
	sh.git({ "switch", "-c", branch })
	raft = move(raft, "active")
	for _, m in members do
		move(m, "active")
	end
	local ftitle = store.readFront(raft.doc).title or raft.slug
	sh.git({ "commit", "--quiet", "-m", `tracker: start {raft.id} {ftitle}` })
	print(`on branch {branch}; {raft.id} and {#members} issue(s) are active`)
	if sh.run("git", { "remote", "get-url", "origin" }).ok then
		sh.git({ "push", "--quiet", "-u", "origin", branch })
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
	for _, m in store.members(raft.id) do
		move(m, "done")
	end
	raft = move(raft, "done")
	if fs.isFile(FOCUS_FILE) then
		fs.removeFile(FOCUS_FILE)
	end
	recordAndCommit(raft, `tracker: done {raft.id}`, {}, nil, true)
	if hasUpstream() then
		sh.must("gh", { "pr", "ready" })
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
				`created placeholder raft {raft.id}; commit and push it before handing out the prompt\n`
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
	local text = render("tracker/templates/prompt.md", {
		RAFT_ID = raft.id,
		RAFT_TITLE = store.readFront(raft.doc).title or raft.slug,
		RAFT_TYPE = store.typeOf(raft),
		ISSUE_IDS = table.concat(ids, ", "),
		ITEMS = items,
		SKILLS = skills,
		ARCHITECTURE = fs.readFile("tracker/architecture.md"),
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
	print("\nRework = defect / (defect + feature). Target: under 20%.")
	print(`  by lines added:  {pct(d.added, f.added)}`)
	print(`  by issues:       {pct(d.count, f.count)}`)
	print(`  by agent time:   {pct(d.minutes, f.minutes)}`)
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
