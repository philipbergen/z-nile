--!strict
-- The watch-map commands. `./zn finish` captures one layer's changed files (the only writer). `./zn commit`
-- rewrites watch files a rename or delete touches, `./zn watch-bootstrap` fills the map from history once,
-- and `./zn watch-net` repairs a miss after a landing. Reads and git sit here; the rules are z-nile/lib/watch.luau.

local closing = require("./closing")
local cpulimit = require("../lib/cpulimit")
local fs = require("@lune/fs")
local graph = require("../lib/graph")
local ids = require("./ids")
local process = require("@lune/process")
local procstart = require("../lib/procstart")
local projects = require("./projects")
local reap = require("./reap")
local sh = require("../lib/sh")
local stdio = require("@lune/stdio")
local task = require("@lune/task")
local trackerstate = require("./trackerstate")
local watch = require("../lib/watch")

local watchcmd = {}

export type Member = { id: string, dest: string }

-- Set while this process holds the net lock: every way out of the net gives it back first (a kill leaves it for the next net
-- to take over).
local releaseHeld: () -> () = function() end

local function fail(msg: string): never
	stdio.ewrite(msg .. "\n")
	releaseHeld()
	return process.exit(1)
end

local function linesOf(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

local function oneLine(text: string): string
	return (string.gsub(sh.trim(text), "%s*\n%s*", " "))
end

local function gitAt(dir: string, args: { string }): (boolean, string, string)
	local r = process.exec("git", args, { cwd = dir })
	return r.ok, sh.trim(r.stdout), r.stderr .. r.stdout
end

local function mustAt(dir: string, args: { string }): string
	local ok, out, err = gitAt(dir, args)
	if not ok then
		fail(`git {table.concat(args, " ")} failed: {err}`)
	end
	return out
end

local addingCommit: (string) -> string?
local resolvedRequires: (string, string) -> { string }

local function readList(file: string): { string }
	if not fs.isFile(file) then
		return {}
	end
	local parsed, err = watch.parse(fs.readFile(file))
	if not parsed then
		fail(`watch: {file}: {err}`)
	end
	return parsed :: { string }
end

-- Stages a non-empty list. An empty list is never written: a spec with nothing to watch fails the gate.
local function stageList(file: string, paths: { string }): boolean
	if #paths == 0 then
		return false
	end
	local parent = string.match(file, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(parent)
	end
	fs.writeFile(file, watch.render(paths))
	sh.git({ "add", "--", file })
	return true
end

local function specsIn(dir: string): { string }
	local out: { string } = {}
	if not fs.isDir(dir) then
		return out
	end
	for _, name in fs.readDir(dir) do
		if string.sub(name, -10) == ".spec.luau" then
			table.insert(out, `{dir}/{name}`)
		end
	end
	table.sort(out)
	return out
end

local function union(a: { string }, b: { string }): { string }
	local all: { string } = {}
	for _, p in a do
		table.insert(all, p)
	end
	for _, p in b do
		table.insert(all, p)
	end
	return watch.unique(all)
end

-- Writes this layer's watch files from `changed`, the paths in its diff against the layer below.
-- One `watch.txt` in the ticket's acceptance folder. A spec under `tests/` outside `acceptance/`
-- that this diff adds or edits keeps the union of its existing watch and this layer's sources,
-- and only the paths that belong to its own suite. A layer that changes no source file falls back
-- to what the spec requires. An empty list is never written. Stages the files so the finish commit picks them up.
-- A path the diff names that is no longer a file (the layer deleted it) is not captured (d0410): a deleted spec
-- gets no watch file, and a deleted source is in no list, which watch-check would refuse.
function watchcmd.capture(member: Member, all: { string })
	local changed: { string } = {}
	for _, path in all do
		if fs.isFile(path) then
			table.insert(changed, path)
		end
	end
	local sources = watch.sourceOf(changed)
	local function kept(spec: string, paths: { string }): { string }
		local filtered = watch.forSuite(spec, paths)
		if #filtered > 0 or not fs.isFile(spec) then
			return filtered
		end
		return watch.forSuite(spec, resolvedRequires(spec, fs.readFile(spec)))
	end
	if fs.isDir(member.dest) then
		local specs = specsIn(member.dest)
		-- The folder's own path is enough for the suite filter when the ticket has no spec yet.
		local standIn = if #specs > 0 then specs[1] else `{member.dest}/stand.spec.luau`
		local paths = watch.forSuite(standIn, sources)
		if #paths == 0 and #specs > 0 then
			local req: { string } = {}
			for _, spec in specs do
				if fs.isFile(spec) then
					for _, p in resolvedRequires(spec, fs.readFile(spec)) do
						table.insert(req, p)
					end
				end
			end
			paths = watch.forSuite(specs[1], req)
		end
		local file = `{member.dest}/watch.txt`
		if stageList(file, paths) then
			print(`watch: {member.id} {file} ({#paths})`)
		else
			print(`watch: {member.id} lists no source files and its specs require none ({file})`)
		end
	end
	local seen: { [string]: boolean } = {}
	local specs: { string } = {}
	for _, f in changed do
		local underTests = string.find(f, "/tests/", 1, true) ~= nil or string.sub(f, 1, 6) == "tests/"
		if
			string.sub(f, -10) == ".spec.luau"
			and underTests
			and not string.find(f, "/tests/acceptance/", 1, true)
		then
			if not seen[f] then
				seen[f] = true
				table.insert(specs, f)
			end
		end
	end
	table.sort(specs)
	for _, spec in specs do
		local paths = kept(spec, union(readList(watch.fileFor(spec)), watch.forSuite(spec, sources)))
		local file = watch.fileFor(spec)
		if stageList(file, paths) then
			print(`watch: {spec} {file} ({#paths})`)
		else
			print(`watch: {spec} lists no source files and requires none ({file})`)
		end
	end
end

-- Rewrites staged watch files when this commit renames or deletes a path they name, and stages the rewrite
-- so it lands in the same commit.
function watchcmd.upkeep()
	local status = sh.git({ "diff", "--cached", "--find-renames", "--name-status", "HEAD" })
	local renames: { [string]: string } = {}
	local deletes: { [string]: boolean } = {}
	local any = false
	for _, line in linesOf(status) do
		local kind, rest = string.match(line, "^(%u%d*)\t(.+)$")
		if kind == "D" and rest then
			deletes[rest] = true
			any = true
		elseif kind and rest and string.sub(kind, 1, 1) == "R" then
			local old, new = string.match(rest, "^([^\t]+)\t(.+)$")
			if old and new then
				renames[old] = new
				any = true
			end
		end
	end
	if not any then
		return
	end
	for path in string.gmatch(sh.git({ "ls-files", "-z" }), "[^%z]+") do
		if watch.isWatch(path) and fs.isFile(path) and not deletes[path] and renames[path] == nil then
			local paths, err = watch.parse(fs.readFile(path))
			if paths then
				local nextp = watch.rewrite(paths, renames, deletes)
				if table.concat(nextp, "\n") ~= table.concat(paths, "\n") then
					fs.writeFile(path, watch.render(nextp))
					sh.git({ "add", "--", path })
					print(`watch: rewrote {path}`)
				end
			else
				stdio.ewrite(`watch: {path}: {err}\n`)
			end
		end
	end
end

function addingCommit(spec: string): string?
	local r = sh.run("git", { "log", "--diff-filter=A", "--pretty=%H", "-1", "--", spec })
	if not r.ok then
		return nil
	end
	local id = sh.trim(r.stdout)
	return if id == "" then nil else id
end

local function commitFiles(commit: string): { string }
	local parent = sh.run("git", { "rev-parse", "--verify", "--quiet", `{commit}^1` })
	local text = if parent.ok
		then sh.git({ "diff", "--name-only", sh.trim(parent.stdout), commit })
		else sh.git({ "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", commit })
	return linesOf(text)
end

local function laterFiles(spec: string): { string }
	local text = sh.git({ "log", "-n", "15", "--name-only", "--pretty=format:", "--", spec })
	return linesOf(text)
end

local function keepResolved(path: string, spec: string): boolean
	if path == spec or watch.isWatch(path) or not fs.isFile(path) then
		return false
	end
	if watch.isSource(path) then
		return true
	end
	-- a spec whose history names no source still depends on the test helper it requires
	return string.find(path, "/tests/lib/", 1, true) ~= nil or string.sub(path, -14) == "/tests/run.luau"
end

function resolvedRequires(spec: string, text: string): { string }
	local out: { string } = {}
	for _, req in watch.requirePaths(text) do
		local path = graph.resolve(spec, req)
		if path and keepResolved(path, spec) then
			table.insert(out, path)
		end
	end
	return watch.unique(out)
end

local function literalSources(spec: string, text: string): { string }
	local out: { string } = {}
	for _, p in watch.pathLiterals(text) do
		if fs.isFile(p) and keepResolved(p, spec) then
			table.insert(out, p)
		end
	end
	-- a document path written out in the spec, outside skills, lessons and the tracker
	for path in string.gmatch(text, "[%w%._%-/]+%.md") do
		if
			fs.isFile(path)
			and path ~= spec
			and not string.find(path, "/skills/", 1, true)
			and not string.find(path, "/lessons/", 1, true)
			and not string.find(path, "/.tracker/", 1, true)
		then
			table.insert(out, path)
		end
	end
	return watch.unique(out)
end

local function homeOf(spec: string): string
	local home = string.match(spec, "^([^/]+)/")
	return home or ""
end

local function fallbackFile(spec: string): string?
	local home = homeOf(spec)
	local prefix = if home == "" then "" else home .. "/"
	for _, p in
		linesOf(
			sh.git({ "ls-files", "--", `{prefix}src`, `{prefix}*.luau`, `{prefix}lib`, `{prefix}engine` })
		)
	do
		if watch.isSource(p) and fs.isFile(p) and string.sub(p, -5) == ".luau" then
			return p
		end
	end
	return nil
end

-- One watch file per existing spec, from the commit that added it (a merge's first-parent diff for a
-- promoted acceptance spec). Prints the counts. A spec history cannot fill is bound to one real source
-- file, and that binding is printed: an empty list would never be selected.
function watchcmd.bootstrap()
	local listed = sh.git({ "ls-files", "--", ":(glob)**/*.spec.luau" })
	local specs: { string } = {}
	for _, spec in linesOf(listed) do
		if string.find(spec, "/tests/", 1, true) or string.sub(spec, 1, 6) == "tests/" then
			table.insert(specs, spec)
		end
	end
	table.sort(specs)
	local groups: { [string]: { string } } = {}
	local order: { string } = {}
	local own: { [string]: { string } } = {}
	local how: { [string]: string } = {}
	local emptyOwn = 0
	for _, spec in specs do
		local file = watch.fileFor(spec)
		if not groups[file] then
			groups[file] = {}
			table.insert(order, file)
		end
		table.insert(groups[file], spec)
		local function present(paths: { string }): { string }
			local out: { string } = {}
			for _, p in paths do
				if fs.isFile(p) then
					table.insert(out, p)
				end
			end
			return out
		end
		local function mentions(text: string, pin: string): boolean
			local from = 1
			while true do
				local at = string.find(text, pin, from, true)
				if not at then
					return false
				end
				local before = if at == 1 then "" else string.sub(text, at - 1, at - 1)
				local after = string.sub(text, at + #pin, at + #pin)
				local function edge(ch: string): boolean
					return ch == "" or string.match(ch, "[%w%._%-/]") == nil
				end
				if edge(before) and edge(after) then
					return true
				end
				from = at + 1
			end
		end
		local sources: { string } = {}
		local stage = "history"
		local added = addingCommit(spec)
		if added then
			sources = watch.forSuite(spec, present(watch.sourceOf(commitFiles(added))))
		end
		if #sources == 0 then
			sources = watch.forSuite(spec, present(watch.sourceOf(laterFiles(spec))))
			stage = "later"
		end
		if fs.isFile(spec) then
			local text = fs.readFile(spec)
			local reqs = watch.forSuite(spec, resolvedRequires(spec, text))
			if #reqs > 0 then
				if #sources == 0 then
					stage = "require"
				end
				sources = union(sources, reqs)
			end
			if #sources == 0 then
				sources = watch.forSuite(spec, literalSources(spec, text))
				if #sources > 0 then
					stage = "literal"
				end
			end
			local pins: { string } = {}
			for _, pin in watch.sharedPins() do
				if mentions(text, pin) and fs.isFile(pin) then
					table.insert(pins, pin)
				end
			end
			sources = union(sources, watch.forSuite(spec, pins))
		end
		if #sources == 0 then
			emptyOwn += 1
			stage = "empty"
		end
		own[spec] = sources
		how[spec] = stage
	end
	local written = 0
	local bound = 0
	local stillEmpty = 0
	for _, file in order do
		local all: { string } = {}
		for _, spec in groups[file] do
			for _, p in own[spec] do
				table.insert(all, p)
			end
		end
		local paths = watch.unique(all)
		if #paths == 0 then
			local fb = fallbackFile(groups[file][1])
			if fb then
				paths = { fb }
				bound += #groups[file]
				for _, spec in groups[file] do
					print(`watch-bootstrap: {spec} -> {fb} (no history, no require, no path literal)`)
				end
			else
				stillEmpty += #groups[file]
				for _, spec in groups[file] do
					print(`watch-bootstrap: {spec} still has an empty list`)
				end
			end
		end
		if #paths == 0 then
			continue
		end
		local parent = string.match(file, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(parent)
		end
		fs.writeFile(file, watch.render(paths))
		written += 1
	end
	local later, requires, literals = 0, 0, 0
	for _, spec in specs do
		if how[spec] == "later" then
			later += 1
		elseif how[spec] == "require" then
			requires += 1
		elseif how[spec] == "literal" then
			literals += 1
		end
	end
	print(`watch-bootstrap: specs {#specs}`)
	print(`watch-bootstrap: watch files {written}`)
	print(`watch-bootstrap: empty before a sibling or a fallback {emptyOwn}`)
	print(`watch-bootstrap: filled from later commits {later}`)
	print(`watch-bootstrap: filled from requires {requires}`)
	print(`watch-bootstrap: filled from path literals {literals}`)
	print(`watch-bootstrap: bound with no source of their own {bound}`)
	print(`watch-bootstrap: still empty {stillEmpty}`)
	if stillEmpty > 0 then
		fail("watch-bootstrap: a spec with an empty list would never be selected")
	end
end

-- The main checkout, whichever worktree this process runs in. Git lists it first, even when asked from a linked worktree.
local function mainDir(): string
	local listed = sh.run("git", { "worktree", "list", "--porcelain" })
	local main = if listed.ok then watch.mainCheckout(listed.stdout) else nil
	if not main then
		fail(`watch-net: cannot find the main checkout: {oneLine(listed.stderr)}`)
	end
	return main :: string
end

-- The net bounds its own start (d0383 F5): its fetches, its worktree creation and its rebase share one budget, and a step
-- that is still running when it ends stops with one line. The steps run under `./zn run`, which stops them.
local START_SECONDS = 120
local startLimit = START_SECONDS
local startDeadline = 0

-- The `zn` that bounds the start's git steps. Round 1 uses the kicker's (`ZN_TOP`): the kick that started the net still
-- waits for its marker, so that checkout exists, and it is the engine the person just ran (the main checkout may still
-- hold an older one). Rounds 2 and up use the standing worktree's own `zn` (set by `net`): round 1's rebase made it
-- origin/main's engine, and it outlives the raft worktree that kicked the net, which is deleted minutes after the kick.
local function kickerZn(): string
	return `{process.env.ZN_TOP or "."}/zn`
end
local znBin = kickerZn()

local function startStep(label: string, dir: string?, args: { string }): (boolean, string)
	local left = startDeadline - os.time()
	if left < 1 then
		fail(`watch-net: no worktree after {startLimit} s ({label})`)
	end
	local argv = { "run", "--time", tostring(left), "--", "git" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec(znBin, argv, { cwd = dir })
	if r.code == 124 then
		fail(`watch-net: no worktree after {startLimit} s ({label})`)
	end
	return r.ok, oneLine(r.stderr .. r.stdout)
end

-- `main` is the main checkout, read once when the net started: every git call here has it or the worktree as its folder,
-- never the folder the net was started from.
local function ensureWorktree(main: string): string
	startDeadline = os.time() + startLimit
	local fetched, why = startStep("git fetch origin main", main, { "fetch", "--quiet", "origin", "main" })
	if not fetched then
		fail(`watch-net: git fetch origin main failed: {why}`)
	end
	local WT = watch.netDir(main)
	local marker = `{WT}/.git`
	if not fs.isFile(marker) and not fs.isDir(marker) then
		if fs.isDir(WT) then
			fail(`watch-net: {WT} exists and is not a worktree`)
		end
		local hasBranch = gitAt(main, { "rev-parse", "--verify", "--quiet", "refs/heads/watch-net" })
		local args = if hasBranch
			then { "worktree", "add", "-q", WT, "watch-net" }
			else { "worktree", "add", "-q", "-b", "watch-net", WT, "origin/main" }
		local added, addWhy = startStep("git worktree add", main, args)
		if not added then
			-- one line, so the kick that started the net can pass it on
			fail(`watch-net: git {table.concat(args, " ")} failed: {addWhy}`)
		end
	end
	local ok, err = startStep(`git fetch in {WT}`, WT, { "fetch", "--quiet", "origin" })
	if not ok then
		fail(`watch-net: fetch in {WT} failed: {err}`)
	end
	local rebased, rerr = startStep(`git rebase in {WT}`, WT, { "rebase", "--quiet", "origin/main" })
	if not rebased then
		gitAt(WT, { "rebase", "--abort" })
		fail(`watch-net: rebase onto origin/main failed: {rerr}`)
	end
	return WT
end

local PASSED = "z-nile/watch-passed"

-- The commit the net last passed on, recorded in the tree. Absent until the first passing run.
local function passedAt(dir: string): string?
	local abs = `{dir}/{PASSED}`
	if not fs.isFile(abs) then
		return nil
	end
	local sha = sh.trim(fs.readFile(abs))
	if not string.match(sha, "^%x+$") then
		return nil
	end
	local ok, full = gitAt(dir, { "rev-parse", "--verify", "--quiet", sha })
	if not ok or full == "" then
		return nil
	end
	return full
end

-- Source files changed since the last passing commit. With no record yet, the last 30 commits:
-- a first run has no earlier pass to stop at.
local function sincePassed(dir: string): ({ string }, string)
	local head = mustAt(dir, { "rev-parse", "origin/main" })
	local base = passedAt(dir)
	if base then
		if base == head then
			return {}, head
		end
		return watch.sourceOf(linesOf(mustAt(dir, { "diff", "--name-only", base, head }))), head
	end
	local sources: { string } = {}
	local cur = head
	for _ = 1, 30 do
		local ok, parent = gitAt(dir, { "rev-parse", "--verify", "--quiet", `{cur}^1` })
		if not ok or parent == "" then
			break
		end
		for _, s in watch.sourceOf(linesOf(mustAt(dir, { "diff", "--name-only", parent, cur }))) do
			table.insert(sources, s)
		end
		cur = parent
	end
	return watch.unique(sources), head
end

local function resolveSpec(dir: string, path: string): string?
	if fs.isFile(`{dir}/{path}`) then
		return path
	end
	local reg = projects.load(dir)
	for _, p in reg.projects do
		local full = if p.home == "." then path else `{p.home}/{path}`
		if fs.isFile(`{dir}/{full}`) then
			return full
		end
	end
	return nil
end

local function extend(dir: string, spec: string, sources: { string }): boolean
	local file = watch.fileFor(spec)
	local abs = `{dir}/{file}`
	local current: { string } = {}
	if fs.isFile(abs) then
		local parsed, err = watch.parse(fs.readFile(abs))
		if not parsed then
			fail(`watch-net: {file}: {err}`)
		end
		current = parsed :: { string }
	end
	local paths = watch.unique(current)
	for _, s in sources do
		table.insert(paths, s)
	end
	paths = watch.unique(paths)
	if watch.render(paths) == watch.render(current) then
		return false
	end
	fs.writeFile(abs, watch.render(paths))
	return true
end

local function slugFor(spec: string): string
	local s = string.lower(spec)
	s = string.gsub(s, "[^a-z0-9]+", "-")
	s = string.gsub(s, "^-+", "")
	s = string.gsub(s, "-+$", "")
	if #s > 48 then
		s = string.sub(s, 1, 48)
		s = string.gsub(s, "-+$", "")
	end
	return `watch-miss-{s}`
end

local function defectExists(dir: string, slug: string): boolean
	local ok, out = gitAt(dir, { "grep", "-l", "-F", `slug: {slug}`, "--", "*.md" })
	return ok and sh.trim(out) ~= ""
end

local function usedIds(dir: string): { string }
	local out: { string } = {}
	local ok, text = gitAt(dir, { "ls-files", "--", ":(glob)**/.tracker/**" })
	if not ok then
		return out
	end
	for _, path in linesOf(text) do
		local id = string.match(path, "/([fdcR]%d%d%d%d)/")
		if id then
			table.insert(out, id)
		end
	end
	return out
end

local function writeDefect(dir: string, spec: string, commit: string, sources: { string })
	local slug = slugFor(spec)
	if defectExists(dir, slug) then
		print(`watch-net: defect {slug} already exists`)
		return
	end
	local nextFile = `{dir}/z-nile/next`
	local text = if fs.isFile(nextFile)
		then fs.readFile(nextFile)
		else "issue 1 watch-net\nraft 1 watch-net\n"
	local counters = ids.parse(text)
	if not counters then
		fail(`watch-net: {ids.FILE} does not parse`)
	end
	local phrase = string.match(text, "^issue %d+ (%S+)") or "watch-net"
	local n = ids.nextFree("issue", counters :: ids.Counters, usedIds(dir))
	local id = string.format("d%04d", n)
	local root = "z-nile/.tracker"
	local folder = `{dir}/{root}/issues/{id}`
	fs.writeDir(folder)
	local today = os.date("%Y-%m-%d") :: string
	local files = table.concat(sources, ", ")
	local doc = table.concat({
		"---",
		`id: {id}`,
		"type: defect",
		`title: Watch map missed {spec}`,
		`slug: {slug}`,
		"raft: ",
		"depends_on: []",
		"emergent: false",
		"design: draft",
		`created: {today}`,
		"status: backlog",
		"---",
		"",
		`# {id}: Watch map missed {spec}`,
		"",
		"## Problem",
		`{spec} failed on {commit} and its watch file did not name that change's source files ({files}).`,
		"The watch-net run added those files to the watch file.",
		"",
		"## Non-goals",
		"Rewriting the selector.",
		"",
		"## Solution",
		"The watch file now names the source files of the change that broke the test.",
		"",
		"## Design",
		"No code change beyond the watch file this run already wrote.",
		"",
		"### Touched modules",
		"- `" .. spec .. "`",
		"",
		"## Acceptance criteria",
		"",
		"### Checked",
		`AC1: {spec}'s watch file names the source files of {commit}.`,
		"",
		"### Judged",
		"",
		"### Observed",
		"",
		"## Test plan",
		"The failing spec, re-run after the watch file lists the change.",
		"",
	}, "\n")
	fs.writeFile(`{folder}/{id}.md`, doc)
	fs.writeFile(
		`{folder}/check.sh`,
		'#!/usr/bin/env bash\nHERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"\n'
			.. 'source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
			.. 'check "AC1: the watch file names the missed source files" true\nfinish\n'
	)
	process.exec("chmod", { "+x", `{folder}/check.sh` })
	local nextText = ids.format({ issue = n + 1, raft = (counters :: ids.Counters).raft }, phrase)
	fs.writeFile(nextFile, nextText)
	print(`watch-net: captured {root}/issues/{id}/{id}.md ({slug})`)
end

-- Whether a defect document at `path` is open: not moved to done/ or retired/, and not closed as won't do (c0278).
function watchcmd.isOpenDefect(path: string, text: string): boolean
	if string.find(path, "/done/", 1, true) or string.find(path, "/retired/", 1, true) then
		return false
	end
	return not closing.closedDoc(text)
end

-- An open defect with this slug.
local function openDefect(dir: string, slug: string): boolean
	local ok, out = gitAt(dir, { "grep", "-l", "-F", `slug: {slug}`, "--", "*.md" })
	if not ok or sh.trim(out) == "" then
		return false
	end
	for _, path in linesOf(out) do
		local file = `{dir}/{path}`
		local text = if fs.isFile(file) then fs.readFile(file) else ""
		if watchcmd.isOpenDefect(path, text) then
			return true
		end
	end
	return false
end

-- One defect for a red slow tier. A second failure while it is open writes nothing.
local function writeSlowDefect(dir: string, specs: { string }, commit: string)
	local slug = "slow-tier-red"
	local nextFile = `{dir}/z-nile/next`
	local text = if fs.isFile(nextFile)
		then fs.readFile(nextFile)
		else "issue 1 watch-net\nraft 1 watch-net\n"
	local counters = ids.parse(text)
	if not counters then
		fail(`watch-net: {ids.FILE} does not parse`)
	end
	local phrase = string.match(text, "^issue %d+ (%S+)") or "watch-net"
	local n = ids.nextFree("issue", counters :: ids.Counters, usedIds(dir))
	local id = string.format("d%04d", n)
	local root = "z-nile/.tracker"
	local folder = `{dir}/{root}/issues/{id}`
	fs.writeDir(folder)
	local today = os.date("%Y-%m-%d") :: string
	local listed = if #specs > 0 then table.concat(specs, ", ") else "the run named no spec"
	local doc = table.concat({
		"---",
		`id: {id}`,
		"type: defect",
		"title: Slow tier failed",
		`slug: {slug}`,
		"raft: ",
		"depends_on: []",
		"emergent: false",
		"design: draft",
		`created: {today}`,
		"status: backlog",
		"---",
		"",
		`# {id}: Slow tier failed`,
		"",
		"## Problem",
		`z-nile/check.sh --slow failed on {commit}. The failing specs: {listed}.`,
		"The fast suite had already passed. This defect is the slow tier's owner.",
		"",
		"## Non-goals",
		"Running the slow tier on the landing path.",
		"",
		"## Solution",
		"Each named spec is rewritten to the behaviour that replaced what it pinned, or deleted with a line saying what it pinned.",
		"",
		"## Design",
		"No code change in this capture.",
		"",
		"### Touched modules",
		"- `z-nile/tests/slow.tsv`",
		"",
		"## Acceptance criteria",
		"",
		"### Checked",
		"AC1: z-nile/check.sh --slow passes.",
		"",
		"### Judged",
		"",
		"### Observed",
		"",
		"## Test plan",
		"`z-nile/check.sh --slow`.",
		"",
	}, "\n")
	fs.writeFile(`{folder}/{id}.md`, doc)
	fs.writeFile(
		`{folder}/check.sh`,
		'#!/usr/bin/env bash\nHERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"\n'
			.. 'source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
			.. 'check "AC1: z-nile/check.sh --slow passes" true\nfinish\n'
	)
	process.exec("chmod", { "+x", `{folder}/check.sh` })
	local nextText = ids.format({ issue = n + 1, raft = (counters :: ids.Counters).raft }, phrase)
	fs.writeFile(nextFile, nextText)
	print(`watch-net: captured {root}/issues/{id}/{id}.md ({slug})`)
end

local function applyRepairs(dir: string, output: string): boolean
	local landed, commit = sincePassed(dir)
	local changed = false
	for _, raw in watch.failingSpecs(output) do
		local spec = resolveSpec(dir, raw)
		if not spec then
			stdio.ewrite(`watch-net: FAIL line names no spec: {raw}\n`)
			continue
		end
		local sources = watch.forSuite(spec, landed)
		if #sources == 0 then
			stdio.ewrite(`watch-net: {spec} failed and the landed commits change no source file\n`)
			continue
		end
		if extend(dir, spec, sources) then
			changed = true
			print(`watch-net: {spec} now watches {table.concat(sources, " ")} from {commit}`)
			writeDefect(dir, spec, commit, sources)
		end
	end
	return changed
end

local function commitRepair(dir: string, message: string)
	mustAt(dir, { "add", "-A" })
	local ok, _, err = gitAt(dir, { "commit", "-q", "-m", message })
	if not ok then
		fail(`watch-net: commit failed: {err}`)
	end
end

-- The repair reaches main the way a tracker commit does: one commit on top of origin/main, never a force.
-- A rejected push rebases onto the new main and pushes again; an empty result means the other machine landed it.
local function pushMain(dir: string): boolean
	local function once(): boolean
		local ok = gitAt(dir, { "push", "-q", "origin", "HEAD:refs/heads/main" })
		return ok
	end
	if once() then
		return true
	end
	local fetched = gitAt(dir, { "fetch", "--quiet", "origin", "main" })
	if not fetched then
		return false
	end
	local rebased = gitAt(dir, { "rebase", "--quiet", "origin/main" })
	if not rebased then
		gitAt(dir, { "rebase", "--abort" })
		return false
	end
	local ahead = mustAt(dir, { "rev-list", "--count", "origin/main..HEAD" })
	if ahead == "0" then
		return true
	end
	return once()
end

local function recordPass(dir: string, head: string, sources: { string })
	local recorded = passedAt(dir)
	if recorded == head then
		print("watch-net: nothing to do")
		return
	end
	if recorded and #sources == 0 then
		print("watch-net: nothing to do")
		return
	end
	fs.writeFile(`{dir}/{PASSED}`, head .. "\n")
	commitRepair(dir, "watch-net: the suite passed")
	if not pushMain(dir) then
		fail("watch-net: could not record the passing commit on main")
	end
	print("watch-net: pushed main")
end

-- After a green fast suite, off the landing path. A failure opens one defect and leaves the fast pass recorded.
local function runSlow(dir: string, head: string)
	print("watch-net: slow tier")
	local slow = process.exec("bash", { "z-nile/check.sh", "--slow" }, { cwd = dir })
	if slow.ok then
		print("watch-net: slow tier passed")
		return
	end
	local names = watch.failingSpecs(slow.stdout .. "\n" .. slow.stderr)
	if #names == 0 then
		stdio.ewrite(slow.stdout .. "\n" .. slow.stderr)
	end
	if openDefect(dir, "slow-tier-red") then
		print("watch-net: the slow tier failed; defect slow-tier-red is already open")
		return
	end
	writeSlowDefect(dir, names, head)
	local _, porcelain = gitAt(dir, { "status", "--porcelain" })
	if sh.trim(porcelain) == "" then
		print("watch-net: the slow tier failed and no new defect was written")
		return
	end
	commitRepair(dir, "watch-net: the slow tier failed")
	if not pushMain(dir) then
		fail("watch-net: could not push the slow-tier defect")
	end
	print("watch-net: the slow tier failed; pushed a defect")
end

local function runOnce(main: string, ready: string?)
	local dir = ensureWorktree(main)
	if ready then
		fs.writeFile(ready, "ready\n")
	end
	local sources, head = sincePassed(dir)
	if passedAt(dir) and #sources == 0 then
		-- a capture or other tracker-only landing: no source file changed since the last pass, so no suite runs
		print("watch-net: nothing to do")
		return
	end
	print(`watch-net: fast suite of every project in {dir}`)
	local ran = process.exec("bash", { "z-nile/check.sh", "--full" }, { cwd = dir })
	local output = ran.stdout .. "\n" .. ran.stderr
	if ran.ok then
		recordPass(dir, head, sources)
		runSlow(dir, head)
		return
	end
	if #watch.failingSpecs(output) == 0 then
		stdio.ewrite(output)
		fail("watch-net: the suite failed and named no spec")
	end
	if not applyRepairs(dir, output) then
		print("watch-net: nothing to do")
		return
	end
	commitRepair(dir, "watch-net: extend the map for a missed failure")
	if pushMain(dir) then
		print("watch-net: pushed main")
		return
	end
	-- the other machine landed first: re-apply against its tree, which is now HEAD
	if not applyRepairs(dir, output) then
		print("watch-net: nothing to do")
		return
	end
	commitRepair(dir, "watch-net: extend the map for a missed failure")
	if not pushMain(dir) then
		fail("watch-net: push rejected twice")
	end
	print("watch-net: pushed main")
end

-- One net at a time per repository (d0383 F3). The lock is a file in the main checkout's `.cache/watch-net/` holding the
-- holder's pid and start id; it is taken over when the holder is gone or the pid is another process's by now. Taking,
-- giving back and the rerun request all happen inside a short mutex (a folder made with `mkdir`, which is atomic), so
-- two nets starting together cannot both take it, and a request recorded just as the holder ends is honoured by it or
-- found by the next net, never lost.
local MAX_ROUNDS = 4

local function startOf(pid: number): string?
	return procstart.startOf(tostring(pid))
end

local function mutexed(dir: string, section: () -> any): any
	local guard = `{dir}/guard`
	local made = false
	for _ = 1, 100 do
		if process.exec("mkdir", { guard }).ok then
			made = true
			break
		end
		task.wait(0.1)
	end
	if not made then
		-- a net that died inside the section left it: take it over, and fail closed when the folder cannot be made (two
		-- nets must never both be inside)
		process.exec("rmdir", { guard })
		for attempt = 1, 2 do
			if process.exec("mkdir", { guard }).ok then
				made = true
				break
			end
			if attempt == 1 then
				task.wait(0.1)
			end
		end
		if not made then
			fail(`watch-net: cannot take the lock's guard {guard}`)
		end
	end
	local ok, result = pcall(section)
	process.exec("rmdir", { guard })
	if not ok then
		error(result, 0)
	end
	return result
end

-- Takes the lock, or records a rerun request with the net that holds it. Returns the holder's pid when it is held.
local function takeLock(dir: string, mine: string): number?
	return mutexed(dir, function(): number?
		local text = if fs.isFile(`{dir}/lock`) then fs.readFile(`{dir}/lock`) else ""
		local held = watch.parseLock(text)
		if held and watch.lockHeld(text, startOf(held.pid)) then
			fs.writeFile(`{dir}/rerun`, "rerun\n")
			return held.pid
		end
		fs.writeFile(`{dir}/lock`, mine)
		if fs.isFile(`{dir}/rerun`) then
			fs.removeFile(`{dir}/rerun`) -- a request left by a net that never got to honour it
		end
		return nil
	end)
end

-- At the end of a round: "again" (the lock kept, the request taken) when a rerun was requested, rounds remain and the time
-- left under the net's own limit fits another round as long as the longest so far; else gives the lock back, and
-- "handoff" when a request is pending (it stays in place: the fresh net that takes the lock next starts from the newest
-- main, which satisfies it, and removes it then), "done" when there was none.
local function finishRound(dir: string, mine: string, round: number, rounds: { number }, left: number): string
	return mutexed(dir, function(): string
		local requested = fs.isFile(`{dir}/rerun`)
		if watch.again(requested, round, MAX_ROUNDS, rounds, left) then
			fs.removeFile(`{dir}/rerun`)
			return "again"
		end
		if fs.isFile(`{dir}/lock`) and fs.readFile(`{dir}/lock`) == mine then
			fs.removeFile(`{dir}/lock`)
		end
		return if requested then "handoff" else "done"
	end)
end

export type NetOptions = { ready: string?, start: number?, limit: number? }

-- Runs every project's fast suite on current main, in the main checkout's `.worktree/watch-net`, and pushes a repair onto
-- main. The files it adds are the source files changed since `z-nile/watch-passed` (the last commit the
-- suite passed on). A green fast suite then runs the slow tier in the same worktree; a slow failure opens
-- one defect and does not undo the fast pass. A second machine rebases; when the repair is already on main
-- it finds nothing to do. One net runs at a time: a net that finds another running prints "watch-net: already running",
-- asks it for one more run and ends 0; `opts.ready` is the file the net writes when it has its worktree (first round
-- only), `opts.start` the limit on getting there.
function watchcmd.net(opts: NetOptions?)
	local given: NetOptions = opts or {}
	startLimit = given.start or START_SECONDS
	local began = os.time()
	-- the main checkout, read once while the kick that started this net still waits in its folder (which is deleted
	-- soon after); every later step names it or the standing worktree, never the current folder
	local main = mainDir()
	local dir = watch.filesDir(main)
	fs.writeDir(dir)
	local me = tonumber(sh.trim(sh.must("sh", { "-c", "echo $PPID" }))) or 0
	local mine = watch.lockText(me, startOf(me) or "unknown")
	local holder = takeLock(dir, mine)
	if holder then
		print(`{watch.ALREADY} (pid {holder}); a rerun is requested`)
		return
	end
	releaseHeld = function()
		if fs.isFile(`{dir}/lock`) and fs.readFile(`{dir}/lock`) == mine then
			fs.removeFile(`{dir}/lock`)
		end
	end
	local limit = watch.netLimit(given.limit, reap.NET_SECONDS)
	local rounds: { number } = {}
	local handoffFailed = false
	-- any error in a round (not only `fail`) gives the lock back and still reaches the log and the exit code
	local ok, err = pcall(function()
		for round = 1, MAX_ROUNDS do
			local roundStart = os.time()
			znBin = if round == 1 then kickerZn() else `{watch.netDir(main)}/zn`
			runOnce(main, if round == 1 then given.ready else nil)
			table.insert(rounds, os.time() - roundStart)
			local left = began + limit - os.time()
			local state = finishRound(dir, mine, round, rounds, left)
			if state == "handoff" then
				-- The request does not fit this net's time (or its rounds are used up). The lock is already given back; a
				-- fresh net with its own full time is started the way every kick starts one (the standing worktree's `zn`,
				-- the same script, its own files, which the reaper recognises). It removes the request when it takes the
				-- lock, and starts from the newest main. This ends: a hand-off needs a request pending at the end of a round,
				-- and the fresh net consumed the one there was before its first round, so only a landing that kicked
				-- after that can ask for the next, once per landing.
				local wt = watch.netDir(main)
				local kicked = process.exec(`{wt}/zn`, { "watch-kick" }, { cwd = wt })
				local said = oneLine(kicked.stdout .. " " .. kicked.stderr)
				if kicked.ok then
					print(`watch-net: the rerun goes to a fresh net: {said}`)
				else
					print(
						`watch-net: the rerun could not be handed to a fresh net: {said}; the next landing's kick runs it`
					)
					handoffFailed = true
				end
			end
			if state ~= "again" then
				break
			end
			print("watch-net: a rerun was requested; running again")
		end
	end)
	releaseHeld()
	releaseHeld = function() end
	if not ok then
		error(err, 0)
	end
	if handoffFailed then
		process.exit(1)
	end
end

-- The limit past which a pass is reported stale: how far the newest source commit on main may lie ahead of the last
-- "watch-net: the suite passed" commit. The kick and the board both ask `watchcmd.noPassLine`, which reads it.
watchcmd.NO_PASS_LIMIT_SECONDS = 24 * 3600

-- "watch-net: no pass since <date>" when origin/main (as `dir` last fetched it) has a commit that changes something outside
-- the tracker folders and is more than the limit newer than the last pass commit, else nil (d0383 F8). Local reads
-- only: it never fetches.
function watchcmd.noPassLine(dir: string): string?
	local _, passes = gitAt(dir, {
		"log",
		"-n",
		"20",
		"--format=%ct%x09%H%x09%s",
		"--grep=^watch-net: the suite passed$",
		"origin/main",
	})
	local passed, sha = watch.lastPass(passes)
	if passed == nil or sha == nil then
		return nil
	end
	local ok, log = gitAt(dir, {
		"log",
		"--first-parent",
		"-m",
		"--no-renames",
		"--name-only",
		"--format=%x01%ct",
		`{sha}..origin/main`,
	})
	if not ok then
		return nil
	end
	local roots = projects.roots(projects.load(dir))
	local newest = watch.newestSource(log, function(path: string): boolean
		return trackerstate.under(path, roots)
	end)
	return watch.noPassLine(passed, newest, watchcmd.NO_PASS_LIMIT_SECONDS)
end

-- How long a kick waits for the net to be known started (its own start limit and a margin) and how long the net may take
-- itself: both are flags of `watch-kick` (`--wait`, `--start`), never inherited variables.
local START_MARGIN_SECONDS = 30
local KEEP_KICKS = 20
local POLL_SECONDS = 0.2

export type KickOptions = { wait: number?, start: number?, limit: number? }

-- Starts the net after a landing under `./zn run` and waits until it is known to have started: it created or reused its
-- worktree (it wrote its marker), or another net was already running (exit 0 and its line), or it has failed (the exit
-- file, the net's last log line on stderr, false), or its shell is gone, or the kick's own backstop bound passed (false,
-- a line on stderr). Never true without one of the first two. The files are this kick's own, in the main checkout's
-- `.cache/watch-net/`, which a deleted raft worktree takes nothing from. The landing that asked ignores the result. The spec runner
-- sets PICKMAN_WATCH_NET=off so a fixture land does not start a suite; a real landing leaves it unset.
function watchcmd.kick(opts: KickOptions?): boolean
	if process.env.PICKMAN_WATCH_NET == "off" then
		return true
	end
	local given: KickOptions = opts or {}
	local root = sh.git({ "rev-parse", "--show-toplevel" })
	-- every way out of the kick, a refusal included, ends with the no-pass line when there is one (it only reads git)
	local function sayNoPass()
		local line = watchcmd.noPassLine(root)
		if line then
			print(line)
		end
	end
	-- two refusals, both before any file or process: a dispatched step's kick first (its wrapped git and bot credential
	-- could not push the net's records), then a CPU limit the net could not shed
	local stepLine = watch.stepKick({
		ZN_DISPATCH = process.env.ZN_DISPATCH,
		ZN_PUBLISH_BROKER = process.env.ZN_PUBLISH_BROKER,
	})
	if stepLine then
		stdio.ewrite(stepLine .. "\n")
		sayNoPass()
		return false
	end
	-- the net inherits this process's hard CPU limit (a `./zn run` around the kick sets one) and cannot raise it: below the
	-- floor no net is started, with the reason on stderr (the landing that kicked goes on)
	local hard = sh.trim(sh.run("sh", { "-c", "ulimit -Ht" }).stdout)
	if not cpulimit.ok(hard, cpulimit.SPEC_DEFAULT) then
		stdio.ewrite(cpulimit.refusal(hard, cpulimit.SPEC_DEFAULT) .. "\n")
		sayNoPass()
		return false
	end
	local main = mainDir()
	local dir = watch.filesDir(main)
	fs.writeDir(`{main}/.cache`)
	fs.writeDir(dir)
	local pid = tonumber(sh.trim(sh.must("sh", { "-c", "echo $PPID" }))) or 0
	local files = watch.kickFiles(dir, os.time(), pid)
	for _, name in watch.pruneKicks(fs.readDir(dir), KEEP_KICKS) do
		fs.removeFile(`{dir}/{name}`)
	end
	local start = given.start or START_SECONDS
	local wait = given.wait or (start + START_MARGIN_SECONDS)
	-- reap.NET_SCRIPT is the one text the reaper recognises. `cd` then the group, not `cd && group &`: that list's own
	-- shell would keep this call's pipes open for as long as the net runs. It prints the group shell's pid.
	local started = process.exec("perl", {
		"-e",
		reap.NET_DETACH,
		"bash",
		"-c",
		reap.NET_SCRIPT,
		reap.NET_ARGV0,
		root,
		files.log,
		files.ready,
		files.exit,
		tostring(start),
		if given.limit then tostring(given.limit) else "",
	})
	if not started.ok then
		stdio.ewrite(`watch-net: not started: {oneLine(started.stderr)}\n`)
		sayNoPass()
		return false
	end
	local shell = tonumber(sh.trim(started.stdout)) or 0
	-- who to look for, should the kick fail: the net's shell (a person reading a stuck kick's folder finds its pid here)
	fs.writeFile(`{dir}/{files.id}.pid`, `{shell}\n`)
	-- wall seconds (os.clock counts CPU time); a counted loop, so it ends however the clock behaves
	local deadline = os.time() + wait
	local state: "ready" | "exited" | "gone" | "waiting" = "waiting"
	local code: number? = nil
	for _ = 1, wait * 5 + 5 do
		-- alive first: a shell that ended has written its files already
		local alive = shell > 0 and process.exec("kill", { "-0", tostring(shell) }).ok
		code = if fs.isFile(files.exit) then tonumber(sh.trim(fs.readFile(files.exit))) or -1 else nil
		state = watch.startState(fs.isFile(files.ready), code, alive)
		if state ~= "waiting" or os.time() >= deadline then
			break
		end
		task.wait(POLL_SECONDS)
	end
	local last = watch.errorLine(if fs.isFile(files.log) then fs.readFile(files.log) else "")
	local good = true
	if state == "ready" then
		print(`watch-net: started, log at {files.log}`)
	elseif
		state == "exited"
		and code == 0
		and last
		and string.sub(last, 1, #watch.ALREADY) == watch.ALREADY
	then
		print(last)
	elseif state == "exited" then
		stdio.ewrite(`{last or `watch-net: the net exited ({code}) before it had its worktree`}\n`)
		stdio.ewrite(`watch-net: log at {files.log}\n`)
		good = false
	elseif state == "gone" then
		stdio.ewrite(`watch-net: the net ended before it had its worktree, log at {files.log}\n`)
		good = false
	else
		stdio.ewrite(`watch-net: no word from the net after {wait} s, log at {files.log}\n`)
		good = false
	end
	sayNoPass()
	return good
end

return watchcmd
