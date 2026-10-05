--!strict
-- Applies an id map to the checkout: renames item folders, their documents and promoted spec folders, then rewrites
-- references. Shared by `compact` and `remap` (c0870). Runs in the working directory, which is the checkout.
local audit = require("./audit")
local fs = require("@lune/fs")
local ids = require("./ids")
local process = require("@lune/process")
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

local function rewritesIds(path: string): boolean
	return string.sub(path, 1, 8) == "tracker/"
		and string.sub(path, 1, 18) ~= "tracker/templates/"
		and (string.match(path, "%.md$") ~= nil or string.match(path, "%.sh$") ~= nil)
end

-- Renames every item in `found` that the map moves, and every tests/acceptance/<old> folder, then rewrites: ids in
-- tracker/ .md and .sh files (templates aside), and tests/acceptance/<id> paths in every other tracked text file.
-- One pass per file, so a new id is never mapped again.
function compact.apply(map: { [string]: string }, found: { audit.Found }, at: string?)
	local root = at or "."
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
	for old, new in map do
		if old ~= new and fs.isDir(`{root}/tests/acceptance/{old}`) then
			table.insert(moves, { from = `tests/acceptance/{old}`, to = `tests/acceptance/{new}` })
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
		local template = string.sub(path, 1, 18) == "tracker/templates/" -- never rewritten (R0270 review 001 F3)
		if path ~= ids.FILE and path ~= ids.MAP_FILE and not template and fs.isFile(abs) then
			local text = fs.readFile(abs)
			if not string.find(text, "\0", 1, true) then
				local out = if rewritesIds(path) then ids.rewrite(text, map) else ids.rewritePaths(text, map)
				if out ~= text then
					fs.writeFile(abs, out)
				end
			end
		end
	end
end

-- Branches that change tracker/ or tests/acceptance/ since they left origin/main: every origin branch and every local
-- one except main and `current`. Compaction renumbers under them, so they block it unless forced.
function compact.busyRefs(current: string): { string }
	local out: { string } = {}
	local refs = sh.git({ "for-each-ref", "--format=%(refname)", "refs/remotes/origin", "refs/heads" })
	for ref in string.gmatch(refs, "[^\n]+") do
		local skip = ref == "refs/remotes/origin/main"
			or ref == "refs/remotes/origin/HEAD"
			or ref == "refs/heads/main"
			or ref == `refs/heads/{current}`
		if not skip then
			local d = sh.run(
				"git",
				{ "diff", "--name-only", `origin/main...{ref}`, "--", "tracker", "tests/acceptance" }
			)
			if not d.ok or sh.trim(d.stdout) ~= "" then
				table.insert(
					out,
					string.match(ref, "^refs/remotes/(.+)$") or string.match(ref, "^refs/heads/(.+)$") or ref
				)
			end
		end
	end
	return out
end

return compact
