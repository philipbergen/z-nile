--!strict
-- Tracker CLI. Run through ./zn at the repository root (c0114). See z-nile/skills/zz-rules/SKILL.md.
local approval = require("./approval")
local audit = require("./audit")
local board = require("./board")
local boardview = require("./boardview")
local brokerLib = require("./broker")
local buffer = require("./buffer")
local claimsLib = require("./claims")
local compactLib = require("./compact")
local completion = require("./completion")
local contract = require("./contract")
local costrow = require("./costrow")
local dispatchLib = require("./dispatch")
local dispatcherLib = require("./dispatcher")
local fs = require("@lune/fs")
local gateLib = require("./gate")
local idea = require("./idea")
local idsLib = require("./ids")
local layergit = require("./layergit")
local ledger = require("./ledger")
local lessonsLib = require("./lessons")
local models = require("./models")
local modelstep = require("./modelstep")
local openlist = require("./openlist")
local pathsLib = require("./paths")
local process = require("@lune/process")
local projects = require("./projects")
local publish = require("./publish")
local raftcheck = require("./raftcheck")
local raftplan = require("./raftplan")
local reapLib = require("./reap")
local sessionread = require("./sessionread")
local sessions = require("./sessions")
local sh = require("../lib/sh")
local skillsLib = require("./skills")
local spend = require("./spend")
local stack = require("./stack")
local statusLib = require("./status")
local stdio = require("@lune/stdio")
local store = require("./store")
local trailLib = require("./trail")
local watchcmd = require("./watchcmd")

-- a space name as the union ids expects: the callers only ever hold "issue" or "raft"
local function asSpace(s: string): idsLib.Space
	return if s == "raft" then "raft" else "issue"
end

local USAGE = [[
usage: ./zn <command> ...
  new issue <f|d|c> <slug> [--raft R0010] [--desc "<line>"] [--project <name>]
                                                create an issue (emergent if the raft is active) in the project
                                                whose folder you are in, or --project (refused elsewhere)
  new raft <feature|defect|chore> <slug> <issue>... [--single] [--project <name>]
                                                make a raft of new issues (claimed with it) or prepared ones (z-raft)
  fold <R-id> <issue>...                        put prepared, raftless issues into a prepared backlog raft (z-raft)
  unfold <R-id> <issue>...                      take members out of a backlog raft, back to no raft (z-raft)
  recombine <keeper> <other> [<issue>...]       move the other backlog raft's members (all, or those named) into the
                                                keeper; retire the other when it ends up empty (z-raft)
  release <R-id> [--force]                      give back a rafting claim: what carries its stamp goes back to
                                                prepared (design ready) or new (z-raft)
  raft-plan [--apply]                           print z-raft's plan for every prepared, raftless issue (--apply runs it)
  status [<id>] [<to>]                          list statuses on origin/main, show one, or move one (new|preparing|prepared; ready claims active)
  sync [--fetch]                                bring origin/main into this checkout (--fetch: update origin/main only)
  land [-m <message>]                           in a capture worktree: merge origin/main, run the gate, push the capture to main
  stamp <state>                                 print a fresh status stamp (diagnostics)
  run [--time S] [--cpu S] -- <command>         run a command that stops at its limits, when it ends and when you do
                                                (the bounded runner, z-nile/lib/bounded.pl; started before this engine)
  reap [--dry-run] [--min-age S] [--root DIR]... [--under PID | --session-end] [--log FILE] [--quiet] [--auto]
                                                stop this user's leaked tool processes: orphans, commands past their
                                                ./zn run deadline, and (at a session end) the session's own
  find <id>                                     print the item's current directory (from where ./zn was run)
  list [backlog|active|done] [--project <name>] list items: of --project, of the project whose folder you are
                                                in, or of every project at the checkout's root
  members <R-id>                                print directories of every issue in the raft (from where ./zn was run)
  busy [<path>...]                              list what holds <path>s (default: every project root and promoted-spec
                                                folder): rafts active on origin/main, branches and worktrees that
                                                change them; exits 1 when anything does (read-only)
  check <id>                                    run an item's check.sh (a raft runs its own)
  renumber <old|item directory> [<new>]         step an id (conflict resolution), or one copy of a duplicated id;
                                                <new> defaults to the next free number (z-nile/next, by one)
  audit                                         check the whole tracker tree: duplicates, documents, the counter
  compact [--force]                             renumber every item from 0001 (a fresh worktree on origin/main)
  remap                                         bring a branch from before a compaction onto the new ids
  migrate                                       rename legacy-named documents to <ID>.md (adds slug: to the frontmatter)
  approve <issue-id> [--check]                 record the human's approval of the issue's contract, or say whether it still holds
  ready <R-id|issue-id>                         claim the raft, move it to active/ on origin/main, write <root>/rafts/active/<R>/prompt.md
  stop <R-id>                                   give back a readied or started raft: move it out of active/ on origin/main, remove its prompt
  stop <issue>                                  give back one active issue whose raft is retired, missing or empty
  start <R-id>                                  open the next layer: branch R0010/1/c0010, claim commit, draft PR on the layer below
  finish <issue-id>                             make that layer one commit ("<issue>: <title>") once its checks are green,
                                                and write that ticket's watch files from the layer's own diff
  restack <R-id>                                rebase each layer onto the one below; stop at the first conflict or red check
  stack <R-id>                                  print the layers, from git (read-only)
  trace <R-id> [--through <issue>] [--check]    print the final review's traceability table skeleton, or verify trace.md
  focus <issue-id>                              attribute following commits to this issue
  commit -m <msg> [--issue <id>]... [--phase build|code-review|deliver] [--model <id>]
                                                stage all, record spend, commit, push. --time and --tokens are ignored
  spend <id> --phase capture|prep|design-review|deliver [--begin] [--model <id>] [--note <text>]
                                                mark a stage; the tool writes the measured row. --time and --tokens are ignored
  record --id <id> --phase <phase> [--report <file>] [--wall <s>] [--cpu <s>] [--ai <s>] [--tokens <n>]
                                                write one measured row (the tool's own; not for typed numbers)
  dispatch <id> [--dry-run]                     run the chain on an item from its tracker state (ticket, design, raft,
                                                ready, run), stopping at a merge gate, questions.md or a failure
  dispatch new "<description>" [--project <name>] [--dry-run]
                                                capture a new issue (z-ticket) and run its chain
  dispatch <step> <id> [--mode design|code|raft] [--dry-run]
                                                run one step: a model step on .models.toml's CLIs, a script step itself
  dispatch stop|retry|status <id>               stop a running step (its process group), rerun the failed step, show it
  dispatch vet                                  the user's: take main as vetted after a tripwire stop (the watermark)
  done <R-id> [--through <issue>]               land the stack, or its layers up to <issue>: one --no-ff merge onto main, one binding commit (refuses an unfinished or incomplete layer)
  watch-bootstrap                               write every spec's watch file from the commit that added it (once)
  watch-kick                                    start watch-net after a landing and return at once (log: .cache/watch-net.log)
  watch-net                                     run every project's fast suite on current main and push a missed test's
                                                files onto main (also started by land and by watch-kick)
  worktree <R-id|name>                          create or reuse .worktree/<R-id|name>: a raft's is detached until a layer exists, then on that layer
  worktree-prune                                remove worktrees of rafts that are done on main
  workstreams <R-id>                            plan parallel workstreams (waves) for a raft
  promote-check <R-id|issue-id>                 dry-run: would promoted acceptance specs pass type check + meta?
  prompt <R-id> [--path]                        print a readied raft's prompt.md (--path: its path)
  capture <id>                                  print the item's document as captured (read-only)
  idea <id> [--text <rough>]                    write the idea as checkable outcomes, challenge it once, revise once
  metrics [<id>] [--include-active]            cost per issue and rework %; with an id, its approvals
  board [--out PATH] [-O]                       write the tracker as one HTML page (default .cache/board.html)
                                                and open it in the browser; -O only writes it
  lessons [--skill <s>]... [--when design|build] [--tag <t>]... [--full] [<word>...]
                                                list skill lessons; also --tags, --check, and --uncovered <id>...
  skills [--check]                              link .claude/skills/<name> to every skill folder (z-nile/skills,
                                                <project>/skills); --check writes nothing and exits 1 on a problem]]

local FOCUS_FILE = ".cache/tracker-focus"
local RETIRED = "retired" -- <root>/rafts/retired/<R-id>: rafts recombine retired (c0116)
-- the issue, raft and prompt templates: engine files, shared by every project (c0114)
local TEMPLATES = "z-nile/templates"

local function fail(msg: string): never
	stdio.ewrite(msg .. "\n")
	return process.exit(1)
end

local function title(slug: string): string
	local s = string.gsub(slug, "%-", " ")
	return (string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2))
end

-- The name of the project whose root is `root` (the raft template's {{PROJECT}}, c0120: its RC0 runs that project's
-- gate); the working tree's registry decides, and a root no project holds is named as it is.
local function projectNameOf(root: string): string
	local p = projects.projectOf(projects.load(), root)
	return if p then p.name else root
end

