--!strict
-- Tracker CLI. Run through ./zn at the repository root (c0114). See z-nile/skills/zz-rules/SKILL.md.
local audit = require("./audit")
local board = require("./board")
local boardview = require("./boardview")
local brokerLib = require("./broker")
local claimsLib = require("./claims")
local compactLib = require("./compact")
local dispatchLib = require("./dispatch")
local dispatcherLib = require("./dispatcher")
local fs = require("@lune/fs")
local gateLib = require("./gate")
local idsLib = require("./ids")
local ledger = require("./ledger")
local lessonsLib = require("./lessons")
local pathsLib = require("./paths")
local process = require("@lune/process")
local projects = require("./projects")
local provenance = require("./provenance")
local publish = require("./publish")
local raftcheck = require("./raftcheck")
local raftplan = require("./raftplan")
local reapLib = require("./reap")
local sh = require("../lib/sh")
local skillsLib = require("./skills")
local spend = require("./spend")
local statusLib = require("./status")
local stdio = require("@lune/stdio")
local store = require("./store")
local trailLib = require("./trail")

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
  ready <R-id|issue-id>                         claim the raft, move it to active/ on origin/main, write <root>/rafts/active/<R>/prompt.md
  stop <R-id>                                   give back a readied or started raft: move it out of active/ on origin/main, remove its prompt
  stop <issue>                                  give back one active issue whose raft is retired, missing or empty
  start <R-id>                                  branch, empty commit, push, draft PR (a readied raft; a backlog raft is claimed and moved)
  focus <issue-id>                              attribute following commits to this issue
  commit -m <msg> [--issue <id>]... [--time <minutes>] [--phase build|code-review|deliver] [--tokens <n>]
         [--model <id>]                         stage all, record spend, commit, push
  spend <id> --phase capture|prep|design-review|deliver --time <minutes> [--tokens <n>] [--model <id>]
         [--note <text>]                        append one phase's rows to origin/main; changes nothing here
  record <id> unblocked|confirmed|ranked [--actor <actor>] [--detail <k=v>]
                                                append one row to the item's provenance.md on origin/main (c0263)
  dispatch <id> [--dry-run]                     run the chain on an item from its tracker state (ticket, design, raft,
                                                ready, run), stopping at a merge gate, questions.md or a failure
  dispatch new "<description>" [--project <name>] [--dry-run]
                                                capture a new issue (z-ticket) and run its chain
  dispatch <step> <id> [--mode design|code|raft] [--dry-run]
                                                run one step: a model step on .models.toml's CLIs, a script step itself
  dispatch stop|retry|status <id>               stop a running step (its process group), rerun the failed step, show it
  dispatch vet                                  the user's: take main as vetted after a tripwire stop (the watermark)
  done <R-id>                                   verify checks + review resolution, move to done, ready PR (commit is deliver)
  worktree <R-id|name>                          create or reuse .worktree/<R-id|name> from origin/main; print its path
  worktree-prune                                remove worktrees of rafts that are done on main
  workstreams <R-id>                            plan parallel workstreams (waves) for a raft
  promote-check <R-id|issue-id>                 dry-run: would promoted acceptance specs pass type check + meta?
  prompt <R-id> [--path]                        print a readied raft's prompt.md (--path: its path)
  capture <id>                                  print the item's document as captured (read-only)
  metrics [--include-active]                    cost per issue and rework %
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

-- c0263: merging two branches that both appended to item records. A record is found by its item id, never by git's
-- pairing of files (git pairs small, templated records across ids and across folder moves).
local function gitLines(args: { string }): { string }
	local out: { string } = {}
	for line in string.gmatch(sh.run("git", args).stdout, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

-- `publish.itemPath` for reading: the layout publish and audit use, plus a retired raft's folder (`rafts/retired/<R-id>/`:
-- `recombine` moves a raft there on its branch while its record may still be published into). Publishing into a retired
-- raft stays refused by `publish.allowed`, which does not use this.
local function itemPathOf(path: string): (string?, string?)
	local id, rel = publish.itemPath(path)
	if id then
		return id, rel
	end
	local plain, swapped = string.gsub(path, "/rafts/retired/", "/rafts/", 1)
	if swapped == 1 then
		return publish.itemPath(plain)
	end
	return nil, nil
end

