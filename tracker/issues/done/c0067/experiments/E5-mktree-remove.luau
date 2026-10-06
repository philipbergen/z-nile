--!strict
-- c0067 E5: mktree with a removed entry, and an emptied directory dropped from its parent. Scratch repo under
-- .cache/c0067-e5 (run from the repository root: lune run tracker/issues/active/c0067/experiments/E5-mktree-remove).
local fs = require("@lune/fs")
local process = require("@lune/process")

local base = ".cache/c0067-e5"
if fs.isDir(base) then
	fs.removeDir(base)
end
fs.writeDir(base)
local repo = process.exec("pwd", { "-P" }).stdout:gsub("%s+$", "") .. "/" .. base .. "/repo.git"
local function git(args: { string }, stdin: string?): string
	local r = process.exec("git", args, { cwd = repo, stdio = if stdin then { stdin = stdin } else nil })
	assert(r.ok, table.concat(args, " ") .. ": " .. r.stderr)
	return (r.stdout:gsub("%s+$", ""))
end
assert(process.exec("git", { "init", "-q", "--bare", repo }).ok, "git init")
local function blob(text: string): string
	return git({ "hash-object", "-w", "--stdin" }, text)
end
local function tree(entries: { string }): string
	return git({ "mktree" }, table.concat(entries, "\n") .. "\n")
end
-- tracker/issues/{.gitkeep, c0010/{c0010.md, acceptance/a.spec.luau}}
local acc = tree({ `100644 blob {blob("spec\n")}\ta.spec.luau` })
local item = tree({ `100644 blob {blob("doc\n")}\tc0010.md`, `040000 tree {acc}\tacceptance` })
local issues = tree({ `100644 blob {blob("")}\t.gitkeep`, `040000 tree {item}\tc0010` })
local root = tree({ `040000 tree {tree({ `040000 tree {issues}\tissues` })}\ttracker` })
-- remove c0010/c0010.md and c0010/acceptance/a.spec.luau: rebuild bottom-up, dropping empty trees
local accAfter = git({ "mktree" }, "") -- empty input
print("empty mktree:", accAfter)
local issuesAfter = tree({ `100644 blob {blob("")}\t.gitkeep` }) -- the emptied c0010 is simply not listed
local rootAfter = tree({ `040000 tree {tree({ `040000 tree {issuesAfter}\tissues` })}\ttracker` })
local listed = git({ "ls-tree", "-r", "--name-only", rootAfter })
print("after:", listed)
assert(listed == "tracker/issues/.gitkeep", "the old directory is gone and .gitkeep is kept")
local diff = git({ "diff-tree", "-r", "--no-renames", "--name-only", root, rootAfter })
print("diff:", (diff:gsub("\n", ", ")))
local c = git({ "commit-tree", rootAfter, "-m", "e5" })
git({ "update-ref", "refs/heads/main", c })
local fsck = process.exec("git", { "fsck", "--strict" }, { cwd = repo })
print("fsck ok:", fsck.ok, fsck.stdout .. fsck.stderr)
assert(fsck.ok, "fsck")
print("E5 PASS")