local function render(path: string, vars: { [string]: string }): string
	return raftcheck.render(fs.readFile(path), vars)
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
	local dest = store.dirFor(item.kind, state, item.id, item.root)
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
	-- the URL as configured, before any insteadOf rewrite (c0117: a spec's GitHub-named origin is a local path)
	local r = sh.run("git", { "config", "--get", "remote.origin.url" })
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
-- every change is made in a worktree (zz-rules skill, "Worktrees").
local function inMainCheckout(): boolean
	return sh.git({ "rev-parse", "--show-toplevel" }) == mainRoot()
end

local function refuseInMainCheckout(what: string)
	if hasOrigin() and inMainCheckout() then
		fail(`{what} must run inside a worktree: cd "$(./zn worktree <target>)"`)
	end
end

-- ./zn changes into the repository root before it starts Lune, so the working directory is the
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
-- Only one answer publishes: exit 0 with exactly `unguarded` on stdout. Every other outcome (fence.sh missing or
-- broken, pickman_guarded missing, a crash, any other output) counts as guarded and publishes nothing (c0114:
-- a guard's "no" is one explicit answer).
local guardedRun: boolean? = nil
local guardedSaying: string? = nil -- what to say, once, when a caller that publishes asks (not `reap --auto`, which asks quietly)
local function guarded(quiet: boolean?): boolean
	if guardedRun == nil then
		local ok, r = pcall(process.exec, "bash", {
			"-c",
			'[ -f z-nile/lib/fence.sh ] || { echo "z-nile/lib/fence.sh is missing" >&2; exit 3; }; '
				.. 'source z-nile/lib/fence.sh && pickman_guarded "$PWD"',
		})
		local answer = if ok then sh.trim(r.stdout) else ""
		guardedRun = not (ok and r.ok and answer == "unguarded")
		if ok and r.ok and answer == "guarded" then
			guardedSaying =
				`not publishing: {process.cwd} is protected by the repository guards (a check run)\n`
		elseif guardedRun then
			local why = if ok then sh.trim(r.stderr) else tostring(r)
			guardedSaying =
				`not publishing: cannot ask z-nile/lib/fence.sh whether a check runs in {process.cwd} (exit {if ok
					then r.code
					else "none"}{if why ~= "" then ": " .. why else ""})\n`
		end
	end
	if quiet ~= true and guardedSaying ~= nil then
		stdio.ewrite(guardedSaying)
		guardedSaying = nil
	end
	return guardedRun == true
end

-- Whether this process runs inside a guarded run (a spec, or a check.sh fenced through ac.sh), asked of the guards'
-- own script like `guarded` (c0117): only the exact answer `free` means no; inside one, ./zn dispatch starts no model
-- CLI but a fake one under the checkout's .cache.
local function checking(): boolean
	local ok, r = pcall(process.exec, "bash", {
		"-c",
		"[ -f z-nile/lib/fence.sh ] || exit 3; source z-nile/lib/fence.sh && pickman_checking",
	})
	return not (ok and r.ok and sh.trim(r.stdout) == "free")
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
		-- the item's own document, never a file of that name nested in another item's directory
		local pid, rel = publish.itemPath(p)
		if pid == id and rel == `{id}.md` then
			return p
		end
	end
	return nil
end

-- Brings what was just published into this worktree. A conflicting merge is aborted, so the tree is
-- left as it was and `./zn sync` can be run again after resolving by hand.
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

-- The active raft whose branch is the current branch. `main` carries every readied raft in active/, so "the only
-- active raft" no longer names this tree's raft.
local function currentRaft(): store.Item?
	local branch = sh.git({ "branch", "--show-current" })
	for _, r in store.all("raft") do
		if r.state == "active" and raftBranch(r) == branch then
			return r
		end
		local layer = stack.parse(branch)
		if r.state == "active" and layer and layer.raft == r.id then
			return r
		end
	end
	return nil
end

local function raftIsActiveHere(): boolean
	return currentRaft() ~= nil
end

local function claimFile(raftId: string): string
	return `.cache/tracker-claim-{raftId}`
end

-- c0116: remembers a rafting claim (`new raft`, `fold`, `recombine`) in this checkout, so a re-run resumes it and
-- `release` gives back only a claim it finds here.
local function rememberClaim(raftId: string, value: string)
	local dir = string.match(claimFile(raftId), "^(.*)/") :: string
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	sh.writeReplacing(claimFile(raftId), value)
end

-- c0116 (review 001 F2): where `recombine` keeps a retired raft's folder: beside the backlog, never a lifecycle folder.
local function retiredDir(root: string, raftId: string): string
	return `{root}/rafts/{RETIRED}/{raftId}`
end

-- The claim this checkout remembers for an item (a raft, or an issue z-design claimed here), or "".
local function rememberedClaim(raftId: string): string
	return if fs.isFile(claimFile(raftId)) then sh.trim(fs.readFile(claimFile(raftId))) else ""
end

local function idsOf(paths: { string }, kind: string): { string }
	local out: { string } = {}
	for _, p in paths do
		local id, rel = publish.itemPath(p)
		if
			id
			and rel == `{id}.md`
			and (if kind == "raft" then store.isRaftId(id) else store.isIssueId(id))
		then
			table.insert(out, id)
		end
	end
	return out
end

-- origin/main's project registry as it is (no fetch), or nil and why: what the guards and every origin read trust
-- (c0114), never the working tree's. Nil and why when origin/main can't be read, has no registry (before c0114 lands:
-- the main checkout's older engine works there until then) or has one that does not parse.
local function originRegistry(): (projects.Registry?, string?)
	return projects.at("origin/main")
end

local function originRoots(): { string }?
	local reg = originRegistry()
	return if reg then projects.roots(reg) else nil
end

-- Every file path under origin/main's project roots as it is (no fetch), and whether origin/main and its registry could
-- be read. The one reader of origin/main's ids: `new` (originIds) and `renumber` (originMainIds) differ only in fetching
-- and failure.
local function originTree(): (boolean, { string })
	local roots = originRoots()
	if not roots then
		return false, {}
	end
	local args = { "ls-tree", "-r", "--name-only", "--full-tree", "origin/main", "--" }
	for _, r in roots do
		table.insert(args, r .. "/")
	end
	local r = sh.run("git", args)
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
	local raft = currentRaft()
	if not raft then
		fail(
			`not on an active raft's branch ({sh.git({ "branch", "--show-current" })}): run it in the raft's worktree (./zn worktree <R-id>)`
		)
	end
	return raft :: store.Item
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
			"this tree predates the compaction on origin/main: a branch that changed tracker/ runs ./zn remap; any other merges origin/main"
		)
	end
end

-- The item directory a tracker path lives in (`<root>/(issues|rafts)/[active/|done/]<id>`), or nil when `path`
-- is not a file of an item. `roots` includes retired roots, so a root that just left the registry is still swept.
local function itemDirOf(path: string, roots: { string }): string?
	local top, rest = projects.rootOf(path, roots)
	if not top or not rest then
		return nil
	end
	local kind, tail = string.match(rest, "^(issues)/(.*)$")
	if not kind then
		kind, tail = string.match(rest, "^(rafts)/(.*)$")
	end
	if not kind or not tail then
		return nil
	end
	local a, b = string.match(tail, "^([^/]+)/([^/]+)")
	if not a or not b then
		return nil
	end
	local id, state = a, ""
	if a == "active" or a == "done" then
		id, state = b, `{a}/`
	end
	local isId = if kind == "rafts" then store.isRaftId(id) else store.isIssueId(id)
	if not isId then
		return nil
	end
	return `{top}/{kind}/{state}{id}`
end

-- A pull that moves an item directory away leaves its ignored and untracked files behind (a raft's prompt.md, a
-- Finder .DS_Store): the main checkout would then hold one id in two directories. Only the item directories the
-- commits from `old` to `new` deleted a file from are looked at (`git diff-tree`), never one `ls-tree` per item.
-- A directory with nothing tracked at HEAD loses its ignored files and is removed; untracked files that are not
-- ignored are kept, and named in a warning. Run after every pull or fast-forward in the main checkout.
local function sweepStale(root: string, old: string, new: string)
	if old == new then
		return
	end
	-- every root the pulled registry names, retired ones too: a root move leaves the old folders behind (c0114)
	local ok, reg = pcall(projects.load, root, true)
	if not ok then
		fail(`sweep: {reg}`) -- never guess which folders hold items (c0114)
	end
	local diff = sh.run("git", {
		"-C",
		root,
		"diff-tree",
		"-r",
		"--name-status",
		"--no-renames",
		old,
		new,
	})
	if not diff.ok then
		fail(`sweep: {sh.trim(diff.stderr)}`)
	end
	local roots: { string } = projects.allRoots(reg :: projects.Registry)
	local seen: { [string]: boolean } = {}
	for line in string.gmatch(diff.stdout, "[^\n]+") do
		local kind, path = string.match(line, "^(%u+)\t(.+)$")
		-- a move is a deletion and an addition (--no-renames); only the path that left can leave a stale folder
		if kind == "D" and path then
			local dir = itemDirOf(path, roots)
			if dir then
				seen[dir] = true
			end
		end
	end
	for dir in seen do
		local base = `{root}/{dir}`
		if fs.isDir(base) then
			-- a directory with anything tracked at HEAD is a live item (a readied raft, or an item mid-edit)
			local tracked = sh.run("git", { "-C", root, "ls-tree", "-r", "--name-only", "HEAD", "--", dir })
			if tracked.ok and sh.trim(tracked.stdout) == "" then
				-- only ignored files (a prompt.md, Finder litter): untracked work is never deleted, only named
				sh.run("git", { "-C", root, "clean", "-ffdXq", "--", dir })
				local left = if fs.isDir(base) then fs.readDir(base) else {}
				if fs.isDir(base) and #left == 0 then
					fs.removeDir(base)
				elseif #left > 0 then
					local name = string.match(dir, "([^/]+)$") or dir
					stdio.ewrite(
						`warning: {dir} is no longer tracked but holds untracked files ({table.concat(
							left,
							", "
						)}); move them and remove it, or ./zn will see {name} twice\n`
					)
				end
			end
		end
	end
end

-- Rebuilds `root`'s .cache/board.html, never opening a browser; a failure is one warning.
-- In-process, not a second ./zn (c0070's fallback: a second Lune process per publish cost c0053's commands spec
-- about a third more). The page is built from every project root of root's registry with this tooling's template, as
-- `board -O` writes it.
local function buildBoard(root: string)
	local ok, err = pcall(function()
		local page = board.build(nil, root)
		fs.writeDir(`{root}/.cache`)
		sh.writeReplacing(`{root}/.cache/board.html`, page)
	end)
	if not ok then
		stdio.ewrite(`warning: board: could not rebuild ({string.match(tostring(err), "^[^\n]*") or ""})\n`)
	end
end

-- Every publish.commit call site goes through this. A publish pushes and does nothing else: it does not fast-forward
-- the main checkout, sweep it, or rebuild the board. `./zn sync` fast-forwards and sweeps; `./zn board` builds the page.
local function published(r: publish.Result): publish.Result
	return r
end

-- The three words of a fresh stamp: the phrase that makes every write of tracker/next differ (c0870).
-- A claim stamp (`active-…`) that no item on origin/main carries, done/ included: `stop` gives back exactly the
-- issues that carry the raft's stamp, so two claims must never share one. One `git grep` over the fetched tree.
local function freshStamp(state: string): string
	local roots = originRoots()
		or fail(`cannot check a claim stamp: origin/main has no readable {projects.FILE}`)
	local value = statusLib.fresh(function()
		return stamp(state)
	end, function(v: string): boolean
		local taken, err = claimsLib.taken(".", v, nil, roots)
		if taken == nil then
			fail(`cannot check a claim stamp against origin/main: {err}`)
		end
		return taken == true
	end)
	return value or fail("could not draw a claim stamp that origin/main does not already carry")
end

local function claimStamp(): string
	return freshStamp("active")
end

local function phrase(): string
	return (string.match(stamp("new"), "^%a+%-(.+)$")) :: string
end

-- Moves whole item directories (every file of each id) to state `to` as one tracker-only commit on origin/main: the
-- document gets `status`, check.sh goes through paths.rewrite for every id moved here, every other file is unchanged.
-- `verify` may refuse an id from its effective status on origin/main. A string result is a refusal, as publish.commit's.
local function moveOnOrigin(
	ids: { string },
	to: store.State,
	status: string,
	message: string,
	verify: ((id: string, st: string) -> string?)?,
	whole: ((paths: { string }, read: (string) -> string?) -> string?)?
): publish.Result
	refuseStale()
	return published(publish.commit(".", function(paths, read)
		-- c0116 (review 004 F1): a check of the tree being published, in the same build
		if whole then
			local refusal = whole(paths, read)
			if refusal then
				return refusal
			end
		end
		local dirs: { [string]: string } = {}
		local sources: { [string]: string } = {}
		for _, id in ids do
			local doc = docPath(paths, id)
			if not doc then
				return `{id} is not on origin/main`
			end
			sources[id] = string.sub(doc, 1, #doc - #id - 4) -- ".../<ID>/<ID>.md" -> ".../<ID>"
			-- a published move stays under the item's own root (c0114)
			local _, _, root = publish.itemPath(doc)
			dirs[id] = store.dirFor(if store.isRaftId(id) then "raft" else "issue", to, id, root :: string)
			if verify then
				local text = read(doc) :: string
				local refusal = verify(id, statusLib.effective(frontOf(text), stateOfPath(doc)))
				if refusal then
					return refusal
				end
			end
		end
		local changes: { publish.Change } = {}
		for _, p in paths do
			local fid, rel = publish.itemPath(p)
			if not fid or not rel or sources[fid] ~= string.sub(p, 1, #p - #rel - 1) then
				continue
			end
			local text = read(p)
			if not text then
				return `cannot read {p} on origin/main`
			end
			if rel == `{fid}.md` then
				text = withFront(text, "status", status)
			elseif rel == "check.sh" then
				text = pathsLib.rewrite(text, dirs)
			end
			table.insert(changes, { path = `{dirs[fid]}/{rel}`, from = p, content = text })
		end
		return changes
	end, message))
end

-- A status-only publish: every id's document on origin/main gets `status` (no move). `verify(id, effectiveStatus)`
-- refuses an id, inside the build, with a reason.
local function restampOnOrigin(
	ids: { string },
	status: string,
	message: string,
	verify: (id: string, st: string) -> string?
): publish.Result
	refuseStale()
	return published(publish.commit(".", function(paths, read)
		local changes: { publish.Change } = {}
		for _, id in ids do
			local doc = docPath(paths, id)
			local text = doc and read(doc)
			if not doc or not text then
				return `{id} is not on origin/main`
			end
			local refusal = verify(id, statusLib.effective(frontOf(text), stateOfPath(doc)))
			if refusal then
				return refusal
			end
			table.insert(changes, { path = doc, content = withFront(text, "status", status) })
		end
		return changes
	end, message))
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
	-- the local copy of the live counter: z-nile/next, or tracker/next in a tree from before origin moved it (c0114)
	local file = if fs.isFile(idsLib.FILE) then idsLib.FILE else idsLib.OLD_FILE
	return if fs.isFile(file) then idsLib.parse(fs.readFile(file)) else nil
end

-- The next number of `space` from origin's live counter `counter` (as `read` returns it; publish passes it: z-nile/next,
-- or tracker/next while origin has no registry), and the change that raises it. Both nil when origin has no counter:
-- the old numbering applies. The third result is an error.
local function reserve(
	space: string,
	used: { string },
	read: (string) -> string?,
	counter: string
): (number?, publish.Change?, string?)
	local text = read(counter)
	if not text then
		return nil, nil, nil
	end
	local c = idsLib.parse(text)
	if not c then
		return nil, nil, `{counter} on origin/main does not parse`
	end
	local n = idsLib.nextFree(asSpace(space), c, used)
	if n > 9999 then
		return nil, nil, "no number above 9999 is free"
	end
	local raised: idsLib.Counters = { issue = c.issue, raft = c.raft }
	if space == "raft" then
		raised.raft = n + 1
	else
		raised.issue = n + 1
	end
	return n, { path = counter, content = idsLib.format(raised, phrase()) }, nil
end

-- Reserves the next number of `space` on origin/main by pushing only the raised counter; nil when origin/main has
-- no tracker/next. `extra`: ids that count besides origin's (the local tree's).
local function reserveOnOrigin(space: string, extra: { string }): number?
	local chosen: number? = nil
	refuseStale()
	local r = published(publish.commit(".", function(paths, read, _roots, counter)
		local used = idsOf(paths, space)
		for _, id in extra do
			table.insert(used, id)
		end
		local n, change, err = reserve(space, used, read, counter)
		if err then
			return err
		end
		chosen = n
		return if change then { change :: publish.Change } else {}
	end, function()
		return `tracker: reserve {space} number {chosen or "?"}`
	end))
	if not r.ok then
		fail(`could not reserve a number on origin/main: {r.reason}`)
	end
	return chosen
end

-- Offline: the local counter when there is one (never written), else the old rule.
local function localNumber(space: string, legacy: () -> number): number
	local c = localCounters()
	if c then
		return idsLib.nextFree(asSpace(space), c, localIds(space))
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
			or a == "--path"
			or a == "--include-active"
			or a == "--open"
			or a == "--fetch"
			or a == "--force"
			or a == "-O"
			or a == "--full"
			or a == "--check"
			or a == "--tags"
			or a == "--uncovered"
			or a == "--apply"
			or a == "--dry-run"
			or a == "--quiet"
			or a == "--auto"
			or a == "--session-end"
			or a == "--begin"
			or a == "--sessions"
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

-- The directory ./zn was run from, relative to the checkout ("" for its root). zn passes it as ZN_CWD with the
-- checkout as ZN_TOP; it counts only when the engine runs in that checkout, so a value inherited by a process that
-- runs another checkout's engine (a spec's fixture) means its root.
local function hereDir(): string
	local top, rel = process.env.ZN_TOP, process.env.ZN_CWD
	if not top or not rel or top == "" then
		return ""
	end
	local cwd = sh.run("pwd", { "-P" })
	if not cwd.ok or sh.trim(cwd.stdout) ~= top then
		return ""
	end
	return rel
end

-- The project a command works in (c0114, decided with the user: "The directory gives the project unless it's given,
-- so at root without project=fail, deduce from PWD with --project override"): the one `--project <name>` names,
-- else the one whose folder holds the directory ./zn was run from. Anywhere else (the checkout's root, or a folder no
-- project holds) the command refuses and names --project. Pickman has no folder before c0120, so its work always
-- passes --project pickman until then. Returns the project's root.
local function projectRoot(opts: { [string]: { string } }, what: string): string
	local reg = projects.load()
	local names: { string } = {}
	for _, q in reg.projects do
		table.insert(names, q.name)
	end
	local list = table.concat(names, ", ")
	local name = opts["--project"] and opts["--project"][1]
	if name then
		local p = projects.named(reg, name)
		if not p then
			fail(`--project {name}: not a project in {projects.FILE} ({list})`)
		end
		return (p :: projects.Project).root
	end
	local here = hereDir()
	local p = projects.inDir(reg, here)
	if p then
		return p.root
	end
	local where = if here == "" then "the checkout's root" else here
	return fail(
		`{what}: no project holds {where}: run it in a project's folder or pass --project <name> ({list})`
	)
end

-- c0114's execution window: origin/main can be read but has no registry (c0114 has not landed). The branch's engine
-- then makes no item, offline (PICKMAN_PUBLISH=0) included: it would number from the local tracker/next, the number
-- main's next capture takes. Captures come from the main checkout, whose engine predates the registry. Called after
-- refuseStale, which fetches when publishing; offline, origin/main is as last fetched, and the message says so.
local function refuseInWindow(what: string)
	if not hasOrigin() or not sh.run("git", { "rev-parse", "--verify", "-q", "origin/main" }).ok then
		return
	end
	local _, why = projects.at("origin/main")
	if why and string.find(why, `has no {projects.FILE}`, 1, true) then
		if not publishing() then
			fail(
				`{what}: origin/main as last fetched has no {projects.FILE}: fetch (./zn sync --fetch) if c0114 has landed; otherwise capture from the main checkout until it does, never offline here`
			)
		end
		fail(
			`{what}: origin/main has no {projects.FILE} (c0114 has not landed): capture from the main checkout until it does, never offline here`
		)
	end
end

-- c0116 (review 002 F1, 003 F1): an item folder's files as path (relative to the folder) -> text, read from the
-- working tree, from origin/main, or from a publish build's tree; raftplan.recordHash picks the design files.
-- The working tree as git sees it (review 004 F1): tracked files and untracked ones that aren't ignored, so a Finder
-- .DS_Store or an editor's swap file never changes a record. Bytes from disk (the index's paths after a rewrite's git mv).
-- `tracked`: the index only (review 005 F1). A reader takes the view its own commit will carry: the carried move's raft
-- reviews may not be committed yet (tracked and untracked, ignored left out); a rewrite (compact, remap, renumber)
-- commits only tracked files, so `keepRecords` hashes the index, and a work-in-progress file never changes its hashes.
local function gitFolderFiles(dir: string, tracked: boolean?): { [string]: string }
	local out: { [string]: string } = {}
	if not fs.isDir(dir) then
		return out
	end
	local args = if tracked
		then { "ls-files", "-c", "-z", "--", "." }
		else { "ls-files", "-co", "--exclude-standard", "-z", "--", "." }
	local listed = process.exec("git", args, { cwd = dir })
	if not listed.ok then
		fail(`cannot list {dir} through git: {listed.stderr}`)
	end
	for _, rel in string.split(listed.stdout, "\0") do
		if rel ~= "" and fs.isFile(`{dir}/{rel}`) then
			out[rel] = fs.readFile(`{dir}/{rel}`)
		end
	end
	return out
end

local function treeFolderFiles(
	paths: { string },
	read: (string) -> string?,
	dir: string
): { [string]: string }
	local out: { [string]: string } = {}
	local prefix = dir .. "/"
	for _, p in paths do
		if string.sub(p, 1, #prefix) == prefix then
			local text = read(p)
			if text then
				out[string.sub(p, #prefix + 1)] = text
			end
		end
	end
	return out
end

local function originFolderFiles(dir: string): { [string]: string }
	local out: { [string]: string } = {}
	local listed = sh.run("git", { "ls-tree", "-r", "--name-only", "origin/main", "--", dir .. "/" })
	if not listed.ok then
		fail(`cannot list {dir} on origin/main to record what was grouped`)
	end
	for p in string.gmatch(listed.stdout, "[^\n]+") do
		local shown = sh.run("git", { "show", `origin/main:{p}` })
		if shown.ok then
			out[string.sub(p, #dir + 2)] = shown.stdout
		end
	end
	return out
end

-- Adds to the raft document's `grouped:` record each issue's record hash as it is on origin/main now, or (`forget`)
-- drops their entries. The record rides in the rafting PR with the members' raft: lines.
local function recordGrouped(raftDoc: string, ids: { string }, forget: boolean?)
	local map, problem = raftplan.parseGrouped(store.readFront(raftDoc).grouped)
	if problem then
		fail(`{raftDoc}: {problem}`)
	end
	for _, id in ids do
		if forget then
			map[id] = nil
		else
			map[id] = raftplan.recordHash(id, originFolderFiles(store.get(id).dir))
		end
	end
	store.setFront(raftDoc, "grouped", raftplan.renderGrouped(map))
end

-- The record's entries whose member now hashes differently (`now`: id -> hash, nil when the member is absent), as
-- "<id> (<recorded> → <now>)" lines.
local function regrouped(map: { [string]: string }, now: { [string]: string? }): { string }
	local out: { string } = {}
	for id, recorded in map do
		local h = now[id]
		if h and h ~= recorded then
			table.insert(out, `{id} ({recorded} → {h})`)
		end
	end
	table.sort(out)
	return out
end

-- c0116 (review 003 F4): runs a mechanical rewrite of ids (compact, remap, renumber) under `root`, then re-records
-- every `grouped:` entry whose member matched its record before the rewrite, in the raft's document and in the
-- `Grouped:` lines its coherence reviews quote. An entry that did not match before still does not.
local function keepRecords(root: string, idMap: { [string]: string }, rewrite: () -> ())
	local function byId(): { [string]: string }
		local out: { [string]: string } = {}
		for _, f in audit.scan(root) do
			out[f.id] = `{root}/{f.path}`
		end
		return out
	end
	local before = byId()
	local kept: { { raft: string, id: string, hash: string } } = {}
	for rid, dir in before do
		local doc = `{dir}/{rid}.md`
		if store.isRaftId(rid) and fs.isFile(doc) then
			local map = raftplan.parseGrouped(store.readFront(doc).grouped)
			for mid, h in map do
				local mdir = before[mid]
				if mdir and raftplan.recordHash(mid, gitFolderFiles(mdir, true)) == h then
					table.insert(kept, { raft = rid, id = mid, hash = h })
				end
			end
		end
	end
	rewrite()
	local after = byId()
	for _, k in kept do
		local rid, mid = idMap[k.raft] or k.raft, idMap[k.id] or k.id
		local rdir, mdir = after[rid], after[mid]
		if rdir and mdir then
			local fresh = raftplan.recordHash(mid, gitFolderFiles(mdir, true))
			local old, new = `{mid}@{k.hash}`, `{mid}@{fresh}`
			for _, name in fs.readDir(rdir) do
				if name == `{rid}.md` or string.match(name, "^design%-review%-%d+%.md$") then
					local p = `{rdir}/{name}`
					local text = fs.readFile(p)
					local parts: { string } = {}
					local at = 1
					while true do
						local a, b = string.find(text, old, at, true)
						if not a then
							break
						end
						table.insert(parts, string.sub(text, at, a - 1) .. new)
						at = (b :: number) + 1
					end
					if #parts > 0 then
						table.insert(parts, string.sub(text, at))
						fs.writeFile(p, table.concat(parts))
					end
				end
			end
		end
	end
end

-- c0116 (review 003 F2): whether a coherence review in the raft's folder quotes a `Grouped:` record that covers the
-- current one: every current entry with the same hash (an unfold only drops entries, so it needs no new review).
local function reviewCovers(files: { [string]: string }, map: { [string]: string }): boolean
	if next(map) == nil then
		return true
	end
	for name, text in files do
		if string.match(name, "^design%-review%-%d+%.md$") then
			for quoted in string.gmatch("\n" .. text, "\nGrouped: (%[[^\n]*%])") do
				local q = raftplan.parseGrouped(quoted)
				local all = true
				for id, h in map do
					if q[id] ~= h then
						all = false
					end
				end
				if all then
					return true
				end
			end
		end
	end
	return false
end

local cmd = {}

function cmd.new(pos: { string }, opts: { [string]: { string } })
	refuseInMainCheckout("new")
	local what = pos[1]
	if what == "issue" then
		local prefix, slug = pos[2], pos[3]
		if not (prefix and store.TYPES[prefix] and slug) then
			fail("usage: new issue <f|d|c> <slug> [--raft R0010] [--project <name>]")
		end
		if not string.match(slug, "^[a-z][a-z0-9%-]*$") then
			fail(`invalid slug: {slug} (lowercase words joined by hyphens)`)
		end
		refuseStale()
		refuseInWindow("new issue")
		local raftId = opts["--raft"] and opts["--raft"][1]
		-- an emergent issue's raft gives its project; any other issue's comes from --project or the directory
		local root = if raftId and not opts["--project"] then "" else projectRoot(opts, "new issue")
		if raftId then
			local raft = store.get(raftId) -- an unknown raft fails here
			-- an emergent issue lives beside its raft, in the raft's project
			if opts["--project"] and root ~= raft.root then
				fail(`--raft {raftId} is in {raft.root}: an emergent issue is made in its raft's project`)
			end
			root = raft.root
			local current = currentRaft()
			if not current or current.id ~= raftId then
				fail(
					`--raft {raftId}: an emergent issue is made on the raft's own branch, in its worktree (./zn worktree {raftId})`
				)
			end
		end
		local state: store.State = if raftId then "active" else "backlog"
		if state == "backlog" and publishing() then
			local chosen = ""
			refuseStale()
			local r = published(publish.commit(".", function(paths, read, roots, counter)
				if not table.find(roots, root) then
					return `{root} is not a project root in origin/main's {projects.FILE}`
				end
				local ids = idsOf(paths, "issue")
				for _, id in localIds("issue") do
					table.insert(ids, id)
				end
				local n, raise, err = reserve("issue", ids, read, counter)
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
				local doc = withDesc(render(`{TEMPLATES}/issue/doc.md`, vars), opts)
				local changes: { publish.Change } = {
					{
						path = `{root}/issues/{chosen}/{chosen}.md`,
						content = withFront(withFront(doc, "idea", "unchallenged"), "status", stamp("new")),
					},
					{
						path = `{root}/issues/{chosen}/check.sh`,
						content = render(`{TEMPLATES}/issue/check.sh`, vars),
						mode = "100755",
					},
				}
				if raise then
					table.insert(changes, raise)
				end
				return changes
			end, function()
				return `tracker: new {chosen} {slug}`
			end))
			if not r.ok then
				fail(
					if string.find(r.reason or "", `has no {projects.FILE}`, 1, true)
						then `new: could not publish to origin/main: {r.reason}`
						else `new: could not publish to origin/main: {r.reason}\n(PICKMAN_PUBLISH=0 creates it locally instead)`
				)
			end
			-- inside a raft's worktree the stub reaches the branch with the final merge of origin/main
			if not raftIsActiveHere() then
				mergeOrigin()
			end
			print(`{root}/issues/{chosen}/{chosen}.md`)
			return
		end
		-- an emergent issue reserves its number on origin/main (only the counter is pushed); offline, the local counter
		local reserved = if publishing() then reserveOnOrigin("issue", localIds("issue")) else nil
		local n = reserved
			or localNumber("issue", function()
				return store.nextNumber("issue", originIds("issue"))
			end)
		local id = store.formatId(prefix, n)
		local dir = store.dirFor("issue", state, id, root)
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
		fs.writeFile(
			`{dir}/{id}.md`,
			withFront(withDesc(render(`{TEMPLATES}/issue/doc.md`, vars), opts), "idea", "unchallenged")
		)
		fs.writeFile(`{dir}/check.sh`, render(`{TEMPLATES}/issue/check.sh`, vars))
		sh.must("chmod", { "+x", `{dir}/check.sh` })
		print(`{dir}/{id}.md`)
	elseif what == "raft" then
		local rtype, slug = pos[2], pos[3]
		if not (rtype and store.PREFIX[rtype] and slug) then
			fail("usage: new raft <feature|defect|chore> <slug> <issue>... [--single] [--project <name>]")
		end
		-- the raft's project comes from --project or the directory, and holds every member (c0114)
		local wanted = projectRoot(opts, "new raft")
		refuseStale()
		refuseInWindow("new raft")
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
			local root = ""
			-- c0116: one fresh value, so `release` and the same-claim test never mistake another raft's claim for it
			local claim = freshStamp("preparing")
			refuseStale()
			local r = published(publish.commit(".", function(paths, read, roots, counter)
				-- a raft lives in its members' project, and never spans two (c0114)
				root = ""
				for _, id in ids do
					local path = docPath(paths, id)
					local at: string? = nil
					if path then
						at = select(3, publish.itemPath(path))
					end
					if at then
						if root ~= "" and at ~= root then
							return `a raft holds issues of one project: {id} is in {at}, not {root}`
						end
						if at ~= wanted then
							return `the raft is made in {wanted}: {id} is in {at}`
						end
						root = at
					end
				end
				if root ~= "" and not table.find(roots, root) then
					return `{root} is not a project root in origin/main's {projects.FILE}`
				end
				local known = idsOf(paths, "raft")
				for _, raft in store.all("raft") do
					table.insert(known, raft.id)
				end
				local n, raise, err = reserve("raft", known, read, counter)
				if err then
					return err
				end
				chosen = store.formatId("R", n or statusLib.nextNumber(known))
				local changes: { publish.Change } = {}
				-- c0116: the members are all `new` (the old prep: each is claimed with the raft's stamp) or all
				-- `prepared` with a ready design (z-raft: the stamp claims the raft only, and a prepared member is never
				-- restamped). Membership itself is each issue's `raft:` line, written in this worktree and carried by the
				-- rafting PR: two PRs that raft one issue edit that one line, so the second cannot merge cleanly.
				local kinds: { [string]: boolean } = {}
				local solo: string? = nil
				for _, id in ids do
					local path = docPath(paths, id)
					local text = path and read(path)
					if not path or not text then
						return `{id} is not on origin/main`
					end
					local front = frontOf(text)
					local owner = front.raft
					if owner and owner ~= "" then
						return `{id} already belongs to {owner}`
					end
					local st = statusLib.effective(front, stateOfPath(path))
					if stateOfPath(path) ~= "backlog" then
						return `{id} is {st} on origin/main: a raft takes backlog issues only`
					end
					if st == "prepared" and front.design ~= "ready" then
						return `{id} is prepared on origin/main without design: ready`
					end
					if st ~= "new" and st ~= "prepared" then
						return `{id} is {st} on origin/main, not new or prepared`
					end
					kinds[st] = true
					if front.solo == "true" then
						solo = id
					end
					if store.TYPES[string.sub(id, 1, 1)] ~= rtype then
						return `{id} is a {store.TYPES[string.sub(id, 1, 1)]}; a {rtype} raft cannot contain it`
					end
					-- only `status:` is written: `raft:` sits beside `depends_on:`, which a capture PR may be editing
					if st == "new" then
						table.insert(changes, { path = path, content = withFront(text, "status", claim) })
					end
				end
				if kinds.new and kinds.prepared then
					return "a raft is made of new issues (claimed with it) or of prepared ones (z-raft), not both"
				end
				if solo and #ids > 1 then
					return `{solo} is solo: true (a recorded user decision): it is rafted alone`
				end
				local vars = {
					ID = chosen,
					TYPE = rtype,
					TITLE = title(slug),
					SLUG = slug,
					SINGLE = if opts["--single"] then "true" else "false",
					ISSUES = table.concat(ids, ", "),
					DATE = today(),
					PROJECT = projectNameOf(root),
				}
				table.insert(changes, {
					path = `{root}/rafts/{chosen}/{chosen}.md`,
					content = withFront(render(`{TEMPLATES}/raft/doc.md`, vars), "status", claim),
				})
				table.insert(changes, {
					path = `{root}/rafts/{chosen}/check.sh`,
					content = render(`{TEMPLATES}/raft/check.sh`, vars),
					mode = "100755",
				})
				if raise then
					table.insert(changes, raise)
				end
				return changes
			end, function()
				return `tracker: new raft {chosen} {slug}`
			end))
			if not r.ok then
				fail(`new raft: {r.reason}`)
			end
			-- this checkout's claim: a re-run here resumes it, and `release` gives back only a claim it finds here
			rememberClaim(chosen, claim)
			mergeOrigin()
			-- membership is written locally and committed, so later merges of origin/main stay clean
			local grouped: { string } = {}
			for _, id in ids do
				local item = store.get(id)
				store.setFront(item.doc, "raft", chosen)
				sh.git({ "add", item.doc })
				if statusLib.effective(frontOf(fs.readFile(item.doc)), item.state) == "prepared" then
					table.insert(grouped, id)
				end
			end
			if #grouped > 0 then
				local raftDoc = store.get(chosen).doc
				recordGrouped(raftDoc, grouped)
				sh.git({ "add", raftDoc })
			end
			sh.git({ "commit", "--quiet", "-m", `tracker: {chosen} members` })
			print(`{root}/rafts/{chosen}/{chosen}.md`)
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
		local root = members[1].root
		for _, m in members do
			if m.root ~= root then
				fail(`a raft holds issues of one project: {m.id} is in {m.root}, not {root}`)
			end
		end
		if root ~= wanted then
			fail(`the raft is made in {wanted}: {members[1].id} is in {root}`)
		end
		local id = store.formatId(
			"R",
			localNumber("raft", function()
				return store.nextNumber("raft", originIds("raft"))
			end)
		)
		local dir = store.dirFor("raft", "backlog", id, root)
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
			PROJECT = projectNameOf(root),
		}
		fs.writeFile(`{dir}/{id}.md`, render(`{TEMPLATES}/raft/doc.md`, vars))
		fs.writeFile(`{dir}/check.sh`, render(`{TEMPLATES}/raft/check.sh`, vars))
		sh.must("chmod", { "+x", `{dir}/check.sh` })
		print(`{dir}/{id}.md`)
	else
		fail(USAGE)
	end
end

-- c0116: whether a document's `## <heading>` section holds any text beyond the template's comment.
local function sectionWritten(text: string, heading: string): boolean
	local body = string.match(text .. "\n## ", `\n## {heading}\n(.-)\n## `)
	if not body then
		return false
	end
	return string.match((string.gsub(body, "<!%-%-.-%-%->", "")), "%S") ~= nil
end

local function originPaths(): { string }
	sh.git({ "fetch", "--quiet", "origin", "main" })
	local ok, paths = originTree()
	if not ok then
		fail(`cannot read origin/main's project roots ({projects.FILE})`)
	end
	return paths
end

-- Publishes `to` for `id` (and, for a raft, its members) on origin/main and brings it into this checkout. Shared by
-- `status` and by `stop`'s give-back of a legacy-started raft.
-- The latest `<prefix>-NNN.md` in a folder (design-review or review), or 0 when there is none.
local function latestRound(dir: string, prefix: string): number
	local best = 0
	if not fs.isDir(dir) then
		return 0
	end
	for _, name in fs.readDir(dir) do
		local pattern = "^" .. prefix .. "%-(%d+)%.md$"
		local found = string.match(name, pattern)
		local n = if typeof(found) == "string" then tonumber(found) else nil
		if n and n > best then
			best = n
		end
	end
	return best
end

-- What the one design review still leaves for the human, or nil when there is no review or the list is ruled.
local function designOpen(item: store.Item): string?
	local n = latestRound(item.dir, "design-review")
	if n == 0 then
		return nil
	end
	local num = string.format("%03d", n)
	local review = fs.readFile(`{item.dir}/design-review-{num}.md`)
	local refutePath = `{item.dir}/design-refute-{num}.md`
	local refute = if fs.isFile(refutePath) then fs.readFile(refutePath) else ""
	return openlist.problem(review, refute, fs.readFile(item.doc))
end

local function setStatus(id: string, to: string)
	local moved: { { id: string, from: string } } = {}
	local carried = false
	refuseStale()
	local r = published(publish.commit(".", function(paths, read)
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
		local rafted = false -- c0116: a member that was prepared on origin (z-raft grouped it)
		local originHashes: { [string]: string? } = {} -- c0116 (review 002 F1, 003 F1): each member's record on origin
		local groupedHere: { string } = {} -- c0116 (review 003 F5): prepared members this rafting grouped
		for _, t in targets do
			local tp = docPath(paths, t)
			local tt = tp and read(tp)
			if not tp or not tt then
				return `{t} is not on origin/main`
			end
			local tf = frontOf(tt)
			if stateOfPath(tp) == "active" then
				local raftId = if store.isRaftId(id) then id else (tf.raft or "")
				return `{t} is readied (in active/): use ./zn stop {if raftId ~= "" then raftId else "<R-id>"}`
			end
			local cur = statusLib.effective(tf, stateOfPath(tp))
			if t ~= id and carried and store.isRaftId(id) then
				originHashes[t] =
					raftplan.recordHash(t, treeFolderFiles(paths, read, string.sub(tp, 1, #tp - #t - 4)))
			end
			-- c0116 (review 001 F1): an issue in a raft is redesigned through its raft, never claimed past it
			if t == id and not store.isRaftId(id) and to == "preparing" and (tf.raft or "") ~= "" then
				return `{id} is in {tf.raft} on origin/main: z-raft takes it out first (./zn unfold {tf.raft} {id}), then z-design claims it`
			end
			if t ~= id then
				-- c0116: an issue belongs to the raft its own `raft:` line names on origin/main. A member another raft
				-- holds there is refused, unless that raft carries this raft's own claim stamp (recombine's other raft).
				local owner = tf.raft or ""
				if owner ~= "" and owner ~= id then
					local op = docPath(paths, owner)
					local ot = op and read(op)
					local same = carried
						and front.status ~= nil
						and ot ~= nil
						and frontOf(ot).status == front.status
					if not same then
						return `{t} belongs to {owner} on origin/main, not {id}`
					end
				end
				-- a prepared member is never restamped: a published move leaves it as it is, the carried move takes it
				if cur == "prepared" then
					if carried then
						if store.readFront(store.get(t).doc).design ~= "ready" then
							return `{t} is not design: ready: set it (z-design) before status {id} prepared`
						end
						rafted = true
						if owner ~= id then
							table.insert(groupedHere, t)
						end
					end
					continue
				end
				-- c0116 (review 001 F1): a preparing member is this raft's own claim (its stamp) or one this
				-- checkout made (`status <id> preparing` here); any other is another terminal's live claim
				if
					carried
					and cur == "preparing"
					and tf.status ~= front.status
					and not (tf.status ~= nil and tf.status == rememberedClaim(t))
				then
					return `{t} is claimed by another terminal ({tf.status}): drop it from {id} or release (if it is this checkout's own claim and its claim file was cleared: ./zn status {t} new, then claim it again)`
				end
			end
			if carried and t ~= id and cur ~= "preparing" then
				return `{t} is {cur} on origin/main: claim it first with ./zn status {t} preparing`
			end
			if carried then
				-- the move to `prepared` ties the two fields together: designs are ready first, and the one
				-- review's open list is empty or ruled (a refutation or an unclosed high waits for the human)
				local localItem = store.get(t)
				if store.readFront(localItem.doc).design ~= "ready" then
					return `{t} is not design: ready: set it (z-design) before status {id} prepared`
				end
				local gap = designOpen(localItem)
				if gap then
					return `{t}: {gap}`
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
			if t == id and not store.isRaftId(id) and to == "preparing" then
				local suffix = `/{t}.md`
				local reviewPath = if string.sub(tp, -#suffix) == suffix
					then string.sub(tp, 1, #tp - #suffix) .. "/idea-review-001.md"
					else ""
				local why = idea.designRefusal(tt, if reviewPath ~= "" then read(reviewPath) else nil, t)
				if why then
					return why
				end
			end
			table.insert(moved, { id = t, from = cur :: string })
			table.insert(changes, { path = tp, content = withFront(tt, "status", value) })
		end
		-- c0116 (review 002 F1): a member redesigned on origin/main since z-raft grouped it (a claim and a landing inside
		-- the rafting window) leaves the rafting: its coherence review read the old design
		if carried and store.isRaftId(id) then
			local raftItem = store.get(id)
			local map, problem = raftplan.parseGrouped(store.readFront(raftItem.doc).grouped)
			if problem then
				return `{raftItem.doc}: {problem}`
			end
			local redesigned = regrouped(map, originHashes)
			if #redesigned > 0 then
				return `{table.concat(redesigned, ", ")}: changed on origin/main since {id} grouped it: drop it (./zn unfold {id} <id>), then fold it again and rerun the coherence review`
			end
			-- review 003 F5: only an old-flow member (stamped with the raft's value) goes without a record
			for _, t in groupedHere do
				if not map[t] then
					return `{t} has no grouped: record in {id}: fold it again (only a member stamped with {id}'s value is exempt)`
				end
			end
		end
		if carried and rafted then
			-- z-raft wrote the raft's own design, and a raft of several issues had its coherence review in this rafting
			local raftItem = store.get(id)
			local doc = fs.readFile(raftItem.doc)
			for _, heading in { "Theme", "Order & dependencies" } do
				if not sectionWritten(doc, heading) then
					return `{id} has no {heading}: z-raft writes it before status {id} prepared`
				end
			end
		end
		-- review 003 F2: a raft of several issues needs a coherence review of the record it now holds (after its Theme)
		if carried and store.isRaftId(id) and #targets > 2 then
			local raftItem = store.get(id)
			local map = raftplan.parseGrouped(store.readFront(raftItem.doc).grouped)
			if not reviewCovers(gitFolderFiles(raftItem.dir), map) then
				local ids: { string } = {}
				for mid in map do
					table.insert(ids, mid)
				end
				table.sort(ids)
				return `{id}'s coherence review predates its record ({table.concat(ids, ", ")}): run a new raft-mode round (zz-review); never edit a review that is already written`
			end
		end
		if carried then
			return {}
		end
		return changes
	end, function()
		return `tracker: {id} {to}`
	end))
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
		-- c0116: an issue claimed here is remembered, so this checkout's carried raft move may take it
		if not store.isRaftId(id) then
			if to == "preparing" then
				rememberClaim(id, frontOf(fs.readFile(store.get(id).doc)).status or "")
			elseif fs.isFile(claimFile(id)) then
				fs.removeFile(claimFile(id))
			end
		end
	end
	-- giving a claim back ends this worktree's ownership of it
	if store.isRaftId(id) and moved[1].from == "active" and fs.isFile(claimFile(id)) then
		fs.removeFile(claimFile(id))
	end
end

-- `status` lists what origin/main says about every item that is not done; `status <id>` prints one
-- item's status; `status <id> <to>` moves it (checked against origin/main, not the local file).
-- A move of a raft moves its members too. Published moves are pushed at once; the move to
-- `prepared` is carried by the prep PR and only edits the local documents. A readied item (in active/) is not
-- moved here: `stop` gives it back.
function cmd.status(pos: { string })
	local id, to = pos[1], pos[2]
	if to then
		refuseInMainCheckout("status")
	end
	if not publishing() then
		fail("status needs an origin remote (PICKMAN_PUBLISH=0 disables it)")
	end
	if not id then
		local listed = originPaths()
		local roots = originRoots() :: { string }
		for _, p in listed do
			-- the item's own document only: spend.md sits beside it and must not list the item twice
			local fid, file = string.match(p, "/([fdcR]%d%d%d%d)/([^/]+)$")
			if fid and file == `{fid}.md` and publish.allowed(p, roots) and stateOfPath(p) ~= "done" then
				local front = frontOf(sh.git({ "show", `origin/main:{p}` }))
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
			"only ./zn start or ./zn ready claims active: it checks the tree, the designs and the dependencies first"
		)
	end
	setStatus(id, to)
end

-- c0116 (z-raft): an issue's raft is its own `raft:` line, written in a worktree and carried by the rafting PR, so two
-- PRs that raft one issue edit one line and the second cannot merge cleanly. The published claim stamps rafts only
-- (`preparing-…`); a prepared issue is never restamped. These commands share the start: a worktree with an origin, a
-- clean tree, and origin/main merged in first, so the local tree holds everything origin/main does.
local function raftingStart(what: string)
	refuseInMainCheckout(what)
	if not publishing() then
		fail(`{what} needs an origin remote (PICKMAN_PUBLISH=0 disables it)`)
	end
	if sh.git({ "status", "--porcelain" }) ~= "" then
		fail(`working tree is not clean: commit first ({what} merges origin/main before and after it claims)`)
	end
	refuseStale()
	local r = sh.run("git", { "merge", "--no-edit", "origin/main" })
	if not r.ok then
		sh.run("git", { "merge", "--abort" })
		fail(`{what}: merging origin/main failed (merge aborted): {r.stderr}{r.stdout}`)
	end
end

-- A raft's member list as a frontmatter value.
local function listValue(ids: { string }): string
	return `[{table.concat(ids, ", ")}]`
end

-- Refuses an issue that can't be rafted by z-raft: not a prepared backlog issue with a ready design, or one that
-- already names a raft (`raft:` is the lock) or is of another type or project than `raft`.
local function refuseUnraftable(issue: store.Item, raft: store.Item)
	local front = store.readFront(issue.doc)
	local st = statusLib.effective(frontOf(fs.readFile(issue.doc)), issue.state)
	if issue.state ~= "backlog" then
		fail(`{issue.id} is {st} in {issue.dir}: a raft takes backlog issues only`)
	end
	if st ~= "prepared" or front.design ~= "ready" then
		fail(
			`{issue.id} is {st} (design: {front.design or "none"}): z-raft groups prepared issues only (z-design first)`
		)
	end
	if store.typeOf(issue) ~= store.typeOf(raft) then
		fail(`{issue.id} is a {store.typeOf(issue)}; a {store.typeOf(raft)} raft cannot contain it`)
	end
	if issue.root ~= raft.root then
		fail(`a raft holds issues of one project: {issue.id} is in {issue.root}, not {raft.root}`)
	end
end

-- `fold <R-id> <issue>...`: puts prepared, raftless issues into a prepared backlog raft. It publishes the raft's claim
-- (its status only), then writes each issue's `raft:` and the raft's `issues:` here and commits; z-raft then writes the
-- raft's design and runs the carried `status <R-id> prepared`. A raft this checkout already claimed is not claimed
-- again.
function cmd.fold(pos: { string })
	local raftId = pos[1]
	if not raftId or not store.isRaftId(raftId) or #pos < 2 then
		fail("usage: fold <R-id> <issue>...")
	end
	raftingStart("fold")
	local raft = store.get(raftId)
	if raft.kind ~= "raft" or raft.state ~= "backlog" then
		fail(`{raftId} is in {raft.dir}: fold takes a backlog raft`)
	end
	local ids: { string } = {}
	for i = 2, #pos do
		table.insert(ids, pos[i])
	end
	local members = store.members(raftId)
	local solo: string? = nil
	for _, m in members do
		if store.readFront(m.doc).solo == "true" then
			solo = m.id
		end
	end
	for _, id in ids do
		local issue = store.get(id)
		local owner = store.readFront(issue.doc).raft or ""
		if owner ~= "" then
			fail(`{id} already belongs to {owner}`)
		end
		refuseUnraftable(issue, raft)
		if store.readFront(issue.doc).solo == "true" and #members + #ids > 1 then
			solo = id
		end
	end
	if solo then
		fail(`{solo} is solo: true (a recorded user decision): it is rafted alone`)
	end
	local mine = rememberedClaim(raftId)
	local claim = freshStamp("preparing")
	local resumed = false
	refuseStale()
	local r = published(publish.commit(".", function(paths, read)
		resumed = false
		local rp = docPath(paths, raftId)
		local rt = rp and read(rp)
		if not rp or not rt then
			return `{raftId} is not on origin/main`
		end
		local rf = frontOf(rt)
		local st = statusLib.effective(rf, stateOfPath(rp))
		if st == "preparing" and mine ~= "" and rf.status == mine then
			resumed = true
		elseif st ~= "prepared" then
			return `{raftId} is {st} on origin/main: fold takes a prepared raft (or one this checkout claimed)`
		end
		for _, id in ids do
			local p = docPath(paths, id)
			local text = p and read(p)
			if not p or not text then
				return `{id} is not on origin/main`
			end
			local owner = frontOf(text).raft or ""
			if owner ~= "" then
				return `{id} already belongs to {owner} on origin/main`
			end
		end
		if resumed then
			return {}
		end
		return { { path = rp, content = withFront(rt, "status", claim) } }
	end, `tracker: fold into {raftId} (claim)`))
	if not r.ok then
		fail(`fold: {r.reason}`)
	end
	if not resumed then
		rememberClaim(raftId, claim)
		mergeOrigin()
	end
	raft = store.get(raftId)
	local list = store.idList(store.readFront(raft.doc).issues)
	for _, id in ids do
		local doc = store.get(id).doc
		store.setFront(doc, "raft", raftId)
		sh.git({ "add", doc })
		if not table.find(list, id) then
			table.insert(list, id)
		end
	end
	store.setFront(raft.doc, "issues", listValue(list))
	recordGrouped(raft.doc, ids)
	sh.git({ "add", raft.doc })
	sh.git({ "commit", "--quiet", "-m", `tracker: fold {table.concat(ids, " ")} into {raftId}` })
	print(`folded {table.concat(ids, ", ")} into {raftId}`)
end

-- `unfold <R-id> <issue>...` (c0116, review 002 F3): takes members out of a backlog raft. It claims the raft as `fold`
-- does (its status only, published; this checkout's own claim is resumed), then clears each issue's `raft:`, drops it
-- from the raft's `issues:` and `grouped:` here and commits; z-raft then prepares the raft again (carried) and lands the
-- PR. A member of a landed raft goes back to z-design this way: once the PR lands, its claim is open again.
function cmd.unfold(pos: { string })
	local raftId = pos[1]
	if not raftId or not store.isRaftId(raftId) or #pos < 2 then
		fail("usage: unfold <R-id> <issue>...")
	end
	raftingStart("unfold")
	-- R0050 code review 002 F1: a raft that is retired or missing can't be claimed, so its members' raft: lines are
	-- cleared here with no claim (audit's dead-raft error names this command); the rafting PR carries them
	if not store.find(raftId) then
		local dead = "missing"
		for _, root in store.roots() do
			if fs.isDir(retiredDir(root, raftId)) then
				dead = "retired"
			end
		end
		local gone: { string } = {}
		for i = 2, #pos do
			local issue = store.get(pos[i])
			if (store.readFront(issue.doc).raft or "") ~= raftId then
				fail(`{issue.id} is not a member of {raftId}`)
			end
			if issue.state == "done" then
				fail(`{issue.id} is done: its raft: is history`)
			end
			-- review 003 F1: an active issue leaves active/ only by a published move, never in a branch
			if issue.state == "active" then
				fail(
					`{issue.id} is in active/: use ./zn stop {issue.id} (it gives the issue back to the backlog)`
				)
			end
			table.insert(gone, issue.id)
		end
		for _, id in gone do
			local doc = store.get(id).doc
			store.setFront(doc, "raft", "")
			sh.git({ "add", doc })
		end
		sh.git({
			"commit",
			"--quiet",
			"-m",
			`tracker: unfold {table.concat(gone, " ")} from {raftId} ({dead}: no claim)`,
		})
		print(`unfolded {table.concat(gone, ", ")} from {raftId} ({dead}: nothing to claim)`)
		return
	end
	local raft = store.get(raftId)
	if raft.kind ~= "raft" or raft.state ~= "backlog" then
		fail(`{raftId} is in {raft.dir}: unfold takes a backlog raft`)
	end
	local ids: { string } = {}
	for i = 2, #pos do
		local issue = store.get(pos[i])
		if (store.readFront(issue.doc).raft or "") ~= raftId then
			fail(`{issue.id} is not a member of {raftId}`)
		end
		table.insert(ids, issue.id)
	end
	local mine = rememberedClaim(raftId)
	local claim = freshStamp("preparing")
	local resumed = false
	refuseStale()
	local r = published(publish.commit(".", function(paths, read)
		resumed = false
		local rp = docPath(paths, raftId)
		local rt = rp and read(rp)
		if not rp or not rt then
			return `{raftId} is not on origin/main`
		end
		local rf = frontOf(rt)
		local st = statusLib.effective(rf, stateOfPath(rp))
		if st == "preparing" and mine ~= "" and rf.status == mine then
			resumed = true
			return {}
		elseif st ~= "prepared" then
			return `{raftId} is {st} on origin/main: unfold takes a prepared raft (or one this checkout claimed)`
		end
		return { { path = rp, content = withFront(rt, "status", claim) } }
	end, `tracker: unfold from {raftId} (claim)`))
	if not r.ok then
		fail(`unfold: {r.reason}`)
	end
	if not resumed then
		rememberClaim(raftId, claim)
		mergeOrigin()
	end
	raft = store.get(raftId)
	local left: { string } = {}
	for _, id in store.idList(store.readFront(raft.doc).issues) do
		if not table.find(ids, id) then
			table.insert(left, id)
		end
	end
	for _, id in ids do
		local doc = store.get(id).doc
		store.setFront(doc, "raft", "")
		sh.git({ "add", doc })
	end
	store.setFront(raft.doc, "issues", listValue(left))
	recordGrouped(raft.doc, ids, true)
	sh.git({ "add", raft.doc })
	sh.git({ "commit", "--quiet", "-m", `tracker: unfold {table.concat(ids, " ")} from {raftId}` })
	print(`unfolded {table.concat(ids, ", ")} from {raftId}`)
end

-- `recombine <keeper> <other> [<issue>...]`: moves the named members of the other backlog raft (all of them when none
-- is named) into the keeper. Both rafts are claimed with one fresh stamp (status lines only, published), so the
-- carried `status <keeper> prepared` sees the other raft as the same claim. The moves are written here and committed;
-- the other raft is retired only when it ends up empty: its folder moves to <root>/rafts/retired/ with `retired: <keeper>`
-- in this branch, so in the rafting PR.
function cmd.recombine(pos: { string })
	local keeperId, otherId = pos[1], pos[2]
	if not (keeperId and otherId and store.isRaftId(keeperId) and store.isRaftId(otherId)) then
		fail("usage: recombine <keeper R-id> <other R-id> [<issue>...]")
	end
	if keeperId == otherId then
		fail("recombine needs two different rafts")
	end
	raftingStart("recombine")
	local keeper, other = store.get(keeperId), store.get(otherId)
	for _, r in { keeper, other } do
		if r.kind ~= "raft" or r.state ~= "backlog" then
			fail(`{r.id} is in {r.dir}: recombine takes backlog rafts only`)
		end
		local st = statusLib.effective(frontOf(fs.readFile(r.doc)), r.state)
		if st ~= "prepared" and st ~= "new" then
			fail(
				`{r.id} is {st}: recombine takes a prepared or new raft, never one being prepared, active or done`
			)
		end
	end
	if keeper.root ~= other.root then
		fail(`rafts never cross projects: {keeperId} is in {keeper.root}, {otherId} in {other.root}`)
	end
	if store.typeOf(keeper) ~= store.typeOf(other) then
		fail(`{keeperId} is a {store.typeOf(keeper)} raft, {otherId} a {store.typeOf(other)} one`)
	end
	local inOther: { [string]: boolean } = {}
	local otherIds: { string } = {}
	for _, m in store.members(otherId) do
		inOther[m.id] = true
		table.insert(otherIds, m.id)
	end
	local moving: { string } = {}
	if #pos > 2 then
		for i = 3, #pos do
			if not inOther[pos[i]] then
				fail(`{pos[i]} is not a member of {otherId}`)
			end
			-- R0050 code review 001 F2: a repeated id would count twice toward emptying the other raft
			if table.find(moving, pos[i]) then
				fail(`{pos[i]} is named twice: name each member once`)
			end
			table.insert(moving, pos[i])
		end
	else
		moving = otherIds
	end
	local keeperMembers = store.members(keeperId)
	local all: { store.Item } = table.clone(keeperMembers)
	for _, id in moving do
		table.insert(all, store.get(id))
	end
	for _, m in all do
		refuseUnraftable(m, keeper)
		if store.readFront(m.doc).solo == "true" and #all > 1 then
			fail(`{m.id} is solo: true (a recorded user decision): it is rafted alone`)
		end
	end
	-- retire only when no member of the other raft stays behind (decided by the members, never by counts: review 001 F2)
	local retire = true
	for _, id in otherIds do
		if not table.find(moving, id) then
			retire = false
			break
		end
	end
	local claim = freshStamp("preparing")
	refuseStale()
	local r = published(publish.commit(".", function(paths, read)
		local changes: { publish.Change } = {}
		for _, rid in { keeperId, otherId } do
			local rp = docPath(paths, rid)
			local rt = rp and read(rp)
			if not rp or not rt then
				return `{rid} is not on origin/main`
			end
			local st = statusLib.effective(frontOf(rt), stateOfPath(rp))
			if stateOfPath(rp) ~= "backlog" or (st ~= "prepared" and st ~= "new") then
				return `{rid} is {st} on origin/main: recombine takes a prepared or new backlog raft`
			end
			table.insert(changes, { path = rp, content = withFront(rt, "status", claim) })
		end
		for _, id in moving do
			local p = docPath(paths, id)
			local text = p and read(p)
			if not p or not text then
				return `{id} is not on origin/main`
			end
			if (frontOf(text).raft or "") ~= otherId then
				return `{id} belongs to {frontOf(text).raft or "no raft"} on origin/main, not {otherId}`
			end
		end
		return changes
	end, `tracker: recombine {otherId} into {keeperId} (claim)`))
	if not r.ok then
		fail(`recombine: {r.reason}`)
	end
	rememberClaim(keeperId, claim)
	rememberClaim(otherId, claim)
	mergeOrigin()
	keeper, other = store.get(keeperId), store.get(otherId)
	local list = store.idList(store.readFront(keeper.doc).issues)
	for _, id in moving do
		local doc = store.get(id).doc
		store.setFront(doc, "raft", keeperId)
		sh.git({ "add", doc })
		if not table.find(list, id) then
			table.insert(list, id)
		end
	end
	store.setFront(keeper.doc, "issues", listValue(list))
	recordGrouped(keeper.doc, moving)
	sh.git({ "add", keeper.doc })
	if retire then
		-- c0116 (review 001 F2): a retired raft keeps its folder (its design reviews, refutes and harvest.md, which
		-- lessons and metrics read) under <root>/rafts/retired/, with `retired: <keeper>`; store, the board and the plan
		-- never find it there; audit's scan and list show it, as retired; the bare status, which walks only publishable
		-- paths, never lists it (review 004 F2)
		local dest = retiredDir(other.root, otherId)
		local parent = string.match(dest, "^(.*)/[^/]+$") :: string
		if not fs.isDir(parent) then
			fs.writeDir(parent)
		end
		store.setFront(other.doc, "retired", keeperId)
		sh.git({ "add", other.doc })
		sh.git({ "mv", other.dir, dest })
	else
		local left: { string } = {}
		for _, id in store.idList(store.readFront(other.doc).issues) do
			if not table.find(moving, id) then
				table.insert(left, id)
			end
		end
		store.setFront(other.doc, "issues", listValue(left))
		recordGrouped(other.doc, moving, true)
		sh.git({ "add", other.doc })
	end
	sh.git({
		"commit",
		"--quiet",
		"-m",
		`tracker: recombine {otherId} into {keeperId} ({if #moving > 0
			then table.concat(moving, " ")
			else "no members"})`,
	})
	print(
		`recombined {otherId} into {keeperId}: {if #moving > 0
			then table.concat(moving, ", ")
			else "no members"}`
	)
	if retire then
		print(`retired {otherId}: its folder moves to {retiredDir(other.root, otherId)} in this branch`)
	else
		print(`{otherId} keeps {table.concat(store.idList(store.readFront(other.doc).issues), ", ")}`)
	end
end

-- `release <R-id> [--force]`: gives back a rafting claim (`new raft`, `fold`, `status <R> preparing`, `recombine`) in
-- one published commit. Every backlog item that carries the raft's `preparing-…` stamp on origin/main goes back:
-- `prepared` when its design there is ready, else `new`. The plain `status <R> prepared` stays carried by the PR. Only
-- the claim this checkout remembers is released, unless `--force` (for a claim the user says is abandoned).
function cmd.release(pos: { string }, opts: { [string]: { string } })
	local raftId = pos[1]
	if not raftId or not store.isRaftId(raftId) then
		fail("usage: release <R-id> [--force]")
	end
	refuseInMainCheckout("release")
	if not publishing() then
		fail("release needs an origin remote (PICKMAN_PUBLISH=0 disables it)")
	end
	refuseStale()
	local paths = originPaths()
	local rp = docPath(paths, raftId) or fail(`{raftId} is not on origin/main`)
	local value = frontOf(sh.git({ "show", `origin/main:{rp}` })).status or ""
	if not string.match(value, "^preparing%-") then
		fail(`{raftId} has no rafting claim on origin/main (status: {if value ~= "" then value else "none"})`)
	end
	local mine = rememberedClaim(raftId)
	if mine ~= value and not opts["--force"] then
		fail(
			`{raftId}'s claim {value} is not this checkout's: give back only your own claim (--force when the user says it is abandoned)`
		)
	end
	local carriers, err = claimsLib.carriers(".", value, nil, originRoots() or {})
	if not carriers then
		fail(`release: cannot list what carries {value}: {err}`)
	end
	-- what goes back: every carrier of the raft's stamp, and (review 002 F4) the issue claims this checkout remembers for
	-- the raft's members here (an issue added to it with `status <id> preparing`), each with the value it must still carry
	local wanted: { { path: string, value: string } } = {}
	for _, p in carriers :: { string } do
		table.insert(wanted, { path = p, value = value })
	end
	local raftItem = store.find(raftId)
	if raftItem then
		local names: { [string]: boolean } = {}
		for _, id in store.idList(store.readFront(raftItem.doc).issues) do
			names[id] = true
		end
		for _, m in store.members(raftId) do
			names[m.id] = true
		end
		for id in names do
			local mineIssue = rememberedClaim(id)
			local item = store.find(id)
			if mineIssue ~= "" and mineIssue ~= value and item then
				table.insert(wanted, { path = item.doc, value = mineIssue })
			end
		end
	end
	local done: { string } = {}
	refuseStale()
	local r = published(publish.commit(".", function(_, read)
		done = {}
		local changes: { publish.Change } = {}
		for _, w in wanted do
			local p = w.path
			local text = read(p)
			local id, rel = publish.itemPath(p)
			if not text or not id or rel ~= `{id}.md` or stateOfPath(p) ~= "backlog" then
				continue
			end
			local front = frontOf(text)
			if front.status ~= w.value then
				continue
			end
			local to = if front.design == "ready" then "prepared" else "new"
			table.insert(done, `{id} ({to})`)
			table.insert(changes, { path = p, content = withFront(text, "status", stamp(to)) })
		end
		if #changes == 0 then
			return `{raftId}: nothing on origin/main carries {value}`
		end
		return changes
	end, `tracker: release {raftId}`))
	if not r.ok then
		fail(`release: {r.reason}`)
	end
	for _, d in done do
		local id = string.match(d, "^(%S+)") :: string
		if fs.isFile(claimFile(id)) then
			fs.removeFile(claimFile(id))
		end
	end
	-- no merge: the branch is given up, and it may well conflict with origin/main (another rafting of its issues)
	print(`released {table.concat(done, ", ")}`)
	print(
		"this branch's own rafting commits are left as they are: reset it to origin/main or remove the worktree"
	)
end

-- Prints a fresh stamp for a state (diagnostics, and how specs prove that stamps differ between processes).
function cmd.stamp(pos: { string })
	local state = pos[1]
	if not state or not statusLib.parse(state) then
		fail("usage: stamp <new|preparing|prepared|active|done>")
	end
	print(stamp(state))
end

-- The reaper at the start of `sync` and of the gate (`reap --auto`, defined with the other commands below)
local function reapAuto()
	cmd.reap({}, { ["--auto"] = { "true" } })
end

-- `sync` brings origin/main into this checkout (a merge in a worktree, a fast-forward in the main
-- checkout). `sync --fetch` only updates origin/main: reviewers and stream agents use it, because
-- a merge would add a commit and change the diff they judge.
function cmd.sync(_: { string }, opts: { [string]: { string } })
	reapAuto()
	sh.git({ "fetch", "--quiet", "origin", "main" })
	if not opts["--fetch"] then
		if sh.git({ "rev-parse", "--show-toplevel" }) == mainRoot() then
			local before = sh.git({ "rev-parse", "HEAD" })
			sh.git({ "pull", "--quiet", "--ff-only" })
			sweepStale(mainRoot(), before, sh.git({ "rev-parse", "HEAD" }))
			buildBoard(mainRoot())
		else
			mergeOrigin()
		end
	end
	print(`synced to {sh.git({ "rev-parse", "--short", "origin/main" })}`)
end

-- What a capture may change, from `git diff --name-status --no-renames origin/main HEAD`: edits (M) to backlog
-- issue documents `<root>/issues/<ID>/<ID>.md`, under a root of `base`'s registry (c0114), that say `design: draft` on
-- both sides, with the status line unchanged, and an added or edited `spend.md` in that same issue's folder (the
-- capture row committed on the branch before land). A spend.md whose issue document this land does not change is refused.
-- Returns the first refusal (naming the path), or nil.
-- The frontmatter keys in order, or nil when one repeats: frontOf reads the last copy of a key, store.withFront
-- rewrites the first, so a document with two is refused rather than read two ways.
local function frontKeys(text: string): { string }?
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-") or ""
	local keys: { string } = {}
	for line in string.gmatch(block .. "\n", "([^\n]*)\n") do
		local k = string.match(line, "^([%w_]+):")
		if k then
			if table.find(keys, k) then
				return nil
			end
			table.insert(keys, k)
		end
	end
	return keys
end

-- what a capture may change in an issue's frontmatter: its title and its dependencies; everything else stays
local CAPTURE_KEYS: { [string]: boolean } = { title = true, depends_on = true }

local function captureScope(diff: string, base: string): string?
	local reg, regErr = projects.at(base)
	if not reg then
		return `cannot read the project roots at {base}: {regErr}`
	end
	local roots = projects.roots(reg :: projects.Registry)
	local seen = false
	local captured: { [string]: boolean } = {}
	local spends: { { id: string, path: string } } = {}
	for line in string.gmatch(diff, "[^\n]+") do
		seen = true
		local kind, path = string.match(line, "^(%a)\t(.+)$")
		if not kind or not path then
			return `cannot read the diff line "{line}"`
		end
		local root, rest = projects.rootOf(path, roots)
		local spendId = if root and rest then string.match(rest, "^issues/([^/]+)/spend%.md$") else nil
		local tsvId = if root and rest
			then string.match(rest, "^issues/([^/]+)/spend%.d/[%w._%-]+%.tsv$")
			else nil
		spendId = spendId or tsvId
		if spendId and store.isIssueId(spendId) and (kind == "A" or kind == "M") then
			local mode = sh.run("git", { "ls-tree", "HEAD", "--", path })
			if not mode.ok or string.sub(mode.stdout, 1, 7) ~= "100644 " then
				return `not a capture change: {path} must stay a plain file (mode 100644)`
			end
			table.insert(spends, { id = spendId, path = path })
			continue
		end
		local a, b = nil, nil
		if root and rest then
			a, b = string.match(rest, "^issues/([^/]+)/([^/]+)%.md$")
		end
		if kind ~= "M" or not a or a ~= b or not store.isIssueId(a) then
			return `not a capture change: {kind} {path} (a capture changes only backlog issue documents; land that through a pull request)`
		end
		captured[a] = true
		local theirs = sh.run("git", { "show", `{base}:{path}` })
		local mine = sh.run("git", { "show", `HEAD:{path}` })
		if not theirs.ok or not mine.ok then
			return `cannot read {path} on both sides`
		end
		local mode = sh.run("git", { "ls-tree", "HEAD", "--", path })
		if not mode.ok or string.sub(mode.stdout, 1, 7) ~= "100644 " then
			return `not a capture change: {path} must stay a plain file (mode 100644)`
		end
		local wasKeys, nowKeys = frontKeys(theirs.stdout), frontKeys(mine.stdout)
		if not wasKeys or not nowKeys then
			return `not a capture change: {path} repeats a frontmatter key`
		end
		local was, now = frontOf(theirs.stdout), frontOf(mine.stdout)
		if now.id ~= a then
			return `not a capture change: {path} must keep id: {a}`
		end
		for _, keys in { wasKeys, nowKeys } do
			for _, k in keys do
				if not CAPTURE_KEYS[k] and was[k] ~= now[k] then
					return `not a capture change: {path} changes {k}: (a capture edits only the title, depends_on and the sections)`
				end
			end
		end
		if was.design ~= "draft" or now.design ~= "draft" then
			return `not a capture change: {path} is not design: draft on both sides (design moves only through prep)`
		end
		if was.status ~= now.status then
			return `not a capture change: {path} changes its status line (./zn status moves it)`
		end
	end
	for _, entry in spends do
		if not captured[entry.id] then
			return `not a capture change: {entry.path} (a capture's spend record belongs to an issue document this land changes)`
		end
	end
	if not seen then
		return "nothing to land: this branch has no change against origin/main"
	end
	return nil
end

-- An issue the landed diff touches, that already has an approval, whose contract no longer matches.
-- An issue with no approval.md is left alone (a capture, or an item prepared before approval).
local function approvedDrift(base: string): string?
	local names = sh.git({ "diff", "--name-only", base, "HEAD" })
	local seen: { [string]: boolean } = {}
	for path in string.gmatch(names, "[^\n]+") do
		local id = string.match(path, "/issues/active/([fdc]%d%d%d%d)/")
			or string.match(path, "/issues/done/([fdc]%d%d%d%d)/")
			or string.match(path, "/issues/([fdc]%d%d%d%d)/")
			or string.match(path, "/tests/acceptance/([fdc]%d%d%d%d)/")
		if id then
			seen[id] = true
		end
	end
	local ids = {}
	for id in seen do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		-- A deleted document leaves the directory (check.sh remains) and store.find throws. That is
		-- captureScope's refusal, which names the path; the approval check has nothing left to read.
		local ok, found = pcall(store.find, id)
		if not ok then
			local why = tostring(found)
			if string.find(why, "has no ", 1, true) then
				continue
			end
			return why
		end
		local item = found :: store.Item?
		if item and item.kind == "issue" then
			local problem = approval.refusal(".", item, false)
			if problem then
				return problem
			end
		end
	end
	return nil
end

-- c0072: lands a capture without a pull request. Merge origin/main, check the scope, run the static stages (not the
-- full gate: a capture is a draft backlog document), push one commit made on top of origin/main (never a force).
-- A lost push race merges the new main and retries the push, not the gate (up to 3 tries).
function cmd.land(_: { string }, opts: { [string]: { string } })
	local branch = sh.trim(sh.run("git", { "branch", "--show-current" }).stdout)
	if string.sub(branch, 1, 8) ~= "capture-" then
		fail("land is for capture worktrees (capture-<slug>)")
	end
	if sh.trim(sh.must("git", { "status", "--porcelain" })) ~= "" then
		fail("the tree is not clean: commit everything first")
	end
	if not publishing() then
		fail("land needs publishing: an origin, and PICKMAN_PUBLISH not 0")
	end
	local root = sh.git({ "rev-parse", "--show-toplevel" })
	local raw = process.env.PICKMAN_LAND_GATE
	local override = if raw and string.match(raw, "%S") then raw else nil
	local gate = override or "z-nile/check.sh --static"
	local given = opts["-m"]
	local function take(base: string)
		local merged = sh.run("git", { "merge", "--no-edit", base })
		if not merged.ok then
			sh.run("git", { "merge", "--abort" })
			fail(
				`merging origin/main failed (merge aborted): {merged.stderr}{merged.stdout}\nresolve it with: git merge origin/main, then run land again`
			)
		end
		refuseStale()
		local drift = approvedDrift(base)
		if drift then
			fail(drift)
		end
		local diff = sh.must("git", { "diff", "--name-status", "--no-renames", base, "HEAD" })
		local refusal = captureScope(diff, base)
		if refusal then
			fail(refusal)
		end
	end
	sh.git({ "fetch", "--quiet", "origin", "main" })
	-- the merge, the scope and the first push all name this sha, so a push during the gate cannot become the
	-- parent of a tree it isn't in
	local base = sh.git({ "rev-parse", "--verify", "origin/main^{commit}" })
	take(base)
	print(`gate: {gate}{if override then " (gate overridden: PICKMAN_LAND_GATE)" else ""}`)
	if not sh.stream("bash", { "-c", gate }) then
		fail("the gate failed: nothing was pushed")
	end
	-- The gate appended its row to the cache. Fold it into the landed tree without an extra commit on the branch.
	local names = sh.git({ "diff", "--name-only", base, "HEAD" })
	local homes: { [string]: string } = {}
	for path in string.gmatch(names, "[^\n]+") do
		local id = string.match(path, "/issues/([fdc]%d%d%d%d)/[fdc]%d%d%d%d%.md$")
		if id then
			local item = store.find(id)
			if item then
				homes[id] = item.dir
			end
		end
	end
	local planned: costrow.Planned? = nil
	local foldedPaths: { string } = {}
	local plannedOk, plannedOrErr = pcall(costrow.plan, root, homes, nil, false)
	if plannedOk then
		local ready = plannedOrErr :: costrow.Planned
		planned = ready
		local wroteOk, wrote = pcall(costrow.writeFiles, ready)
		if wroteOk and wrote then
			foldedPaths = wrote
		else
			planned = nil
		end
	end
	local function treeNow(): string
		if #foldedPaths == 0 then
			return sh.git({ "rev-parse", "HEAD^{tree}" })
		end
		local args = { "add", "--" }
		for _, path in foldedPaths do
			table.insert(args, path)
		end
		sh.git(args)
		return sh.git({ "write-tree" })
	end
	local message = if given and given[1] and given[1] ~= "" then given[1] else nil
	if not message then
		local subjects = sh.git({ "log", "--reverse", "--no-merges", "--format=%s", `{base}..HEAD` })
		local bodies = sh.git({ "log", "--reverse", "--no-merges", "--format=%b", `{base}..HEAD` })
		local subject = string.match(subjects, "^[^\n]*") or "tracker: capture"
		message = if bodies ~= "" then `{subject}\n\n{bodies}` else subject
	end
	local parent = base
	for _ = 1, 3 do
		local tree = treeNow()
		local sha = sh.git({ "commit-tree", tree, "-p", parent, "-m", message :: string })
		local pushed: sh.Result
		if process.env.ZN_PUBLISH_BROKER and process.env.ZN_PUBLISH_BROKER ~= "" then
			-- inside a dispatched step the agent's credential can't push to main: the dispatcher pushes it (c0117)
			local ok, said = brokerLib.request(
				process.env.ZN_PUBLISH_BROKER :: string,
				process.env.ZN_PUBLISH_TOKEN or "",
				sha,
				nil
			)
			pushed = { ok = ok, code = if ok then 0 else 1, stdout = "", stderr = said }
		else
			pushed = sh.run("git", { "push", "origin", `{sha}:refs/heads/main` })
		end
		if pushed.ok then
			if planned then
				pcall(costrow.writeBuffer, root, planned)
			end
			sh.git({ "reset", "--hard", "--quiet", sha })
			sh.run("git", { "fetch", "--quiet", "origin", "main" })
			local suffix = if override then " (gate overridden)" else ""
			print(
				`landed {sha} on main; remove this worktree: git -C {mainRoot()} worktree remove {root} && git -C {mainRoot()} branch -D {branch}{suffix}`
			)
			local kickErr: any = nil
			local kicked = xpcall(watchcmd.kick, function(e)
				kickErr = e
			end)
			if not kicked then
				stdio.ewrite(`watch-net: not started ({kickErr})\n`)
			end
			return
		end
		sh.run("git", { "fetch", "--quiet", "origin", "main" })
		local now = sh.git({ "rev-parse", "--verify", "origin/main^{commit}" })
		if now == parent then
			if planned then
				pcall(costrow.restore, planned)
				pcall(function()
					sh.git({ "reset", "--quiet" })
				end)
			end
			fail(`the push failed (origin/main did not move): {pushed.stderr}{pushed.stdout}`)
		end
		-- origin/main moved: merge it and push again. The gate already passed; it is not run again.
		take(now)
		parent = now
	end
	if planned then
		pcall(costrow.restore, planned)
		pcall(function()
			sh.git({ "reset", "--quiet" })
		end)
	end
	fail("lost the race to main 3 times: run land again")
end

-- A repo-relative path as the caller can use it (c0120): relative to the directory ./zn was run from (hereDir, c0114's
-- ZN_CWD in ZN_TOP), so `$(./zn find <id>)/...` works from a project's home as from the root.
local function callerPath(rel: string): string
	local from = hereDir()
	if from == "" then
		return rel
	end
	local a = string.split(from, "/")
	local b = string.split(rel, "/")
	local i = 1
	while i <= #a and i <= #b and a[i] == b[i] do
		i += 1
	end
	local parts: { string } = {}
	for _ = i, #a do
		table.insert(parts, "..")
	end
	for j = i, #b do
		table.insert(parts, b[j])
	end
	return if #parts == 0 then "." else table.concat(parts, "/")
end

function cmd.find(pos: { string })
	print(callerPath(store.get(pos[1] or fail("usage: find <id>")).dir))
end

function cmd.members(pos: { string })
	for _, m in store.members(pos[1] or fail("usage: members <R-id>")) do
		print(callerPath(m.dir))
	end
end

-- The moves that freeze paths while they are in flight, and the branches each one's freeze ignores (one rule for every
-- move, in `ignoredBy`; c0115 G14, decided with the user 2026-10-24: "Yes, same rule"). A move's freeze is on while
-- `./zn busy` is given paths, all of them inside the move's own `paths` (c0115 design review 013 F5, decided with the
-- user 2026-10-25: "Scope to its paths"), and origin/main still holds its mark (a path the move takes away); then it
-- ignores, by exact name, its own roots, the branches listed as stacked on them and the branches the user approved;
-- any branch whose history holds the move commit (`pinned`); with `history`, any branch whose history holds a commit
-- of one of its roots on origin that origin/main doesn't (c0120's; useless once main takes a base as a squash, whose
-- commits never reach main: 013 F1); and an active raft that lists the item (013 F2, decided with the user 2026-10-25:
-- "Yes, ignore its own raft"). A name that only looks stacked counts for nothing.
type Freeze = {
	item: string,
	mark: string,
	roots: { [string]: string }, -- root branch -> why ("stacked on its prep")
	stacked: { [string]: boolean },
	approved: { [string]: boolean },
	paths: { string }, -- busy's paths must all lie inside these
	pinned: (() -> string?)?,
	history: boolean,
}

-- c0120's move, as the approving review pins it (`Move commit: <sha>` in the newest approved review-NNN.md in c0120's
-- folder at this checkout; AC18 reads the same line): a branch whose history holds it is built on c0120's
-- implementation, so stacked on c0120 (decided with the coordinator, 2026-10-24, after #99 merged c0120's prep into
-- main and the prep test could no longer tell a stacked branch apart). Nil when no approved review pins one.
local function c0120Move(): string?
	local top = sh.git({ "rev-parse", "--show-toplevel" })
	local best, pinned = -1, nil
	for _, dir in
		{
			"z-nile/.tracker/issues/c0120",
			"z-nile/.tracker/issues/active/c0120",
			"z-nile/.tracker/issues/done/c0120",
		}
	do
		local path = `{top}/{dir}`
		if fs.isDir(path) then
			for _, name in fs.readDir(path) do
				local n = tonumber(string.match(name, "^review%-(%d+)%.md$"))
				if n and n > best then
					local text = fs.readFile(`{path}/{name}`)
					local sha = string.match(text, "\nMove commit: (%x+)")
					if string.find(text, "\nVerdict: approve", 1, true) and sha then
						best, pinned = n, sha
					end
				end
			end
		end
	end
	return pinned
end

-- c0115's move commit: among the commits of origin/impl-c0115 that origin/main doesn't have (the range AC13 reads),
-- the one whose subject (never a body line) starts "c0115: move the skills". Exactly one, or nil: none, two, or a
-- missing branch pins nothing (c0115 design review 014 F2).
local function c0115Move(): string?
	local r = sh.run("git", {
		"log",
		"--format=%H %s",
		"refs/remotes/origin/main..refs/remotes/origin/impl-c0115",
		"--",
	})
	if not r.ok then
		return nil
	end
	local found: { string } = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		local sha, subject = string.match(line, "^(%x+) (.*)$")
		if
			sha
			and string.sub(subject :: string, 1, #"c0115: move the skills") == "c0115: move the skills"
		then
			table.insert(found, sha :: string)
		end
	end
	return if #found == 1 then found[1] else nil
end

local FREEZES: { Freeze } = {
	{
		-- decided with the user, 2026-10-23: "Re-prep R0044 after; exempt the stack" and "Named exemptions you approve";
		-- 2026-10-24: "Approve all three" (prep-c0121, proto-c0121, impl-c0120)
		item = "c0120",
		mark = "tracker/rafts/done/R0001/check.sh",
		roots = { ["prep-c0120"] = "stacked on its prep" },
		stacked = {
			["prep-c0115"] = true,
			["prep-c0116"] = true,
			["prep-c0117"] = true,
			["prep-c0118"] = true,
		},
		approved = {
			["proto-linux-jail"] = true,
			["proto-r0260"] = true,
			["prep-guard-follow-ups"] = true,
			["proto-c0117"] = true,
			["proto-c0118"] = true,
			["prep-c0121"] = true,
			["proto-c0121"] = true,
			["impl-c0120"] = true,
		},
		-- the old layout it moved and the new home (AC16: `./zn busy tracker src tests`; its spec asks about pickman/.tracker)
		paths = { "tracker", "src", "tests", "pickman" },
		pinned = c0120Move,
		history = true,
	},
	{
		-- c0115 (decided with the user, 2026-10-24, G14: "Yes, same rule"): the items stacked on c0115's
		-- prep or implementation (c0116, c0117, c0118, c0121) touch the skill paths by design; their prototypes are
		-- approved by name. Its mark is a file the move takes away, kept with the rename map (skillsLib.MOVE_MARK).
		item = "c0115",
		mark = skillsLib.MOVE_MARK,
		roots = { ["prep-c0115"] = "stacked on its prep", ["impl-c0115"] = "stacked on its implementation" },
		stacked = {
			["prep-c0116"] = true,
			["prep-c0117"] = true,
			["prep-c0118"] = true,
			["prep-c0121"] = true,
			["impl-c0116"] = true,
			["impl-c0117"] = true,
			["impl-c0118"] = true,
			["impl-c0121"] = true,
		},
		approved = {
			["proto-c0116"] = true,
			["proto-c0117"] = true,
			["proto-c0118"] = true,
			["proto-c0121"] = true,
		},
		paths = { ".claude/skills", "z-nile/skills", "pickman/skills" },
		pinned = c0115Move,
		history = false,
	},
}

-- Why the freeze `fr` ignores the branch `ref` (a full refname, as compact.busyRefNames gives it), or nil. Only
-- `refs/remotes/origin/` loses its `origin/`: a local branch named `origin/proto-c0117` is not proto-c0117 (c0120 code
-- review 011 F5).
local function ignoredBy(fr: Freeze, ref: string): string?
	local name = string.match(ref, "^refs/remotes/origin/(.+)$")
		or string.match(ref, "^refs/heads/(.+)$")
		or ref
	if fr.approved[name] then
		return "approved by name"
	end
	if fr.roots[name] then
		return fr.roots[name]
	end
	if fr.stacked[name] then
		return "stacked on its prep"
	end
	local pinned = if fr.pinned then fr.pinned() else nil
	if pinned and sh.run("git", { "merge-base", "--is-ancestor", pinned, ref }).ok then
		return "holds its move"
	end
	if not fr.history then
		return nil
	end
	local roots: { string } = {}
	for root in fr.roots do
		table.insert(roots, root)
	end
	table.sort(roots)
	for _, root in roots do
		local remote = `refs/remotes/origin/{root}`
		if sh.run("git", { "rev-parse", "--verify", "-q", remote }).ok then
			local base = sh.trim(sh.run("git", { "merge-base", ref, remote }).stdout)
			if
				base ~= ""
				and not sh.run("git", { "merge-base", "--is-ancestor", base, "refs/remotes/origin/main" }).ok
			then
				return fr.roots[root]
			end
		end
	end
	return nil
end

-- whether every path in `pos` is one of `inside` or under one, by whole segments ("./" and a trailing "/" ignored;
-- a path with a ".." segment is never inside: c0115 design review 014 F4)
local function allInside(pos: { string }, inside: { string }): boolean
	for _, p in pos do
		local n = string.gsub(string.gsub(p, "^%./", ""), "/+$", "")
		if n == ".." or string.find(`/{n}/`, "/../", 1, true) then
			return false
		end
		local ok = false
		for _, top in inside do
			if n == top or string.sub(n, 1, #top + 1) == `{top}/` then
				ok = true
				break
			end
		end
		if not ok then
			return false
		end
	end
	return true
end

-- The freezes that are on: `./zn busy` was given paths, all inside the move's own, and origin/main still holds the
-- move's mark. Without paths (compaction's set), or once a move lands, nothing is exempt for it, so busy agrees with
-- `./zn compact` and a later branch reusing one of these names blocks like any other (c0120 code review 011 F1).
local function freezesOn(pos: { string }): { Freeze }
	local on: { Freeze } = {}
	if #pos == 0 then
		return on
	end
	for _, fr in FREEZES do
		if
			allInside(pos, fr.paths)
			and sh.run("git", { "cat-file", "-e", `refs/remotes/origin/main:{fr.mark}` }).ok
		then
			table.insert(on, fr)
		end
	end
	return on
end

-- the first freeze that ignores `ref`: its item and why, or nil
local function frozenOut(freezes: { Freeze }, ref: string): (string?, string?)
	for _, fr in freezes do
		local why = ignoredBy(fr, ref)
		if why then
			return fr.item, why
		end
	end
	return nil, nil
end

-- What holds `paths` (c0120): every raft active on origin/main (but the current branch's own), every branch that
-- changes them since it left origin/main (compaction's check, compact.busyRefNames) and every other worktree with
-- uncommitted changes under them. c0120's raft is readied only when `./zn busy tracker src tests` prints nothing.
-- While a move's freeze is on (freezesOn: c0120's, c0115's), a branch it ignores, a worktree on one, and an active raft
-- that lists the item, are named on stderr and not counted.
function cmd.busy(pos: { string })
	local current = sh.trim(sh.run("git", { "branch", "--show-current" }).stdout)
	local own = string.match(current, "^(R%d%d%d%d)%-")
	local paths = if #pos > 0 then pos else compactLib.guarded()
	local found = 0
	local ok, tree = originTree()
	if not ok then
		fail("busy: cannot read origin/main (git fetch origin main)")
	end
	local freezes = freezesOn(pos)
	local seen: { [string]: boolean } = {}
	for _, p in tree do
		local r = string.match(p, "/rafts/active/(R%d%d%d%d)/")
			or string.match(p, "^rafts/active/(R%d%d%d%d)/")
		if r and r ~= own and not seen[r] then
			seen[r] = true
			-- a move's own raft, readied for it, is no freeze on it: its document on origin/main lists the item
			-- (c0120's branch is impl2-c0120, not named by the raft)
			local doc = string.match(p, "^(.*/rafts/active/R%d%d%d%d)/")
				or string.match(p, "^(rafts/active/R%d%d%d%d)/")
			local text = sh.run("git", { "show", `refs/remotes/origin/main:{doc}/{r}.md` }).stdout
			local members =
				`,{(string.gsub(string.match(text, "\nissues:%s*%[([^%]]*)%]") or "", "%s", ""))},`
			local ownOf: string? = nil
			for _, fr in freezes do
				if string.find(members, `,{fr.item},`, 1, true) then
					ownOf = fr.item
					break
				end
			end
			if ownOf then
				stdio.ewrite(`ignored for {ownOf}'s freeze: raft {r} ({ownOf}'s own)\n`)
			else
				print(`raft {r} is active`)
				found += 1
			end
		end
	end
	for _, ref in compactLib.busyRefNames(current, paths) do
		local short = compactLib.shortRef(ref)
		local item, why = frozenOut(freezes, ref)
		if item then
			stdio.ewrite(`ignored for {item}'s freeze: {short} ({why})\n`)
		else
			print(`branch {short} changes {table.concat(paths, ", ")}`)
			found += 1
		end
	end
	local here = sh.trim(sh.run("pwd", { "-P" }).stdout)
	for _, wt in compactLib.dirtyWorktrees(here, paths) do
		-- a worktree on a branch the freeze ignores is ignored with it (the same function); a detached one is not
		local on = sh.trim(sh.run("git", { "-C", wt, "branch", "--show-current" }).stdout)
		local item, why = nil :: string?, nil :: string?
		if on ~= "" then
			item, why = frozenOut(freezes, `refs/heads/{on}`)
		end
		if item then
			stdio.ewrite(`ignored for {item}'s freeze: worktree {wt} on {on} ({why})\n`)
		else
			print(`worktree {wt} has uncommitted changes under {table.concat(paths, ", ")}`)
			found += 1
		end
	end
	if found > 0 then
		process.exit(1)
	end
end

-- Prints every item it can read, both copies of a duplicated id included, then fails on the problems that stop
-- store.find (c0880): the other commands refuse such a tree, so `list` says where the trouble is.
-- The project `list` shows (c0114): --project's, else the one whose folder holds the directory ./zn was run from;
-- nil (every project) at the checkout's root or in a folder no project holds. Decided with the user (2026-10-21):
-- "list shows all projects": only the commands that create an item, and so must choose its project, refuse there; reading needs none.
local function listedRoot(opts: { [string]: { string } }): string?
	if opts["--project"] then
		return projectRoot(opts, "list")
	end
	local p = projects.inDir(projects.load(), hereDir())
	return if p then p.root else nil
end

function cmd.list(pos: { string }, opts: { [string]: { string } })
	local only = listedRoot(opts)
	local found = audit.scan(".")
	if only then
		local kept = {}
		for _, f in found do
			if string.sub(f.path, 1, #only + 1) == only .. "/" then
				table.insert(kept, f)
			end
		end
		found = kept
	end
	table.sort(found, function(a, b)
		return if a.id == b.id then a.path < b.path else a.id < b.id
	end)
	for _, kind in { "raft", "issue" } do
		for _, f in found do
			local doc = `{f.path}/{f.id}.md`
			if f.kind == kind and idsLib.spaceOf(f.id) == kind and fs.isFile(doc) then
				-- review 003 F3: a retired raft is shown as retired, never as a live backlog raft no command takes
				local state = if string.find(f.path .. "/", "/rafts/retired/", 1, true)
					then "retired"
					else stateOfPath(f.path .. "/")
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
		local root, under = projects.rootOf(path, store.roots())
		local kindDir, state, id = nil, nil, nil
		if root and under then
			kindDir, state, id = string.match(under, "^(%a+)/(%a+)/([^/]+)$")
			if not kindDir then
				kindDir, id = string.match(under, "^(%a+)/([^/]+)$")
				state = nil
			end
		end
		local space = id and idsLib.spaceOf(id)
		local want = if kindDir == "issues" then "issue" elseif kindDir == "rafts" then "raft" else nil
		local okState = state == nil or state == "active" or state == "done"
		if not (id and space and space == want and okState and fs.isFile(`{path}/{id}.md`)) then
			fail(`renumber: {arg} is not an item directory (<root>/<issues|rafts>/[active/|done/]<id>)`)
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
			root = root :: string,
		}
	else
		local ok, got = pcall(store.get, arg)
		if not ok then
			local why = tostring(got)
			if string.find(why, "duplicate id", 1, true) then
				fail(
					`{why}\nrenumber one copy by its directory: ./zn renumber <directory> (not the one in done/)`
				)
			end
			fail(why)
		end
		item = got
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
			n = idsLib.nextFree(asSpace(kind), localCounters() :: idsLib.Counters, used)
		end
		if not n then
			n = store.nextAbove(kind, originMainIds(kind))
		end
		if (n :: number) > 9999 then
			fail("no number above 9999 is free")
		end
		new = store.formatId(string.sub(old, 1, 1), n :: number)
	end
	local dest = store.dirFor(item.kind, item.state, new :: string, item.root)
	if fs.isDir(dest) then
		fail(`{new} already exists`)
	end
	-- c0116 (review 003 F4): a grouped raft keeps its record of every member the rename touches
	keepRecords(".", { [old] = new :: string }, function()
		local tracked = sh.run("git", { "ls-files", "--error-unmatch", item.doc }).ok
		if tracked then
			sh.git({ "mv", item.dir, dest })
			sh.git({ "mv", `{dest}/{old}.md`, `{dest}/{new}.md` })
		else
			fs.move(item.dir, dest)
			fs.move(`{dest}/{old}.md`, `{dest}/{new}.md`)
		end
		if byDir then
			rewriteUnder(dest, old, new :: string)
		else
			-- every reference, in every project's documents: ids are unique across the roots
			for _, r in store.roots() do
				if fs.isDir(r) then
					rewriteUnder(r, old, new :: string)
				end
			end
		end
	end)
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
			`compact: these branches change a project root (tracker/, z-nile/.tracker/, ...) or tests/acceptance/: {table.concat(
				busy,
				", "
			)}\n` .. "land or delete them first, or pass --force and run ./zn remap on each"
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
		local space: string = idsLib.spaceOf(f.id) or "issue"
		counts[space] += 1
	end
	local map = idsLib.plan(all)
	keepRecords(".", map, function()
		compactLib.apply(map, found)
	end)
	fs.writeFile(idsLib.FILE, idsLib.format({ issue = counts.issue + 1, raft = counts.raft + 1 }, phrase()))
	-- a compaction before origin moved the counter moves it too: the old file becomes the tombstone (c0114)
	if fs.isFile(idsLib.OLD_FILE) and idsLib.parse(fs.readFile(idsLib.OLD_FILE)) then
		fs.writeFile(idsLib.OLD_FILE, idsLib.TOMBSTONE)
	end
	fs.writeFile(idsLib.MAP_FILE, idsLib.formatMap(map, `./zn compact, {today()}, from origin/main {base}`))
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
		print(`in flight: {table.concat(busy, ", ")}: on each, run ./zn remap before merging origin/main`)
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
	-- a remap whose merge conflicted kept its commit but has no local map yet: its ids are already the new ones, and a
	-- second remap would renumber them again (R0270 review 001 F6)
	local since = sh.git({ "log", "--format=%s", `{sh.git({ "merge-base", "HEAD", "origin/main" })}..HEAD` })
	for subject in string.gmatch(since, "[^\n]+") do
		if subject == "tracker: remap ids" then
			fail(
				"remap: this branch already ran remap; finish it with git merge origin/main and resolve by hand"
			)
		end
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
			local n = idsLib.nextFree(asSpace(space), c, used)
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
			local r = published(publish.commit(".", function(paths, read, _roots, counter)
				local c = idsLib.parse(read(counter) or "")
				if not c then
					return `origin/main has no usable {counter}`
				end
				local used = idsOf(paths, "issue")
				for _, id in idsOf(paths, "raft") do
					table.insert(used, id)
				end
				return { { path = counter, content = idsLib.format(number(c, used), phrase()) } }
			end, "tracker: reserve numbers for a remap"))
			if not r.ok then
				fail(`remap: could not reserve numbers on origin/main: {r.reason}`)
			end
		else
			local _, paths = originTree()
			local live = sh.run("git", { "show", `origin/main:{idsLib.FILE}` })
			if not live.ok then
				live = sh.run("git", { "show", `origin/main:{idsLib.OLD_FILE}` }) -- origin has not moved it yet
			end
			local c = idsLib.parse(live.stdout)
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
	keepRecords(".", m, function()
		compactLib.apply(m, found)
	end)
	local problems = audit.run(".")
	if audit.errors(problems) > 0 then
		for _, p in problems do
			stdio.ewrite(audit.format(p) .. "\n")
		end
		sh.git({ "reset", "--quiet", "--hard", "HEAD" })
		fail("remap: the remapped tree fails the audit (above); nothing was committed")
	end
	sh.git({ "add", "-A" })
	sh.git({ "commit", "--quiet", "-m", "tracker: remap ids" })
	-- Then merge origin/main against the merge base with the same map applied: every path then matches on all three
	-- sides, so git never has to guess a rename (similar documents, such as stubs, get paired wrongly).
	local mb = sh.git({ "merge-base", "HEAD", "origin/main" })
	-- in a fresh temporary folder, never at a fixed name under .cache: a spec may have swapped a link in there, and git
	-- would build (and remove) the worktree through it (R0026 review 001 F2)
	local tmpBase = string.gsub(process.env.TMPDIR or "", "/+$", "")
	local scratch = `{sh.must(
		"mktemp",
		{ "-d", `{if tmpBase == "" then "/tmp" else tmpBase}/tracker-remap-base.XXXXXX` }
	)}/base`
	-- any failure here leaves the scratch worktree removed and says what to do (R0270 review 001 F5)
	local built, baseTree = pcall(function(): string
		sh.git({ "worktree", "add", "-q", "--detach", scratch, mb })
		keepRecords(scratch, m, function()
			compactLib.apply(m, audit.scan(scratch), scratch)
		end)
		-- the scratch worktree's tracked state as a commit object, with no ref moved: empty when nothing changed
		local addBase = process.exec("git", { "add", "-A" }, { cwd = scratch })
		local saved = process.exec("git", { "stash", "create" }, { cwd = scratch })
		if not addBase.ok or not saved.ok then
			error(addBase.stderr .. saved.stderr, 0)
		end
		local commit = sh.trim(saved.stdout)
		local tree = process.exec(
			"git",
			{ "rev-parse", (if commit == "" then mb else commit) .. "^{tree}" },
			{ cwd = scratch }
		)
		if not tree.ok then
			error(tree.stderr, 0)
		end
		return sh.trim(tree.stdout)
	end)
	sh.run("git", { "worktree", "remove", "--force", scratch })
	sh.run("git", { "worktree", "prune" })
	pcall(fs.removeDir, (string.gsub(scratch, "/base$", "")))
	if not built then
		fail(
			`remap committed, but the remapped merge base could not be built ({baseTree}): git merge origin/main and resolve by hand`
		)
	end
	local mt = sh.run("git", { "merge-tree", `--merge-base={baseTree}`, "HEAD", "origin/main" }) -- writes a tree (two commits)
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
	-- every project root's three folders of each kind (c0114)
	local folders: { { root: string, kind: string, state: string } } = {}
	for _, r in store.roots() do
		for _, k in { "issues", "rafts" } do
			for _, st in { "", "active/", "done/" } do
				table.insert(folders, { root = r, kind = k, state = st })
			end
		end
	end
	for _, folder in folders do
		local kind, state = folder.kind, folder.state
		do
			local base = `{folder.root}/{kind}/{state}`
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

-- c0248: every open layer pull request of the raft carries the raft's Theme, its Order and the stack. A view of git,
-- never state: a failed edit warns and the command goes on.
local function refreshPrBodies(raft: store.Item)
	if not hasOrigin() or not onGitHub() then
		return
	end
	local ok, err = pcall(function()
		local rows = layergit.rows(raft)
		local numbers: { [number]: string } = {}
		for _, row in rows do
			if row.state ~= "landed" and row.state ~= "missing" then
				local listed = sh.run("gh", {
					"pr",
					"list",
					"--head",
					row.name,
					"--state",
					"open",
					"--json",
					"number",
					"-q",
					".[0].number",
				})
				local number = if listed.ok then sh.trim(listed.stdout) else ""
				if number ~= "" and number ~= "null" then
					numbers[row.position] = number
					row.pr = `#{number}`
				end
			end
		end
		local doc = fs.readFile(raft.doc)
		local theme = stack.firstParagraph(layergit.raftSection(doc, "Theme"))
		local order = layergit.raftSection(doc, "Order & dependencies")
		local raftTitle = store.readFront(raft.doc).title or raft.slug
		for position, number in numbers do
			local body = stack.prBody({
				raftId = raft.id,
				title = raftTitle,
				theme = theme,
				order = order,
				rows = rows,
				here = position,
			})
			local edited = sh.run("gh", { "pr", "edit", number, "--body-file", "-" }, body)
			if not edited.ok then
				stdio.ewrite(
					`warning: could not refresh the body of pull request #{number}: {sh.trim(edited.stderr)}\n`
				)
			end
		end
	end)
	if not ok then
		stdio.ewrite(`warning: could not refresh the pull request bodies: {err}\n`)
	end
end

-- Pushes the layer and opens its draft PR (when the origin is on GitHub): the end of every start.
local function pushAndOpenPr(
	raft: store.Item,
	members: { store.Item },
	branch: string,
	ftitle: string,
	reuse: boolean?,
	base: string?,
	prTitle: string?
)
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
		-- a readied raft that was stopped and readied again keeps its branch and open PR: reuse it (review 001 F3)
		local open = if not reuse
			then { ok = false, stdout = "" }
			else sh.run(
				"gh",
				{ "pr", "list", "--head", branch, "--state", "open", "--json", "url", "-q", ".[0].url" }
			)
		local existing = if open.ok then sh.trim(open.stdout) else ""
		if existing ~= "" and existing ~= "null" then
			print(`draft PR (already open): {existing}`)
			return
		end
		local heading = prTitle or `{raft.id}: {ftitle}`
		local create = {
			"pr",
			"create",
			"--draft",
			"--base",
			base or "main",
			"--head",
			branch,
			"--title",
			heading,
			"--body",
			body,
		}
		local url = sh.must("gh", create)
		print(`draft PR: {url}`)
	else
		print("no origin remote: skipped push and draft PR")
	end
end

function cmd.start(pos: { string })
	local raft = store.get(pos[1] or fail("usage: start <R-id>"))
	if raft.kind ~= "raft" then
		fail("only rafts are started; make a `--single` raft with `new raft ... --single` (z-design)")
	end
	if raft.state == "active" then
		-- a readied raft: ready claimed it and moved it to active/ on origin/main, so start only branches
		if sh.git({ "status", "--porcelain" }) ~= "" then
			fail("working tree is not clean")
		end
		if hasOrigin() then
			sh.git({ "fetch", "--quiet", "origin", "main" })
			local _, originFiles = originTree()
			local theirs = docPath(originFiles, raft.id)
			local shown = if theirs then sh.run("git", { "show", `origin/main:{theirs}` }) else nil
			local readied = shown ~= nil
				and shown.ok
				and stateOfPath(theirs :: string) == "active"
				and statusLib.effective(frontOf(shown.stdout), "active") == "active"
			if not readied then
				fail(`{raft.id} is not readied on origin/main: run ./zn ready {raft.id} in the main checkout`)
			end
		end
		local issue, _, branch, startAt, prBase = layergit.startLayer(raft)
		if startAt ~= "" then
			refuseInMainCheckout("start")
			if layergit.shaOf(`refs/heads/{branch}`) or layergit.shaOf(`refs/remotes/origin/{branch}`) then
				fail(`{issue.id} is claimed on {branch}`)
			end
			sh.git({ "switch", "-c", branch, startAt })
			local ftitle = store.readFront(raft.doc).title or raft.slug
			sh.git({ "commit", "--quiet", "--allow-empty", "-m", `tracker: start {raft.id} {ftitle}` })
		end
		local members = store.members(raft.id)
		local ftitle = store.readFront(raft.doc).title or raft.slug
		print(`on branch {branch}; {raft.id} and {#members} issue(s) are active`)
		pushAndOpenPr(raft, members, branch, ftitle, true, prBase, `{issue.id}: {layergit.issueTitle(issue)}`)
		refreshPrBodies(raft)
		return
	end
	if raft.state ~= "backlog" then
		fail(`{raft.id} is already {raft.state}`)
	end
	if sh.git({ "status", "--porcelain" }) ~= "" then
		fail("working tree is not clean")
	end
	if publishing() then
		-- a worktree made before `ready` still has the raft in the backlog
		sh.git({ "fetch", "--quiet", "origin", "main" })
		local _, originFiles = originTree()
		local theirs = docPath(originFiles, raft.id)
		if theirs and stateOfPath(theirs) == "active" then
			fail(`{raft.id} is readied on origin/main: run ./zn sync first`)
		end
	end
	local members = store.members(raft.id)
	for _, m in members do
		if store.readFront(m.doc).design ~= "ready" then
			fail(`{m.id} is not design: ready (run z-design first)`)
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
	local issue, _, branch, startAt, prBase = layergit.startLayer(raft)
	local prTitle = `{issue.id}: {layergit.issueTitle(issue)}`
	-- every local precondition first: a refusal after the claim would leave origin saying `active`
	local onBranch = startAt == "" or sh.git({ "branch", "--show-current" }) == branch
	if not onBranch then
		refuseInMainCheckout("start")
		if layergit.shaOf(`refs/heads/{branch}`) or layergit.shaOf(`refs/remotes/origin/{branch}`) then
			fail(`{issue.id} is claimed on {branch}`)
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
		-- a resumed start keeps this terminal's earlier claim while the raft on origin/main still carries it, so every
		-- member it claims now carries the raft's value (review 004 F2); any other claim is new on origin/main
		local raftOnOrigin = docPath(select(2, originTree()), raft.id)
		local carried = if raftOnOrigin
			then frontOf(sh.run("git", { "show", `origin/main:{raftOnOrigin}` }).stdout).status
			else nil
		local claim = if mine ~= "" and carried == mine then mine else claimStamp()
		-- written before the push: a start that dies right after it can then be resumed by this terminal
		sh.writeReplacing(claimFile(raft.id), claim)
		local raftPath: string? = nil
		refuseStale()
		local r = published(publish.commit(".", function(paths, read)
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
		end, `tracker: start {raft.id}`))
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
		sh.git({ "switch", "-c", branch, startAt })
	end
	raft = move(raft, "active")
	for _, m in members do
		move(m, "active")
	end
	local ftitle = store.readFront(raft.doc).title or raft.slug
	sh.git({ "commit", "--quiet", "-m", `tracker: start {raft.id} {ftitle}` })
	print(`on branch {branch}; {raft.id} and {#members} issue(s) are active`)
	pushAndOpenPr(raft, members, branch, ftitle, nil, prBase, prTitle)
end

-- One commit for the layer the working tree is on. Worker commits stay until this.
function cmd.finish(pos: { string })
	local id = pos[1] or fail("usage: finish <issue-id>")
	if sh.git({ "status", "--porcelain" }) ~= "" then
		fail("commit everything first (./zn commit); finish needs a clean tree")
	end
	local issue = store.get(id)
	if issue.kind ~= "issue" then
		fail(`{id} is not an issue`)
	end
	local branch = sh.git({ "branch", "--show-current" })
	local parsed = stack.parse(branch)
	if not parsed or parsed.issue ~= id then
		fail(`finish {id} on its layer branch (this is {branch})`)
	end
	local layer = parsed :: stack.Layer
	if hasOrigin() then
		sh.git({ "fetch", "--quiet", "origin" })
	end
	local raft = store.get(layer.raft)
	local issues = layergit.orderedMembers(raft)
	local base = layergit.mainTip()
	if layer.position > 1 then
		local below = issues[layer.position - 1]
		if not below then
			fail(`{raft.id} has no issue at layer {layer.position - 1}`)
		end
		local belowName = stack.branch(raft.id, layer.position - 1, below.id)
		local belowTip = layergit.layerTip({
			raft = raft.id,
			position = layer.position - 1,
			issue = below.id,
			name = belowName,
		})
		local belowLanded = layergit.landed(below.id)
		if not belowTip and not belowLanded then
			fail(`{belowName} does not exist: finish the layer below first`)
		end
		-- a landed layer below may have lost its branch: the layer is then built on a commit main holds
		base = layergit.baseOf(layer.position, belowTip, belowLanded, "HEAD")
			or fail(`{belowName} does not exist: finish the layer below first`)
	end
	if not sh.run("git", { "merge-base", "--is-ancestor", base, "HEAD" }).ok then
		fail(`{branch} is not based on the layer below: ./zn restack {raft.id}`)
	end
	local onMain = sh.run("git", { "cat-file", "-e", `refs/remotes/origin/main:{approval.file(issue)}` }).ok
	local drift = approval.refusal(".", issue, onMain)
	if drift then
		fail(drift)
	end
	if not runCheck(issue) then
		fail(`{id} check.sh failed; not finished`)
	end
	local paths = layergit.diffPaths(base)
	if #paths == 0 then
		fail(`{id}: nothing to finish`)
	end
	watchcmd.capture({ id = id, dest = `{issue.dir}/acceptance` }, paths)
	local resultsOut = `{issue.dir}/results.txt`
	sh.writeReplacing(resultsOut, "")
	if gateLib.doneGate(process.env) == "promoted" then
		print("finish: inside a spec run, so the affected specs are skipped")
	else
		-- The same path the affected gate uses: one project's home per selection. tests/run from the
		-- repository root is not a project's home, so it refuses every spec.
		local reg = projects.load(".")
		for _, project in reg.projects do
			local argv = { "run", "z-nile/affected", "--", "--project", project.name }
			for _, path in paths do
				table.insert(argv, path)
			end
			local listed = sh.run("lune", argv)
			if not listed.ok then
				pcall(fs.removeFile, resultsOut)
				fail(`affected failed: {listed.stderr}`)
			end
			local specs: { string } = {}
			for line in string.gmatch(listed.stdout .. "\n", "([^\n]*)\n") do
				if line ~= "" then
					table.insert(specs, line)
				end
			end
			if #specs > 0 then
				local run = {
					"run",
					"z-nile/specs",
					"--",
					"run",
					"--project",
					project.name,
					"--out",
					resultsOut,
					"--",
				}
				for _, spec in specs do
					table.insert(run, spec)
				end
				if not sh.stream("lune", run) then
					pcall(fs.removeFile, resultsOut)
					fail(`{id}: a spec the watch map selects is red`)
				end
			end
		end
	end
	local saved = sh.git({ "rev-parse", "HEAD" })
	sh.git({ "reset", "--soft", base })
	sh.git({ "add", "-A" })
	if sh.git({ "diff", "--cached", "--name-only" }) == "" then
		sh.git({ "reset", "--hard", saved })
		fail(`{id}: nothing to finish`)
	end
	local message = stack.finishSubject(id, layergit.issueTitle(issue))
	sh.git({ "commit", "--quiet", "-m", message })
	if hasOrigin() then
		if not stack.owns(branch, raft.id) then
			fail(`{branch} is not a layer of {raft.id}`)
		end
		local remote = layergit.shaOf(`origin/{branch}`)
		if remote then
			sh.git({
				"push",
				"--quiet",
				`--force-with-lease=refs/heads/{branch}:{remote}`,
				"origin",
				branch,
			})
		else
			sh.git({ "push", "--quiet", "-u", "origin", branch })
		end
	end
	print(`finished {branch}: {message}`)
	refreshPrBodies(raft)
end

-- Rebase every layer onto the tip below it. A conflict or a red check.sh stops at that layer.
function cmd.restack(pos: { string })
	local raft = store.get(pos[1] or fail("usage: restack <R-id>"))
	if raft.kind ~= "raft" then
		fail(`{raft.id} is not a raft`)
	end
	if sh.git({ "status", "--porcelain" }) ~= "" then
		fail("working tree is not clean")
	end
	if hasOrigin() then
		sh.git({ "fetch", "--quiet", "origin" })
	end
	local why = layergit.oldShapeRefusal(raft)
	if why then
		fail(why)
	end
	local layers = layergit.layersOf(raft.id)
	if #layers == 0 then
		fail(`{raft.id} has no layers`)
	end
	local back = sh.git({ "branch", "--show-current" })
	local below = layergit.mainTip()
	local moved = false
	local landedIssue: { [string]: boolean } = {}
	local landedPos: { [number]: boolean } = {}
	for i, issue in layergit.orderedMembers(raft) do
		landedIssue[issue.id] = layergit.landed(issue.id)
		landedPos[i] = landedIssue[issue.id]
	end
	for _, layer in layers do
		if landedIssue[layer.issue] then
			-- landed: main holds it, and the layer above is stacked while the commit it was built on is reachable
			below = layergit.mainTip()
			continue
		end
		local onto = if layer.position == 1 then layergit.mainTip() else below
		local tip = layergit.layerTip(layer) or fail(`{layer.name} has no tip`)
		if
			layer.position > 1
			and landedPos[layer.position - 1] == true
			and layergit.baseOf(layer.position, nil, true, tip) ~= nil
		then
			below = tip
			continue
		end
		if stack.alreadyStacked(sh.run("git", { "merge-base", "--is-ancestor", onto, tip }).ok) then
			below = tip
			continue
		end
		local fork = sh.run("git", { "merge-base", tip, onto })
		if not fork.ok then
			fail(`restack stopped at {layer.name}: no common base`)
		end
		local tipSubject = sh.trim(sh.git({ "log", "-1", "--format=%s", tip }))
		local tipParent = sh.trim(sh.git({ "rev-parse", `{tip}^` }))
		local parentInLower = sh.run("git", { "merge-base", "--is-ancestor", tipParent, onto }).ok
		local raw = sh.git({
			"log",
			"--reverse",
			"--format=%s%x00%P",
			`{sh.trim(fork.stdout)}..{tip}`,
		})
		local rows: { stack.CommitRow } = {}
		for subject, parents in string.gmatch(raw .. "\n", "(.-)%z(.-)\n") do
			local text = if type(parents) == "string" then parents else ""
			local matched = string.match(text, "%S+")
			local parent: string = if type(matched) == "string" then matched else ""
			table.insert(
				rows,
				{ subject = if type(subject) == "string" then subject else "", parent = parent }
			)
		end
		local upstream = stack.rebaseUpstream(
			layer.issue,
			raft.id,
			tipSubject,
			tipParent,
			parentInLower,
			rows
		) or sh.trim(fork.stdout)
		layergit.checkoutLayer(layer)
		sh.git({ "reset", "--hard", tip })
		local before = tip
		local rebasing = sh.run("git", { "rebase", "--onto", onto, upstream, layer.name })
		if not rebasing.ok then
			sh.run("git", { "rebase", "--abort" })
			if back ~= "" then
				sh.git({ "switch", "--quiet", back })
			end
			fail(`restack stopped at {layer.name}: conflict\n{rebasing.stderr}`)
		end
		local issue = store.find(layer.issue)
		if not issue or not runCheck(issue) then
			sh.git({ "reset", "--hard", before })
			if back ~= "" then
				sh.git({ "switch", "--quiet", back })
			end
			fail(`restack stopped at {layer.name}: {layer.issue} check.sh failed`)
		end
		if hasOrigin() then
			if not stack.owns(layer.name, raft.id) then
				fail(`{layer.name} is not a layer of {raft.id}`)
			end
			local remote = layergit.shaOf(`origin/{layer.name}`) or before
			sh.git({
				"push",
				"--quiet",
				`--force-with-lease=refs/heads/{layer.name}:{remote}`,
				"origin",
				layer.name,
			})
		end
		below = sh.git({ "rev-parse", "HEAD" })
		moved = true
	end
	if back ~= "" and sh.git({ "branch", "--show-current" }) ~= back then
		sh.git({ "switch", "--quiet", back })
	end
	if moved then
		print(`restacked {raft.id}`)
	else
		print(`{raft.id} is already stacked`)
	end
	refreshPrBodies(raft)
end

-- What another clone can see: the layers, from git, after a fetch. No local file is the authority.
function cmd.stack(pos: { string })
	local raftId = pos[1] or fail("usage: stack <R-id>")
	if hasOrigin() then
		local fetched = sh.run("git", { "fetch", "--quiet", "origin" })
		if not fetched.ok then
			fail(`stack: fetch failed: {sh.trim(fetched.stderr)}`)
		end
	end
	local raft = store.find(raftId) or fail(`{raftId} is not in this tree`)
	if raft.kind ~= "raft" then
		fail(`{raftId} is not a raft`)
	end
	local rows = layergit.rows(raft)
	print(stack.render(raftId, rows))
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

-- Two paths overlap when they are equal or one is a parent directory of the other, by whole components (one rule,
-- shared with z-raft's plan, c0116).
local overlaps = raftplan.overlaps

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

-- `raft-plan [--apply]` (c0116, z-raft with no argument): prints the plan for every prepared, raftless issue as the
-- commands that carry it out, one per line (`./zn fold …`, `./zn new raft …`), and `skip <id>: <why>` for an issue it
-- cannot place. Read-only; `--apply` runs the commands in this worktree, in order. The policy is raftplan.plan's.
cmd["raft-plan"] = function(pos: { string }, opts: { [string]: { string } })
	if #pos > 0 then
		fail("usage: raft-plan [--apply]")
	end
	if opts["--apply"] then
		refuseInMainCheckout("raft-plan --apply")
	end
	local issues: { raftplan.Issue } = {}
	local slugOf: { [string]: string } = {}
	for _, it in store.all("issue") do
		local front = frontOf(fs.readFile(it.doc))
		slugOf[it.id] = it.slug
		table.insert(issues, {
			id = it.id,
			type = store.typeOf(it),
			root = it.root,
			state = it.state,
			status = statusLib.effective(front, it.state),
			design = front.design,
			raft = front.raft or "",
			size = raftplan.parseSize(front.size),
			solo = front.solo == "true",
			touched = touchedModules(it),
		})
	end
	local rafts: { raftplan.Raft } = {}
	for _, r in store.all("raft") do
		local front = frontOf(fs.readFile(r.doc))
		local members: { string } = {}
		for _, m in store.members(r.id) do
			table.insert(members, m.id)
		end
		table.insert(rafts, {
			id = r.id,
			type = store.typeOf(r),
			root = r.root,
			state = r.state,
			status = statusLib.effective(front, r.state),
			single = front.single == "true",
			members = members,
		})
	end
	local ops, skips = raftplan.plan(issues, rafts)
	-- since c0115 a new raft names its project: every command is built, and a root no project holds refused, before
	-- anything is printed or run (design review 006 F1)
	local reg = projects.load()
	local runs, why = raftplan.commands(ops, slugOf, function(root: string): string?
		local project = projects.projectOf(reg, root)
		return if project then project.name else nil
	end)
	if not runs then
		fail(why :: string)
	end
	for _, args in runs :: { { string } } do
		print(`./zn {table.concat(args, " ")}`)
	end
	for _, sk in skips do
		print(`skip {sk.id}: {sk.reason}`)
	end
	if #ops == 0 and #skips == 0 then
		print("raft-plan: nothing to raft (no prepared issue without a raft)")
	end
	if opts["--apply"] then
		for _, args in runs :: { { string } } do
			local rest = table.move(args, 2, #args, 1, {})
			local p, o = flags(rest);
			(cmd :: any)[args[1]](p, o)
		end
	end
end

function cmd.worktree(pos: { string }, opts: { [string]: { string } })
	local target = pos[1] or fail("usage: worktree <R-id|name>")
	local branch: string? = nil
	local detach = false
	local dirName: string
	if string.match(target, "^R%d%d%d%d$") then
		local missing = `{target} is not in this tree; if it was just merged, run {mainRoot()}/zn sync`
		local raft = store.find(target) or fail(missing)
		if raft.state == "done" then
			fail(`{target} is done`)
		end
		dirName = target
		-- A raft worktree is on its latest layer, or on no branch until start opens one.
		-- It does not create the old R####-<slug> branch.
		local layers = layergit.layersOf(raft.id)
		if #layers > 0 then
			branch = layers[#layers].name
		else
			detach = true
		end
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
		elseif branch and w.branch == branch then
			fail(`{branch} is already used by worktree at {w.path}`)
		end
	end
	local base = from
		or if sh.run("git", { "show-ref", "--verify", "--quiet", "refs/remotes/origin/main" }).ok
			then "origin/main"
			else "main"
	if detach then
		sh.git({ "worktree", "add", "--detach", path, base })
	elseif branch and sh.run("git", { "show-ref", "--verify", "--quiet", `refs/heads/{branch}` }).ok then
		local track = sh.git({ "for-each-ref", "--format=%(upstream:track)", `refs/heads/{branch}` })
		if track == "[gone]" then
			stdio.ewrite(
				`warning: the upstream of {branch} is gone (merged?); resuming it anyway: git branch -D {branch} gives a fresh start\n`
			)
		end
		sh.git({ "worktree", "add", path, branch })
	elseif
		branch and sh.run("git", { "show-ref", "--verify", "--quiet", `refs/remotes/origin/{branch}` }).ok
	then
		sh.git({ "branch", "--track", branch, `origin/{branch}` })
		sh.git({ "worktree", "add", path, branch })
	else
		-- --no-track: a bare `git push` must not target origin/main before start or landing sets the upstream
		sh.git({ "worktree", "add", "--no-track", "-b", branch :: string, path, base })
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
	-- a raft is finished when it is in done/ under any project root of the base branch (c0114)
	local baseReg, regErr = projects.at(base, root)
	if not baseReg then
		fail(`worktree-prune: {regErr}`) -- prune nothing rather than guess which rafts are done (c0114)
	end
	local doneRoots: { string } = projects.allRoots(baseReg :: projects.Registry)
	local function isDone(name: string): boolean
		for _, r in doneRoots do
			if sh.git({ "-C", root, "ls-tree", "-d", base, `{r}/rafts/done/{name}` }) ~= "" then
				return true
			end
		end
		return false
	end
	for _, w in worktrees() do
		local name = if string.sub(w.path, 1, #prefix) == prefix then string.sub(w.path, #prefix + 1) else nil
		if name and not string.find(name, "/", 1, true) then
			if not string.match(name, "^R%d%d%d%d$") then
				print(`kept {w.path} (named worktree: remove it when its PR has merged)`)
			elseif isDone(name) then
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

-- `--model <id>` of commit and spend (c0117): the model that spent the row's tokens; nil when not given.
local function modelOption(what: string, opts: { [string]: { string } }): string?
	if not opts["--model"] then
		return nil
	end
	local raw = opts["--model"][1]
	if #opts["--model"] > 1 or not ledger.isModel(raw) then
		fail(`{what} --model takes one model id (letters, digits, '.', '_' and '-')`)
	end
	return raw
end

local function recordAndCommit(
	raft: store.Item,
	message: string,
	issueIds: { string },
	explicitMinutes: number?,
	isDone: boolean?,
	phase: string?,
	tokens: number?,
	model: string?
)
	phase = if phase and phase ~= "" then phase else "build"
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
	-- Typed --time and the gap since the last commit are not stored. Line counts are the diff; wall, CPU,
	-- AI time and tokens are unmeasured here (a commit did not run the process it would time).
	local minutes = explicitMinutes or 0
	local shares = spend.attribute(issues, spend.stagedStats(isDone), minutes, how, tokens)
	local trailers: { string } = {}
	local foldHomes: { [string]: string } = {}
	local extraRows: { [string]: { ledger.Row } } = {}
	local keptAny = false
	for _, share in shares do
		-- The ticket is folded whether or not this commit adds a line-count row. A build share that moved no
		-- lines is still not given a row of its own.
		local issue = store.get(share.id)
		foldHomes[share.id] = issue.dir
		if
			phase == "build"
			and share.added + share.removed == 0
			and share.minutes < 0.1
			and (share.tokens or 0) == 0
		then
			continue
		end
		keptAny = true
		local row: ledger.Row = {
			when = os.date("!%Y-%m-%d %H:%M", os.time()) :: string,
			subject = string.match(message, "^[^\n]*") or message,
			added = share.added,
			removed = share.removed,
			minutes = 0,
			how = "measured",
			phase = phase :: string,
			tokens = nil,
			model = model,
			unmeasured = "tokens,wall,cpu,ai",
		}
		local list = extraRows[share.id]
		if not list then
			list = {}
			extraRows[share.id] = list
		end
		table.insert(list, row)
		local trailer =
			string.format("Issue: %s +%d/-%d %.1fm", share.id, share.added, share.removed, share.minutes)
		if phase ~= "build" then
			trailer ..= " " .. (phase :: string)
		end
		if share.tokens ~= nil then
			trailer ..= ` {share.tokens} tokens`
		end
		if model then
			trailer ..= ` {model}`
		end
		table.insert(trailers, trailer)
	end
	local top = sh.git({ "rev-parse", "--show-toplevel" })
	local planned = costrow.plan(top, foldHomes, extraRows, false)
	local folded = costrow.writeFiles(planned)
	if keptAny and #folded == 0 then
		fail("could not write the measured row")
	end
	spend.writeRaft(raft)
	for _, r in store.roots() do
		if fs.isDir(r) then
			sh.git({ "add", "-A", r })
		end
	end
	watchcmd.upkeep()
	local committed, commitErr = pcall(function()
		sh.git({ "commit", "--quiet", "-m", message, "-m", table.concat(trailers, "\n") })
	end)
	if not committed then
		pcall(costrow.restore, planned)
		error(commitErr, 0)
	end
	costrow.writeBuffer(top, planned)
	print(`committed: {message}\n  {table.concat(trailers, "\n  ")}`)
	push()
end

function cmd.commit(_pos: { string }, opts: { [string]: { string } })
	local message = opts["-m"] and opts["-m"][1]
	if not message or message == "" then
		fail("usage: commit -m <msg> [--issue <id>]... [--phase build|code-review|deliver] [--model <id>]")
	end
	-- phase and tokens are checked before anything is staged
	local phase = "build"
	if opts["--phase"] then
		phase = opts["--phase"][1]
		if phase == "capture" or phase == "prep" or phase == "design-review" then
			fail(`{phase} is recorded with ./zn spend`)
		elseif phase ~= "build" and phase ~= "code-review" and phase ~= "deliver" then
			fail("commit --phase is build, code-review or deliver")
		end
	end
	if opts["--tokens"] or opts["--time"] then
		stdio.ewrite("commit: --time and --tokens are ignored; cost is measured\n")
	end
	local model = modelOption("commit", opts)
	recordAndCommit(activeRaft(), message, opts["--issue"] or {}, nil, nil, phase, nil, model)
end

-- The project home of an item (c0120): where its check.sh runs and its specs are promoted to, from the working
-- tree's registry; "." for the root's project.
local function homeOf(item: store.Item): string
	return projects.homeOf(projects.load(), item.dir)
end

-- `<home>/<rel>`, or `<rel>` for the root's home.
local function inHome(home: string, rel: string): string
	return if home == "." then rel else `{home}/{rel}`
end

-- Where a member's acceptance specs are promoted to: its project's tests/acceptance/<id> (c0120).
local function promotedDir(m: store.Item): string
	return projects.promotedDir(projects.load(), m.root, m.id)
end

-- Copy each member's acceptance specs into its project's tests/acceptance/<id>, run `check`, then remove the
-- copies. Returns check's result. Used by `done` (for real) and `promote-check` (dry run). `check` gets the copied
-- spec paths, repo-relative.
-- The issues whose specs a promotion covers: a raft's members, or an issue by itself (c0116: z-design checks an
-- issue's promotion before it has a raft).
local function promotedItems(item: store.Item): { store.Item }
	return if item.kind == "issue" then { item } else store.members(item.id)
end

local function withPromotedCopies(raft: store.Item, check: ({ string }) -> boolean): boolean
	local copied: { string } = {}
	for _, m in promotedItems(raft) do
		local acc = `{m.dir}/acceptance`
		local dest = promotedDir(m)
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
	for _, m in promotedItems(raft) do
		local dest = promotedDir(m)
		if fs.isDir(dest) and not sh.run("git", { "ls-files", "--error-unmatch", dest }).ok then
			fs.removeDir(dest)
		end
	end
	if not pok then
		error(result, 0)
	end
	return ok
end

-- Structural checks promoted acceptance specs must pass in their project's tests/ (c0120: `home`): type check +
-- meta spec (+ the specs themselves when `runSpecs`), run from that home. `specs` are repo-relative.
local function promotedChecks(home: string, specs: { string }, runSpecs: boolean): boolean
	local ok = sh.stream("luau-lsp", {
		"analyze",
		"--base-luaurc=.luaurc",
		"--platform=standard",
		"--ignore=**/.tracker/**",
		inHome(home, "tests"),
	})
	local args = { "run", "tests/run", "--", "tests/meta/architecture.spec.luau" }
	if runSpecs then
		local prefix = if home == "." then "" else home .. "/"
		for _, p in specs do
			if string.sub(p, 1, #prefix) == prefix then
				table.insert(args, string.sub(p, #prefix + 1))
			end
		end
	end
	return sh.streamIn(home, "lune", args) and ok
end

-- promotedChecks for every home the specs land in (a raft's members share one project, c0114).
local function promotedChecksAll(raft: store.Item, specs: { string }, runSpecs: boolean): boolean
	local seen: { [string]: boolean } = {}
	local ok = true
	for _, m in promotedItems(raft) do
		local home = homeOf(m)
		if not seen[home] then
			seen[home] = true
			ok = promotedChecks(home, specs, runSpecs) and ok
		end
	end
	if next(seen) == nil then
		ok = promotedChecks(homeOf(raft), specs, runSpecs)
	end
	return ok
end

cmd["promote-check"] = function(pos: { string })
	local raft = store.get(pos[1] or fail("usage: promote-check <R-id|issue-id>"))
	print(`=== {raft.id}: dry-run promotion of acceptance specs (type check + meta)`)
	if
		not withPromotedCopies(raft, function(specs)
			-- c0116: say how many were copied, so a promotion that found nothing to copy is not mistaken for a clean one
			print(`copied {#specs} acceptance specs`)
			return promotedChecksAll(raft, specs, false)
		end)
	then
		fail("promoted acceptance specs would break tests/ (see above)")
	end
	print("promote-check OK")
end

-- Latest final review round must be resolved (completion.reviewProblem holds the rule, which a layer's review shares);
-- this reads the raft's files.
local function backlogIssue(id: string): boolean
	local item = store.find(id)
	return item ~= nil and item.kind == "issue" and item.state == "backlog"
end

local function reviewProblem(raft: store.Item): string?
	local reviewPrefix, refutePrefix, latest = layergit.latestReview(raft)
	local num = string.format("%03d", latest)
	local reviewPath = `{raft.dir}/{reviewPrefix}-{num}.md`
	local refutePath = `{raft.dir}/{refutePrefix}-{num}.md`
	return completion.reviewProblem(
		if latest > 0 then fs.readFile(reviewPath) else nil,
		if fs.isFile(refutePath) then fs.readFile(refutePath) else nil,
		if fs.isFile(raft.doc) then fs.readFile(raft.doc) else "",
		{
			kind = "final",
			reviewName = `{reviewPrefix}-{num}.md`,
			refuteName = `{refutePrefix}-{num}.md`,
			backlog = backlogIssue,
		}
	)
end

local function traceProblems(raft: store.Item, printSkeletonOnly: boolean?, through: string?): { string }
	local trace = require("./trace")
	local watch = require("../lib/watch")

	local function diffNamesBetween(base: string, tip: string): { string }
		local names = sh.git({ "diff", "--name-only", base, tip })
		local out: { string } = {}
		for path in string.gmatch(names .. "\n", "([^\n]*)\n") do
			if path ~= "" then
				table.insert(out, path)
			end
		end
		return out
	end

	local function gitFileTextAt(atCommit: string, path: string): string?
		local shown = sh.run("git", { "show", `{atCommit}:{path}` })
		if shown.ok then
			return shown.stdout
		end
		return nil
	end

	local function fileTextAt(atCommit: string, path: string, useWorktree: boolean): string?
		if useWorktree and fs.isFile(path) then
			return fs.readFile(path)
		end
		return gitFileTextAt(atCommit, path)
	end

	local function capturedDocText(issue: store.Item, atCommit: string): string
		local head = if sh.run("git", { "rev-parse", "--verify", "-q", "origin/main" }).ok
			then "origin/main"
			else atCommit
		local commits, _ = trailLib.read("issues", issue.id, trailLib.isDoc, head)
		local found = if commits then (trailLib.capture(commits)) else nil
		if found then
			local shown = sh.run("git", { "show", `{found.sha}:{found.path}` })
			if shown.ok then
				return shown.stdout
			end
		end
		return fileTextAt(atCommit, issue.doc, sh.git({ "rev-parse", "HEAD" }) == atCommit) or ""
	end

	local function buildTraceIssueDocs(issues: { store.Item }, atCommit: string): { trace.IssueDoc }
		local useWorktree = sh.git({ "rev-parse", "HEAD" }) == atCommit
		local out: { trace.IssueDoc } = {}
		for _, issue in issues do
			local checkPath = `{issue.dir}/check.sh`
			local resultsPath = `{issue.dir}/results.txt`
			local docText = fileTextAt(atCommit, issue.doc, useWorktree) or ""
			local checkText = gitFileTextAt(atCommit, checkPath)
			local resultsText = gitFileTextAt(atCommit, resultsPath)
			local captured = capturedDocText(issue, atCommit)
			table.insert(out, {
				id = issue.id,
				docPath = issue.doc,
				checkPath = checkPath,
				dirPath = issue.dir,
				home = homeOf(issue),
				capturedText = if captured ~= "" then captured else docText,
				docText = docText,
				checkText = checkText,
				resultsPath = resultsPath,
				resultsText = resultsText,
			})
		end
		return out
	end

	local function localOrOriginTip(layer: stack.Layer): string?
		local loc = layergit.shaOf(layer.name)
		local rem = layergit.shaOf(`origin/{layer.name}`)
		if loc and rem then
			if sh.run("git", { "merge-base", "--is-ancestor", rem, loc }).ok then
				return loc
			end
			return rem
		end
		return loc or rem
	end

	local function collectLayerCommits(base: string, tip: string): { trace.LayerCommit }
		local raw = sh.git({ "log", "--reverse", "--format=%H%x09%P%x09%s", `{base}..{tip}` })
		local out: { trace.LayerCommit } = {}
		for line in string.gmatch(raw .. "\n", "([^\n]+)\n") do
			local sha, parents, subject = string.match(line, "^(%x+)\t([^\t]*)\t(.*)$")
			if sha then
				local firstParent = string.match(parents or "", "^(%x+)") or ""
				local changed = sh.git({ "diff-tree", "--no-commit-id", "--name-only", "-r", sha })
				local files: { string } = {}
				for path in string.gmatch(changed .. "\n", "([^\n]+)\n") do
					if path ~= "" then
						table.insert(files, path)
					end
				end
				table.insert(out, {
					sha = sha,
					parent = firstParent,
					subject = subject or "",
					files = files,
				})
			end
		end
		return out
	end

	local issues = layergit.orderedMembers(raft)
	local layers = layergit.layersOf(raft.id)
	-- c0248: the layers a bind lands (the unlanded ones up to `through`); all of them when none has landed
	local firstPos = 1
	local baseTip = layergit.mainTip()
	do
		local ids: { string } = {}
		local landedMap: { [string]: boolean } = {}
		local landedAt: { [number]: boolean } = {}
		for i, issue in issues do
			table.insert(ids, issue.id)
			landedMap[issue.id] = layergit.landed(issue.id)
			landedAt[i] = landedMap[issue.id]
		end
		local bindIds, whyBind = stack.bindMembers(ids, landedMap, through)
		if not bindIds then
			if printSkeletonOnly then
				fail(whyBind :: string)
			end
			return { whyBind :: string }
		end
		local inBind: { [string]: boolean } = {}
		for _, id in bindIds do
			inBind[id] = true
		end
		local scopedIssues: { store.Item } = {}
		for i, issue in issues do
			if inBind[issue.id] then
				if #scopedIssues == 0 then
					firstPos = i
				end
				table.insert(scopedIssues, issue)
			end
		end
		local have: { [number]: stack.Layer } = {}
		local scopedLayers: { stack.Layer } = {}
		for _, layer in layers do
			have[layer.position] = layer
			if layer.position >= firstPos and layer.position < firstPos + #scopedIssues then
				table.insert(scopedLayers, layer)
			end
		end
		if firstPos > 1 then
			baseTip = layergit.baseFor(have, landedAt, firstPos) or baseTip
		end
		issues = scopedIssues
		layers = scopedLayers
	end
	if printSkeletonOnly then
		if #layers == 0 then
			fail(`{raft.id} has no layers: ./zn start {raft.id}`)
		end
		if #layers ~= #issues then
			fail(`{raft.id} has {#layers} layer(s) for {#issues} issue(s)`)
		end
		local onto = baseTip
		local topFinishSha = ""
		local topTip = ""
		for i, layer in layers do
			if layer.position ~= firstPos + i - 1 or layer.issue ~= issues[i].id then
				fail(`{raft.id} layer {firstPos + i - 1} is {layer.name}, expected {issues[i].id}`)
			end
			local tip = localOrOriginTip(layer) or fail(`{layer.name} has no tip`)
			if not sh.run("git", { "merge-base", "--is-ancestor", onto, tip }).ok then
				fail(`{layer.name} is not stacked on the layer below: ./zn restack {raft.id}`)
			end
			local finishSha = layergit.layerFinishSha(layer, onto, tip)
			if not finishSha then
				fail(`{layer.issue} is not finished: ./zn finish {layer.issue}`)
			end
			if i == #layers then
				topFinishSha = finishSha :: string
				topTip = tip
			end
			onto = tip
		end
		local issueDocs = buildTraceIssueDocs(issues, topTip)
		local changedSources = watch.sourceOf(diffNamesBetween(baseTip, topTip))
		local claims, claimErrors = trace.deriveClaims(issueDocs)
		if #claimErrors > 0 then
			fail(table.concat(claimErrors, "\n"))
		end
		stdio.write(trace.skeleton(raft.id, topFinishSha, claims, changedSources))
		return {}
	end

	if #layers == 0 then
		return { `{raft.id} has no layers: ./zn start {raft.id}` }
	end
	local topLayer = layers[#layers]
	local topTip = localOrOriginTip(topLayer)
	if not topTip then
		return { `{topLayer.name} has no tip` }
	end
	local useWorktree = sh.git({ "rev-parse", "HEAD" }) == topTip
	local tracePath = `{raft.dir}/trace.md`
	local tableText = fileTextAt(topTip, tracePath, useWorktree)
	if tableText == nil then
		return { `no {tracePath}: run ./zn trace {raft.id} and fill the table` }
	end

	local onto = baseTip
	local layerHistories: { trace.LayerHistory } = {}
	for _, layer in layers do
		local tip = localOrOriginTip(layer)
		local stacked = if tip ~= nil
			then sh.run("git", { "merge-base", "--is-ancestor", onto, tip }).ok
			else false
		local commits: { trace.LayerCommit } = if tip ~= nil and stacked
			then collectLayerCommits(onto, tip)
			else {}
		local issueItem = store.find(layer.issue)
		local layerTitle = if issueItem then layergit.issueTitle(issueItem) else layer.issue
		table.insert(layerHistories, {
			name = layer.name,
			issue = layer.issue,
			title = layerTitle,
			base = onto,
			tip = tip,
			stackedOnBelow = stacked,
			commits = commits,
		})
		if tip ~= nil then
			onto = tip
		end
	end

	local issueDocs = buildTraceIssueDocs(issues, topTip)
	local diffList = diffNamesBetween(baseTip, topTip)
	local changedSources = watch.sourceOf(diffList)

	local candidatePaths: { [string]: boolean } = {}
	for _, idoc in issueDocs do
		candidatePaths[idoc.docPath] = true
		candidatePaths[idoc.checkPath] = true
	end
	for _, src in changedSources do
		candidatePaths[src] = true
	end
	for refPath in string.gmatch(tableText, "([A-Za-z0-9_./%-]+):%d+") do
		candidatePaths[refPath] = true
	end

	local filesAtCommit: { [string]: trace.FileMeta } = {}
	for path in candidatePaths do
		local text = gitFileTextAt(topTip, path)
		if text ~= nil then
			filesAtCommit[path] = { lines = trace.splitLines(text) }
		end
	end

	local raftDocText = fileTextAt(topTip, raft.doc, useWorktree) or ""
	return trace.check({
		raftId = raft.id,
		raftDir = raft.dir,
		tableText = tableText,
		layers = layerHistories,
		issues = issueDocs,
		raftDocText = raftDocText,
		changedSources = changedSources,
		filesAtCommit = filesAtCommit,
	})
end

function cmd.trace(pos: { string }, opts: { [string]: { string } })
	for k in opts do
		if k ~= "--check" and k ~= "--through" then
			fail(`usage: trace <R-id> [--through <issue>] [--check] (unknown option {k})`)
		end
	end
	if #pos ~= 1 then
		fail("usage: trace <R-id> [--through <issue>] [--check]")
	end
	local through = if opts["--through"] then opts["--through"][1] else nil
	if through == "" then
		fail("usage: trace <R-id> [--through <issue>] [--check] (--through needs an issue id)")
	end
	local raftId = pos[1]
	if hasOrigin() then
		sh.run("git", { "fetch", "--quiet", "origin" })
	end
	local raft = store.get(raftId)
	if raft.kind ~= "raft" then
		fail(`{raft.id} is not a raft`)
	end
	if opts["--check"] then
		local findings = traceProblems(raft, nil, through)
		if #findings > 0 then
			stdio.ewrite(table.concat(findings, "\n") .. "\n")
			process.exit(1)
		end
		print(`ok: {raft.id}`)
		return
	end
	traceProblems(raft, true, through)
end

function cmd.done(pos: { string }, opts: { [string]: { string } })
	refuseListMode()
	for k in opts do
		if k ~= "--through" then
			fail(`usage: done <R-id> [--through <issue>] (unknown option {k})`)
		end
	end
	local through = if opts["--through"] then opts["--through"][1] else nil
	if through == "" then
		fail("usage: done <R-id> [--through <issue>] (--through needs an issue id)")
	end
	local raft = store.get(pos[1] or fail("usage: done <R-id> [--through <issue>]"))
	if raft.kind ~= "raft" or raft.state ~= "active" then
		fail(`{raft.id} must be an active raft`)
	end
	if sh.git({ "status", "--porcelain" }) ~= "" then
		fail("commit everything first (./zn commit); done needs a clean tree")
	end
	local whyOld = layergit.oldShapeRefusal(raft)
	if whyOld then
		fail(whyOld)
	end
	if hasOrigin() then
		sh.git({ "fetch", "--quiet", "origin" })
	end
	local issues = layergit.orderedMembers(raft)
	local layers = layergit.layersOf(raft.id)
	if #layers == 0 then
		fail(`{raft.id} has no layers: ./zn start {raft.id}`)
	end
	-- The commit that will be merged is the published top layer. The working tree has to be that
	-- commit before any check reads it: a lower layer, or a top layer behind origin, is a different tree.
	-- c0248: the layers this bind lands are the ones not yet landed, up to `through` (all of them without it)
	local orderedIds: { string } = {}
	local landedMap: { [string]: boolean } = {}
	local landedAt: { [number]: boolean } = {}
	for i, issue in issues do
		table.insert(orderedIds, issue.id)
		landedMap[issue.id] = layergit.landed(issue.id)
		landedAt[i] = landedMap[issue.id]
	end
	local bindIds, whyBind = stack.bindMembers(orderedIds, landedMap, through)
	if not bindIds then
		fail(whyBind :: string)
	end
	local bindSet: { [string]: boolean } = {}
	for _, id in bindIds :: { string } do
		bindSet[id] = true
	end
	local haveAt: { [number]: stack.Layer } = {}
	for _, layer in layers do
		haveAt[layer.position] = layer
	end
	local firstPos = 1
	for i, issue in issues do
		if bindSet[issue.id] then
			firstPos = i
			break
		end
	end
	local bindLayers: { stack.Layer } = {}
	for i = firstPos, firstPos + #(bindIds :: { string }) - 1 do
		if haveAt[i] then
			table.insert(bindLayers, haveAt[i])
		end
	end
	local anyLanded = firstPos > 1
	local wholeRaft = (bindIds :: { string })[#(bindIds :: { string })] == orderedIds[#orderedIds]
	local topLayer = bindLayers[#bindLayers] or layers[#layers]
	local land = layergit.layerTip(topLayer) or fail(`{topLayer.name} has no tip`)
	local here = sh.git({ "rev-parse", "HEAD" })
	local hereName = sh.git({ "branch", "--show-current" })
	if hereName == "" then
		hereName = "detached HEAD"
	end
	if here ~= land then
		fail(`{hereName} is {here} and {topLayer.name} is {land}: done checks the commit it lands`)
	end
	local problem = reviewProblem(raft)
	if problem then
		fail(problem)
	end
	if not runCheck(raft) then
		fail(`{raft.id} check.sh failed; not done`)
	end
	for _, m in store.members(raft.id) do
		if not bindSet[m.id] then
			continue
		end
		-- An approval `ready` published stays required: deleting approval.md on the branch is not a way
		-- past the check. An item readied before approval has none on origin/main and is left alone.
		local onMain = sh.run("git", { "cat-file", "-e", `refs/remotes/origin/main:{approval.file(m)}` }).ok
		local drift = approval.refusal(".", m, onMain)
		if drift then
			fail(drift)
		end
	end
	local verdict = layergit.reviewVerdict(raft)
	if not verdict then
		fail(`{raft.id} has no Verdict line: a verdict nobody wrote is not recorded`)
	end
	-- a final review of an earlier bind does not stand in for this bind's own (every landing has its own)
	local _, _, newest = layergit.latestReview(raft)
	if anyLanded and newest > 0 then
		local usedPath = `{raft.dir}/final-review-{string.format("%03d", newest)}.md`
		local ref = if layergit.shaOf("origin/main") then "origin/main" else "main"
		if sh.run("git", { "cat-file", "-e", `{ref}:{usedPath}` }).ok then
			fail(
				`{usedPath} belongs to a layer that already landed: write final-review-{string.format(
					"%03d",
					newest + 1
				)}.md for these layers`
			)
		end
	end
	local unlandedLayers = 0
	for _, layer in layers do
		if layer.position >= firstPos then
			unlandedLayers += 1
		end
	end
	if #bindLayers ~= #(bindIds :: { string }) or (through == nil and unlandedLayers ~= #bindLayers) then
		fail(`{raft.id} has {unlandedLayers} layer(s) for {#(bindIds :: { string })} issue(s)`)
	end
	for n, layer in bindLayers do
		local i = firstPos + n - 1
		if layer.position ~= i or layer.issue ~= issues[i].id then
			fail(`{raft.id} layer {i} is {layer.name}, expected {issues[i].id}`)
		end
		local tip = layergit.layerTip(layer) or fail(`{layer.name} has no tip`)
		local onto = layergit.baseFor(haveAt, landedAt, i)
		if not onto or not sh.run("git", { "merge-base", "--is-ancestor", onto, tip }).ok then
			fail(`{layer.name} is not stacked on the layer below: ./zn restack {raft.id}`)
		end
		if not layergit.layerFinished(layer, onto :: string) then
			fail(`{layer.issue} is not finished: ./zn finish {layer.issue}`)
		end
		-- c0248: a layer is complete (finished, green, reviewed) before it is bound, the top one included
		local why = layergit.completeReason(raft, layer, onto :: string)
		if why then
			fail(why)
		end
	end
	local traceFindings = traceProblems(raft, nil, through)
	if #traceFindings > 0 then
		fail(`{raft.id} trace --check failed:\n{table.concat(traceFindings, "\n")}`)
	end
	local layerBranch = sh.git({ "branch", "--show-current" })
	local baseRef = if layergit.shaOf("origin/main")
		then "origin/main"
		elseif layergit.shaOf("main") then "main"
		else layergit.mainTip()
	sh.git({ "switch", "--detach", baseRef })
	local top = topLayer.name
	local merged = sh.run("git", { "merge", "--no-ff", "--no-commit", land })
	if not merged.ok then
		sh.run("git", { "merge", "--abort" })
		if layerBranch ~= "" then
			sh.git({ "switch", "--quiet", layerBranch })
		end
		fail(`{top} does not merge onto main: {sh.trim(merged.stderr)}`)
	end
	local bound = false
	-- Promote sequestered acceptance specs into the permanent suite, then prove they still pass
	-- there (type check + structural meta spec + the specs themselves). Roll back on failure.
	local promoted: { string } = {}
	for _, m in store.members(raft.id) do
		if not bindSet[m.id] then
			continue
		end
		local acc = `{m.dir}/acceptance`
		if fs.isDir(acc) and #fs.readDir(acc) > 0 then
			local dest = promotedDir(m)
			fs.writeDir(string.match(dest, "^(.*)/[^/]+$") :: string)
			sh.git({ "mv", acc, dest })
			for _, name in fs.readDir(dest) do
				if string.match(name, "%.spec%.luau$") then
					table.insert(promoted, `{dest}/{name}`)
				end
			end
		end
	end
	-- Move everything to done/ now, so the gate sees the final tree. A rollback (git reset --hard HEAD) undoes
	-- both the promotion and the moves, since nothing is committed yet.
	local members: { store.Item } = {}
	for _, m in store.members(raft.id) do
		if bindSet[m.id] then
			table.insert(members, m)
		end
	end
	local movedDirs: { string } = {}
	for _, m in members do
		table.insert(movedDirs, store.dirFor(m.kind, "done", m.id, m.root))
	end
	if wholeRaft then
		table.insert(movedDirs, store.dirFor(raft.kind, "done", raft.id, raft.root))
	end
	local function rollback()
		if bound then
			sh.git({ "reset", "--hard", layerBranch })
		else
			sh.run("git", { "merge", "--abort" })
		end
		if layerBranch ~= "" then
			sh.run("git", { "switch", "--quiet", layerBranch })
		end
		-- git removes the folders it empties; if one is left, store.find would see a duplicate id
		for _, dir in movedDirs do
			if fs.isDir(dir) and #fs.readDir(dir) == 0 then
				fs.removeDir(dir)
			end
		end
	end
	-- every moved item's check.sh follows the move: its own item paths name done/ from now on (c0067)
	local doneDirs: { [string]: string } = {}
	if wholeRaft then
		doneDirs[raft.id] = store.dirFor("raft", "done", raft.id, raft.root)
	end
	for _, m in members do
		doneDirs[m.id] = store.dirFor("issue", "done", m.id, m.root)
	end
	local movedItems: { store.Item } = {}
	for _, m in members do
		table.insert(movedItems, move(m, "done"))
	end
	if wholeRaft then
		raft = move(raft, "done")
		table.insert(movedItems, raft)
	end
	for _, item in movedItems do
		local check = `{item.dir}/check.sh`
		if fs.isFile(check) then
			local text = fs.readFile(check)
			local rewritten = pathsLib.rewrite(text, doneDirs)
			if rewritten ~= text then
				fs.writeFile(check, rewritten)
				sh.git({ "add", check })
			end
		end
	end
	-- finish already wrote each layer's watch from that layer's own files. Capturing again, from the
	-- merge, would give every ticket the whole stack: a finish commit's subject is not an Issue: trailer.
	if gateLib.doneGate(process.env) == "promoted" then
		print("done: inside a spec run, so the gate is skipped; checking the promoted specs")
		if #promoted > 0 then
			print("\n=== promoted acceptance specs: type check + meta + run")
			if not promotedChecksAll(raft, promoted, true) then
				rollback()
				fail("promoted acceptance specs fail in tests/acceptance (rolled back); fix and retry done")
			end
		end
	else
		print("\n=== affected gate on the done tree")
		if not sh.stream("bash", { "z-nile/check.sh", "--affected" }) then
			rollback()
			fail("the affected gate fails on the done tree (rolled back); fix and retry done")
		end
	end
	if fs.isFile(FOCUS_FILE) then
		fs.removeFile(FOCUS_FILE)
	end
	-- the raft stays in active/ until its last layer lands
	local doneTracePath =
		`{if wholeRaft then store.dirFor("raft", "done", raft.id, raft.root) else raft.dir}/trace.md`
	local committed, commitErr = pcall(function()
		recordAndCommit(
			raft,
			stack.bindMessage(raft.id, bindIds :: { string }, verdict :: string, doneTracePath),
			if anyLanded or through ~= nil then bindIds :: { string } else {},
			nil,
			true,
			"deliver"
		)
	end)
	if not committed then
		rollback()
		fail(`binding commit failed (rolled back): {commitErr}`)
	end
	bound = true
	-- Remember each pull request's base, retarget it to main, and put that base back if the push fails.
	-- GitHub marks a pull request merged when its head is reachable from its base; base main does that
	-- once the binding commit is on main. Retargeting first and then failing the push would leave the
	-- pull request pointing at main while main does not have the commit.
	local retargeted: { { number: string, base: string, layer: string } } = {}
	local function restoreBases()
		local unrestored: { string } = {}
		for _, row in retargeted do
			if row.base ~= "main" then
				local back = sh.run("gh", { "pr", "edit", row.number, "--base", row.base })
				if not back.ok then
					table.insert(unrestored, row.layer)
				end
			end
		end
		return unrestored
	end
	if onGitHub() then
		-- the layers landed, and the next layer, whose base was the top landed layer
		local retargetLayers: { stack.Layer } = {}
		for _, layer in bindLayers do
			table.insert(retargetLayers, layer)
		end
		local nextLayer = haveAt[firstPos + #bindLayers]
		if nextLayer and not bindSet[nextLayer.issue] then
			table.insert(retargetLayers, nextLayer)
		end
		for _, layer in retargetLayers do
			local listed = sh.run("gh", {
				"pr",
				"list",
				"--head",
				layer.name,
				"--state",
				"open",
				"--json",
				"number",
				"-q",
				".[0].number",
			})
			local number = if listed.ok then sh.trim(listed.stdout) else ""
			if number ~= "" and number ~= "null" then
				local viewed = sh.run("gh", {
					"pr",
					"view",
					number,
					"--json",
					"baseRefName",
					"-q",
					".baseRefName",
				})
				local oldBase = if viewed.ok then sh.trim(viewed.stdout) else ""
				if oldBase == "" then
					rollback()
					fail(`could not read the pull request base for {layer.name} (rolled back)`)
				end
				local edited = sh.run("gh", { "pr", "edit", number, "--base", "main" })
				if not edited.ok then
					local unrestored = restoreBases()
					rollback()
					local extra = if #unrestored > 0
						then `; could not put back {table.concat(unrestored, ", ")}`
						else ""
					fail(`could not retarget the pull request for {layer.name} (rolled back){extra}`)
				end
				table.insert(retargeted, { number = number, base = oldBase, layer = layer.name })
			end
		end
	end
	if hasOrigin() then
		-- HEAD is detached, so the destination has to be a full ref. This is the binding commit on main.
		local pushed = sh.run("git", { "push", "--quiet", "origin", "HEAD:refs/heads/main" })
		if not pushed.ok then
			local unrestored = restoreBases()
			rollback()
			local extra = if #unrestored > 0
				then `; could not put back {table.concat(unrestored, ", ")}`
				else ""
			fail(`could not push the binding commit to main (rolled back){extra}: {sh.trim(pushed.stderr)}`)
		end
	end
	if sh.run("git", { "branch", "-f", "main", "HEAD" }).ok then
		sh.git({ "switch", "--quiet", "main" })
	else
		-- main is checked out in the main checkout. Fast-forward that checkout; this one stays on the commit.
		local root = mainRoot()
		local before = sh.git({ "-C", root, "rev-parse", "HEAD" })
		local pulled = sh.run("git", { "-C", root, "pull", "--ff-only", "--quiet" })
		if pulled.ok then
			sweepStale(root, before, sh.git({ "-C", root, "rev-parse", "HEAD" }))
		else
			stdio.ewrite(
				`landed on origin/main, but pulling the main checkout failed: {sh.trim(pulled.stderr)}\n`
			)
		end
	end
	print(`landed {raft.id}`)
	if not wholeRaft then
		-- the raft goes on: its remaining layer pull requests show the stack as it now stands
		pcall(refreshPrBodies, store.get(raft.id))
	end
end

-- The parsed lessons of a loaded tree; a lesson that fails to parse is left out and named on stderr.
local function parsedLessons(tree: lessonsLib.Tree): { lessonsLib.Lesson }
	local ids = {}
	for id in tree.lessons do
		table.insert(ids, id)
	end
	table.sort(ids)
	local out = {}
	for _, id in ids do
		local l, err = lessonsLib.parse(id, tree.lessons[id])
		if l then
			table.insert(out, l)
		else
			stdio.ewrite(`warning: {err}\n`)
		end
	end
	return out
end

local LESSONS_USAGE = "usage: ./zn lessons [--skill <s>]... [--when design|build] [--tag <t>]... [--full] [<word>...]\n"
	.. "       ./zn lessons --tags | --check | --uncovered [<id>...]"

-- `skills [--check]` (c0115): one relative link in .claude/skills per skill folder. --check only reads (the gate
-- runs it); without it the links are written, so it refuses in the main checkout like every other writer.
function cmd.skills(pos: { string }, opts: { [string]: { string } })
	for k in opts do
		if k ~= "--check" then
			fail(`usage: ./zn skills [--check] (unknown option {k})`)
		end
	end
	if #pos > 0 then
		fail("usage: ./zn skills [--check]")
	end
	local found, present = skillsLib.load(".")
	local list, problems = skillsLib.plan(found)
	if #problems > 0 then
		fail(table.concat(problems, "\n"))
	end
	-- a linked .claude or .claude/skills points both modes outside the repository: report it, write nothing
	local parents = skillsLib.linkedParents(".")
	if opts["--check"] then
		local wrong = table.clone(parents)
		if #parents == 0 then
			for _, p in skillsLib.diff(list, present) do
				table.insert(wrong, p)
			end
		end
		for _, p in skillsLib.trackedNonLinks(".") do
			table.insert(wrong, p)
		end
		if #wrong > 0 then
			fail(table.concat(wrong, "\n") .. "\nrun ./zn skills in a worktree to fix the links")
		end
		print(`skills: {#list} skills, one link each, ok`)
		return
	end
	refuseInMainCheckout("skills")
	if #parents > 0 then
		fail(table.concat(parents, "\n"))
	end
	local done, refused = skillsLib.apply(".", list, present)
	if #refused > 0 then
		fail(table.concat(refused, "\n"))
	end
	for _, line in done do
		print(line)
	end
	print(`skills: {#list} skills linked`)
end

-- `lessons`: list, show, search, validate and report harvest coverage (c0111). Read-only. Usage errors exit 2.
function cmd.lessons(pos: { string }, opts: { [string]: { string } })
	local function usage(why: string): never
		stdio.ewrite(`{why}\n{LESSONS_USAGE}\n`)
		return process.exit(2)
	end
	local KNOWN = {
		["--skill"] = true,
		["--when"] = true,
		["--tag"] = true,
		["--full"] = true,
		["--tags"] = true,
		["--check"] = true,
		["--uncovered"] = true,
	}
	local n = 0
	for k, values in opts do
		if not KNOWN[k] then
			usage(`unknown option {k}`)
		end
		for _, v in values do
			if v == "" then
				usage(`{k} needs a value`)
			end
		end
		n += 1
	end
	local modes = 0
	for _, k in { "--tags", "--check", "--uncovered" } do
		if opts[k] then
			modes += 1
		end
	end
	if modes > 0 and (n > 1 or (not opts["--uncovered"] and #pos > 0)) then
		usage("--tags, --check and --uncovered take no other option")
	end
	local when = opts["--when"] and opts["--when"][1]
	if opts["--when"] and (#opts["--when"] > 1 or (when ~= "design" and when ~= "build")) then
		usage("--when is design or build")
	end
	local tree = lessonsLib.load(".")
	local sources = lessonsLib.sources(tree.items)
	if opts["--check"] then
		local problems = lessonsLib.check(tree)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
			process.exit(1)
		end
		local lessonCount, entries = 0, 0
		for _ in tree.lessons do
			lessonCount += 1
		end
		for _, item in tree.items do
			if item.harvest then
				local e = lessonsLib.parseHarvest(item.id, item.harvest)
				entries += #e
			end
		end
		print(`lessons: {lessonCount} lessons, {entries} harvest entries, ok`)
		return
	end
	if opts["--uncovered"] then
		local items = tree.items
		if #pos > 0 then
			items = {}
			for _, id in pos do
				local found = false
				for _, item in tree.items do
					if item.id == id then
						table.insert(items, item)
						found = true
					end
				end
				if not found and tree.found[id] then
					print(`{id}: no reviews`)
				elseif not found then
					usage(`{id}: no such item`)
				end
			end
		end
		local gaps = lessonsLib.uncovered(items)
		if #gaps > 0 then
			print(table.concat(gaps, "\n"))
			process.exit(1)
		end
		print("harvest: every finding is covered")
		return
	end
	local all = parsedLessons(tree)
	if opts["--tags"] then
		local counts: { [string]: number } = {}
		for _, l in all do
			for _, tag in l.tags do
				counts[tag] = (counts[tag] or 0) + 1
			end
		end
		local tags = {}
		for tag in counts do
			table.insert(tags, tag)
		end
		table.sort(tags, function(a, b)
			if counts[a] ~= counts[b] then
				return counts[a] > counts[b]
			end
			return a < b
		end)
		for _, tag in tags do
			print(`{tag} {counts[tag]}`)
		end
		return
	end
	local chosen = lessonsLib.select(all, sources, {
		skills = opts["--skill"],
		when = when :: any,
		tags = opts["--tag"],
		words = pos,
	})
	if not opts["--full"] then
		stdio.write(lessonsLib.index(chosen, sources))
		return
	end
	for i, l in chosen do
		if i > 1 then
			print("")
		end
		local src = table.clone(sources[l.id] or {})
		if l.from then
			table.insert(src, l.from)
		end
		print(`== {lessonsLib.folderOf(tree, l.skill)}/lessons/{l.slug}.md`)
		print(`sources: {if #src > 0 then table.concat(src, ", ") else "none"}`)
		stdio.write(tree.lessons[l.id])
	end
	if #chosen == 0 then
		print("(none)")
	end
end

-- The raft's project's architecture map (c0120): the path, not the text. A project without one (z-nile) gets a line saying so.
local function architectureOf(raft: store.Item): string
	local path = `{raft.root}/architecture.md`
	return if fs.isFile(path)
		then `Read \`{path}\` before you change a dependency.`
		else `({raft.root} has no architecture.md: this project has none)`
end

-- The project whose current root is `root`, from the working tree's registry; nil when none is.
local function projectOfRoot(root: string): string?
	local ok, reg = pcall(projects.load, ".")
	if not ok then
		return nil
	end
	local p = projects.projectOf(reg :: projects.Registry, root)
	return p and p.name
end

-- The SKILL.md files a raft's prompt names (c0115, c0184): skills.inlined over the skills found. The prompt
-- gives the path and when to read it; it pastes none of the text.
local function namedSkills(project: string?): { string }
	return skillsLib.inlined((skillsLib.plan((skillsLib.load(".")))), project)
end

local SKILL_WHEN: { [string]: string } = {
	["zz-execute"] = "Read it first and follow it step by step. It is the protocol.",
	["zz-rules"] = "Read it before creating, moving, committing or finishing tracked work.",
	["zz-arch"] = "Read it before designing or writing tooling code.",
	["zz-test"] = "Read it before writing a spec or running the gate.",
	["zz-review"] = "Read it before the adversarial review, and give it to the reviewer.",
}

local function skillLine(path: string): string
	local name = string.match(path, "([^/]+)/SKILL%.md$") or path
	local when = SKILL_WHEN[name]
	if not when then
		if string.match(name, "%-arch$") then
			when = "Read it before designing or writing that project's code."
		elseif string.match(name, "%-test$") then
			when = "Read it before writing that project's specs."
		else
			when = "Read it before the work it governs."
		end
	end
	return `- \`{path}\` — {when}`
end

-- One `## ` section of a raft document, without the heading. Missing sections are named, not invented.
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

-- The execution prompt of a raft: theme, order and interfaces inline; every other file named by path.
local function renderPrompt(raft: store.Item): string
	local ids = {}
	local issues = {}
	for _, m in store.members(raft.id) do
		table.insert(ids, m.id)
		local issueTitle = store.readFront(m.doc).title or m.id
		local acc = `{m.dir}/acceptance`
		local accNote = if fs.isDir(acc) then `, acceptance \`{acc}/\`` else ""
		table.insert(
			issues,
			`- {m.id} {issueTitle}: document \`{m.doc}\`, checks \`{m.dir}/check.sh\`{accNote}`
		)
	end
	local project = projectOfRoot(raft.root)
	local skills = {}
	for _, path in namedSkills(project) do
		table.insert(skills, skillLine(path))
	end
	local plan, _, planError = workstreamPlan(raft)
	local planText = if planError then `plan unavailable: {planError}\nparallel: no` else plan
	local raftDoc = fs.readFile(raft.doc)
	local text = render(`{TEMPLATES}/prompt.md`, {
		RAFT_ID = raft.id,
		RAFT_TITLE = store.readFront(raft.doc).title or raft.slug,
		RAFT_TYPE = store.typeOf(raft),
		ISSUE_IDS = table.concat(ids, ", "),
		ISSUES = table.concat(issues, "\n"),
		SKILLS = table.concat(skills, "\n"),
		ARCHITECTURE = architectureOf(raft),
		ARCHITECTURE_PATH = `{raft.root}/architecture.md`,
		RAFT_DOC = raft.doc,
		RAFT_CHECK = `{raft.dir}/check.sh`,
		THEME = raftSection(raftDoc, "Theme"),
		ORDER = raftSection(raftDoc, "Order & dependencies"),
		INTERFACES = raftSection(raftDoc, "Whole-raft design"),
		WORKSTREAMS = planText,
		PROJECT = project or raft.root,
	})
	for _, m in store.members(raft.id) do
		if store.readFront(m.doc).design ~= "ready" then
			stdio.ewrite(`warning: {m.id} is not design: ready\n`)
		end
	end
	return text
end

-- A readied raft's prompt, beside it in its project's active/ folder of the main checkout (ignored there, c0114).
local function promptPath(root: string, raftId: string): string
	return `{mainRoot()}/{root}/rafts/active/{raftId}/prompt.md`
end

-- The reader of a readied raft's prompt.md (the z-run skill's input). The decision is made from origin/main's
-- tree, never from the local store; nothing is written.
function cmd.prompt(pos: { string }, opts: { [string]: { string } })
	local id = pos[1]
	if not id or #pos > 1 or not string.match(id, "^R%d%d%d%d$") then
		fail("prompt takes a raft id (an issue's raft: ./zn find <id>)")
	end
	local notReadied = `{id} is not readied: run /z-ready {id} (./zn ready {id}) in the main checkout`
	if not hasOrigin() then
		fail(notReadied)
	end
	sh.git({ "fetch", "--quiet", "origin", "main" })
	local readTree, files = originTree()
	local theirs = if readTree then docPath(files, id) else nil
	local shown = if theirs then sh.run("git", { "show", `origin/main:{theirs}` }) else nil
	if
		not (
			shown
			and shown.ok
			and stateOfPath(theirs :: string) == "active"
			and statusLib.effective(frontOf(shown.stdout), "active") == "active"
		)
	then
		fail(notReadied)
	end
	local path = promptPath(select(3, publish.itemPath(theirs :: string)) :: string, id)
	if not fs.isFile(path) then
		fail(`no prompt for {id}: run ./zn ready {id} in the main checkout to regenerate it`)
	end
	if opts["--path"] then
		print(path)
	else
		stdio.write(fs.readFile(path))
	end
end

-- Whether `text` has a line that runs a check (`check "AC1: ..."`), not a commented one.
local function hasCheckLine(text: string): boolean
	for line in string.gmatch(text, "[^\n]+") do
		if string.match(line, '^%s*check "') then
			return true
		end
	end
	return false
end

-- The guards of the commands that publish from the main checkout (`ready`, `stop`): it is the main checkout, the repo
-- has an origin, `main` is checked out and clean.
local function mainCheckoutGuards(name: string)
	if not inMainCheckout() then
		fail(`{name} runs in the main checkout`)
	end
	if not publishing() then
		fail(`{name} needs an origin remote`)
	end
	local branch = sh.git({ "branch", "--show-current" })
	if branch ~= "main" then
		fail(`the main checkout is on {if branch == "" then "a detached HEAD" else branch}, not main`)
	end
	local dirty = sh.git({ "status", "--porcelain" })
	if dirty ~= "" then
		fail(`the main checkout is not clean: {dirty}`)
	end
end

-- Fast-forwards the main checkout to origin/main and sweeps the item folders that fast-forward moved. A string is
-- the failure. It does not rebuild the board (`./zn board`).
local function pullMain(): string?
	local before = sh.git({ "rev-parse", "HEAD" })
	sh.git({ "fetch", "--quiet", "origin", "main" })
	local r = sh.run("git", { "pull", "--ff-only", "--quiet" })
	if not r.ok then
		return sh.trim(r.stderr .. r.stdout)
	end
	sweepStale(mainRoot(), before, sh.git({ "rev-parse", "HEAD" }))
	return nil
end

-- A controlling terminal. Lune's own stdin is not a tty even when `./zn` was started on one (a child
-- cannot inherit it), so this opens /dev/tty. `./zn` also refuses when its own stdin is not a terminal.
local function stdinIsTerminal(): boolean
	local r = process.exec("perl", {
		"-e",
		"open(my $f, q{<}, q{/dev/tty}) or exit 1; exit(-t $f ? 0 : 1)",
	})
	return r.ok
end

local function contractDirty(paths: { string }): string?
	local args = { "status", "--porcelain", "--" }
	for _, path in paths do
		table.insert(args, path)
	end
	local out = sh.git(args)
	local line = string.match(out, "^([^\n]+)")
	if not line or line == "" then
		return nil
	end
	return line
end

-- `approve <issue-id>` records the contract hash in the issue's approval.md and commits only that file.
-- `--check` reads: it says whether the latest row still matches, and which part changed.
function cmd.approve(pos: { string }, opts: { [string]: { string } })
	for k in opts do
		if k ~= "--check" then
			fail(`usage: approve <issue-id> [--check] (unknown option {k})`)
		end
	end
	if #pos ~= 1 then
		fail("usage: approve <issue-id> [--check]")
	end
	local id = pos[1]
	local onlyCheck = opts["--check"] ~= nil
	if not onlyCheck then
		local dispatched = process.env.ZN_DISPATCH
		if dispatched and dispatched ~= "" then
			fail(
				`{id}: approve is refused while ZN_DISPATCH is set. Run ./zn approve {id} yourself, in a terminal, in this worktree.`
			)
		end
		if not stdinIsTerminal() then
			local where = sh.git({ "rev-parse", "--show-toplevel" })
			fail(
				`{id}: approve is refused without a terminal on stdin. Run ./zn approve {id} yourself, in a terminal, in this worktree ({where}).`
			)
		end
		refuseInMainCheckout("approve")
	end
	local item = store.get(id)
	if item.kind ~= "issue" then
		fail(`approve takes an issue ({id} is a {item.kind})`)
	end
	if onlyCheck then
		local found, err = approval.verdict(".", item)
		if not found then
			fail(`{id}: {err}`)
		end
		local verdict: approval.Verdict = found :: approval.Verdict
		if verdict.state == "none" then
			fail(`{id} has no approval`)
		end
		if verdict.state == "bad" then
			fail(`{id}: {approval.file(item)} does not parse: {verdict.err}`)
		end
		if verdict.state == "changed" then
			fail(
				`{id}'s contract changed since approval: {table.concat(verdict.changed, ", ")}. Run ./zn approve {id} again.`
			)
		end
		local row = verdict.row :: contract.Row
		print(`{id} approved {row.hash} at {row.when} by {row.who}`)
		return
	end
	local front = store.readFront(item.doc)
	if front.design ~= "ready" then
		fail(`{id} is not design: ready`)
	end
	local pending = openlist.pending(fs.readFile(item.doc))
	if #pending > 0 then
		fail(
			`{id} has an unruled open-list bullet ({table.concat(pending, ", ")}): rule each under ## Open to the human, then ./zn approve {id}`
		)
	end
	local check = `{item.dir}/check.sh`
	if not fs.isFile(check) then
		fail(`{id} has no check.sh`)
	end
	local named = sh.run("git", { "config", "--get", "user.name" })
	local who = if named.ok then contract.who(sh.trim(named.stdout)) else ""
	if who == "" then
		fail("approve needs a git identity (git config user.name)")
	end
	local _, paths, collectErr = approval.collect(".", item)
	if collectErr then
		fail(`{id}: {collectErr}`)
	end
	local dirty = contractDirty(paths)
	if dirty then
		fail(`{id}: commit the contract first ({dirty}), then ./zn approve {id}`)
	end
	local when = os.date("!%Y-%m-%dT%H:%M:%SZ") :: string
	local text, aerr = approval.append(".", item, who, when)
	if not text then
		fail(`{id}: {aerr}`)
	end
	local path = approval.file(item)
	sh.writeReplacing(path, text :: string)
	sh.git({ "add", "--", path })
	sh.git({ "commit", "-q", "-m", `tracker: approve {id}`, "--", path })
	local rows = contract.parse(text :: string)
	local hash = if rows then rows[#rows].hash else ""
	print(`approved {id} {hash}`)
end

-- `ready <R-id|issue-id>`: claims a prepared raft, moves it and its members to active/ on origin/main (one tracker-only
-- commit, check.sh paths rewritten), pulls the main checkout and writes the ignored prompt.md. On a raft that is
-- already active it only regenerates the prompt.
function cmd.ready(pos: { string })
	local target = store.get(pos[1] or fail("usage: ready <R-id|issue-id>"))
	local raft = target
	if target.kind == "issue" then
		local raftId = store.readFront(target.doc).raft
		if not raftId or raftId == "" then
			fail(`{target.id} has no raft: z-raft makes one (./zn raft-plan)`)
		end
		raft = store.get(raftId)
	end
	if raft.kind ~= "raft" then
		fail(`{raft.id} is not a raft`)
	end
	mainCheckoutGuards("ready")
	local pulled = pullMain()
	if pulled then
		fail(`ready: cannot fast-forward the main checkout: {pulled}`)
	end
	raft = store.get(raft.id) -- the tree is now origin/main
	local st = statusLib.effective(frontOf(fs.readFile(raft.doc)), raft.state)
	local reissue = raft.state == "active" and st == "active"
	local ids: { string } = {}
	local members = store.members(raft.id)
	for _, m in members do
		table.insert(ids, m.id)
	end
	if not reissue then
		if not (raft.state == "backlog" and st == "prepared") then
			fail(`{raft.id} is {st} in {raft.dir} on origin/main: only a prepared raft is readied`)
		end
		if #members == 0 then
			fail(`{raft.id} has no member issues`)
		end
		-- the raft's issues: list and its members' raft: fields name one set, or `stop` could not move back what
		-- `ready` moved (review 001 F1)
		local listed: { [string]: boolean } = {}
		for _, id in store.idList(store.readFront(raft.doc).issues) do
			listed[id] = true
		end
		local unlisted, missing = {}, {}
		for _, m in members do
			if not listed[m.id] then
				table.insert(unlisted, m.id)
			end
			listed[m.id] = nil
		end
		for id in listed do
			table.insert(missing, id)
		end
		table.sort(missing)
		if #unlisted > 0 or #missing > 0 then
			fail(
				`{raft.id}'s issues: list and its members' raft: fields disagree (raft: {raft.id} but not listed: {table.concat(
					unlisted,
					", "
				)}; listed without raft: {raft.id}: {table.concat(missing, ", ")}); fix the documents (z-design) and ready again`
			)
		end
		local everyone: { store.Item } = { raft }
		for _, m in members do
			table.insert(everyone, m)
		end
		local isMember: { [string]: boolean } = {}
		for _, m in members do
			isMember[m.id] = true
		end
		for _, it in everyone do
			if store.readFront(it.doc).design ~= "ready" then
				fail(`{it.id} is not design: ready (run z-design first)`)
			end
			local gap = designOpen(it)
			if gap then
				fail(`{it.id}: {gap}`)
			end
			local check = `{it.dir}/check.sh`
			if not fs.isFile(check) or not hasCheckLine(fs.readFile(check)) then
				fail(`{it.id} has no check: its check.sh needs at least one line starting check "..."`)
			end
		end
		for _, m in members do
			for _, dep in store.idList(store.readFront(m.doc).depends_on) do
				if not isMember[dep] then
					local found = store.find(dep)
					if not found or found.state ~= "done" then
						fail(
							`{m.id} depends on {dep}, which is {if found then found.state else "unknown"} on origin/main: it must be done first`
						)
					end
				end
			end
		end
		for _, m in members do
			local problem = approval.refusal(".", m, true)
			if problem then
				fail(problem)
			end
		end
		local all = { raft.id }
		for _, id in ids do
			table.insert(all, id)
		end
		local r = moveOnOrigin(
			all,
			"active",
			claimStamp(),
			`tracker: ready {raft.id} {store.readFront(raft.doc).title or raft.slug}`,
			function(id: string, cur: string): string?
				if not statusLib.canMove(cur, "active") then
					return `{id} is {cur} on origin/main, not prepared`
				end
				return nil
			end,
			-- c0116 (review 002 F1, 004 F1): a member redesigned since z-raft grouped it is never handed out under the
			-- old review; read from the tree being published, so a redesign landing after the pull is seen too
			function(paths, read): string?
				local rp = docPath(paths, raft.id)
				local rt = rp and read(rp)
				if not rp or not rt then
					return `{raft.id} is not on origin/main`
				end
				local map, problem = raftplan.parseGrouped(frontOf(rt).grouped)
				if problem then
					return `{rp}: {problem}`
				end
				local now: { [string]: string? } = {}
				for _, m in members do
					local mp = docPath(paths, m.id)
					if mp then
						now[m.id] = raftplan.recordHash(
							m.id,
							treeFolderFiles(paths, read, string.sub(mp, 1, #mp - #m.id - 4))
						)
					end
				end
				local redesigned = regrouped(map, now)
				if #redesigned > 0 then
					return `{raft.id}: {table.concat(redesigned, ", ")} changed on origin/main since {raft.id} grouped it: z-raft drops it (./zn unfold {raft.id} <id>) or folds it again with a new coherence review`
				end
				if
					#members > 1
					and not reviewCovers(
						treeFolderFiles(paths, read, string.sub(rp, 1, #rp - #raft.id - 4)),
						map
					)
				then
					return `{raft.id}'s coherence review predates its record: run a new raft-mode round (z-raft, zz-review); never edit a review that is already written`
				end
				return nil
			end
		)
		if not r.ok then
			fail(`ready: {r.reason}`)
		end
		local failed = pullMain()
		if failed then
			fail(
				`readied on origin/main, but pulling the main checkout failed: {failed}; fix it and run ready again (it regenerates the prompt)`
			)
		end
		raft = store.get(raft.id)
	end
	local text = renderPrompt(raft)
	local path = promptPath(raft.root, raft.id)
	sh.writeReplacing(path, text)
	local plan, _, planError = workstreamPlan(raft)
	local parallel = if planError then "parallel: no" else string.match(plan, "[^\n]*$") :: string
	print(`{if reissue then "regenerated" else "readied"} {raft.id}`)
	print(`prompt for {raft.id} ({table.concat(ids, ", ")}): {#text} chars -> {path}`)
	print(parallel)
end

-- `stop <issue>` (R0050 code review 003 F1): gives back one active issue whose raft is retired, missing or empty (a
-- dead raft can't be stopped as a raft): the same published move to the backlog, stamped prepared, check.sh paths
-- rewritten back, that stop gives a member. Its raft: line is left: audit then names `unfold` for it (a backlog
-- issue), which clears it in a rafting PR. An issue whose raft is live is refused: stop the raft.
local function stopIssue(id: string)
	if not store.isIssueId(id) then
		fail(`{id} is neither a raft nor an issue`)
	end
	mainCheckoutGuards("stop")
	local pulled = pullMain()
	if pulled then
		fail(`stop: cannot fast-forward the main checkout: {pulled}`)
	end
	local issue = store.get(id)
	if issue.state ~= "active" then
		fail(`{id} is in {issue.dir} on origin/main: stop <issue> gives back an active issue only`)
	end
	local fm = store.readFront(issue.doc)
	local raftId = fm.raft or ""
	-- the one rule audit uses too (audit.raftHolds, review 004 F1): refused only when stop <R-id> takes it
	local raft = if store.isRaftId(raftId) then store.find(raftId) else nil
	local raftStatus = if raft then store.readFront(raft.doc).status else nil
	if audit.raftHolds(fm, if raft then raft.dir else nil, raftStatus) then
		fail(`{id} is held by its raft {raftId}: use ./zn stop {raftId}`)
	end
	local function stillActive(item: string, now: string): string?
		return if now == "active" then nil else `{item} is {now} on origin/main, not active: nothing to stop`
	end
	local why = if raftId == "" then "no raft" else `raft {raftId} doesn't hold it`
	local r = moveOnOrigin({ id }, "backlog", stamp("prepared"), `tracker: stop {id} ({why})`, stillActive)
	if not r.ok then
		fail(`stop: {r.reason}`)
	end
	local failed = pullMain()
	if failed then
		fail(`stopped on origin/main, but pulling the main checkout failed: {failed}`)
	end
	print(`gave back {id} ({why}): it is in the backlog, prepared`)
end

-- `stop <R-id>`: gives back a readied raft (moves it and its members to the backlog on origin/main, stamped prepared,
-- check.sh paths rewritten back) or a raft claimed by the legacy `start` (a status-only publish). Removes prompt.md,
-- pulls the main checkout and names the raft's branch and PR, which are left as they are.
function cmd.stop(pos: { string })
	local raftId = pos[1] or fail("usage: stop <R-id> | stop <issue>")
	if not store.isRaftId(raftId) then
		stopIssue(raftId)
		return
	end
	mainCheckoutGuards("stop")
	local pulled = pullMain()
	if pulled then
		fail(`stop: cannot fast-forward the main checkout: {pulled}`)
	end
	local raft = store.get(raftId) -- looked up after the pull: the tree is now origin/main
	local st = statusLib.effective(frontOf(fs.readFile(raft.doc)), raft.state)
	-- Who is given back is decided by the claim, not by membership fields (review 003 F3, the third finding on
	-- membership): `ready` and `start` stamp the raft and every issue they claim with one fresh `active-…` value, so
	-- the claimed set is exactly the issues carrying the raft's own stamp. Neither the issues: list nor a raft: edit
	-- made since can add or drop one. An issue that names the raft but carries another status was never claimed
	-- with it (filed after the claim, say): it is left as it is and named in a warning.
	local claim = frontOf(fs.readFile(raft.doc)).status
	local ids: { string } = {}
	local left: { string } = {}
	local rtitle = store.readFront(raft.doc).title or raft.slug
	local value = stamp("prepared")
	local r: publish.Result
	if not ((raft.state == "active" or raft.state == "backlog") and st == "active") then
		fail(`{raft.id} is {st} in {raft.dir} on origin/main: only a readied or started raft is stopped`)
	end
	if not claim or not string.match(claim, "^active%-") then
		fail(`{raft.id} has no claim stamp on origin/main (status: {claim or "none"}): give it back by hand`)
	end
	for _, issue in store.all("issue") do
		local raw = frontOf(fs.readFile(issue.doc)).status
		-- a done issue of another raft that once carried this value (claims are unique only since R0025) is not ours
		local foreignDone = issue.state == "done" and store.readFront(issue.doc).raft ~= raft.id
		if raw == claim and not foreignDone then
			if issue.state ~= raft.state then
				fail(
					`{issue.id} is in {issue.dir} on origin/main, not beside {raft.id}: stop does not move it back`
				)
			end
			table.insert(ids, issue.id)
		elseif store.readFront(issue.doc).raft == raft.id and issue.state ~= "done" then
			table.insert(left, issue.id)
		end
	end
	local all = { raft.id }
	for _, id in ids do
		table.insert(all, id)
	end
	-- checked again inside the build: an item that left `active` since the pull (merged, done) is never touched
	local function stillActive(id: string, now: string): string?
		return if now == "active" then nil else `{id} is {now} on origin/main, not active: nothing to stop`
	end
	if raft.state == "active" then
		r = moveOnOrigin(all, "backlog", value, `tracker: stop {raft.id} {rtitle}`, stillActive)
	else
		-- a legacy start claimed in place (backlog, status active): a status-only give-back, no move
		r = restampOnOrigin(all, value, `tracker: {raft.id} prepared`, stillActive)
	end
	if not r.ok then
		fail(`stop: {r.reason}`)
	end
	if #left > 0 then
		stdio.ewrite(
			`warning: {table.concat(left, ", ")} name {raft.id} but were not claimed with it; left as they are\n`
		)
	end
	local prompt = promptPath(raft.root, raft.id)
	if fs.isFile(prompt) then
		fs.removeFile(prompt)
	end
	local failed = pullMain()
	if failed then
		fail(`stopped on origin/main, but pulling the main checkout failed: {failed}`)
	end
	if fs.isFile(claimFile(raft.id)) then
		fs.removeFile(claimFile(raft.id))
	end
	sh.run("git", { "fetch", "--quiet", "--prune", "origin" })
	local layers = layergit.layersOf(raft.id)
	local branch = if #layers > 0 then layers[#layers].name else raftBranch(raft)
	local exists = false
	if #layers > 0 then
		exists = true
		local names: { string } = {}
		for _, layer in layers do
			table.insert(names, layer.name)
		end
		branch = table.concat(names, ", ")
	else
		exists = sh.run("git", { "show-ref", "--verify", "--quiet", `refs/heads/{branch}` }).ok
			or sh.run("git", { "show-ref", "--verify", "--quiet", `refs/remotes/origin/{branch}` }).ok
	end
	if exists then
		local pr = "its pull request, if any"
		local head = if #layers > 0 then layers[1].name else branch
		if onGitHub() then
			local g = sh.run(
				"gh",
				{ "pr", "list", "--head", head, "--state", "open", "--json", "url", "-q", ".[0].url" }
			)
			local url = if g.ok then sh.trim(g.stdout) else ""
			if url ~= "" and url ~= "null" then
				pr = `its pull request {url}`
			end
		end
		print(`{branch} and {pr} are left as they are: close or keep them yourself`)
	end
	print(`stopped {raft.id} ({table.concat(ids, ", ")})`)
end

local SPEND_PHASES = { "capture", "prep", "design-review", "deliver" }

-- origin/main's issue spend.md blobs, keyed by id, loaded once. nil means this checkout has no
-- origin/main of its own (a sandbox under .cache, or a cwd that is not the git toplevel): metrics
-- then reads only the working tree, and it never fetches.
local originSpend: { [string]: { string } }? = nil
local originBody: { [string]: string } = {}
local originChecked = false

-- One git process for every origin spend.md. A process per issue is what made metrics take half a minute.
local function readBatch(paths: { string })
	if #paths == 0 then
		return
	end
	local names: { string } = {}
	for _, p in paths do
		table.insert(names, `origin/main:{p}`)
	end
	local shown = process.exec("git", { "cat-file", "--batch" }, {
		stdio = { stdin = table.concat(names, "\n") .. "\n" },
	})
	if not shown.ok then
		return
	end
	local text = shown.stdout
	local i, n = 1, 1
	while n <= #paths do
		local nl = string.find(text, "\n", i, true)
		if not nl then
			break
		end
		local header = string.sub(text, i, nl - 1)
		local size = tonumber(string.match(header, " (%d+)$"))
		if not size then
			i = nl + 1
		else
			local startAt = nl + 1
			originBody[paths[n]] = string.sub(text, startAt, startAt + size - 1)
			i = startAt + size + 1
		end
		n += 1
	end
end

local function originBlobs(id: string): { string }?
	if not originChecked then
		originChecked = true
		-- the same pair guardRepoRoot uses: process.cwd keeps a trailing slash, so it never
		-- equals git's toplevel and the origin read would never run
		local here = sh.run("pwd", { "-P" })
		local top = sh.run("git", { "rev-parse", "--show-toplevel" })
		if here.ok and top.ok and sh.trim(here.stdout) == sh.trim(top.stdout) then
			local roots = originRoots()
			local args = { "ls-tree", "-r", "--name-only", "origin/main", "--" }
			local within: { string } = roots or {}
			for _, r in within do
				table.insert(args, `{r}/issues`)
			end
			local listed = if roots then sh.run("git", args) else { ok = false, stdout = "" }
			if listed.ok then
				originSpend = {}
				local all: { string } = {}
				for path in string.gmatch(listed.stdout, "[^\n]+") do
					local found = string.match(path, "/([fdc]%d%d%d%d)/spend%.md$")
					if found and originSpend then
						local list = originSpend[found]
						if not list then
							list = {}
							originSpend[found] = list
						end
						table.insert(list, path)
						table.insert(all, path)
					end
				end
				readBatch(all)
			end
		end
	end
	if not originSpend then
		return nil
	end
	return originSpend[id] or {}
end

-- The longer of the working-tree ledger and origin/main's, when one is a prefix of the other.
-- nil means the issue is skipped. A checkout with no origin/main keeps the local read.
local function ledgerRows(issue: store.Item): { ledger.Row }?
	local function attach(rows: { ledger.Row }?): { ledger.Row }?
		if not rows then
			return nil
		end
		for _, row in costrow.readMeasured(issue.dir) do
			table.insert(rows, row)
		end
		return rows
	end
	local path = `{issue.dir}/spend.md`
	local localRows: { ledger.Row }? = nil
	local localErr: string? = nil
	if not fs.isFile(path) then
		localRows = {}
	else
		local parsed, err = ledger.parse(fs.readFile(path))
		if parsed then
			localRows = parsed.rows
		else
			localErr = err
		end
	end
	local blobs = originBlobs(issue.id)
	if not blobs then
		if localErr then
			stdio.ewrite(`metrics: {path} does not parse ({localErr}); skipped\n`)
			return nil
		end
		return attach(localRows)
	end
	if #blobs > 1 then
		stdio.ewrite(`metrics: {issue.id} spend.md appears twice on origin/main; skipped\n`)
		return nil
	end
	local originRows: { ledger.Row }? = nil
	local originErr: string? = nil
	local absent = #blobs == 0
	if not absent then
		local blob = blobs[1]
		local body = originBody[blob]
		if body == nil then
			local shown = sh.run("git", { "show", `origin/main:{blob}` })
			if not shown.ok then
				stdio.ewrite(`metrics: origin/main:{blob} could not be read; using the working tree\n`)
				absent = true
			else
				body = shown.stdout
			end
		end
		if body ~= nil then
			local parsed, err = ledger.parse(body)
			if parsed then
				originRows = parsed.rows
			else
				originErr = err
			end
		end
	end
	if localErr and (absent or originErr) then
		stdio.ewrite(`metrics: {path} does not parse ({localErr}); skipped\n`)
		if originErr then
			stdio.ewrite(`metrics: origin/main:{blobs[1]} does not parse ({originErr}); skipped\n`)
		end
		return nil
	end
	if localErr and originRows then
		stdio.ewrite(`metrics: {path} does not parse ({localErr}); using origin/main\n`)
		return attach(originRows)
	end
	if originErr then
		stdio.ewrite(`metrics: origin/main:{blobs[1]} does not parse ({originErr}); using the working tree\n`)
		return attach(localRows)
	end
	if absent or not originRows then
		return attach(localRows)
	end
	local here = localRows :: { ledger.Row }
	if ledger.extends(here, originRows) or ledger.extends(originRows, here) then
		return attach(if #originRows > #here then originRows else here)
	end
	stdio.ewrite(
		`metrics: {issue.id} spend.md on origin/main and in the working tree have diverged; skipped\n`
	)
	return nil
end

function cmd.spend(pos: { string }, opts: { [string]: { string } })
	if hasOrigin() and inMainCheckout() then
		fail(
			"spend writes its row on the work branch: run it in that worktree (./zn worktree <id>), not the main checkout"
		)
	end
	if not publishing() then
		fail(
			"spend needs an origin remote (PICKMAN_PUBLISH=0 disables it); inside a raft, record with ./zn commit --phase"
		)
	end
	local id = pos[1]
	if not id or not (store.isIssueId(id) or store.isRaftId(id)) then
		fail(
			"usage: spend <id> --phase capture|prep|design-review|deliver [--begin] [--model <id>] [--note <text>]"
		)
	end
	local phase = opts["--phase"] and opts["--phase"][1] or ""
	if phase == "build" or phase == "code-review" then
		fail(`{phase} is recorded with ./zn commit --phase`)
	elseif not table.find(SPEND_PHASES, phase) then
		fail("spend --phase is capture, prep, design-review or deliver")
	end
	if opts["--time"] or opts["--tokens"] then
		stdio.ewrite("spend: --time and --tokens are ignored; cost is measured\n")
	end
	local minutes = 0
	local tokens: number? = nil
	local model = modelOption("spend", opts)
	local note = phase
	if opts["--note"] and opts["--note"][1] ~= "" then
		note = opts["--note"][1]
	end
	local targets: { store.Item } = {}
	local raftItem: store.Item? = nil
	if store.isRaftId(id) then
		raftItem = store.find(id)
		targets = if raftItem then store.members(id) else {}
		if not raftItem or #targets == 0 then
			fail("run ./zn sync first")
		end
	else
		local item = store.find(id)
		if item then
			targets = { item }
		end
	end
	local stats: { { path: string, added: number, removed: number } } = {}
	local owners: { [string]: { string } }? = nil
	if phase == "prep" then
		local fetched = sh.run("git", { "fetch", "-q", "origin", "main" })
		if not fetched.ok then
			fail("could not fetch origin/main: " .. sh.trim(fetched.stderr))
		end
		if store.isIssueId(id) then
			if #targets == 1 then
				stats, owners = spend.prepStats(targets, nil)
			end
		else
			stats, owners = spend.prepStats(targets, raftItem)
		end
	end
	local issues = targets
	if store.isIssueId(id) and #targets == 0 then
		-- looked up on origin/main inside the publish; it need not exist in this checkout
		issues = {
			{
				id = id,
				kind = "issue" :: "issue",
				state = "backlog" :: "backlog",
				dir = "",
				doc = "",
				slug = "",
				root = "",
			},
		}
	end
	local shares = spend.attribute(
		issues,
		if phase == "prep" then stats else {},
		minutes :: number,
		"spend",
		tokens,
		if phase == "prep" then owners else nil
	)
	local kept: { spend.Share } = shares
	if #kept == 0 then
		fail("nothing to record")
	end
	-- one stamp for every retry of the publish, so a lost race appends the same row
	local when = os.date("!%Y-%m-%d %H:%M", os.time()) :: string
	local function activeThere(doc: string, text: string): boolean
		return string.find(doc, "/active/", 1, true) ~= nil
			or statusLib.effective(frontOf(text), stateOfPath(doc)) == "active"
	end
	local function activeReason(target: string): string
		if phase == "capture" or phase == "deliver" then
			return `{target} is active on origin/main: inside its raft, record with ./zn commit --phase`
		end
		return `{target} was readied before its {phase} spend was recorded: record nothing and report it`
	end
	-- The row is committed on this branch and pushed nowhere. It reaches main with the branch (a pull request, or
	-- `./zn land` when the commit is already in the capture tree). An item that is active on origin/main is still
	-- refused: inside a raft, `./zn commit --phase` records it.
	refuseStale()
	if publishing() then
		local fetched = sh.run("git", { "fetch", "-q", "origin", "main" })
		if not fetched.ok then
			fail("could not fetch origin/main: " .. sh.trim(fetched.stderr))
		end
		local readable, pathsOnOrigin = originTree()
		if not readable then
			fail("could not read origin/main")
		end
		local function originText(doc: string): string?
			local shown = sh.run("git", { "show", `origin/main:{doc}` })
			return if shown.ok then shown.stdout else nil
		end
		if store.isRaftId(id) then
			local doc = docPath(pathsOnOrigin, id)
			local text = if doc then originText(doc) else nil
			if doc and text and activeThere(doc, text) then
				fail(activeReason(id))
			end
		end
		for _, share in kept do
			local doc = docPath(pathsOnOrigin, share.id)
			local text = if doc then originText(doc) else nil
			if not doc or not text then
				fail(`{share.id} is not on origin/main`)
			end
			if activeThere(doc :: string, text :: string) then
				fail(activeReason(share.id))
			end
			local localItem = store.find(share.id)
			if not localItem then
				fail(`{share.id} is not in this checkout: run ./zn sync first`)
			end
			if stateOfPath(doc :: string) ~= (localItem :: store.Item).state then
				fail(
					`{share.id} is {stateOfPath(doc :: string)} on origin/main and {(localItem :: store.Item).state} in this checkout: run ./zn sync first`
				)
			end
		end
	end
	local top = sh.git({ "rev-parse", "--show-toplevel" })
	local branch, head = costrow.branchOf(top)
	if opts["--begin"] then
		local began = costrow.append(top, {
			ms = 0,
			kind = "begin",
			phase = phase,
			subject = note,
			id = id,
			branch = branch,
			head = head,
		})
		if not began then
			fail("spend: could not record the stage start")
		end
		for _, share in kept do
			print(string.format("%s %s +%d/-%d began", share.id, phase, share.added, share.removed))
		end
		return
	end
	local ai: number? = nil
	local tok: number? = nil
	local modelId = model
	local noteText = note
	local openCells = "ai,tokens"
	local buf = ""
	local bufPath = costrow.bufferFile(top)
	if fs.isFile(bufPath) then
		buf = fs.readFile(bufPath)
	end
	local since: buffer.Line? = nil
	for _, line in buffer.parse(buf) do
		if line.kind == "begin" and line.phase == phase then
			local match = line.id == id
			if not match and line.id == "" then
				match = (line.branch ~= "" and line.branch == branch)
					or (line.branch == "" and line.head ~= "" and line.head == head)
			end
			if match then
				since = line
			end
		end
	end
	if since then
		local sec = math.floor(since.ms / 1000)
		local stamped = (os.date("!%Y-%m-%dT%H:%M:%S", sec) :: string) .. ".000Z"
		local untilIso = (os.date("!%Y-%m-%dT%H:%M:%S") :: string) .. ".999Z"
		local sinceUnix = sessions.unix(stamped) or 0
		local untilUnix = sessions.unix(untilIso) or sinceUnix
		local readOk, reading = pcall(sessionread.span, process.cwd, stamped, sinceUnix, untilIso, untilUnix)
		if readOk and reading then
			local got = reading :: any
			ai = got.ai
			tok = got.tokens
			if got.model then
				modelId = got.model
			end
			if type(got.note) == "string" and got.note ~= "" then
				noteText = `{note} {got.note}`
			end
			openCells = if type(got.unmeasured) == "string" then got.unmeasured else ""
		end
	end
	local homes: { [string]: string } = {}
	local extra: { [string]: { ledger.Row } } = {}
	local memberIds: { string } = {}
	for _, share in kept do
		table.insert(memberIds, share.id)
	end
	table.sort(memberIds)
	local primary = memberIds[1]
	for _, share in kept do
		local item = store.find(share.id)
		if not item then
			fail(`{share.id} is not in this checkout: run ./zn sync first`)
		end
		local here = item :: store.Item
		homes[share.id] = here.dir
		local useAi, useTok = ai, tok
		local cellFlags = openCells
		if share.id ~= primary then
			useAi, useTok = nil, nil
			cellFlags = buffer.flags(`{cellFlags},tokens,ai`) or "tokens,ai"
		end
		extra[share.id] = {
			{
				when = when,
				subject = noteText,
				added = share.added,
				removed = share.removed,
				minutes = 0,
				how = "measured",
				phase = phase,
				tokens = useTok,
				model = modelId,
				ai = useAi,
				unmeasured = if cellFlags ~= "" then cellFlags else nil,
			},
		}
	end
	if store.isRaftId(id) then
		local raft = store.find(id)
		if raft then
			homes[id] = raft.dir
		end
	end
	local planned = costrow.plan(top, homes, extra, true)
	local wrote = costrow.writeFiles(planned)
	if #wrote == 0 then
		fail("spend: could not write the measured row")
	end
	local addArgs = { "add", "--" }
	local commitArgs = { "commit", "-q", "--only", "-m", `tracker: spend {id} {phase}`, "--" }
	for _, path in wrote do
		table.insert(addArgs, path)
		table.insert(commitArgs, path)
	end
	local added = sh.run("git", addArgs)
	if not added.ok then
		costrow.restore(planned)
		fail(`spend: could not stage the row: {sh.trim(added.stderr)}`)
	end
	local committed = sh.run("git", commitArgs)
	if not committed.ok then
		costrow.restore(planned)
		fail(`spend: could not commit the row: {sh.trim(committed.stderr .. committed.stdout)}`)
	end
	costrow.writeBuffer(top, planned)
	for _, share in kept do
		print(string.format("%s %s +%d/-%d measured", share.id, phase, share.added, share.removed))
	end
	print(sh.git({ "rev-parse", "HEAD" }))
end

-- the earliest commit time (unix seconds) that added any of `paths` (a file's homes before and after a move); nil
-- without git history
local function addedAt(paths: { string }): number?
	local args = { "log", "--diff-filter=A", "--format=%ct", "--" }
	for _, p in paths do
		table.insert(args, p)
	end
	local r = process.exec("git", args)
	if not r.ok then
		return nil
	end
	local first: number? = nil
	for line in string.gmatch(r.stdout, "[^\n]+") do
		local n = tonumber(line)
		if n and (not first or n < first) then
			first = n
		end
	end
	return first
end

-- metrics over lessons (c0111): findings per lesson tag, and design rounds before and after lessons existed
-- c0116: the design-review-NNN.md files in one item's folder.
local function designRoundsIn(dir: string): number
	-- c0118: counted by boardview.rounds, the one rule the board's chart uses too
	local paths: { string } = {}
	for _, name in fs.readDir(dir) do
		table.insert(paths, `{dir}/{name}`)
	end
	local design = boardview.rounds(paths)
	return design
end

-- metrics asks for every raft's members several times. store.members scans every issue on each call,
-- which is what made `./zn metrics` take half a minute. Filled once at the start of that command.
local memberCache: { [string]: { store.Item } }? = nil

local function metricsMembers(raftId: string): { store.Item }
	if not memberCache then
		local built: { [string]: { store.Item } } = {}
		for _, issue in store.all("issue") do
			local rid = store.readFront(issue.doc).raft
			if rid and rid ~= "" then
				local list = built[rid]
				if not list then
					list = {}
					built[rid] = list
				end
				table.insert(list, issue)
			end
		end
		memberCache = built
	end
	local cache = memberCache :: { [string]: { store.Item } }
	local found = cache[raftId]
	if found then
		return found
	end
	local empty: { store.Item } = {}
	return empty
end

-- A raft's design rounds: z-design's reviews live on each issue and z-raft's coherence review on the raft, so they
-- roll up to the raft through its members' `raft:` lines (c0116).
local function raftDesignRounds(raft: store.Item): number
	local n = designRoundsIn(raft.dir)
	for _, m in metricsMembers(raft.id) do
		n += designRoundsIn(m.dir)
	end
	return n
end

-- c0116 (review 001 F2): every retired raft's folder and document (`<root>/rafts/retired/<R-id>`), by id.
local function retiredRafts(): { { id: string, dir: string, doc: string } }
	local out: { { id: string, dir: string, doc: string } } = {}
	for _, root in store.roots() do
		local base = `{root}/rafts/{RETIRED}`
		if fs.isDir(base) then
			for _, name in fs.readDir(base) do
				local doc = `{base}/{name}/{name}.md`
				if store.isRaftId(name) and fs.isFile(doc) then
					table.insert(out, { id = name, dir = `{base}/{name}`, doc = doc })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

local function metricsLessons()
	local tree = lessonsLib.load(".")
	local all: { lessonsLib.Lesson } = {}
	for id, text in tree.lessons do
		local l = lessonsLib.parse(id, text)
		if l then
			table.insert(all, l)
		end
	end
	print("\nFindings per lesson tag (harvested review findings; a finding counts once per tag).")
	print("| tag | findings | items |\n|---|---|---|")
	for _, c in lessonsLib.tagCounts(all, tree.items) do
		print(string.format("| %s | %d | %d |", c.tag, c.findings, c.items))
	end
	local rafts: { lessonsLib.RaftRounds } = {}
	for _, raft in store.all("raft") do
		local n = raftDesignRounds(raft)
		if n > 0 then
			-- a raft is dated by its `created:` day, which no compaction or renumber rewrites
			local created = store.readFront(raft.doc).created
			table.insert(
				rafts,
				{ id = raft.id, rounds = n, start = if created then lessonsLib.day(created) else nil }
			)
		end
	end
	for _, r in retiredRafts() do
		local n = designRoundsIn(r.dir)
		if n > 0 then
			local created = store.readFront(r.doc).created
			table.insert(
				rafts,
				{ id = r.id, rounds = n, start = if created then lessonsLib.day(created) else nil }
			)
		end
	end
	-- the cutoff keeps the original add: c0114 moved the file to z-nile/engine/lessons.luau
	local added = addedAt({ "scripts/tracker/lessons.luau", "z-nile/engine/lessons.luau" })
	-- `created:` is written as the local calendar day, so the cutoff is the local day of that commit too
	local split =
		lessonsLib.roundsSplit(rafts, if added then lessonsLib.day(os.date("%Y-%m-%d", added)) else nil)
	print(
		"\nDesign rounds before and after lessons (a raft's created day against the day scripts/tracker/lessons.luau was added)."
	)
	print("| | rafts | design rounds | rounds/raft |\n|---|---|---|---|")
	print(
		string.format(
			"| before | %d | %d | %.1f |",
			split.before.rafts,
			split.before.rounds,
			split.before.mean
		)
	)
	print(
		string.format("| after | %d | %d | %.1f |", split.after.rafts, split.after.rounds, split.after.mean)
	)
end

-- capture <id> (c0119): the item's document as captured, read-only. The capture is the newest commit on origin/main
-- (HEAD without one), under the item's current id, whose subject is `tracker: new` naming it, or else the document's
-- first add; the header line carries a marker for every weaker answer (trail.capture, trail.read).
function cmd.capture(pos: { string }, _opts: { [string]: { string } })
	local id = pos[1]
	if not id or not string.match(id, "^[fdcR]%d%d%d%d$") then
		fail("usage: capture <id>")
	end
	local kind = if string.sub(id, 1, 1) == "R" then "rafts" else "issues"
	local head = if process.exec("git", { "rev-parse", "--verify", "-q", "origin/main" }).ok
		then "origin/main"
		else "HEAD"
	local commits, notes = trailLib.read(kind, id, trailLib.isDoc, head)
	local found, isCapture = nil, false
	if commits then
		found, isCapture = trailLib.capture(commits)
	end
	if not found then
		fail(`capture: no history for {id} on {head}`)
	end
	local c = found :: trailLib.Commit
	local shown = process.exec("git", { "show", `{c.sha}:{c.path}` })
	if not shown.ok then
		fail(`capture: cannot read {c.path} at {c.sha}`)
	end
	local marks = if isCapture then "" else " (no capture commit: first add)"
	if trailLib.ambiguous(commits :: { trailLib.Commit }) then
		marks ..= " (ambiguous: two items held this id at once)"
	end
	for _, note in notes do
		marks ..= ` (history before {note.sha} not followed: it changed {note.file})`
	end
	print(`capture {c.sha} {c.path} {c.subject}{marks}`)
	stdio.write(shown.stdout)
end

-- idea <id> [--text <rough>]: the idea stage. The author drafts, the challenge role challenges once,
-- and the author answers the findings when there are any. The three calls go through modelstep,
-- the same supervised start the dispatcher uses. Files land in the working tree.
function cmd.idea(pos: { string }, opts: { [string]: { string } })
	refuseInMainCheckout("idea")
	local id = pos[1]
	if not id or not string.match(id, "^[fdc]%d%d%d%d$") then
		fail("usage: idea <id> [--text <rough>]")
	end
	local item = store.find(id)
	if not item or item.kind ~= "issue" then
		fail(`idea: {id} is not an issue in this checkout`)
	end
	local here = item :: store.Item
	local doc = fs.readFile(here.doc)
	local rough = if opts["--text"] and opts["--text"][1] then opts["--text"][1] else doc
	local layers = models.walk(".", here.dir)
	local calls = 0
	local function physicalCache(): string
		-- the outermost .cache this checkout lies in, else this checkout's own
		local cwd = sh.trim(process.exec("pwd", { "-P" }).stdout) .. "/"
		local at = string.find(cwd, "/.cache/", 1, true)
		return if at then string.sub(cwd, 1, at + 7) else cwd .. ".cache/"
	end
	local function guard(bin: string): string?
		if not checking() then
			return nil
		end
		if string.sub(bin, 1, #physicalCache()) ~= physicalCache() then
			local argv = { bin }
			return `refusing to start {argv[1]}: inside a check run only a CLI under this checkout's .cache may start (found {bin})`
		end
		return nil
	end
	local function run(
		resolved: models.Resolved,
		prompt: string,
		phase: string,
		accept: (string) -> boolean
	): (string, string)
		local okDrive, drivenOrErr = pcall(function()
			return modelstep.drive({
				resolved = resolved,
				prompt = prompt,
				cwd = process.cwd,
				stateDir = `.cache/idea-run/{id}/{phase}`,
				path = process.env.PATH or "/usr/bin:/bin",
				guard = guard,
				accept = function(raw)
					return accept(idea.prose(raw))
				end,
			})
		end)
		if not okDrive then
			fail(tostring(drivenOrErr))
		end
		local driven = drivenOrErr :: modelstep.Driven
		local branch, head = costrow.branchOf(".")
		for _, a in driven.attempts do
			calls += 1
			local missing: { string } = {}
			if not a.cpu then
				table.insert(missing, "cpu")
			end
			if a.tokens <= 0 then
				table.insert(missing, "tokens")
			end
			if not a.wall then
				table.insert(missing, "wall")
			end
			costrow.append(".", {
				ms = 0,
				kind = "row",
				phase = phase,
				subject = `{id} {a.outcome}`,
				wall = a.wall,
				cpu = a.cpu,
				tokens = if a.tokens > 0 then a.tokens else nil,
				model = models.id(a.spec),
				unmeasured = if #missing > 0 then table.concat(missing, ",") else nil,
				id = id,
				branch = branch,
				head = head,
			})
			local shown = if a.tokens > 0 then tostring(a.tokens) else "unmeasured"
			local cpuShown = if a.cpu then string.format("%.3f", a.cpu) else "unmeasured"
			local wallShown = if a.wall then string.format("%.1f", a.wall) else "unmeasured"
			local note = if a.outcome == "ok" then "" else ` {a.detail}`
			print(
				`idea: {phase} model {models.id(a.spec)} tokens {shown} wall {wallShown} cpu {cpuShown} {a.outcome}{note}`
			)
		end
		if driven.outcome ~= "ok" then
			fail(`idea: {phase}: {driven.detail}`)
			return "", ""
		end
		return idea.prose(driven.prose), driven.model
	end
	local drafted: idea.Draft? = nil
	local prose, wrote = run(models.resolve(layers, "idea"), idea.authorPrompt(rough), "idea", function(text)
		drafted = idea.parseDraft(text)
		return drafted ~= nil
	end)
	local challenge = models.resolve(layers, "idea-challenge")
	challenge.authorModel = wrote
	local findings: { idea.Finding } = {}
	local verdict: string? = nil
	run(challenge, idea.challengePrompt(prose), "idea-challenge", function(text)
		local found, said = idea.parseReview(text)
		findings = found
		verdict = said
		return said == "approve" or said == "revise"
	end)
	local body = drafted :: idea.Draft
	local answers: { [string]: string } = {}
	if not (verdict == "approve" and #findings == 0) then
		local revised: idea.Draft? = nil
		run(models.resolve(layers, "idea"), idea.answerPrompt(rough, findings), "idea", function(text)
			revised = idea.parseDraft(text)
			answers = idea.parseAnswers(text)
			return revised ~= nil
		end)
		body = revised :: idea.Draft
	end
	local openLines = idea.openLines(findings, answers)
	local reviewPath = `{here.dir}/idea-review-001.md`
	fs.writeFile(here.doc, withFront(idea.apply(doc, body, openLines), "idea", "challenged"))
	fs.writeFile(reviewPath, idea.reviewText(findings, verdict or "revise"))
	local refutePath = `{here.dir}/idea-refute-001.md`
	if #findings > 0 then
		fs.writeFile(refutePath, idea.refuteText(findings, answers))
		print(refutePath)
	end
	print(here.doc)
	print(reviewPath)
	print(`idea: calls {calls}`)
	print(
		`idea: verdict {verdict}; commit these and push them to origin/main before ./zn status {id} preparing`
	)
end

local function optNum(opts: { [string]: { string } }, name: string): number?
	local raw = opts[name] and opts[name][1]
	return if raw and raw ~= "" then tonumber(raw) else nil
end

local function optStr(opts: { [string]: { string } }, name: string): string?
	local raw = opts[name] and opts[name][1]
	return if raw and raw ~= "" then raw else nil
end

function cmd.record(_pos: { string }, opts: { [string]: { string } })
	local root = process.env.ZN_TOP or "."
	local phase = optStr(opts, "--phase") or "test"
	local wall, cpu = optNum(opts, "--wall"), optNum(opts, "--cpu")
	local report = optStr(opts, "--report")
	if report and fs.isFile(report) then
		local w, c = costrow.report(fs.readFile(report))
		wall = wall or w
		cpu = cpu or c
	end
	local missing: { string } = {}
	if opts["--unmeasured"] then
		for _, name in opts["--unmeasured"] do
			if name ~= "" then
				table.insert(missing, name)
			end
		end
	end
	if report and wall == nil then
		table.insert(missing, "wall")
	end
	if report and cpu == nil then
		table.insert(missing, "cpu")
	end
	local test = optNum(opts, "--test")
	if phase == "test" and test == nil then
		test = wall
	end
	local branch, head = costrow.branchOf(root)
	local kind = if phase == "test" then "test" elseif phase == "other" then "run" else "row"
	local appended = costrow.append(root, {
		ms = 0,
		kind = kind,
		phase = phase,
		subject = optStr(opts, "--subject") or "measured",
		wall = wall,
		cpu = cpu,
		ai = optNum(opts, "--ai"),
		test = test,
		tokens = optNum(opts, "--tokens"),
		model = optStr(opts, "--model"),
		unmeasured = if #missing > 0 then table.concat(missing, ",") else nil,
		id = optStr(opts, "--id") or "",
		branch = branch,
		head = head,
	})
	if not appended then
		fail("record: could not append the measurement")
	end
	print(costrow.bufferFile(root))
end

local function showSeconds(n: number, open: boolean): string
	if open and n == 0 then
		return "unmeasured"
	end
	return string.format("%.3f", n)
end

local function showTokens(n: number, open: boolean): string
	if open and n == 0 then
		return "unmeasured"
	end
	return tostring(n)
end

function cmd.metrics(pos: { string }, opts: { [string]: { string } })
	type Counted = {
		id: string,
		type: string,
		raft: string,
		added: number,
		removed: number,
		minutes: number,
		tokens: number,
		rows: { ledger.Row },
	}
	memberCache = nil
	local rows: { Counted } = {}
	local byType: { [string]: { added: number, minutes: number, count: number } } = {}
	local seenRows: { [string]: boolean } = {}
	local cachedRows: { [string]: { ledger.Row }? } = {}
	local function rowsOf(issue: store.Item): { ledger.Row }?
		if seenRows[issue.id] then
			return cachedRows[issue.id]
		end
		seenRows[issue.id] = true
		local parsed = ledgerRows(issue)
		cachedRows[issue.id] = parsed
		return parsed
	end
	for _, issue in store.all("issue") do
		if issue.state == "done" or (issue.state == "active" and opts["--include-active"]) then
			local parsed = rowsOf(issue)
			if not parsed then
				continue
			end
			local t = ledger.sum(parsed)
			local cost = ledger.cost(parsed)
			local ty = store.typeOf(issue)
			table.insert(rows, {
				id = issue.id,
				type = ty,
				raft = store.readFront(issue.doc).raft or "",
				added = t.added,
				removed = t.removed,
				minutes = cost.reported,
				tokens = cost.tokens,
				rows = parsed,
			})
			local b = byType[ty] or { added = 0, minutes = 0, count = 0 }
			b.added += t.added
			b.minutes += cost.reported
			b.count += 1
			byType[ty] = b
		end
	end
	print(
		"\nCost per issue (done, plus active with --include-active). Reported is typed minutes; wall, cpu, ai and test are measured seconds."
	)
	print(
		"| issue | type | raft | +lines | -lines | reported | wall | cpu | tokens | ai | test | n |\n|---|---|---|---|---|---|---|---|---|---|---|---|"
	)
	for _, r in rows do
		local cost = ledger.cost(r.rows)
		print(
			string.format(
				"| %s | %s | %s | %d | %d | %.1f | %s | %s | %s | %s | %s | %d |",
				r.id,
				r.type,
				r.raft,
				r.added,
				r.removed,
				cost.reported,
				showSeconds(cost.wall, false),
				showSeconds(cost.cpu, false),
				showTokens(cost.tokens, cost.tokensOpen),
				showSeconds(cost.ai, cost.aiOpen),
				showSeconds(cost.test, false),
				cost.n
			)
		)
	end
	print("\nTotals by type (reported minutes).")
	print("| type | issues | +lines | reported | minutes/issue |\n|---|---|---|---|---|")
	for _, ty in { "feature", "defect", "chore" } do
		local b = byType[ty] or { added = 0, minutes = 0, count = 0 }
		local per = if b.count > 0 then b.minutes / b.count else 0
		print(string.format("| %s | %d | %d | %.1f | %.1f |", ty, b.count, b.added, b.minutes, per))
	end
	local phaseMin: { [string]: { [string]: number } } = {}
	local phaseTok: { [string]: number } = {}
	for _, p in ledger.PHASES do
		phaseMin[p] = { feature = 0, defect = 0, chore = 0 }
		phaseTok[p] = 0
	end
	for _, p in ledger.EXTRA do
		phaseMin[p] = { feature = 0, defect = 0, chore = 0 }
		phaseTok[p] = 0
	end
	for _, r in rows do
		for _, row in r.rows do
			local tenths = math.floor(row.minutes * 10 + 0.5)
			phaseMin[row.phase][r.type] += tenths
			phaseTok[row.phase] += row.tokens or 0
		end
	end
	print("\nSpend by phase (agent-minutes).")
	print("| phase | feature | defect | chore | all | tokens |\n|---|---|---|---|---|---|")
	local phaseOrder = table.clone(ledger.PHASES)
	for _, p in ledger.EXTRA do
		table.insert(phaseOrder, p)
	end
	for _, p in phaseOrder do
		local m = phaseMin[p]
		local all = m.feature + m.defect + m.chore
		if (p == "test" or p == "other") and all == 0 and phaseTok[p] == 0 then
			continue
		end
		print(
			string.format(
				"| %s | %.1f | %.1f | %.1f | %.1f | %d |",
				p,
				m.feature / 10,
				m.defect / 10,
				m.chore / 10,
				all / 10,
				phaseTok[p]
			)
		)
	end
	print("\nSpend per raft by phase (rafts with at least one counted issue).")
	print(
		"| raft | type | capture | prep | design-review | build | code-review | deliver | all | tokens |\n|---|---|---|---|---|---|---|---|---|---|"
	)
	local byRaft: { [string]: { Counted } } = {}
	local raftIds: { string } = {}
	for _, r in rows do
		if r.raft ~= "" then
			if not byRaft[r.raft] then
				byRaft[r.raft] = {}
				table.insert(raftIds, r.raft)
			end
			table.insert(byRaft[r.raft], r)
		end
	end
	table.sort(raftIds)
	for _, rid in raftIds do
		local raft = store.find(rid)
		local ty = if raft then store.typeOf(raft) else "?"
		local tenths: { [string]: number } = {}
		local tokens, allTenths = 0, 0
		for _, p in ledger.PHASES do
			tenths[p] = 0
		end
		for _, p in ledger.EXTRA do
			tenths[p] = 0
		end
		for _, r in byRaft[rid] do
			for _, row in r.rows do
				local n = math.floor(row.minutes * 10 + 0.5)
				tenths[row.phase] += n
				allTenths += n
				tokens += row.tokens or 0
			end
		end
		print(
			string.format(
				"| %s | %s | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %d |",
				rid,
				ty,
				tenths.capture / 10,
				tenths.prep / 10,
				tenths["design-review"] / 10,
				tenths.build / 10,
				tenths["code-review"] / 10,
				tenths.deliver / 10,
				allTenths / 10,
				tokens
			)
		)
	end
	print("\nDesign-review cost per round (every raft with a design-review file, members in any state).")
	print(
		"| raft | design rounds | design-review minutes | minutes/round | tokens/round |\n|---|---|---|---|---|"
	)
	for _, raft in store.all("raft") do
		local rounds = raftDesignRounds(raft)
		if rounds == 0 then
			continue
		end
		local tenths, tokens = 0, 0
		for _, issue in metricsMembers(raft.id) do
			local parsed = rowsOf(issue)
			if parsed then
				for _, row in parsed do
					if row.phase == "design-review" then
						tenths += math.floor(row.minutes * 10 + 0.5)
						tokens += row.tokens or 0
					end
				end
			end
		end
		local mins = tenths / 10
		print(
			string.format(
				"| %s | %d | %.1f | %.1f | %d |",
				raft.id,
				rounds,
				mins,
				mins / rounds,
				math.floor(tokens / rounds + 0.5)
			)
		)
	end
	-- a retired raft keeps its rounds; its spend went with its members (c0116, review 001 F2)
	for _, r in retiredRafts() do
		local rounds = designRoundsIn(r.dir)
		if rounds > 0 then
			print(string.format("| %s | %d | %.1f | %.1f | %d |", r.id, rounds, 0, 0, 0))
		end
	end
	print("\nMeasured per raft (sums of its counted issues).")
	print("| raft | reported | wall | cpu | tokens | ai | test | n |\n|---|---|---|---|---|---|---|---|")
	for _, rid in raftIds do
		local all: { ledger.Row } = {}
		for _, r in byRaft[rid] do
			for _, row in r.rows do
				table.insert(all, row)
			end
		end
		local cost = ledger.cost(all)
		print(
			string.format(
				"| %s | %.1f | %s | %s | %s | %s | %s | %d |",
				rid,
				cost.reported,
				showSeconds(cost.wall, false),
				showSeconds(cost.cpu, false),
				showTokens(cost.tokens, cost.tokensOpen),
				showSeconds(cost.ai, cost.aiOpen),
				showSeconds(cost.test, false),
				cost.n
			)
		)
	end
	if pos[1] then
		local item = store.find(pos[1])
		local parsed: { ledger.Row }? = nil
		if item and item.kind == "issue" then
			parsed = rowsOf(item) or {}
		elseif item and item.kind == "raft" then
			local stageRows: { ledger.Row } = {}
			for _, member in metricsMembers(item.id) do
				local part = rowsOf(member)
				if part then
					for _, row in part do
						table.insert(stageRows, row)
					end
				end
			end
			parsed = stageRows
		end
		if parsed then
			print(`\nStages for {pos[1]}.`)
			print(
				"| stage | reported | wall | cpu | tokens | ai | test | n |\n|---|---|---|---|---|---|---|---|"
			)
			local stageOrder = table.clone(ledger.PHASES)
			for _, p in ledger.EXTRA do
				table.insert(stageOrder, p)
			end
			for _, p in stageOrder do
				local group: { ledger.Row } = {}
				for _, row in parsed do
					if row.phase == p then
						table.insert(group, row)
					end
				end
				if #group == 0 then
					continue
				end
				local cost = ledger.cost(group)
				print(
					string.format(
						"| %s | %.1f | %s | %s | %s | %s | %s | %d |",
						p,
						cost.reported,
						showSeconds(cost.wall, false),
						showSeconds(cost.cpu, false),
						showTokens(cost.tokens, cost.tokensOpen),
						showSeconds(cost.ai, cost.aiOpen),
						showSeconds(cost.test, false),
						cost.n
					)
				)
			end
		end
		if item and item.kind == "issue" then
			print(approval.summary(item))
		elseif item and item.kind == "raft" then
			for _, member in store.members(item.id) do
				print(approval.summary(member))
			end
		end
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
	-- one id-sorted list: the rafts store finds, and (c0116, review 001 F2) the retired ones, whose review files stay in
	-- rafts/retired/<R-id>
	local roundRows: { { id: string, line: string } } = {}
	local function formatOf(first: string): string
		if not fs.isFile(first) then
			return "none"
		end
		return if string.find("\n" .. fs.readFile(first), "\nConsequences:", 1, true)
			then "second-order"
			else "classic"
	end
	local function codeRounds(dir: string): number
		-- c0118: counted by boardview.rounds, the one rule the board's chart uses too
		local paths: { string } = {}
		for _, name in fs.readDir(dir) do
			table.insert(paths, `{dir}/{name}`)
		end
		local _, code = boardview.rounds(paths)
		return code
	end
	for _, raft in store.all("raft") do
		local first = `{raft.dir}/design-review-001.md`
		if not fs.isFile(first) then
			for _, m in metricsMembers(raft.id) do
				if fs.isFile(`{m.dir}/design-review-001.md`) then
					first = `{m.dir}/design-review-001.md`
					break
				end
			end
		end
		table.insert(roundRows, {
			id = raft.id,
			line = string.format(
				"| %s | %d | %d | %s |",
				raft.id,
				raftDesignRounds(raft),
				codeRounds(raft.dir),
				formatOf(first)
			),
		})
	end
	for _, r in retiredRafts() do
		table.insert(roundRows, {
			id = r.id,
			line = string.format(
				"| %s | %d | %d | %s |",
				r.id,
				designRoundsIn(r.dir),
				codeRounds(r.dir),
				formatOf(`{r.dir}/design-review-001.md`)
			),
		})
	end
	table.sort(roundRows, function(a, b)
		return a.id < b.id
	end)
	for _, row in roundRows do
		print(row.line)
	end
	print("\nDesign rounds per issue (design-review-NNN.md in the issue's own folder, from z-design; c0116).")
	print("| issue | raft | design rounds |\n|---|---|---|")
	for _, issue in store.all("issue") do
		local n = designRoundsIn(issue.dir)
		if n > 0 then
			print(string.format("| %s | %s | %d |", issue.id, store.readFront(issue.doc).raft or "", n))
		end
	end
	print(
		"\nSize estimates (z-design's size: against the changed lines counted, for counted issues with one)."
	)
	print("| issue | size | changed lines | ratio |\n|---|---|---|---|")
	for _, r in rows do
		local issue = store.find(r.id)
		local size = issue and raftplan.parseSize(store.readFront(issue.doc).size)
		if size then
			local changed = r.added + r.removed
			print(string.format("| %s | %d | %d | %.2f |", r.id, size, changed, changed / size))
		end
	end
	metricsLessons()
	print("\nRework = defect / (defect + feature). Target: under 20%.")
	print("Rework counts every phase, capture to deliver.")
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
	-- ./zn runs from the repo root, so say where a relative path really is
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

-- `dispatch …` (c0117): the dispatcher, dispatcher.luau, with the tracker's readers of origin/main.
function cmd.dispatch(pos: { string }, opts: { [string]: { string } })
	local function origin(id: string): dispatcherLib.OriginItem?
		if not hasOrigin() then
			return nil
		end
		sh.run("git", { "fetch", "-q", "origin", "main" })
		local readTree, files = originTree()
		local path = if readTree then docPath(files, id) else nil
		if not path then
			return nil
		end
		local shown = sh.run("git", { "show", `origin/main:{path}` })
		if not shown.ok then
			return nil
		end
		local front = frontOf(shown.stdout)
		local state = stateOfPath(path)
		return { path = path, front = front, state = state, status = statusLib.effective(front, state) }
	end
	local function originIssueIds(): { string }
		sh.run("git", { "fetch", "-q", "origin", "main" })
		local _, files = originTree()
		local out: { string } = {}
		for _, p in files do
			local pid, rel = publish.itemPath(p)
			if pid and store.isIssueId(pid) and rel == `{pid}.md` then
				table.insert(out, pid)
			end
		end
		return out
	end
	local code = dispatcherLib.main({
		fail = fail,
		mainRoot = mainRoot,
		onGitHub = onGitHub,
		checking = checking,
		origin = origin,
		originIssueIds = originIssueIds,
		-- a PR's state for the chain's gates (c0117): only on a GitHub origin, through the real gh
		-- a pull request's merge commit (c0117: a commit on main that is vetted without being tracker state)
		prMerged = function(sha: string): boolean
			if not onGitHub() then
				return false
			end
			local r = sh.run("gh", { "api", `repos/\{owner\}/\{repo\}/commits/{sha}/pulls` })
			return r.ok and dispatchLib.prMergedFrom(r.stdout, sha)
		end,
		prView = function(branch: string): string?
			if not onGitHub() then
				return nil
			end
			local r = sh.run("gh", {
				"pr",
				"view",
				branch,
				"--json",
				"number,state,isDraft,mergeable,statusCheckRollup,headRefOid",
			})
			return if r.ok then r.stdout else nil
		end,
	}, pos, opts)
	process.exit(code)
end

-- `reap` finds this user's leaked processes (z-nile/engine/reap.luau decides; this reads `ps` and `lsof` and signals,
-- zz-test skill, "Bounded commands"). Returns true when a leak could not be stopped.
local function reapRun(opts: { [string]: { string } }): boolean
	local quiet = opts["--quiet"] ~= nil
	if process.os ~= "macos" then
		if quiet then
			return false -- `--auto` on another host: the reaper reads BSD `ps`, so there is nothing to do
		end
		stdio.ewrite("reap: supported on macOS only (it reads BSD ps and lsof)\n")
		process.exit(2)
	end
	local function num(flag: string, default: number): number
		local v = opts[flag] and opts[flag][1]
		if v == nil then
			return default
		end
		if not string.match(v, "^%d+$") then
			stdio.ewrite(`reap: {flag} needs a whole number of seconds\n`)
			process.exit(2)
		end
		return tonumber(v) :: number
	end
	local listing = "pid=,ppid=,uid=,etime=,time=,lstart=,command="
	local procs, problems = reapLib.parse(sh.must("env", { "LC_ALL=C", "ps", "-axww", "-o", listing }))
	if #problems > 0 then
		-- one line under --quiet: a host whose `ps` prints another layout must not print a page at every sync
		stdio.ewrite(
			if quiet
				then `reap: skipped ({#problems} unreadable ps lines)\n`
				else table.concat(problems, "\n") .. "\n"
		)
		if quiet then
			return false
		end
	end
	local byPid: { [number]: reapLib.Proc } = {}
	for _, pr in procs do
		byPid[pr.pid] = pr
	end
	for pid, deadline in
		reapLib.markers(sh.must("env", { "LC_ALL=C", "ps", "-axww", "-E", "-o", "pid=,command=" }), procs)
	do
		byPid[pid].deadline = deadline
	end
	-- the reaper and its ancestors: this process's parent shell is the first
	local me = tonumber(sh.trim(sh.must("sh", { "-c", "echo $PPID" }))) or 0
	local self: { number } = { me }
	local at = byPid[me]
	while at ~= nil and at.ppid > 1 and #self < 64 do
		table.insert(self, at.ppid)
		at = byPid[at.ppid]
	end
	local roots: { string } = opts["--root"] or {}
	local under: number? = if opts["--under"]
		then tonumber(opts["--under"][1])
		elseif opts["--session-end"] then reapLib.sessionRoot(procs, self)
		else nil
	local minAge = num("--min-age", 60)
	local home = process.env.HOME or ""
	local bad = reapLib.checkOptions({
		roots = roots,
		under = if opts["--under"] then under else nil,
		underIsClaude = under ~= nil
			and byPid[under] ~= nil
			and reapLib.name(byPid[under].command) == "claude",
		minAge = minAge,
		home = home,
	})
	if bad then
		stdio.ewrite(`reap: {bad}\n`)
		process.exit(2)
	end
	local main = ""
	if #roots == 0 then
		local common = sh.git({ "rev-parse", "--path-format=absolute", "--git-common-dir" })
		main = (string.gsub(common, "/%.git/?$", ""))
	end
	local temp = sh.trim(sh.run("getconf", { "DARWIN_USER_TEMP_DIR" }).stdout)
	local scope = reapLib.scope(
		main,
		sh.trim(sh.must("id", { "-u" })),
		if temp ~= "" then "/private" .. (string.gsub(temp, "/+$", "")) else "",
		roots
	)
	local options: reapLib.Options = {
		uid = tonumber(sh.trim(sh.must("id", { "-u" }))) :: number,
		now = os.time(),
		minAge = minAge,
		grace = 5,
		roots = scope.roots,
		scratch = scope.scratch,
		self = self,
		under = under,
		sessionAnywhere = scope.sessionAnywhere,
	}
	local want = reapLib.wantCwd(procs, options)
	for i = 1, #want, 200 do
		local chunk = table.move(want, i, math.min(i + 199, #want), 1, {})
		-- lsof exits 1 when some pid is gone; what it printed is still right
		local r = sh.run("lsof", { "-a", "-d", "cwd", "-Fpn", "-p", table.concat(chunk, ",") })
		local current: reapLib.Proc? = nil
		for line in string.gmatch(r.stdout, "[^\n]+") do
			local tag, rest = string.sub(line, 1, 1), string.sub(line, 2)
			if tag == "p" then
				current = byPid[tonumber(rest) :: number]
			elseif tag == "n" and current ~= nil then
				current.cwd = rest
			end
		end
	end
	local targets = reapLib.decide(procs, options)
	local dry = opts["--dry-run"] ~= nil
	local lines: { string } = {}
	local failed = false
	-- Every target's tree is checked first (each process is still the one the snapshot saw: a pid may have been reused;
	-- a changed root leaves its target alone, a changed descendant is left out), then all are signalled together: TERM,
	-- a shared wait of up to two seconds, KILL for what is left. One wait for all keeps a session end inside its budget.
	local stopping: { { target: reapLib.Target, pids: { string } } } = {}
	-- the start time of every process of every tree, read once: a pid whose start time still is the snapshot's is the
	-- same process (a pid may have been reused since)
	local snapshot: { [string]: string } = {}
	for _, t in targets do
		snapshot[tostring(t.proc.pid)] = t.proc.start
		for _, d in t.tree do
			snapshot[tostring(d.pid)] = d.start
		end
	end
	local ids: { string } = {}
	for id in snapshot do
		table.insert(ids, id)
	end
	-- the pids of `ids` that are running now and are still the snapshot's process: one `ps` for all (a zombie is gone)
	local function running(ofIds: { string }): { string }
		if #ofIds == 0 then
			return {}
		end
		local r =
			sh.run("env", { "LC_ALL=C", "ps", "-o", "pid=,stat=,lstart=", "-p", table.concat(ofIds, ",") })
		local same: { [string]: boolean } = {}
		for line in string.gmatch(r.stdout, "[^\n]+") do
			local pid, stat, started = string.match(line, "^%s*(%d+)%s+(%S+)%s+(.-)%s*$")
			if pid and stat and started and string.sub(stat, 1, 1) ~= "Z" and snapshot[pid] == started then
				same[pid] = true
			end
		end
		local left: { string } = {}
		for _, id in ofIds do
			if same[id] then
				table.insert(left, id)
			end
		end
		return left
	end
	local alive: { [string]: boolean } = {}
	for _, id in running(ids) do
		alive[id] = true
	end
	for _, t in targets do
		if dry then
			table.insert(lines, reapLib.line(t, "would stop"))
			continue
		end
		local pids: { string } = {}
		local root = tostring(t.proc.pid)
		if alive[root] then
			table.insert(pids, root)
			for _, d in t.tree do
				if alive[tostring(d.pid)] then
					table.insert(pids, tostring(d.pid))
				end
			end
			table.insert(stopping, { target = t, pids = pids })
		else
			table.insert(lines, reapLib.line(t, "left alone (changed since the snapshot)"))
		end
	end
	local all: { string } = {}
	for _, item in stopping do
		for _, pid in item.pids do
			table.insert(all, pid)
		end
	end
	if #all > 0 then
		sh.run("kill", { "-TERM", table.unpack(all) })
		-- a shared wait, bounded by the clock (two seconds), polling every tenth of a second: one `ps` and one `sleep` a poll
		local left = all
		local deadline = os.time() + 2
		repeat
			left = running(left)
			if #left == 0 then
				break
			end
			sh.run("sleep", { "0.1" })
		until os.time() >= deadline
		left = running(left)
		if #left > 0 then
			sh.run("kill", { "-KILL", table.unpack(left) }) -- only what is still the snapshot's process
			sh.run("sleep", { "0.2" })
		end
	end
	local remaining: { [string]: boolean } = {}
	for _, pid in running(all) do
		remaining[pid] = true
	end
	for _, item in stopping do
		local stuck = false
		for _, pid in item.pids do
			stuck = stuck or remaining[pid] == true
		end
		failed = failed or stuck
		table.insert(lines, reapLib.line(item.target, if stuck then "COULD NOT STOP" else "stopped"))
	end
	if #lines == 0 and not quiet then
		table.insert(lines, "reap: no leaked processes")
	end
	for _, l in lines do
		stdio.ewrite(l .. "\n")
	end
	local log = opts["--log"] and opts["--log"][1]
	if log ~= nil and #targets > 0 then
		-- one appending write per line (O_APPEND is atomic for a line, so two reapers never interleave inside one)
		local when = os.date("%Y-%m-%d %H:%M:%S ") :: string
		for _, l in lines do
			sh.run("sh", { "-c", 'printf "%s\\n" "$1" >> "$2"', "_", when .. l, log })
		end
	end
	return failed
end

-- `reap` is also what `sync` and the gate run (`--auto`): quiet unless it stops something, a no-op inside a check run
-- (the guards protect this repository there), and never a reason for the caller to fail.
cmd["watch-bootstrap"] = function()
	watchcmd.bootstrap()
end

-- Returns at once. The net runs under ./zn run and writes .cache/watch-net.log in this checkout.
cmd["watch-kick"] = function()
	watchcmd.kick()
end

-- Edits `.worktree/watch-net`, never this checkout's files, and pushes a repair onto main.
cmd["watch-net"] = function()
	watchcmd.net()
end

function cmd.reap(_: { string }, opts: { [string]: { string } })
	if opts["--auto"] == nil then
		if reapRun(opts) then
			process.exit(1)
		end
		return
	end
	if guarded(true) then
		return
	end
	opts["--quiet"] = { "true" }
	local ok, err = pcall(reapRun, opts)
	if not ok then
		stdio.ewrite(`reap: skipped ({err})\n`)
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
	stack = true,
	stamp = true,
	trace = true,
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