-- the id of the item whose record `path` is (the item's own folder under a project root, like publish and audit), or nil
local function recordIdOf(path: string): string?
	local id, rel = itemPathOf(path)
	return if rel == "provenance.md" then id else nil
end

-- the paths of `paths` that are item records
local function recordPaths(paths: { string }): { string }
	local out: { string } = {}
	for _, path in paths do
		if recordIdOf(path) then
			table.insert(out, path)
		end
	end
	return out
end

-- The ids of every record either side changed since `base` (git trees or commits; old and new paths of a rename
-- alike, found with `--no-renames`), in the order found (ours', then theirs'), and whether each side changed any.
local function changedRecordIds(base: string, ours: string, theirs: string): ({ string }, boolean, boolean)
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	local flags: { [string]: boolean } = {}
	for _, side in { ours, theirs } do
		for _, path in gitLines({ "diff", "--name-only", "--no-renames", base, side }) do
			local id = recordIdOf(path)
			if id then
				flags[side] = true
				if not seen[id] then
					seen[id] = true
					table.insert(ids, id)
				end
			end
		end
	end
	return ids, flags[ours] == true, flags[theirs] == true
end

type Planned = { id: string, action: string, text: string?, folder: string? }

-- What to do with each record of `ids`: `provenance.settle` over the record of each id at `ours`, `theirs` and `base`
-- (commits or trees), and for a written record the folder of the item's one document in `merged` (the listing of the
-- merged tree). `unmerged` are the ids git left unmerged. Nil and why on the first stop.
local function planRecords(
	ids: { string },
	ours: string,
	theirs: string,
	base: string,
	merged: { string }
): ({ Planned }?, string?)
	local lists: { [string]: { string } } = {}
	for _, tree in { ours, theirs, base } do
		lists[tree] = recordPaths(gitLines({ "ls-tree", "-r", "--name-only", tree }))
	end
	local function recordAt(tree: string, id: string): (string?, string?)
		local path, why = provenance.locate(lists[tree], id)
		if why then
			return nil, why
		end
		return if path then sh.run("git", { "show", `{tree}:{path}` }).stdout else nil, nil
	end
	local plans: { Planned } = {}
	for _, id in ids do
		local own, ownWhy = recordAt(ours, id)
		local their, theirWhy = recordAt(theirs, id)
		local common, commonWhy = recordAt(base, id)
		if ownWhy or theirWhy or commonWhy then
			return nil, ownWhy or theirWhy or commonWhy
		end
		local action, text, problem = provenance.settle(common, own, their)
		if not action then
			return nil, `{id}: {problem}`
		end
		local folder: string? = nil
		if action == "write" then
			for _, path in merged do
				local found = string.match(path, `^(.*/{id})/{id}%.md$`)
				if found and select(2, itemPathOf(path)) == `{id}.md` then
					if folder then
						return nil, `{id} has its document in two places`
					end
					folder = found
				end
			end
			if not folder then
				return nil,
					`{id}: the merge has no document for its record (the item was removed or its id changed: ./zn remap after a compaction, a merge by hand after a renumber)`
			end
		end
		local act: string = action
		table.insert(plans, { id = id, action = act, text = text, folder = folder })
	end
	return plans, nil
end

-- The way through a merge that stopped on a conflict outside the records.
local HAND =
	"merge by hand: git merge origin/main, resolve every conflict except provenance.md (leave the records to the engine), git add the files, then run ./zn sync again: it finishes that merge, uniting the records"

-- A merge of `ref` into this worktree that unites the item records both sides appended to. The merge is made with
-- `--no-commit`; then every record either side changed since the merge base is settled by item id (planRecords): the
-- record goes beside the item's document in the merge (written through the index, and never over a path with
-- uncommitted changes), every other path of that id's record is removed with `git rm -f`, and the merge is committed
-- with the message git prepared. A stop aborts the merge we started (no MERGE_HEAD, the tree as it was), as does any
-- error: the body runs in a `pcall`. Refused first: a merge of a branch `ref` does not contain, a cherry-pick, a
-- revert or a rebase in progress (not ours to finish or abort). A merge in progress of `ref` or of an older commit of it
-- (a hand merge that has only records left) is finished first, never aborted, and then `ref` is merged on top.
-- Returns whether it merged, the failure text, and whether it aborted a merge.
local function mergeRef(ref: string): (boolean, string, boolean)
	local function inProgress(name: string): boolean
		return sh.run("git", { "rev-parse", "-q", "--verify", name }).ok
	end
	local target = sh.trim(sh.run("git", { "rev-parse", "-q", "--verify", ref .. "^{commit}" }).stdout)
	local gitDir = sh.trim(sh.run("git", { "rev-parse", "--absolute-git-dir" }).stdout)
	-- settle the records of the merge in progress and commit it; `ours` says whether we started it (a stop aborts it)
	local function settleAndCommit(detail: string, ours: boolean): (boolean, string)
		local function abort(why: string): (boolean, string)
			if ours then
				sh.run("git", { "merge", "--abort" })
			end
			return false, why
		end
		local ran, done, why = pcall(function(): (boolean, string)
			local unmerged: { [string]: boolean } = {}
			local unmergedIds: { string } = {}
			for _, line in gitLines({ "ls-files", "-u" }) do
				local path = string.match(line, "^%d+ %x+ %d\t(.+)$")
				local id = if path then recordIdOf(path) else nil
				if not path or not id then
					return false, `{detail}\n{HAND}` -- a conflict outside the records
				end
				unmerged[path] = true
				if not table.find(unmergedIds, id) then
					table.insert(unmergedIds, id)
				end
			end
			local base = sh.trim(sh.run("git", { "merge-base", "HEAD", "MERGE_HEAD" }).stdout)
			local ids, oursChanged, theirsChanged = changedRecordIds(base, "HEAD", "MERGE_HEAD")
			for _, id in unmergedIds do
				if not table.find(ids, id) then
					table.insert(ids, id)
				end
			end
			if #ids > 0 then
				-- ids mean the same item only while both sides number items alike: a compaction on one side reuses them
				local function mapAt(commit: string): string?
					local shown = sh.run("git", { "show", `{commit}:{idsLib.MAP_FILE}` })
					return if shown.ok then shown.stdout else nil
				end
				local crossing = provenance.compactionProblem(
					mapAt(base),
					mapAt("HEAD"),
					mapAt("MERGE_HEAD"),
					oursChanged,
					theirsChanged
				)
				if crossing then
					return false, `{crossing}\n{detail}`
				end
				local index = gitLines({ "ls-files" })
				local plans, problem = planRecords(ids, "HEAD", "MERGE_HEAD", base, index)
				if not plans then
					return false, `{problem}\n{detail}`
				end
				-- never over uncommitted work: a path the merge did not leave unmerged must match the index
				local function dirty(path: string): boolean
					if unmerged[path] then
						return false
					end
					local tracked = sh.run("git", { "ls-files", "--error-unmatch", "--", path }).ok
					if not tracked then
						return fs.isFile(path)
					end
					return not sh.run("git", { "diff", "--quiet", "--", path }).ok
				end
				for _, plan in plans do
					local dest: string? = nil
					if plan.action == "write" then
						dest = `{plan.folder}/provenance.md`
						local hashed = sh.run("git", { "hash-object", "-w", "--stdin" }, plan.text)
						if not hashed.ok then
							error(hashed.stderr, 0)
						end
						local blob = sh.trim(hashed.stdout)
						local current = sh.run("git", { "rev-parse", "-q", "--verify", `:{dest}` })
						if not (current.ok and sh.trim(current.stdout) == blob) then
							if dirty(dest :: string) then
								return false,
									`{dest} has uncommitted changes the merge would overwrite: commit or stash them first\n{detail}`
							end
							sh.must("git", { "update-index", "--add", "--cacheinfo", `100644,{blob},{dest}` })
							sh.must("git", { "checkout-index", "-f", "--", dest :: string })
						end
					end
					if plan.action ~= "keep" then
						for _, path in recordPaths(index) do
							if path ~= dest and recordIdOf(path) == plan.id then
								if dirty(path) then
									return false,
										`{path} has uncommitted changes the merge would remove: commit or stash them first\n{detail}`
								end
								sh.must("git", { "rm", "-q", "-f", "--ignore-unmatch", "--", path })
							end
						end
					end
				end
			end
			if #gitLines({ "ls-files", "-u" }) > 0 then
				return false, detail
			end
			local c = sh.run("git", { "commit", "--no-edit", "-q" })
			if not c.ok then
				return false, c.stderr .. c.stdout
			end
			return true, ""
		end)
		if not ran then
			return abort(`the merge stopped on an error: {done}`)
		end
		if not done then
			return abort(why :: string)
		end
		return true, ""
	end
	local finished = ""
	if inProgress("MERGE_HEAD") then
		local head = sh.trim(sh.run("git", { "rev-parse", "MERGE_HEAD" }).stdout)
		if target == "" or not sh.run("git", { "merge-base", "--is-ancestor", head, target }).ok then
			return false,
				"a merge of another branch is in progress: finish it (git merge --continue) or abort it (git merge --abort), then run this again",
				false
		end
		-- a hand merge of origin/main, or of an older commit of it: finish it, then merge the newer tip on top
		local ok, why = settleAndCommit(
			`origin/main is being merged by hand: every conflict except provenance.md must be resolved and added first`,
			false
		)
		if not ok then
			return false, why, false
		end
		finished = "your merge was finished and committed; "
	elseif
		inProgress("CHERRY_PICK_HEAD")
		or inProgress("REVERT_HEAD")
		or fs.isDir(`{gitDir}/rebase-merge`)
		or fs.isDir(`{gitDir}/rebase-apply`)
	then
		return false,
			"a cherry-pick, a revert or a rebase is in progress: finish or abort it, then run this again",
			false
	end
	local r = sh.run("git", { "merge", "--no-commit", "--no-edit", ref })
	local detail = r.stderr .. r.stdout
	if not inProgress("MERGE_HEAD") then
		return r.ok, if r.ok then "" else detail, false -- up to date, fast-forwarded, or git refused to start
	end
	local ok, why = settleAndCommit(detail, true)
	if not ok then
		return false, finished .. why, true
	end
	return true, "", false
