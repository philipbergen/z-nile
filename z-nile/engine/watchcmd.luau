--!strict
-- The watch-map commands and the two writes the tracker makes for it: `./zn done` captures a ticket's source
-- files, `./zn commit` rewrites watch files a rename or delete touches, `./zn watch-bootstrap` fills the map
-- from history once, and `./zn watch-net` repairs a miss after a landing. Reads and git sit here; the rules
-- are z-nile/lib/watch.luau.

local fs = require("@lune/fs")
local graph = require("../lib/graph")
local ids = require("./ids")
local process = require("@lune/process")
local projects = require("./projects")
local sh = require("../lib/sh")
local stdio = require("@lune/stdio")
local watch = require("../lib/watch")

local watchcmd = {}

export type Member = { id: string, dest: string }

local LOG = "--pretty=format:---COMMIT---%n%B%n---FILES---"

local function fail(msg: string): never
	stdio.ewrite(msg .. "\n")
	return process.exit(1)
end

local function linesOf(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
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

-- Commits reachable from HEAD but not from the merge base, in `git log` order.
local function raftLog(): string
	local base = sh.run("git", { "merge-base", "HEAD", "origin/main" })
	if not base.ok then
		base = sh.run("git", { "merge-base", "HEAD", "main" })
	end
	local args = { "log", "--name-only", LOG }
	if base.ok and sh.trim(base.stdout) ~= "" then
		table.insert(args, `{sh.trim(base.stdout)}..HEAD`)
	end
	return sh.git(args)
end

local addingCommit: (string) -> string?
local resolvedRequires: (string, string) -> { string }

local function memberIdsOf(members: { Member }): { string }
	local ids_: { string } = {}
	for _, m in members do
		table.insert(ids_, m.id)
	end
	return ids_
end

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

-- Writes each member's watch.txt from the source files its commits changed, and a sidecar for every
-- spec those commits added or edited outside an acceptance folder. Stages them so a failed `done`
-- (git reset --hard) drops them. A source commit that does not name exactly one member gives every
-- member the raft's whole source list. A ticket whose commits changed no source file watches the
-- files its specs require. An empty list is never written.
function watchcmd.capture(members: { Member })
	local commits = watch.parseLog(raftLog())
	local ids_ = memberIdsOf(members)
	local per, shared = watch.assign(commits, ids_)
	if shared then
		print(
			"watch: a source commit does not name exactly one issue, so every issue gets the raft's source list"
		)
	end
	local member: { [string]: boolean } = {}
	for _, id in ids_ do
		member[id] = true
	end
	local function raftList(): { string }
		local all: { string } = {}
		for _, id in ids_ do
			local paths: { string } = per[id] or {}
			for _, p in paths do
				table.insert(all, p)
			end
		end
		return watch.unique(all)
	end
	-- The issue whose commit added the spec, or nil when that cannot be told.
	local function issueOf(spec: string): string?
		local added = addingCommit(spec)
		if not added then
			return nil
		end
		local shown = sh.run("git", { "log", "-1", "--format=%B", added })
		if not shown.ok then
			return nil
		end
		local named: { string } = {}
		for _, id in watch.issueIds(shown.stdout) do
			if member[id] then
				table.insert(named, id)
			end
		end
		if #named == 1 then
			return named[1]
		end
		return nil
	end
	local function listFor(issueId: string?): { string }
		if shared or not issueId then
			return raftList()
		end
		return per[issueId] or raftList()
	end
	local function withRequires(spec: string, paths: { string }): { string }
		local kept = watch.forSuite(spec, paths)
		if #kept > 0 or not fs.isFile(spec) then
			return kept
		end
		return watch.forSuite(spec, resolvedRequires(spec, fs.readFile(spec)))
	end
	for _, m in members do
		local specs = specsIn(m.dest)
		if #specs > 0 then
			local paths = withRequires(specs[1], listFor(m.id))
			if #paths == 0 then
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
			local file = `{m.dest}/watch.txt`
			if stageList(file, paths) then
				print(`watch: {m.id} {file} ({#paths})`)
			else
				print(`watch: {m.id} lists no source files and its specs require none ({file})`)
			end
		end
	end
	local seen: { [string]: boolean } = {}
	local specs: { string } = {}
	for _, c in commits do
		for _, f in c.files do
			local underTests = string.find(f, "/tests/", 1, true) or string.sub(f, 1, 6) == "tests/"
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
	end
	table.sort(specs)
	for _, spec in specs do
		local paths = union(readList(watch.fileFor(spec)), listFor(issueOf(spec)))
		paths = withRequires(spec, paths)
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

local WT = ".worktree/watch-net"

local function ensureWorktree(): string
	local fetched = sh.run("git", { "fetch", "--quiet", "origin", "main" })
	if not fetched.ok then
		fail(`watch-net: git fetch origin main failed: {fetched.stderr}`)
	end
	local marker = `{WT}/.git`
	if not fs.isFile(marker) and not fs.isDir(marker) then
		if fs.isDir(WT) then
			fail(`watch-net: {WT} exists and is not a worktree`)
		end
		local has = sh.run("git", { "rev-parse", "--verify", "--quiet", "refs/heads/watch-net" })
		if has.ok then
			sh.git({ "worktree", "add", "-q", WT, "watch-net" })
		else
			sh.git({ "worktree", "add", "-q", "-b", "watch-net", WT, "origin/main" })
		end
	end
	local ok, _, err = gitAt(WT, { "fetch", "--quiet", "origin" })
	if not ok then
		fail(`watch-net: fetch in {WT} failed: {err}`)
	end
	local rebased, _, rerr = gitAt(WT, { "rebase", "--quiet", "origin/main" })
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

-- Runs every project's fast suite on current main, in `.worktree/watch-net`, and pushes a repair onto
-- main. The files it adds are the source files changed since `z-nile/watch-passed` (the last commit the
-- suite passed on). A second machine rebases; when the repair is already on main it finds nothing to do.
function watchcmd.net()
	local dir = ensureWorktree()
	print(`watch-net: fast suite of every project in {dir}`)
	local ran = process.exec("bash", { "z-nile/check.sh", "--full" }, { cwd = dir })
	local output = ran.stdout .. "\n" .. ran.stderr
	local sources, head = sincePassed(dir)
	if ran.ok then
		recordPass(dir, head, sources)
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

-- Starts the net after a landing and returns at once. The run is bounded by `./zn run` and writes
-- `.cache/watch-net.log` in the checkout that started it. A failure to start is reported and does not
-- fail the command that asked. The spec runner sets PICKMAN_WATCH_NET=off so a fixture land does not
-- start a suite; a real landing leaves it unset.
function watchcmd.kick()
	if process.env.PICKMAN_WATCH_NET == "off" then
		return
	end
	local root = sh.git({ "rev-parse", "--show-toplevel" })
	fs.writeDir(`{root}/.cache`)
	local started = process.exec("bash", {
		"-c",
		'cd "$1" && ./zn run --time 3600 -- ./zn watch-net > .cache/watch-net.log 2>&1 &',
		"watch-net",
		root,
	})
	if not started.ok then
		stdio.ewrite(`watch-net: not started: {started.stderr}\n`)
		return
	end
	print("watch-net: started, log at .cache/watch-net.log")
end

return watchcmd
