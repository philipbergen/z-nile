--!strict
-- Applies an id map to the checkout: renames item folders, their documents and promoted spec folders, then rewrites
-- references. Shared by `compact` and `remap` (c0870). Runs in the working directory, which is the checkout.
local audit = require("./audit")
local fs = require("@lune/fs")
local ids = require("./ids")
local process = require("@lune/process")
local projects = require("./projects")
local sh = require("../lib/sh")

local compact = {}

-- git in `root` (the checkout, or a scratch worktree of it); raises with git's output on failure.
local function gitIn(root: string, args: { string }): string
	local r = process.exec("git", args, { cwd = root })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed in {root}: {r.stderr}{r.stdout}`, 0)
	end
	return sh.trim(r.stdout)
end

-- Moves each `from` to its `to` in two phases (through a hidden name beside it), so a chain where one item's new
-- name is another's old one never lands on a folder that has not moved yet.
local function moveAll(root: string, moves: { { from: string, to: string } })
	for _, m in moves do
		local parent = string.match(m.to, "^(.*)/[^/]+$") :: string
		local name = string.match(m.to, "([^/]+)$") :: string
		gitIn(root, { "mv", m.from, `{parent}/{name}.compacting` })
	end
	for _, m in moves do
		local parent = string.match(m.to, "^(.*)/[^/]+$") :: string
		local name = string.match(m.to, "([^/]+)$") :: string
		gitIn(root, { "mv", `{parent}/{name}.compacting`, m.to })
	end
end

-- The templates are never rewritten (R0270 review 001 F3); they left tracker/templates/ in c0114.
local TEMPLATES = "z-nile/templates/"

-- ids are rewritten in the .md and .sh files under every project root (c0114); elsewhere only acceptance paths are.
local function rewritesIds(path: string, roots: { string }): boolean
	return projects.rootOf(path, roots) ~= nil
		and (string.match(path, "%.md$") ~= nil or string.match(path, "%.sh$") ~= nil)
end

-- Renames every item in `found` that the map moves, and every tests/acceptance/<old> folder of every project
-- (c0120: pickman/tests/acceptance too), then rewrites: ids in the .md and .sh files under every project root, and
-- tests/acceptance/<id> paths (also as <home>/tests/acceptance/<id>) in every other tracked text file (the templates
-- are left alone). One pass per file, so a new id is never mapped again.
function compact.apply(map: { [string]: string }, found: { audit.Found }, at: string?)
	local root = at or "."
	local reg = projects.load(root)
	local roots = projects.roots(reg)
	local homes: { string } = {}
	for _, p in reg.projects do
		if p.home ~= "." then
			table.insert(homes, p.home)
		end
	end
	local moves: { { from: string, to: string } } = {}
	local docs: { { dir: string, old: string, new: string } } = {}
	for _, f in found do
		local new = map[f.id]
		if new and new ~= f.id then
			local parent = string.match(f.path, "^(.*)/[^/]+$") :: string
			table.insert(moves, { from = f.path, to = `{parent}/{new}` })
			table.insert(docs, { dir = `{parent}/{new}`, old = f.id, new = new })
		end
	end
	for _, acc in projects.acceptanceRoots(reg) do
		for old, new in map do
			if old ~= new and fs.isDir(`{root}/{acc}/{old}`) then
				table.insert(moves, { from = `{acc}/{old}`, to = `{acc}/{new}` })
			end
		end
	end
	moveAll(root, moves)
	for _, d in docs do
		if fs.isFile(`{root}/{d.dir}/{d.old}.md`) then
			gitIn(root, { "mv", `{d.dir}/{d.old}.md`, `{d.dir}/{d.new}.md` })
		end
	end
	for path in string.gmatch(gitIn(root, { "ls-files" }), "[^\n]+") do
		local abs = `{root}/{path}`
		local template = string.sub(path, 1, #TEMPLATES) == TEMPLATES
		if path ~= ids.FILE and path ~= ids.MAP_FILE and not template and fs.isFile(abs) then
			local text = fs.readFile(abs)
			if not string.find(text, "\0", 1, true) then
				local out = if rewritesIds(path, roots)
					then ids.rewrite(text, map)
					else ids.rewritePaths(text, map, homes)
				if out ~= text then
					fs.writeFile(abs, out)
				end
			end
		end
	end
end

-- The paths compaction guards: every project root and every project's promoted specs (c0120: pickman/tests/acceptance).
function compact.guarded(): { string }
	local reg = projects.load()
	local out = projects.acceptanceRoots(reg)
	for _, r in projects.roots(reg) do
		table.insert(out, r)
	end
	return out
end

-- Branches that change any of `paths` (default compact.guarded()) since they left origin/main: every origin branch
-- and every local one except main and `current`. Compaction renumbers under them, so they block it unless forced;
-- `./zn busy` reports them for any paths (c0120's readiness: tracker/, src/, tests/). Full refnames
-- (`refs/heads/x`, `refs/remotes/origin/x`), so a local branch named `origin/x` stays told apart (code review 011 F5);
-- compact.busyRefs gives the short names.
function compact.busyRefNames(current: string, paths: { string }?): { string }
	local out: { string } = {}
	local within = paths or compact.guarded()
	local refs = sh.git({ "for-each-ref", "--format=%(refname)", "refs/remotes/origin", "refs/heads" })
	for ref in string.gmatch(refs, "[^\n]+") do
		local skip = ref == "refs/remotes/origin/main"
			or ref == "refs/remotes/origin/HEAD"
			or ref == "refs/heads/main"
			or ref == `refs/heads/{current}`
			or ref == `refs/remotes/origin/{current}`
		if not skip then
			local args = { "diff", "--name-only", `origin/main...{ref}`, "--" }
			for _, r in within do
				table.insert(args, r)
			end
			local d = sh.run("git", args)
			if not d.ok or sh.trim(d.stdout) ~= "" then
				table.insert(out, ref)
			end
		end
	end
	return out
end

-- A refname as people write it: `origin/x` for a remote-tracking branch, `x` for a local one.
function compact.shortRef(ref: string): string
	return string.match(ref, "^refs/remotes/(.+)$") or string.match(ref, "^refs/heads/(.+)$") or ref
end

-- compact.busyRefNames by short name (compaction's refusal lists these).
function compact.busyRefs(current: string, paths: { string }?): { string }
	local out: { string } = {}
	for _, ref in compact.busyRefNames(current, paths) do
		table.insert(out, compact.shortRef(ref))
	end
	return out
end

-- Other worktrees of this repository with uncommitted changes (tracked or not) under any of `paths`, read without
-- taking git's optional locks, so nothing of theirs is written (c0120). `self` is this checkout's physical path.
function compact.dirtyWorktrees(self: string, paths: { string }): { string }
	local out: { string } = {}
	local list = sh.git({ "worktree", "list", "--porcelain" })
	for path in string.gmatch(list, "worktree ([^\n]+)") do
		if path ~= self then
			local args = { "--no-optional-locks", "-C", path, "status", "--porcelain", "--" }
			for _, p in paths do
				table.insert(args, p)
			end
			local r = sh.run("git", args)
			if r.ok and sh.trim(r.stdout) ~= "" then
				table.insert(out, path)
			end
		end
	end
	return out
end

return compact