end

-- Brings what was just published into this worktree. A merge that stops is aborted (the tree is left as it was) or
-- refused (nothing was started): the message says which, and the way through.
local function mergeOrigin()
	local ok, why, aborted = mergeRef("origin/main")
	if not ok then
		fail(
			`merging origin/main failed{if aborted then " (merge aborted)" else ""}; anything this command published is already on origin/main: {why}`
		)
	end
end

-- The live actor of a command that records: --actor, then ZN_ACTOR, then an agent-session hint, then the git name.
local function liveActor(opts: { [string]: { string } }?): string
	local flagList = if opts then opts["--actor"] else nil
	local ident = sh.run("git", { "var", "GIT_AUTHOR_IDENT" })
	local name = if ident.ok then string.match(ident.stdout, "^(.-) <") else nil
	local hint = provenance.hint({
		CLAUDECODE = process.env.CLAUDECODE,
		AI_AGENT = process.env.AI_AGENT,
		CURSOR_AGENT = process.env.CURSOR_AGENT,
		GROK_SESSION_ID = process.env.GROK_SESSION_ID,
		ZN_DISPATCH = process.env.ZN_DISPATCH,
		CLAUDE_EFFORT = process.env.CLAUDE_EFFORT,
	})
	local actor, why =
		provenance.resolve(if flagList then flagList[1] else nil, process.env.ZN_ACTOR, hint, name)
	if not actor then
		fail(why or "not an actor")
	end
	return actor :: string
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

-- A pull that moves an item directory away leaves its ignored and untracked files behind (a raft's prompt.md, a
-- Finder .DS_Store): the main checkout would then hold one id in two directories. Every item directory under `root`
-- with nothing tracked at HEAD loses its ignored files and is removed; untracked files that are not ignored are kept,
-- and named in a warning. Run after every pull or fast-forward in the main checkout.
local function sweepStale(root: string)
	-- every root the pulled registry names, retired ones too: a root move leaves the old folders behind (c0114)
	local ok, reg = pcall(projects.load, root, true)
	if not ok then
		fail(`sweep: {reg}`) -- never guess which folders hold items (c0114)
	end
	local roots: { string } = projects.allRoots(reg :: projects.Registry)
	for _, top in roots do
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/", "done/" } do
				local rel = `{top}/{kind}/{state}`
				local base = `{root}/{rel}`
				if not fs.isDir(base) then
					continue
				end
				for _, name in fs.readDir(base) do
					local isId = if kind == "rafts" then store.isRaftId(name) else store.isIssueId(name)
					if not isId or not fs.isDir(`{base}{name}`) then
						continue
					end
					local dir = `{rel}{name}`
					-- a directory with anything tracked at HEAD is a live item (a readied raft, or an item mid-edit)
					local tracked =
						sh.run("git", { "-C", root, "ls-tree", "-r", "--name-only", "HEAD", "--", dir })
					if tracked.ok and sh.trim(tracked.stdout) == "" then
						-- only ignored files (a prompt.md, Finder litter): untracked work is never deleted, only named
						sh.run("git", { "-C", root, "clean", "-ffdXq", "--", dir })
						local left = if fs.isDir(`{base}{name}`) then fs.readDir(`{base}{name}`) else {}
						if fs.isDir(`{base}{name}`) and #left == 0 then
							fs.removeDir(`{base}{name}`)
						elseif #left > 0 then
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

