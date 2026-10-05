--!strict
-- Tracker CLI. Run through scripts/tracker.sh. See .claude/skills/tracker/SKILL.md.
local audit = require("./audit")
local board = require("./board")
local compactLib = require("./compact")
local fs = require("@lune/fs")
local idsLib = require("./ids")
local process = require("@lune/process")
local publish = require("./publish")
local sh = require("../lib/sh")
local spend = require("./spend")
local statusLib = require("./status")
local stdio = require("@lune/stdio")
local store = require("./store")

local USAGE = [[
usage: scripts/tracker.sh <command> ...
  new issue <f|d|c> <slug> [--raft R0010] [--desc "<line>"]   create an issue (emergent if the raft is active)
  new raft <feature|defect|chore> <slug> <issue>... [--single]
  status [<id>] [<to>]                          list statuses on origin/main, show one, or move one (new|preparing|prepared; start claims active)
  sync [--fetch]                                bring origin/main into this checkout (--fetch: update origin/main only)
  stamp <state>                                 print a fresh status stamp (diagnostics)
  find <id>                                     print the item's current directory
  list [backlog|active|done]                    list items
  members <R-id>                                print directories of every issue in the raft
  check <id>                                    run an item's check.sh (a raft runs its own)
  renumber <old> [<new>]                        step an id (conflict resolution); <new> defaults to one above the highest
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
  board [--out PATH] [-O]                       write the tracker as one HTML page (default .cache/board.html)
                                                and open it in the browser; -O only writes it]]

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

-- tracker.sh changes into the repository root before it starts Lune, so the working directory is the
-- checkout the tracker belongs to. A fixture whose own `.git` is missing would otherwise fall through to an
-- enclosing repository, the real one, and change it.
local function guardRepoRoot()
	local here = sh.run("pwd", { "-P" })
	local top = sh.run("git", { "rev-parse", "--show-toplevel" })
	-- no repository at all (a sandbox outside any checkout) cannot fall through to another one
	if here.ok and top.ok and sh.trim(top.stdout) ~= sh.trim(here.stdout) then
		fail(
			`refusing to run: git's repository root is "{sh.trim(top.stdout)}", not "{sh.trim(here.stdout)}" (is .git missing here?)`
		)
	end
	-- the root alone is not enough: an inherited git-directory variable makes the working directory the root while
	-- git reads and writes another repository. So git's directory must be this checkout's own .git (a directory,
	-- or in a linked worktree a `gitdir:` file).
	local dir = sh.run("git", { "rev-parse", "--absolute-git-dir" })
	if here.ok and dir.ok then
		local root = sh.trim(here.stdout)
		local own: string? = nil
		if fs.isDir(`{root}/.git`) then
			own = `{root}/.git`
		elseif fs.isFile(`{root}/.git`) then
			local target = string.match(fs.readFile(`{root}/.git`), "^gitdir:%s*(.-)%s*$")
			if target then
				own = if string.sub(target, 1, 1) == "/" then target else `{root}/{target}`
			end
		end
		local function physical(path: string): string?
			local r = sh.run("sh", { "-c", 'cd "$1" 2>/dev/null && pwd -P', "_", path })
			return if r.ok then sh.trim(r.stdout) else nil
		end
		local used = physical(sh.trim(dir.stdout))
		if not own or physical(own) ~= used then
			fail(
				`refusing to run: git's repository is "{used or sh.trim(dir.stdout)}", not this checkout's own .git in "{root}"`
			)
		end
	end
end

-- A check run protects this repository (the repository guards, c0640): tracker state is never published from
-- inside one (c0650). Asked once per command; the guards' own script answers, so no variable is named here.
local guardedRun: boolean? = nil
local function guarded(): boolean
	if guardedRun == nil then
		local r = process.exec("bash", {
			"-c",
			'[ -f scripts/lib/fence.sh ] && source scripts/lib/fence.sh && pickman_guarded "$PWD"',
		})
		guardedRun = r.ok
		if r.ok then
			stdio.ewrite(
				`not publishing: {process.cwd} is protected by the repository guards (a check run)\n`
			)
		end
	end
	return guardedRun == true
end

local function publishing(): boolean
	local v = process.env.PICKMAN_PUBLISH
	return hasOrigin() and (v == nil or v == "" or v ~= "0") and not guarded()
end

local function frontOf(text: string): { [string]: string }
	local out: { [string]: string } = {}
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-") or ""
	-- one key per line, anchored at the line start like the writer (store.withFront)
	for line in string.gmatch(block .. "\n", "([^\n]*)\n") do
		local k, v = string.match(line, "^([%w_]+):[ ]*(.*)$")
		if k and v then
			out[k] = sh.trim(v)
		end
	end
	return out
end

local function withFront(text: string, key: string, value: string): string
	local out = store.withFront(text, key, value)
	if not out then
		fail("a tracker document has no frontmatter")
	end
	return out :: string
end

local function stateOfPath(path: string): store.State
	return if string.find(path, "/active/", 1, true)
		then "active"
		elseif string.find(path, "/done/", 1, true) then "done"
		else "backlog"
end

