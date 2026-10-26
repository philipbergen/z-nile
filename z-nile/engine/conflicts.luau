--!strict
-- c0139: tools that rewrite tracked files refuse to run over a merge conflict. A checkout with unmerged paths (a merge,
-- rebase or cherry-pick stopped on conflicts), or a file under a project root or a skills folder whose working copy
-- (tracked or untracked, not ignored: what `git add -A` would commit) holds a whole conflict (a `<<<<<<< ` line, then a
-- `>>>>>>> ` line, each at the start of a line), stops the command before it writes anything, naming each path to
-- resolve and how. Reads only. The folders come from the registry (`conflicts.folders`), one list for every caller.
local fs = require("@lune/fs")
local projects = require("./projects")
local sh = require("../lib/sh")
local skills = require("./skills")

local conflicts = {}

-- how to get out once a conflict is in: ./zn refuses until it is resolved, so the fix is plain git and a PR
conflicts.RECOVERY = "resolve with plain git (edit the file or `git checkout --ours/--theirs`, then `git add` and "
	.. "`git commit`); a conflict that reached main lands its fix by a pull request made with plain git and gh"

-- the first line of `text` that opens a conflict closed later in the text (`<<<<<<< ` … `>>>>>>> `), or nil
function conflicts.markerLine(text: string): number?
	local open: number? = nil
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		if string.sub(line, 1, 8) == "<<<<<<< " and not open then
			open = n
		elseif string.sub(line, 1, 8) == ">>>>>>> " and open then
			return open
		end
	end
	return nil
end

-- every project root and every skills folder of the registry at `top`, or nil and why when it can't be read
function conflicts.folders(top: string): ({ string }?, string?)
	local ok, reg = pcall(projects.load, top, true)
	if not ok then
		return nil, `can't read the registry ({reg})`
	end
	local out: { string } = {}
	for _, r in projects.roots(reg) do
		table.insert(out, r)
	end
	for _, f in skills.folders(reg) do
		table.insert(out, f.path)
	end
	return out, nil
end

-- the paths git reports as unmerged in the checkout at `top`, sorted and unique; nil and why when git fails (design
-- review 002 F2: only an ok read with no output means none)
function conflicts.unmerged(top: string): ({ string }?, string?)
	local r = sh.run("git", { "-C", top, "diff", "--name-only", "--diff-filter=U" })
	if not r.ok then
		return nil, `git diff --name-only --diff-filter=U failed: {sh.trim(r.stderr)}`
	end
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for p in string.gmatch(r.stdout, "[^\n]+") do
		if not seen[p] then
			seen[p] = true
			table.insert(out, p)
		end
	end
	table.sort(out)
	return out, nil
end

-- files under `folders` whose working copy (tracked or untracked, not ignored) holds a whole conflict: "<path>:<line>"
-- nil and why when git grep fails (exit 0 is a hit, exit 1 none, anything else an error)
function conflicts.marked(top: string, folders: { string }): ({ string }?, string?)
	if #folders == 0 then
		return nil, "no folders to check"
	end
	local args =
		{ "-C", top, "grep", "--untracked", "--exclude-standard", "-l", "-I", "-e", "^<<<<<<< ", "--" }
	for _, f in folders do
		table.insert(args, f)
	end
	local r = sh.run("git", args)
	if not r.ok and r.code ~= 1 then
		return nil, `git grep failed: {sh.trim(r.stderr)}`
	end
	local out: { string } = {}
	for p in string.gmatch(r.stdout, "[^\n]+") do
		local path = `{top}/{p}`
		local at = if fs.isFile(path) then conflicts.markerLine(fs.readFile(path)) else nil
		if at then
			table.insert(out, `{p}:{at}`)
		end
	end
	table.sort(out)
	return out, nil
end

-- why `tool` must not run in the checkout at `top`, or nil: unmerged paths first, then whole conflicts in the working
-- tree under the registry's folders; a registry that can't be read refuses too (fail closed)
function conflicts.refusal(top: string, tool: string): string?
	-- outside any git repository nothing can be mid-merge: git saying "not a git repository" is that explicit answer
	-- (migrate runs in such a tree); any other failure of this read refuses below
	local inside = sh.run("git", { "-C", top, "rev-parse", "--is-inside-work-tree" })
	if not inside.ok and string.find(inside.stderr, "not a git repository", 1, true) then
		return nil
	end
	local u, uWhy = conflicts.unmerged(top)
	if not u then
		return `{tool}: refusing to run: can't tell whether files hold merge conflicts: {uWhy}\n{conflicts.RECOVERY}`
	end
	if #u > 0 then
		return `{tool}: refusing to run while the checkout has unmerged paths; resolve them first:\n  {table.concat(
			u,
			"\n  "
		)}\n{conflicts.RECOVERY}`
	end
	local folders, why = conflicts.folders(top)
	if not folders then
		return `{tool}: refusing to run: can't tell whether files hold merge conflicts: {why}`
	end
	local m, mWhy = conflicts.marked(top, folders)
	if not m then
		return `{tool}: refusing to run: can't tell whether files hold merge conflicts: {mWhy}\n{conflicts.RECOVERY}`
	end
	if #m > 0 then
		return `{tool}: refusing to run: these files hold merge-conflict markers; resolve them first:\n  {table.concat(
			m,
			"\n  "
		)}\n{conflicts.RECOVERY}`
	end
	return nil
end

return conflicts