-- After origin/main moved: bring the main checkout up to it and rewrite its .cache/board.html. Never fails the caller:
-- each problem is one `warning: board: …` line on stderr.
local function refreshBoard()
	local root = mainRoot()
	local branch = sh.trim(sh.run("git", { "-C", root, "branch", "--show-current" }).stdout)
	if branch == "main" then
		local m = sh.run("git", { "-C", root, "merge", "--ff-only", "--quiet", "origin/main" })
		if m.ok then
			sweepStale(root)
		else
			local first = string.match(sh.trim(m.stderr .. m.stdout), "^[^\n]*") or ""
			stdio.ewrite(`warning: board: the main checkout was not updated ({first})\n`)
		end
	else
		stdio.ewrite(
			`warning: board: the main checkout is on {if branch == "" then "a detached HEAD" else branch}, not main; not updated\n`
		)
	end
	buildBoard(root)
end

-- Every publish.commit call site goes through this: it fails like before on a refusal, and refreshes the board when a
-- commit was pushed (r.sha set). It returns r unchanged.
local function published(r: publish.Result): publish.Result
	if r.ok and r.sha then
		refreshBoard()
	end
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
						content = withFront(doc, "status", stamp("new")),
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
		fs.writeFile(`{dir}/{id}.md`, withDesc(render(`{TEMPLATES}/issue/doc.md`, vars), opts))
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
				-- the move to `prepared` ties the two fields together: designs are ready first
				local localItem = store.get(t)
				if store.readFront(localItem.doc).design ~= "ready" then
					return `{t} is not design: ready: set it (z-design) before status {id} prepared`
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
	local ok, why, aborted = mergeRef("origin/main")
	if not ok then
		fail(`{what}: merging origin/main failed{if aborted then " (merge aborted)" else ""}: {why}`)
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
			sh.git({ "pull", "--quiet", "--ff-only" })
			sweepStale(mainRoot())
			buildBoard(mainRoot())
		else
			mergeOrigin()
		end
	end
	print(`synced to {sh.git({ "rev-parse", "--short", "origin/main" })}`)
end

-- What a capture may change, from `git diff --name-status --no-renames origin/main HEAD`: only edits (M) to backlog
-- issue documents `<root>/issues/<ID>/<ID>.md`, under a root of `base`'s registry (c0114), that say `design: draft` on
-- both sides, with the status line unchanged.
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
	for line in string.gmatch(diff, "[^\n]+") do
		seen = true
		local kind, path = string.match(line, "^(%a)\t(.+)$")
		if not kind or not path then
			return `cannot read the diff line "{line}"`
		end
		local root, rest = projects.rootOf(path, roots)
		local a, b = nil, nil
		if root and rest then
			a, b = string.match(rest, "^issues/([^/]+)/([^/]+)%.md$")
		end
		if kind ~= "M" or not a or a ~= b or not store.isIssueId(a) then
			return `not a capture change: {kind} {path} (a capture changes only backlog issue documents; land that through a pull request)`
		end
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
	if not seen then
		return "nothing to land: this branch has no change against origin/main"
	end
	return nil
end

-- c0072: lands a capture without a pull request. Merge origin/main, check the scope, run the gate, push one commit
-- made on top of origin/main (never a force), and retry a lost race (up to 3 tries).
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
	local gate = override or "z-nile/check.sh --full"
	local given = opts["-m"]
	for _ = 1, 3 do
		sh.git({ "fetch", "--quiet", "origin", "main" })
		-- one origin/main per try: the merge, the scope, the commit's parent and the race test all name this sha, so
		-- a push elsewhere during the gate (or a later fetch) can never become the parent of a tree it isn't in
		local base = sh.git({ "rev-parse", "--verify", "origin/main^{commit}" })
		local merged, why, aborted = mergeRef(base)
		if not merged then
			fail(
				`merging origin/main failed{if aborted then " (merge aborted)" else ""}: {why}\nthen run land again`
			)
		end
		refuseStale()
		local diff = sh.must("git", { "diff", "--name-status", "--no-renames", base, "HEAD" })
		local refusal = captureScope(diff, base)
		if refusal then
			fail(refusal)
		end
		print(`gate: {gate}{if override then " (gate overridden: PICKMAN_LAND_GATE)" else ""}`)
		if not sh.stream("bash", { "-c", gate }) then
			fail("the gate failed: nothing was pushed")
		end
		local parent = base
		local message = if given and given[1] and given[1] ~= "" then given[1] else nil
		if not message then
			local subjects = sh.git({ "log", "--reverse", "--no-merges", "--format=%s", `{base}..HEAD` })
			local bodies = sh.git({ "log", "--reverse", "--no-merges", "--format=%b", `{base}..HEAD` })
			local subject = string.match(subjects, "^[^\n]*") or "tracker: capture"
			message = if bodies ~= "" then `{subject}\n\n{bodies}` else subject
		end
		local sha = sh.git({ "commit-tree", "HEAD^{tree}", "-p", parent, "-m", message :: string })
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
			sh.git({ "reset", "--hard", "--quiet", sha })
			sh.run("git", { "fetch", "--quiet", "origin", "main" })
			refreshBoard()
			local suffix = if override then " (gate overridden)" else ""
			print(
				`landed {sha} on main; remove this worktree: git -C {mainRoot()} worktree remove {root} && git -C {mainRoot()} branch -D {branch}{suffix}`
			)
			return
		end
		sh.run("git", { "fetch", "--quiet", "origin", "main" })
		if sh.git({ "rev-parse", "--verify", "origin/main^{commit}" }) == parent then
			fail(`the push failed (origin/main did not move): {pushed.stderr}{pushed.stdout}`)
		end
		-- origin/main moved: a lost race; sync, scope and gate again
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