local function docPath(paths: { string }, id: string): string?
	for _, p in paths do
		if string.sub(p, -(#id * 2 + 5)) == `/{id}/{id}.md` then
			return p
		end
	end
	return nil
end

-- Brings what was just published into this worktree. A conflicting merge is aborted, so the tree is
-- left as it was and `tracker.sh sync` can be run again after resolving by hand.
local function mergeOrigin()
	local r = sh.run("git", { "merge", "--no-edit", "origin/main" })
	if not r.ok then
		sh.run("git", { "merge", "--abort" })
		fail(
			`published, but merging origin/main failed (merge aborted): {r.stderr}{r.stdout}\nresolve it with: git merge origin/main`
		)
	end
end

-- Real entropy, folded into 31 bits: Lune's math.randomseed saturates larger seeds, so seeding with
-- os.time() plus os.clock() (seconds since boot) gave every process the same stamp.
local function entropy(): number
	local r = sh.run("od", { "-An", "-N4", "-tu4", "/dev/urandom" })
	local n = tonumber(sh.trim(r.stdout))
	if r.ok and n then
		return n % 2147483647
	end
	return (os.time() * 31 + math.floor((os.clock() % 1) * 1e6)) % 2147483647
end

local seeded = false
local function stamp(state: string): string
	if not seeded then
		math.randomseed(entropy())
		seeded = true
	end
	return statusLib.stamp(state, function(n: number): number
		return math.random(1, n)
	end)
end

local function raftIsActiveHere(): boolean
	for _, r in store.all("raft") do
		if r.state == "active" then
			return true
		end
	end
	return false
end

local function claimFile(raftId: string): string
	return `.cache/tracker-claim-{raftId}`
end

local function idsOf(paths: { string }, kind: string): { string }
	local out: { string } = {}
	for _, p in paths do
		local id = string.match(p, "/([fdcR]%d%d%d%d)/[^/]+$")
		if id and (if kind == "raft" then store.isRaftId(id) else store.isIssueId(id)) then
			table.insert(out, id)
		end
	end
	return out
end

-- Every file path under tracker/ on origin/main as it is (no fetch), and whether origin/main could be read. The one
-- reader of origin/main's ids: `new` (originIds) and `renumber` (originMainIds) differ only in fetching and failure.
local function originTree(): (boolean, { string })
	local r = sh.run("git", { "ls-tree", "-r", "--name-only", "--full-tree", "origin/main", "tracker/" })
	return r.ok, if r.ok then string.split(r.stdout, "\n") else {}
end

-- The ids of `kind` on origin/main, after a quiet fetch, when publishing is on; otherwise none (no network).
-- Local-only creations (emergent issues, PICKMAN_PUBLISH=0 aside) then still number above what origin holds.
local function originIds(kind: string): { string }
	if not publishing() then
		return {}
	end
	sh.run("git", { "fetch", "-q", "origin", "main" })
	local _, paths = originTree()
	return idsOf(paths, kind)
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

-- A tree from before a compaction on origin/main never acts on origin (c0870): its old-scheme ids would push the
-- counter back up, and old ids name other items there now. Asked before every publish, and by every allocating
-- command; `remap` is the way out, so it does not ask.
local function refuseStale()
	if publishing() then
		sh.run("git", { "fetch", "-q", "origin", "main" })
	end
	local theirs = sh.run("git", { "show", `origin/main:{idsLib.MAP_FILE}` })
	if not theirs.ok then
		return
	end
	local mine = if fs.isFile(idsLib.MAP_FILE) then fs.readFile(idsLib.MAP_FILE) else nil
	if mine ~= theirs.stdout then
		fail(
			"this tree predates the compaction on origin/main: a branch that changed tracker/ runs tracker.sh remap; any other merges origin/main"
		)
	end
end

-- publish.commit for every command but remap: a stale tree is refused first.
local function publishFresh(build: publish.Build, message: string | () -> string): publish.Result
	refuseStale()
	return publish.commit(".", build, message)
end

-- The three words of a fresh stamp: the phrase that makes every write of tracker/next differ (c0870).
local function phrase(): string
	return (string.match(stamp("new"), "^%a+%-(.+)$")) :: string
end

-- Ids of `space` in the local tree, read without store.find, so a malformed tree still yields them.
local function localIds(space: string): { string }
	local out: { string } = {}
	for _, f in audit.scan(".") do
		if idsLib.spaceOf(f.id) == space then
			table.insert(out, f.id)
		end
	end
	return out
end

local function localCounters(): idsLib.Counters?
	return if fs.isFile(idsLib.FILE) then idsLib.parse(fs.readFile(idsLib.FILE)) else nil
end

-- The next number of `space` from origin's tracker/next (as `read` returns it), and the change that raises it.
-- Both nil when origin has no counter: the old numbering applies. The third result is an error.
local function reserve(
	space: string,
	used: { string },
	read: (string) -> string?
): (number?, publish.Change?, string?)
	local text = read(idsLib.FILE)
	if not text then
		return nil, nil, nil
	end
	local c = idsLib.parse(text)
	if not c then
		return nil, nil, `{idsLib.FILE} on origin/main does not parse`
	end
	local n = idsLib.nextFree(space, c, used)
	if n > 9999 then
		return nil, nil, "no number above 9999 is free"
	end
	local raised: idsLib.Counters = { issue = c.issue, raft = c.raft }
	if space == "raft" then
		raised.raft = n + 1
	else
		raised.issue = n + 1
	end
	return n, { path = idsLib.FILE, content = idsLib.format(raised, phrase()) }, nil
end

-- Reserves the next number of `space` on origin/main by pushing only the raised counter; nil when origin/main has
-- no tracker/next. `extra`: ids that count besides origin's (the local tree's).
local function reserveOnOrigin(space: string, extra: { string }): number?
	local chosen: number? = nil
	local r = publishFresh(function(paths, read)
		local used = idsOf(paths, space)
		for _, id in extra do
			table.insert(used, id)
		end
		local n, change, err = reserve(space, used, read)
		if err then
			return err
		end
		chosen = n
		return if change then { change :: publish.Change } else {}
	end, function()
		return `tracker: reserve {space} number {chosen or "?"}`
	end)
	if not r.ok then
		fail(`could not reserve a number on origin/main: {r.reason}`)
	end
	return chosen
end

-- Offline: the local counter when there is one (never written), else the old rule.
local function localNumber(space: string, legacy: () -> number): number
	local c = localCounters()
	if c then
		return idsLib.nextFree(space, c, localIds(space))
	end
	return legacy()
end

local function flags(args: { string }): ({ string }, { [string]: { string } })
	local pos: { string } = {}
	local opts: { [string]: { string } } = {}
	local i = 1
	while i <= #args do
		local a = args[i]
		if
			a == "--single"
			or a == "--stdout"
			or a == "--include-active"
			or a == "--open"
			or a == "--fetch"
			or a == "--force"
			or a == "-O"
		then
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

-- The issue document with `--desc` (when given) in place of the Problem section's comment.
local function withDesc(doc: string, opts: { [string]: { string } }): string
	local desc = opts["--desc"] and opts["--desc"][1]
	if not desc then
		return doc
	end
	return (string.gsub(doc, "## Problem\n<!%-%-.-%-%->", function()
		return "## Problem\n" .. desc
	end, 1))
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
		refuseStale()
		local raftId = opts["--raft"] and opts["--raft"][1]
		local raft = raftId and store.get(raftId)
		local state: store.State = if raft and raft.state == "active" then "active" else "backlog"
		if raftId and state == "backlog" and publishing() then
			fail("--raft is only for emergent issues of an active raft")
		end
		if state == "backlog" and publishing() then
			local chosen = ""
			local r = publishFresh(function(paths, read)
				local ids = idsOf(paths, "issue")
				for _, id in localIds("issue") do
					table.insert(ids, id)
				end
				local n, counter, err = reserve("issue", ids, read)
				if err then
					return err
				end
				chosen = store.formatId(prefix, n or statusLib.nextNumber(ids))
				local vars = {
					ID = chosen,
					TYPE = store.TYPES[prefix],
					TITLE = title(slug),
					SLUG = slug,
					RAFT = "",
					EMERGENT = "false",
					DATE = today(),
				}
				local doc = withDesc(render("tracker/templates/issue/doc.md", vars), opts)
				local changes: { publish.Change } = {
					{
						path = `tracker/issues/{chosen}/{chosen}.md`,
						content = withFront(doc, "status", stamp("new")),
					},
					{
						path = `tracker/issues/{chosen}/check.sh`,
						content = render("tracker/templates/issue/check.sh", vars),
						mode = "100755",
					},
				}
				if counter then
					table.insert(changes, counter)
				end
				return changes
			end, function()
				return `tracker: new {chosen} {slug}`
			end)
			if not r.ok then
				fail(
					`new: could not publish to origin/main: {r.reason}\n(PICKMAN_PUBLISH=0 creates it locally instead)`
				)
			end
			-- inside a raft's worktree the stub reaches the branch with the final merge of origin/main
			if not raftIsActiveHere() then
				mergeOrigin()
			end
			print(`tracker/issues/{chosen}/{chosen}.md`)
			return
		end
		-- an emergent issue reserves its number on origin/main (only the counter is pushed); offline, the local counter
		local reserved = if publishing() then reserveOnOrigin("issue", localIds("issue")) else nil
		local n = reserved
			or localNumber("issue", function()
				return store.nextNumber("issue", originIds("issue"))
			end)
		local id = store.formatId(prefix, n)
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
		fs.writeFile(`{dir}/{id}.md`, withDesc(render("tracker/templates/issue/doc.md", vars), opts))
		fs.writeFile(`{dir}/check.sh`, render("tracker/templates/issue/check.sh", vars))
		sh.must("chmod", { "+x", `{dir}/check.sh` })
		print(`{dir}/{id}.md`)
	elseif what == "raft" then
		local rtype, slug = pos[2], pos[3]
		if not (rtype and store.PREFIX[rtype] and slug) then
			fail("usage: new raft <feature|defect|chore> <slug> <issue>... [--single]")
		end
		refuseStale()
		if not string.match(slug, "^[a-z][a-z0-9%-]*$") then
			fail(`invalid slug: {slug} (lowercase words joined by hyphens)`)
		end
		if publishing() then
			if sh.git({ "status", "--porcelain" }) ~= "" then
				fail(
					"working tree is not clean: commit or stash first (new raft merges origin/main right after it claims)"
				)
			end
			local ids: { string } = {}
			for i = 4, #pos do
				table.insert(ids, pos[i])
			end
			if #ids == 0 then
				fail("a raft needs at least one issue")
			end
			local chosen = ""
			local r = publishFresh(function(paths, read)
				local known = idsOf(paths, "raft")
				for _, raft in store.all("raft") do
					table.insert(known, raft.id)
				end
				local n, counter, err = reserve("raft", known, read)
				if err then
					return err
				end
				chosen = store.formatId("R", n or statusLib.nextNumber(known))
				local claim = stamp("preparing")
				local changes: { publish.Change } = {}
				for _, id in ids do
					local path = docPath(paths, id)
					local text = path and read(path)
					if not path or not text then
						return `{id} is not on origin/main`
					end
					local owner = frontOf(text).raft
					if owner and owner ~= "" then
						return `{id} already belongs to {owner}`
					end
					local st = statusLib.effective(frontOf(text), stateOfPath(path))
					if st ~= "new" then
						return `{id} is {st} on origin/main, not new`
					end
					if store.TYPES[string.sub(id, 1, 1)] ~= rtype then
						return `{id} is a {store.TYPES[string.sub(id, 1, 1)]}; a {rtype} raft cannot contain it`
					end
					-- only `status:` is written: `raft:` sits beside `depends_on:`, which a capture PR may be editing
					table.insert(changes, { path = path, content = withFront(text, "status", claim) })
				end
				local vars = {
					ID = chosen,
					TYPE = rtype,
					TITLE = title(slug),
					SLUG = slug,
					SINGLE = if opts["--single"] then "true" else "false",
					ISSUES = table.concat(ids, ", "),
					DATE = today(),
				}
				table.insert(changes, {
					path = `tracker/rafts/{chosen}/{chosen}.md`,
					content = withFront(render("tracker/templates/raft/doc.md", vars), "status", claim),
				})
				table.insert(changes, {
					path = `tracker/rafts/{chosen}/check.sh`,
					content = render("tracker/templates/raft/check.sh", vars),
					mode = "100755",
				})
				if counter then
					table.insert(changes, counter)
				end
				return changes
			end, function()
				return `tracker: new raft {chosen} {slug}`
			end)
			if not r.ok then
				fail(`new raft: {r.reason}`)
			end
			mergeOrigin()
			-- membership is written locally and committed, so later merges of origin/main stay clean
			for _, id in ids do
				local doc = store.get(id).doc
				store.setFront(doc, "raft", chosen)
				sh.git({ "add", doc })
			end
			sh.git({ "commit", "--quiet", "-m", `tracker: {chosen} members` })
			print(`tracker/rafts/{chosen}/{chosen}.md`)
			return
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
		local id = store.formatId(
			"R",
			localNumber("raft", function()
				return store.nextNumber("raft", originIds("raft"))
			end)
		)
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

local function originPaths(): { string }
	sh.git({ "fetch", "--quiet", "origin", "main" })
	return string.split(
		sh.git({ "ls-tree", "-r", "--name-only", "--full-tree", "origin/main", "tracker/" }),
		"\n"
	)
end

-- `status` lists what origin/main says about every item that is not done; `status <id>` prints one
-- item's status; `status <id> <to>` moves it (checked against origin/main, not the local file).
-- A move of a raft moves its members too. Published moves are pushed at once; the move to
-- `prepared` is carried by the prep PR and only edits the local documents.
function cmd.status(pos: { string })
	local id, to = pos[1], pos[2]
	if to then
		refuseInMainCheckout("status")
	end
	if not publishing() then
		fail("status needs an origin remote (PICKMAN_PUBLISH=0 disables it)")
	end
	if not id then
		for _, p in originPaths() do
			if publish.allowed(p) and string.match(p, "/[^/]+%.md$") and stateOfPath(p) ~= "done" then
				local front = frontOf(sh.git({ "show", `origin/main:{p}` }))
				local fid = string.match(p, "/([fdcR]%d%d%d%d)/[^/]+$") :: string
				print(`{fid} {statusLib.effective(front, stateOfPath(p))} {front.title or ""}`)
			end
		end
		return
	end
	if not to then
		local p = docPath(originPaths(), id)
		if not p then
			fail(`{id} is not on origin/main`)
		end
		print(
			statusLib.effective(
				frontOf(sh.git({ "show", `origin/main:{p :: string}` })),
				stateOfPath(p :: string)
			)
		)
		return
	end
	if not statusLib.parse(to) then
		fail(`unknown status {to} (new, preparing, prepared, active, done)`)
	end
	if to == "active" then
		fail(
			"only tracker.sh start claims active: it checks the tree, the designs and the dependencies first"
		)
	end
	local moved: { { id: string, from: string } } = {}
	local carried = false
	local r = publishFresh(function(paths, read)
		moved = {}
		local path = docPath(paths, id)
		local text = path and read(path)
		if not path or not text then
			return `{id} is not on origin/main`
		end
		local front = frontOf(text)
		local from = statusLib.effective(front, stateOfPath(path))
		carried = statusLib.carriedByPr(from, to)
		-- a carried move lands with the prep PR, so it follows the member list that PR will carry
		local list = front.issues
		if carried and store.isRaftId(id) then
			list = store.readFront(store.get(id).doc).issues
		end
		local targets = { id }
		if store.isRaftId(id) then
			for _, m in store.idList(list) do
				table.insert(targets, m)
			end
		end
		local value = stamp(to)
		local changes: { publish.Change } = {}
		for _, t in targets do
			local tp = docPath(paths, t)
			local tt = tp and read(tp)
			if not tp or not tt then
				return `{t} is not on origin/main`
			end
			local tf = frontOf(tt)
			local cur = statusLib.effective(tf, stateOfPath(tp))
			if carried and t ~= id and cur ~= "preparing" then
				return `{t} is {cur} on origin/main: claim it first with tracker.sh status {t} preparing`
			end
			if carried then
				-- the move to `prepared` ties the two fields together: designs are ready first
				local localItem = store.get(t)
				if store.readFront(localItem.doc).design ~= "ready" then
					return `{t} is not design: ready: set it (ticket-prep) before status {id} prepared`
				end
			end
			if
				not (
					statusLib.canMove(cur, to)
					or statusLib.canClaim(cur, to, tf.status ~= nil, store.isRaftId(id))
				)
			then
				return `{t} is {cur} on origin/main: cannot move to {to}`
			end
			table.insert(moved, { id = t, from = cur :: string })
			table.insert(changes, { path = tp, content = withFront(tt, "status", value) })
		end
		if carried then
			return {}
		end
		return changes
	end, function()
		return `tracker: {id} {to}`
	end)
	if not r.ok then
		fail(r.reason or "publish failed")
	end
	if carried then
		local value = stamp(to)
		for _, m in moved do
			store.setFront(store.get(m.id).doc, "status", value)
		end
	else
		mergeOrigin()
	end
	-- giving a claim back ends this worktree's ownership of it
	if store.isRaftId(id) and moved[1].from == "active" and fs.isFile(claimFile(id)) then
		fs.removeFile(claimFile(id))
	end
end

-- Prints a fresh stamp for a state (diagnostics, and how specs prove that stamps differ between processes).
function cmd.stamp(pos: { string })
	local state = pos[1]
	if not state or not statusLib.parse(state) then
		fail("usage: stamp <new|preparing|prepared|active|done>")
	end
	print(stamp(state))
end

-- `sync` brings origin/main into this checkout (a merge in a worktree, a fast-forward in the main
-- checkout). `sync --fetch` only updates origin/main: reviewers and stream agents use it, because
-- a merge would add a commit and change the diff they judge.
function cmd.sync(_: { string }, opts: { [string]: { string } })
	sh.git({ "fetch", "--quiet", "origin", "main" })
	if not opts["--fetch"] then
		if sh.git({ "rev-parse", "--show-toplevel" }) == mainRoot() then
			sh.git({ "pull", "--quiet", "--ff-only" })
		else
			mergeOrigin()
		end
	end
	print(`synced to {sh.git({ "rev-parse", "--short", "origin/main" })}`)
end

function cmd.find(pos: { string })
	print(store.get(pos[1] or fail("usage: find <id>")).dir)
end

function cmd.members(pos: { string })
	for _, m in store.members(pos[1] or fail("usage: members <R-id>")) do
		print(m.dir)
	end
end

-- Prints every item it can read, both copies of a duplicated id included, then fails on the problems that stop
-- store.find (c0880): the other commands refuse such a tree, so `list` says where the trouble is.
function cmd.list(pos: { string })
	local found = audit.scan(".")
	table.sort(found, function(a, b)
		return if a.id == b.id then a.path < b.path else a.id < b.id
	end)
	for _, kind in { "raft", "issue" } do
		for _, f in found do
			local doc = `{f.path}/{f.id}.md`
			if f.kind == kind and idsLib.spaceOf(f.id) == kind and fs.isFile(doc) then
				local state = stateOfPath(f.path .. "/")
				if not pos[1] or pos[1] == state then
					local fm = store.readFront(doc)
					local ftype = if kind == "issue"
						then store.TYPES[string.sub(f.id, 1, 1)]
						else (fm.type or "?")
					print(
						string.format(
							"%-6s %-8s %-8s %-7s %s",
							f.id,
							state,
							ftype,
							fm.raft or "",
							fm.title or fm.slug or ""
						)
					)
				end
			end
		end
	end
	local broken = 0
	for _, p in audit.run(".") do
		if audit.ITEM_CODES[p.code] then
			stdio.ewrite(audit.format(p) .. "\n")
			broken += 1
		end
	end
	if broken > 0 then
		process.exit(1)
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

-- Every problem in the tracker tree (c0880); fails when any is an error. Read-only.
function cmd.audit()
	local problems = audit.run(".")
	for _, p in problems do
		print(audit.format(p))
	end
	local errors = audit.errors(problems)
	print(`audit: {errors} errors, {#problems - errors} warnings`)
	if errors > 0 then
		process.exit(1)
	end
end

-- List mode (AC_LIST) would make check.sh verify nothing and still print a clean summary.
local function refuseListMode()
	local v = process.env.AC_LIST
	if v ~= nil and v ~= "" then
		fail("AC_LIST is set: checks would only be listed, not run; unset it")
	end
end

-- Runs check.sh for an item. A raft's check.sh is responsible for running its members' checks.
local function runCheck(item: store.Item): boolean
	refuseListMode()
	print(`\n=== {item.id} check.sh`)
	return sh.stream("bash", { `{item.dir}/check.sh` })
end

function cmd.check(pos: { string })
	if not runCheck(store.get(pos[1] or fail("usage: check <id>"))) then
		process.exit(1)
	end
end

-- Ids of `kind` on origin/main (any state) as it is: the local tree may be behind. Unlike originIds (used by `new`),
-- it never fetches and refuses when origin/main can't be read: renumber must not guess.
local function originMainIds(kind: string): { string }
	local ok, paths = originTree()
	if not ok then
		fail("cannot read origin/main (run `git fetch origin main`), or pass <new> explicitly")
	end
	return idsOf(paths, kind)
end

-- Rewrites `old` to `new` as a whole id in every .md and .sh file under `dir`.
local function rewriteUnder(dir: string, old: string, new: string)
	for _, name in fs.readDir(dir) do
		local p = `{dir}/{name}`
		if fs.isDir(p) then
			rewriteUnder(p, old, new)
		elseif string.match(name, "%.md$") or string.match(name, "%.sh$") then
			local text = fs.readFile(p)
			local replaced, n = string.gsub(text, `%f[%w]{old}%f[^%w]`, new)
			if n > 0 then
				fs.writeFile(p, replaced)
			end
		end
	end
end

-- `renumber <old> [<new>]`, or `renumber <item directory> [<new>]` for one copy of a duplicated id: only that folder
-- moves, and ids are rewritten only inside it, because every other reference means the other copy (c0880).
function cmd.renumber(pos: { string })
	refuseInMainCheckout("renumber")
	local arg, new = pos[1], pos[2]
	if not arg then
		fail("usage: renumber <old> [<new>] (same type prefix)")
	end
	local item: store.Item
	local byDir = string.find(arg, "/", 1, true) ~= nil
	if byDir then
		local path = string.gsub(arg, "/+$", "")
		local kindDir, state, id = string.match(path, "^tracker/(%a+)/(%a+)/([^/]+)$")
		if not kindDir then
			kindDir, id = string.match(path, "^tracker/(%a+)/([^/]+)$")
			state = nil
		end
		local space = id and idsLib.spaceOf(id)
		local want = if kindDir == "issues" then "issue" elseif kindDir == "rafts" then "raft" else nil
		local okState = state == nil or state == "active" or state == "done"
		if not (id and space and space == want and okState and fs.isFile(`{path}/{id}.md`)) then
			fail(`renumber: {arg} is not an item directory (tracker/<issues|rafts>/[active/|done/]<id>)`)
		end
		if state == "done" then
			local others: { string } = {}
			for _, f in audit.scan(".") do
				if f.id == id and f.path ~= path then
					table.insert(others, f.path)
				end
			end
			fail(
				`renumber: {path} is done (its specs are promoted under its id); renumber the copy that is not in done/: {table.concat(
					others,
					", "
				)}`
			)
		end
		local st: store.State = if state then state :: string else "backlog"
		item = {
			id = id :: string,
			kind = space :: string,
			state = st,
			dir = path,
			doc = `{path}/{id}.md`,
			slug = "",
		}
	else
		item = store.get(arg)
	end
	local old = item.id
	if new and string.sub(old, 1, 1) ~= string.sub(new, 1, 1) then
		fail("usage: renumber <old> [<new>] (same type prefix)")
	end
	if new and store.find(new) then
		fail(`{new} already exists`)
	end
	if not new then
		refuseStale()
		local kind = item.kind
		local n: number? = nil
		if publishing() then
			n = reserveOnOrigin(kind, localIds(kind))
		elseif localCounters() then
			local used = localIds(kind)
			for _, id in originMainIds(kind) do
				table.insert(used, id)
			end
			n = idsLib.nextFree(kind, localCounters() :: idsLib.Counters, used)
		end
		if not n then
			n = store.nextAbove(kind, originMainIds(kind))
		end
		if (n :: number) > 9999 then
			fail("no number above 9999 is free")
		end
		new = store.formatId(string.sub(old, 1, 1), n :: number)
	end
	local dest = store.dirFor(item.kind, item.state, new :: string)
	if fs.isDir(dest) then
		fail(`{new} already exists`)
	end
	local tracked = sh.run("git", { "ls-files", "--error-unmatch", item.doc }).ok
	if tracked then
		sh.git({ "mv", item.dir, dest })
		sh.git({ "mv", `{dest}/{old}.md`, `{dest}/{new}.md` })
	else
		fs.move(item.dir, dest)
		fs.move(`{dest}/{old}.md`, `{dest}/{new}.md`)
	end
	rewriteUnder(if byDir then dest else store.ROOT, old, new :: string)
	print(`{old} -> {new}`)
end

local function refuseDirty(what: string)
	if sh.git({ "status", "--porcelain" }) ~= "" then
		fail(`{what}: the working tree is not clean`)
	end
end

local function auditErrors(skip: (string) -> boolean): { string }
	local out: { string } = {}
	for _, p in audit.run(".") do
		if p.level == "error" and not skip(p.code) then
			table.insert(out, audit.format(p))
		end
	end
	return out
end

local function noSkip(_: string): boolean
	return false
end

-- `compact [--force]`: renumbers every item from 0001 (c0870), as one local commit in a worktree cut from origin/main.
function cmd.compact(_: { string }, opts: { [string]: { string } })
	refuseInMainCheckout("compact")
	refuseDirty("compact")
	sh.git({ "fetch", "-q", "--prune", "origin" })
	local base = sh.git({ "rev-parse", "origin/main" })
	if sh.git({ "rev-parse", "HEAD" }) ~= base then
		fail(
			"compact runs on a branch cut from origin/main with no commits of its own: HEAD is not origin/main"
		)
	end
	local busy = compactLib.busyRefs(sh.git({ "branch", "--show-current" }))
	if #busy > 0 and not opts["--force"] then
		fail(
			`compact: these branches change tracker/ or tests/acceptance/: {table.concat(busy, ", ")}\n`
				.. "land or delete them first, or pass --force and run tracker.sh remap on each"
		)
	end
	local before = auditErrors(noSkip)
	if #before > 0 then
		fail("compact: the tracker tree has problems; fix them first:\n" .. table.concat(before, "\n"))
	end
	local found = audit.scan(".")
	local all: { string } = {}
	local counts = { issue = 0, raft = 0 }
	for _, f in found do
		table.insert(all, f.id)
		local space = idsLib.spaceOf(f.id) :: string
		counts[space] += 1
	end
	local map = idsLib.plan(all)
	compactLib.apply(map, found)
	fs.writeFile(idsLib.FILE, idsLib.format({ issue = counts.issue + 1, raft = counts.raft + 1 }, phrase()))
	fs.writeFile(
		idsLib.MAP_FILE,
		idsLib.formatMap(map, `tracker.sh compact, {today()}, from origin/main {base}`)
	)
	local after = auditErrors(noSkip)
	if #after > 0 then
		fail(
			"compact: the result fails the audit (discard it with git reset --hard HEAD):\n"
				.. table.concat(after, "\n")
		)
	end
	sh.git({ "add", "-A" })
	sh.git({ "commit", "--quiet", "-m", "tracker: compact ids" })
	print(`compacted {counts.issue} issues and {counts.raft} rafts; the map is in {idsLib.MAP_FILE}`)
	if #busy > 0 then
		print(
			`in flight: {table.concat(busy, ", ")}: on each, run tracker.sh remap before merging origin/main`
		)
	end
end

-- `remap`: a branch that was in flight during a compaction takes the new ids (c0870): origin/main's map, plus numbers
-- from origin's counter for the branch's own items, then one commit. Merge origin/main afterwards.
function cmd.remap()
	refuseInMainCheckout("remap")
	refuseDirty("remap")
	sh.git({ "fetch", "-q", "origin", "main" })
	local shown = sh.run("git", { "show", `origin/main:{idsLib.MAP_FILE}` })
	if not shown.ok then
		fail(`remap: origin/main has no {idsLib.MAP_FILE}: nothing was compacted`)
	end
	if fs.isFile(idsLib.MAP_FILE) and fs.readFile(idsLib.MAP_FILE) == shown.stdout then
		fail("remap: this branch already has origin/main's compaction")
	end
	local map = idsLib.parseMap(shown.stdout)
	if not map then
		fail(`remap: origin/main's {idsLib.MAP_FILE} does not parse`)
	end
	local m = map :: { [string]: string }
	local found = audit.scan(".")
	local unmapped: { string } = {}
	for _, f in found do
		if not m[f.id] and not table.find(unmapped, f.id) then
			table.insert(unmapped, f.id)
		end
	end
	-- The branch's own items, in plan order (number, then prefix), take consecutive numbers from origin's counter,
	-- which one publish raises past the last of them. Only origin's ids count: the branch's are in the old scheme.
	local order = idsLib.plan(unmapped)
	table.sort(unmapped, function(a, b)
		return order[a] < order[b]
	end)
	local function number(c: idsLib.Counters, used: { string }): idsLib.Counters
		local raised: idsLib.Counters = { issue = c.issue, raft = c.raft }
		for _, space in { "issue", "raft" } do
			local n = idsLib.nextFree(space, c, used)
			for _, id in unmapped do
				if idsLib.spaceOf(id) == space then
					m[id] = store.formatId(string.sub(id, 1, 1), n)
					n += 1
				end
			end
			if space == "raft" then
				raised.raft = n
			else
				raised.issue = n
			end
		end
		return raised
	end
	if #unmapped > 0 then
		if publishing() then
			local r = publish.commit(".", function(paths, read)
				local c = idsLib.parse(read(idsLib.FILE) or "")
				if not c then
					return `origin/main has no usable {idsLib.FILE}`
				end
				local used = idsOf(paths, "issue")
				for _, id in idsOf(paths, "raft") do
					table.insert(used, id)
				end
				return { { path = idsLib.FILE, content = idsLib.format(number(c, used), phrase()) } }
			end, "tracker: reserve numbers for a remap")
			if not r.ok then
				fail(`remap: could not reserve numbers on origin/main: {r.reason}`)
			end
		else
			local _, paths = originTree()
			local c = idsLib.parse(sh.run("git", { "show", `origin/main:{idsLib.FILE}` }).stdout)
			if not c then
				fail(`remap: origin/main has no usable {idsLib.FILE}`)
			end
			local used = idsOf(paths, "issue")
			for _, id in idsOf(paths, "raft") do
				table.insert(used, id)
			end
			number(c :: idsLib.Counters, used)
		end
	end
	compactLib.apply(m, found)
	sh.git({ "add", "-A" })
	sh.git({ "commit", "--quiet", "-m", "tracker: remap ids" })
	-- Then merge origin/main against the merge base with the same map applied: every path then matches on all three
	-- sides, so git never has to guess a rename (similar documents, such as stubs, get paired wrongly).
	local mb = sh.git({ "merge-base", "HEAD", "origin/main" })
	local scratch = ".cache/tracker-remap-base"
	fs.writeDir(".cache")
	sh.run("git", { "worktree", "remove", "--force", scratch })
	sh.git({ "worktree", "add", "-q", "--detach", scratch, mb })
	compactLib.apply(m, audit.scan(scratch), scratch)
	local addBase = process.exec("git", { "add", "-A" }, { cwd = scratch })
	local baseTree = process.exec("git", { "write-tree" }, { cwd = scratch })
	sh.run("git", { "worktree", "remove", "--force", scratch })
	if not addBase.ok or not baseTree.ok then
		fail("remap committed, but the remapped merge base could not be built: git merge origin/main by hand")
	end
	local mt = sh.run(
		"git",
		{ "merge-tree", "--write-tree", `--merge-base={sh.trim(baseTree.stdout)}`, "HEAD", "origin/main" }
	)
	if not mt.ok then
		fail(
			`remap committed, but merging origin/main conflicts: git merge origin/main and resolve\n{mt.stdout}`
		)
	end
	local tree = string.match(mt.stdout, "^(%x+)") :: string
	local merge = sh.git({
		"commit-tree",
		tree,
		"-p",
		"HEAD",
		"-p",
		"origin/main",
		"-m",
		"Merge origin/main after remap",
	})
	sh.git({ "merge", "--quiet", "--ff-only", merge })
	local lines: { string } = {}
	for _, f in found do
		if m[f.id] ~= f.id then
			table.insert(lines, `{f.id} -> {m[f.id]}`)
		end
	end
	table.sort(lines)
	print(table.concat(lines, "\n"))
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
	-- a dependency outside the raft must already be done: nothing else orders rafts
	local inRaft: { [string]: boolean } = {}
	for _, m in members do
		inRaft[m.id] = true
	end
	for _, m in members do
		for _, dep in store.idList(store.readFront(m.doc).depends_on) do
			if not inRaft[dep] then
				local found = store.find(dep)
				if not found or found.state ~= "done" then
					fail(
						`{m.id} depends on {dep}, which is {if found then found.state else "unknown"} as this branch sees it: it must be done first. If it has merged, git merge origin/main and retry; never edit depends_on to get past this`
					)
				end
			end
		end
	end
	local branch = raftBranch(raft)
	-- every local precondition first: a refusal after the claim would leave origin saying `active`
	local onBranch = sh.git({ "branch", "--show-current" }) == branch
	if not onBranch then
		refuseInMainCheckout("start")
		if sh.run("git", { "rev-parse", "--verify", "--quiet", `refs/heads/{branch}` }).ok then
			fail(`branch {branch} already exists: switch to it and run start there`)
		end
	end
	if publishing() then
		refuseStale() -- before the claim file is written
		local ids = { raft.id }
		for _, m in members do
			table.insert(ids, m.id)
		end
		fs.writeDir(".cache")
		local mine = if fs.isFile(claimFile(raft.id)) then sh.trim(fs.readFile(claimFile(raft.id))) else ""
		local claim = stamp("active")
		-- written before the push: a start that dies right after it can then be resumed by this terminal
		sh.writeReplacing(claimFile(raft.id), claim)
		local raftPath: string? = nil
		local r = publishFresh(function(paths, read)
			local changes: { publish.Change } = {}
			for _, id in ids do
				local path = docPath(paths, id)
				if id == raft.id then
					raftPath = path
				end
				local text = path and read(path)
				if not path or not text then
					return `{id} is not on origin/main`
				end
				local raw = frontOf(text).status
				if mine ~= "" and raw == mine then
					continue -- claimed earlier by this terminal: a retry of a failed start
				end
				local st = statusLib.effective(frontOf(text), stateOfPath(path))
				if not statusLib.canMove(st, "active") then
					return `{id} is {st} on origin/main, not prepared`
				end
				table.insert(changes, { path = path, content = withFront(text, "status", claim) })
			end
			return changes
		end, `tracker: start {raft.id}`)
		-- a push that reached origin but reported failure (the connection dropped after it): origin already
		-- carries this claim, so it is ours and start goes on
		if not r.ok and raftPath then
			sh.run("git", { "fetch", "-q", "origin", "main" })
			local now = sh.run("git", { "show", `origin/main:{raftPath}` })
			if now.ok and frontOf(now.stdout).status == claim then
				r = { ok = true, sha = sh.trim(sh.run("git", { "rev-parse", "origin/main" }).stdout) }
			end
		end
		if not r.ok or not r.sha then
			-- refused, or nothing to claim (a resumed claim): keep or restore the file accordingly
			if mine ~= "" then
				sh.writeReplacing(claimFile(raft.id), mine)
			elseif fs.isFile(claimFile(raft.id)) then
				fs.removeFile(claimFile(raft.id))
			end
		end
		if not r.ok then
			fail(r.reason or "publish failed")
		end
		mergeOrigin()
		raft = store.get(raft.id)
		members = store.members(raft.id)
	end
	if not onBranch then
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
	sh.writeReplacing(FOCUS_FILE, issue.id)
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
-- answers every finding id with "fixed", "refuted" or a valid "deferred <id>: <why>".
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
	local invalid = {}
	for id, rest in string.gmatch(review, "\n###%s+(F%d+)([^\n]*)") do
		local line = string.match(refute, `\n%-%s+{id}:%s*([^\n]*)`)
		if line and (string.find(line, "^fixed") or string.find(line, "^refuted")) then
			continue
		end
		if not line or not (line == "deferred" or string.find(line, "^deferred%s")) then
			table.insert(missing, id)
			continue
		end
		local target = string.match(line, "^deferred%s+([fdc]%d%d%d%d):%s*%S")
		local severity = string.match(rest or "", "^%s*%[(%a+)%]")
		local rating = if severity then string.lower(severity) else "unrated"
		if not target then
			table.insert(invalid, `{id}: deferred needs "<issue id>: <why>"`)
		elseif rating ~= "medium" and rating ~= "low" then
			table.insert(invalid, `{id} is {rating}: only a medium or low finding can be deferred`)
		else
			local item = store.find(target)
			if not item or item.kind ~= "issue" or item.state ~= "backlog" then
				table.insert(invalid, `{id}: {target} is not a backlog issue`)
			end
		end
	end
	if #missing > 0 then
		return `review-{num}.md findings not answered in refute-{num}.md: {table.concat(missing, ", ")}`
	end
	if #invalid > 0 then
		return `refute-{num}.md: {table.concat(invalid, "; ")}`
	end
	return nil
end

function cmd.done(pos: { string })
	refuseListMode()
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
		fail("usage: board [--out PATH] [-O]  (an --out path can't start with -; write ./-x for such a file)")
	end
	if opts["--open"] and opts["-O"] then
		fail("board: --open and -O contradict each other (the page opens by default; -O only writes it)")
	end
	local out = given or ".cache/board.html"
	local dir = string.match(out, "^(.*)/[^/]*$")
	if dir and dir ~= "" then
		fs.writeDir(dir)
	end
	sh.writeReplacing(out, board.build())
	-- tracker.sh runs from the repo root, so say where a relative path really is
	if string.sub(out, 1, 1) ~= "/" then
		out = process.cwd .. out
	end
	print(out)
	if not opts["-O"] then
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
-- Every command that can change a repository checks first that git's root is the checkout the tracker
-- lives in, whatever PICKMAN_PUBLISH says. Only commands that read the tracker run in `.git`-less
-- sandboxes on purpose (specs do), so they alone are exempt.
local READ_ONLY: { [string]: boolean } = {
	list = true,
	audit = true,
	find = true,
	members = true,
	metrics = true,
	board = true,
	workstreams = true,
	["promote-check"] = true,
	stamp = true,
}
if not READ_ONLY[name :: string] then
	guardRepoRoot()
end
local rest = table.move(args, 2, #args, 1, {})
local pos, opts = flags(rest)
local ok, err = pcall(handler, pos, opts)
if not ok then
	fail(`tracker {name}: {err}`)
end