-- c0263: the tree `git merge-tree` wrote for remap, with every item record settled by id (planRecords) over the remapped
-- base, the branch (`HEAD`) and `origin/main`: whether or not git reported a conflict there, and wherever git paired
-- the files. `mt` is the merge-tree output: the tree id, the conflicted-file lines "<mode> <sha> <stage>\t<path>", a
-- blank line, then messages. Nil (and the merge stops, as it always did) when a conflicted path is not a record or a
-- record cannot be settled. Built in the index only (`read-tree`, `update-index`, `write-tree`), then the index is put
-- back to HEAD; the worktree is never touched.
local function settleRemapRecords(mt: string, tree: string, baseTree: string): string?
	local unmerged: { [string]: boolean } = {}
	local unmergedIds: { string } = {}
	local first = true
	for line in string.gmatch(mt .. "\n", "([^\n]*)\n") do
		if first then
			first = false
		elseif line == "" then
			break
		else
			local path = string.match(line, "^%d+ %x+ %d\t(.+)$")
			local id = if path then recordIdOf(path) else nil
			if not id then
				return nil
			end
			if not unmerged[id] then
				unmerged[id] = true
				table.insert(unmergedIds, id)
			end
		end
	end
	local ids = changedRecordIds(baseTree, "HEAD", "origin/main")
	for _, id in unmergedIds do
		if not table.find(ids, id) then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return tree
	end
	local merged = gitLines({ "ls-tree", "-r", "--name-only", tree })
	local plans = planRecords(ids, "HEAD", "origin/main", baseTree, merged)
	if not plans then
		return nil
	end
	for _, plan in plans do
		if plan.action == "keep" and unmerged[plan.id] then
			return nil -- git left a conflicted record that neither side changed: not ours to guess
		end
	end
	local ok, built = pcall(function(): string?
		sh.must("git", { "read-tree", tree })
		for _, plan in plans do
			local target: string? = nil
			if plan.action == "write" then
				target = `{plan.folder}/provenance.md`
				local hashed = sh.run("git", { "hash-object", "-w", "--stdin" }, plan.text)
				if not hashed.ok then
					error(hashed.stderr, 0)
				end
				local blob = sh.trim(hashed.stdout)
				sh.must("git", { "update-index", "--add", "--cacheinfo", `100644,{blob},{target}` })
			end
			if plan.action ~= "keep" then
				for _, path in recordPaths(merged) do
					if path ~= target and recordIdOf(path) == plan.id then
						sh.must("git", { "update-index", "--force-remove", "--", path })
					end
				end
			end
		end
		return sh.trim(sh.must("git", { "write-tree" }))
	end)
	sh.run("git", { "reset", "--quiet", "HEAD" })
	return if ok then built else nil
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
	local mtTree = string.match(mt.stdout, "^(%x+)")
	-- c0263: item records are settled by id whether or not git reported a conflict (it can pair a record with another
	-- item's and exit 0); any other conflict, or a record that cannot be settled, stops as it always did
	local settled = if mtTree then settleRemapRecords(mt.stdout, mtTree, baseTree) else nil
	if not settled then
		fail(
			`remap committed, but merging origin/main conflicts: git merge origin/main and resolve (a provenance.md both sides appended: keep the common rows, then origin/main's new rows, then yours)\n{mt.stdout}`
		)
	end
	local tree: string = settled :: string
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

-- Pushes the raft's branch and opens its draft PR (when the origin is on GitHub): the end of every start.
local function pushAndOpenPr(
	raft: store.Item,
	members: { store.Item },
	branch: string,
	ftitle: string,
	reuse: boolean?
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
		local url =
			sh.must("gh", { "pr", "create", "--draft", "--title", `{raft.id}: {ftitle}`, "--body", body })
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
		local branch = raftBranch(raft)
		if sh.git({ "branch", "--show-current" }) ~= branch then
			refuseInMainCheckout("start")
			if sh.run("git", { "rev-parse", "--verify", "--quiet", `refs/heads/{branch}` }).ok then
				fail(`branch {branch} already exists: switch to it and run start there`)
			end
			sh.git({ "switch", "-c", branch })
		end
		local members = store.members(raft.id)
		local ftitle = store.readFront(raft.doc).title or raft.slug
		sh.git({ "commit", "--quiet", "--allow-empty", "-m", `tracker: start {raft.id} {ftitle}` })
		print(`on branch {branch}; {raft.id} and {#members} issue(s) are active`)
		pushAndOpenPr(raft, members, branch, ftitle, true)
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
						`{m.id} depends on {dep}, which is {if found then found.state else "unknown"} as this branch sees it: it must be done first. If it has merged, run ./zn sync (or merge origin/main by hand) and retry; never edit depends_on to get past this`
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
		sh.git({ "switch", "-c", branch })
	end
	raft = move(raft, "active")
	for _, m in members do
		move(m, "active")
	end
	local ftitle = store.readFront(raft.doc).title or raft.slug
	sh.git({ "commit", "--quiet", "-m", `tracker: start {raft.id} {ftitle}` })
	print(`on branch {branch}; {raft.id} and {#members} issue(s) are active`)
	pushAndOpenPr(raft, members, branch, ftitle)
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
	local branch: string
	local dirName: string
	if string.match(target, "^R%d%d%d%d$") then
		local missing = `{target} is not in this tree; if it was just merged, run {mainRoot()}/zn sync`
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
	local minutes = explicitMinutes or spend.elapsedMinutes()
	local shares = spend.attribute(issues, spend.stagedStats(isDone), minutes, how, tokens)
	local trailers: { string } = {}
	for _, share in shares do
		-- a share with tokens is kept even when it moved no lines and took no measurable time
		if share.added + share.removed == 0 and share.minutes < 0.1 and (share.tokens or 0) == 0 then
			continue
		end
		spend.appendRow(store.get(share.id), share, message, phase, model)
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
	spend.writeRaft(raft)
	for _, r in store.roots() do
		if fs.isDir(r) then
			sh.git({ "add", "-A", r })
		end
	end
	sh.git({ "commit", "--quiet", "-m", message, "-m", table.concat(trailers, "\n") })
	print(`committed: {message}\n  {table.concat(trailers, "\n  ")}`)
	push()
end

function cmd.commit(_pos: { string }, opts: { [string]: { string } })
	local message = opts["-m"] and opts["-m"][1]
	if not message or message == "" then
		fail(
			"usage: commit -m <msg> [--issue <id>]... [--time <minutes>] [--phase build|code-review|deliver] [--tokens <n>] [--model <id>]"
		)
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
	local tokens: number? = nil
	if opts["--tokens"] then
		local raw = opts["--tokens"][1]
		if not string.match(raw, "^%d+$") then
			fail("commit --tokens must be a non-negative integer")
		end
		tokens = tonumber(raw)
	end
	local model = modelOption("commit", opts)
	local t = opts["--time"] and tonumber((string.gsub(opts["--time"][1], "m$", "")))
	recordAndCommit(activeRaft(), message, opts["--issue"] or {}, t, nil, phase, tokens, model)
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
		if line and string.find(line, "^fixed") then
			if not string.find(line, "consequences:%s*%S", 6) then
				table.insert(
					invalid,
					`{id}: a fixed answer needs "; consequences: <what the fix could break, and how that was checked, or none>"`
				)
			end
			continue
		end
		if line and string.find(line, "^refuted") then
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
		fail("commit everything first (./zn commit); done needs a clean tree")
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
	local members = store.members(raft.id)
	local movedDirs: { string } = {}
	for _, m in members do
		table.insert(movedDirs, store.dirFor(m.kind, "done", m.id, m.root))
	end
	table.insert(movedDirs, store.dirFor(raft.kind, "done", raft.id, raft.root))
	local function rollback()
		sh.git({ "reset", "-q", "--hard", "HEAD" })
		-- git removes the folders it empties; if one is left, store.find would see a duplicate id
		for _, dir in movedDirs do
			if fs.isDir(dir) and #fs.readDir(dir) == 0 then
				fs.removeDir(dir)
			end
		end
	end
	-- every moved item's check.sh follows the move: its own item paths name done/ from now on (c0067)
	local doneDirs: { [string]: string } = { [raft.id] = store.dirFor("raft", "done", raft.id, raft.root) }
	for _, m in members do
		doneDirs[m.id] = store.dirFor("issue", "done", m.id, m.root)
	end
	local movedItems: { store.Item } = {}
	for _, m in members do
		table.insert(movedItems, move(m, "done"))
	end
	raft = move(raft, "done")
	table.insert(movedItems, raft)
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
	-- Mark the PR ready before the final push: CI skips drafts, so the push below is what gets tested.
	if hasUpstream() and onGitHub() then
		-- pcall: process.exec throws when gh can't be spawned at all (not on PATH)
		local ok, r = pcall(sh.run, "gh", { "pr", "ready" })
		if not (ok and r.ok) then
			rollback()
			fail("could not mark the PR ready (rolled back); fix gh and retry done")
		end
	end
	if fs.isFile(FOCUS_FILE) then
		fs.removeFile(FOCUS_FILE)
	end
	recordAndCommit(raft, `tracker: done {raft.id}`, {}, nil, true, "deliver")
	if hasUpstream() and onGitHub() then
		local summary = fs.readFile(`{raft.dir}/spend.md`)
		local body = sh.must("gh", { "pr", "view", "--json", "body", "-q", ".body" })
		sh.must("gh", { "pr", "edit", "--body", body .. "\n\n" .. summary })
		print("PR marked ready for review")
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

-- The prompt's Lessons section: the index of the build and both lessons (c0111).
-- Only the lessons of z-nile's skills, of the raft's own project's and of the skills those extend (c0115, c0184): another
-- project's are left out.
local function buildLessons(project: string?): string
	local tree = lessonsLib.load(".")
	local sources = lessonsLib.sources(tree.items)
	local mine = {}
	local bases = skillsLib.bases((skillsLib.plan((skillsLib.load(".")))), project)
	for _, l in parsedLessons(tree) do
		local owner = tree.owners and tree.owners[l.skill]
		if not owner or owner == skillsLib.ZNILE or owner == project or bases[l.skill] then
			table.insert(mine, l)
		end
	end
	local text = lessonsLib.index(lessonsLib.select(mine, sources, { when = "build" }), sources)
	return (string.gsub(text, "\n$", ""))
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

-- The raft's project's architecture map (c0120): `<root>/architecture.md`, pickman's in pickman/.tracker/; a project
-- without one (z-nile) gets a line saying so.
local function architectureOf(raft: store.Item): string
	local path = `{raft.root}/architecture.md`
	return if fs.isFile(path)
		then fs.readFile(path)
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

-- The SKILL.md files a raft's prompt inlines (c0115, c0184): skills.inlined over the skills found.
local function inlinedSkills(project: string?): { string }
	return skillsLib.inlined((skillsLib.plan((skillsLib.load(".")))), project)
end

-- The execution prompt of a raft: the template with the documents, check.sh files, sequestered specs, skills,
-- architecture map and workstream plan filled in.
local function renderPrompt(raft: store.Item): string
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
	-- z-nile's step skills, then every skill of the raft's own project, each from its real folder (c0115)
	local project = projectOfRoot(raft.root)
	local skills = ""
	for _, path in inlinedSkills(project) do
		skills ..= section(path)
	end
	local plan, _, planError = workstreamPlan(raft)
	local planText = if planError then `plan unavailable: {planError}\nparallel: no` else plan
	local text = render(`{TEMPLATES}/prompt.md`, {
		RAFT_ID = raft.id,
		RAFT_TITLE = store.readFront(raft.doc).title or raft.slug,
		RAFT_TYPE = store.typeOf(raft),
		ISSUE_IDS = table.concat(ids, ", "),
		ITEMS = items,
		SKILLS = skills,
		ARCHITECTURE = architectureOf(raft),
		ARCHITECTURE_PATH = `{raft.root}/architecture.md`,
		ROOT = raft.root,
		WORKSTREAMS = planText,
		LESSONS = buildLessons(project),
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

-- Fast-forwards the main checkout to origin/main and sweeps what the pull left behind. A string is the failure.
local function pullMain(): string?
	sh.git({ "fetch", "--quiet", "origin", "main" })
	local r = sh.run("git", { "pull", "--ff-only", "--quiet" })
	if not r.ok then
		return sh.trim(r.stderr .. r.stdout)
	end
	sweepStale(mainRoot())
	return nil
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
	local branch = raftBranch(raft)
	sh.run("git", { "fetch", "--quiet", "--prune", "origin" })
	local exists = sh.run("git", { "show-ref", "--verify", "--quiet", `refs/heads/{branch}` }).ok
		or sh.run("git", { "show-ref", "--verify", "--quiet", `refs/remotes/origin/{branch}` }).ok
	if exists then
		local pr = "its pull request, if any"
		if onGitHub() then
			local g = sh.run(
				"gh",
				{ "pr", "list", "--head", branch, "--state", "open", "--json", "url", "-q", ".[0].url" }
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

local function nonNegativeMinutes(raw: string?): number?
	if not raw or not string.match(raw, "^%d+%.?%d*m?$") then
		return nil
	end
	return tonumber((string.gsub(raw, "m$", "")))
end

-- origin/main's issue spend.md blobs, keyed by id, loaded once. nil means this checkout has no
-- origin/main of its own (a sandbox under .cache, or a cwd that is not the git toplevel): metrics
-- then reads only the working tree, and it never fetches.
local originSpend: { [string]: { string } }? = nil
local originChecked = false

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
				for path in string.gmatch(listed.stdout, "[^\n]+") do
					local found = string.match(path, "/([fdc]%d%d%d%d)/spend%.md$")
					if found and originSpend then
						local list = originSpend[found]
						if not list then
							list = {}
							originSpend[found] = list
						end
						table.insert(list, path)
					end
				end
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
		return localRows
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
		local shown = sh.run("git", { "show", `origin/main:{blob}` })
		if not shown.ok then
			stdio.ewrite(`metrics: origin/main:{blob} could not be read; using the working tree\n`)
			absent = true
		else
			local parsed, err = ledger.parse(shown.stdout)
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
		return originRows
	end
	if originErr then
		stdio.ewrite(`metrics: origin/main:{blobs[1]} does not parse ({originErr}); using the working tree\n`)
		return localRows
	end
	if absent or not originRows then
		return localRows
	end
	local here = localRows :: { ledger.Row }
	if ledger.extends(here, originRows) or ledger.extends(originRows, here) then
		return if #originRows > #here then originRows else here
	end
	stdio.ewrite(
		`metrics: {issue.id} spend.md on origin/main and in the working tree have diverged; skipped\n`
	)
	return nil
end

-- c0263: `record <id> <event> [--actor A] [--detail k=v]` publishes one row of an item's provenance.md for the
-- events other tickets call (unblocked, confirmed, ranked), built from origin/main's file. An active item takes
-- unblocked only (the validator).
function cmd.record(pos: { string }, opts: { [string]: { string } })
	refuseInMainCheckout("record")
	if not publishing() then
		fail("record needs an origin remote (PICKMAN_PUBLISH=0 disables it)")
	end
	local id, event = pos[1], pos[2]
	if not id or not event or not (store.isIssueId(id) or store.isRaftId(id)) then
		fail(
			`usage: record <id> <{table.concat(provenance.PUBLISHED, "|")}> [--actor <actor>] [--detail <k=v>]`
		)
	end
	if not table.find(provenance.PUBLISHED, event) then
		fail(
			`record publishes {table.concat(provenance.PUBLISHED, ", ")} only, not {event}: the other events are written by their own commands`
		)
	end
	local actor = liveActor(opts)
	local detail = if opts["--detail"] then opts["--detail"][1] else ""
	local when = os.date("!%Y-%m-%d %H:%M", os.time()) :: string
	refuseStale()
	local r = published(publish.commit(".", function(paths, read)
		local doc = docPath(paths, id)
		if not doc then
			return `{id} is not on origin/main`
		end
		-- backlog: unblocked, confirmed, ranked; active (an issue or a raft): unblocked; done: written in a PR
		if string.find(doc, "/done/", 1, true) then
			return `record refuses {id}: it is done, and a done item's record is written in a pull request, never published`
		elseif string.find(doc, "/active/", 1, true) and event ~= "unblocked" then
			return `record refuses {id}: it is active, and only an unblocked row is published for it, not {event}`
		end
		local rec = string.gsub(doc, "[^/]+$", "provenance.md")
		local text, why = provenance.record(read(rec), id, event, actor, detail, when)
		if not text then
			return why or "not a record"
		end
		return { { path = rec, content = text } }
	end, function()
		return `tracker: {id} record {event}`
	end))
	if not r.ok then
		fail(r.reason or "publish failed")
	end
	mergeOrigin()
end

function cmd.spend(pos: { string }, opts: { [string]: { string } })
	refuseInMainCheckout("spend")
	if not publishing() then
		fail(
			"spend needs an origin remote (PICKMAN_PUBLISH=0 disables it); inside a raft, record with ./zn commit --phase"
		)
	end
	local id = pos[1]
	if not id or not (store.isIssueId(id) or store.isRaftId(id)) then
		fail(
			"usage: spend <id> --phase capture|prep|design-review|deliver --time <minutes> [--tokens <n>] [--model <id>] [--note <text>]"
		)
	end
	local phase = opts["--phase"] and opts["--phase"][1] or ""
	if phase == "build" or phase == "code-review" then
		fail(`{phase} is recorded with ./zn commit --phase`)
	elseif not table.find(SPEND_PHASES, phase) then
		fail("spend --phase is capture, prep, design-review or deliver")
	end
	local minutes = nonNegativeMinutes(opts["--time"] and opts["--time"][1])
	if not opts["--time"] then
		fail("spend needs --time <minutes>: spend has no commit gap to measure")
	elseif minutes == nil then
		fail("spend --time must be a non-negative number")
	end
	local tokens: number? = nil
	if opts["--tokens"] then
		local raw = opts["--tokens"][1]
		if not string.match(raw, "^%d+$") then
			fail("spend --tokens must be a non-negative integer")
		end
		tokens = tonumber(raw)
	end
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
	local kept: { spend.Share } = {}
	for _, share in shares do
		if not (share.added + share.removed == 0 and share.minutes < 0.1 and (share.tokens or 0) == 0) then
			table.insert(kept, share)
		end
	end
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
	refuseStale()
	local r = published(publish.commit(".", function(paths, read)
		if store.isRaftId(id) then
			local doc = docPath(paths, id)
			local text = if doc then read(doc) else nil
			if not doc or not text then
				return `{id} is not on origin/main`
			end
			if activeThere(doc, text) then
				return activeReason(id)
			end
		end
		local changes: { publish.Change } = {}
		for _, share in kept do
			local doc = docPath(paths, share.id)
			local text = if doc then read(doc) else nil
			if not doc or not text then
				return `{share.id} is not on origin/main`
			end
			if activeThere(doc, text) then
				return activeReason(share.id)
			end
			local dir = string.sub(doc, 1, #doc - #share.id - 4) -- ".../<ID>/<ID>.md" -> ".../<ID>"
			local spendPath = `{dir}/spend.md`
			local row: ledger.Row = {
				when = when,
				subject = note,
				added = share.added,
				removed = share.removed,
				minutes = share.minutes,
				how = share.how,
				phase = phase,
				tokens = share.tokens,
				model = model,
			}
			local itemTitle = frontOf(text).title or share.id
			local okAppend, content = pcall(ledger.append, read(spendPath), share.id, itemTitle, row)
			if not okAppend then
				return tostring(content)
			end
			table.insert(changes, { path = spendPath, content = content :: string })
		end
		return changes
	end, `tracker: spend {id} {phase}`))
	if not r.ok then
		fail(r.reason or "publish failed")
	end
	for _, share in kept do
		local tok = if share.tokens ~= nil then ` {share.tokens} tokens` else ""
		print(
			string.format(
				"%s %s +%d/-%d %.1f min%s",
				share.id,
				phase,
				share.added,
				share.removed,
				share.minutes,
				tok
			)
		)
	end
	if r.sha then
		print(r.sha)
	end
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

-- A raft's design rounds: z-design's reviews live on each issue and z-raft's coherence review on the raft, so they
-- roll up to the raft through its members' `raft:` lines (c0116).
local function raftDesignRounds(raft: store.Item): number
	local n = designRoundsIn(raft.dir)
	for _, m in store.members(raft.id) do
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

function cmd.metrics(_pos: { string }, opts: { [string]: { string } })
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
	local rows: { Counted } = {}
	local byType: { [string]: { added: number, minutes: number, count: number } } = {}
	for _, issue in store.all("issue") do
		if issue.state == "done" or (issue.state == "active" and opts["--include-active"]) then
			local parsed = ledgerRows(issue)
			if not parsed then
				continue
			end
			local t = ledger.sum(parsed)
			local ty = store.typeOf(issue)
			table.insert(rows, {
				id = issue.id,
				type = ty,
				raft = store.readFront(issue.doc).raft or "",
				added = t.added,
				removed = t.removed,
				minutes = t.minutes,
				tokens = t.tokens,
				rows = parsed,
			})
			local b = byType[ty] or { added = 0, minutes = 0, count = 0 }
			b.added += t.added
			b.minutes += t.minutes
			b.count += 1
			byType[ty] = b
		end
	end
	print("\nCost per issue (done, plus active with --include-active).")
	print("| issue | type | raft | +lines | -lines | agent-minutes | tokens |\n|---|---|---|---|---|---|---|")
	for _, r in rows do
		print(
			string.format(
				"| %s | %s | %s | %d | %d | %.1f | %d |",
				r.id,
				r.type,
				r.raft,
				r.added,
				r.removed,
				r.minutes,
				r.tokens
			)
		)
	end
	print("\nTotals by type.")
	print("| type | issues | +lines | agent-minutes | minutes/issue |\n|---|---|---|---|---|")
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
	for _, r in rows do
		for _, row in r.rows do
			local tenths = math.floor(row.minutes * 10 + 0.5)
			phaseMin[row.phase][r.type] += tenths
			phaseTok[row.phase] += row.tokens or 0
		end
	end
	print("\nSpend by phase (agent-minutes).")
	print("| phase | feature | defect | chore | all | tokens |\n|---|---|---|---|---|---|")
	for _, p in ledger.PHASES do
		local m = phaseMin[p]
		local all = m.feature + m.defect + m.chore
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
		for _, issue in store.members(raft.id) do
			local parsed = ledgerRows(issue)
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
			for _, m in store.members(raft.id) do
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
