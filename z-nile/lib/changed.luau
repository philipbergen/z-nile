--!strict
-- Files changed relative to a base ref: what `z-nile/affected` selects specs from.

local process = require("@lune/process")

local changed = {}

local function git(args: { string }, cwd: string?): string
	local r = process.exec("git", args, { cwd = cwd })
	return if r.ok then r.stdout else ""
end

-- Files that differ from the merge-base with `base` (default origin/main when it exists, else main):
-- committed, staged and unstaged changes, plus untracked files. `--no-renames` lists a moved file
-- at both its old and its new path. `cwd` defaults to the process's directory.
function changed.files(base: string?, cwd: string?): { string }
	local ref = base
	if not ref then
		ref = if git({ "rev-parse", "--verify", "-q", "origin/main" }, cwd) ~= ""
			then "origin/main"
			else "main"
	end
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	local function add(text: string)
		for line in string.gmatch(text, "[^\n]+") do
			if not seen[line] then
				seen[line] = true
				table.insert(out, line)
			end
		end
	end
	local mergeBase = string.gsub(git({ "merge-base", "HEAD", ref :: string }, cwd), "%s+$", "")
	if mergeBase ~= "" then
		add(git({ "diff", "--name-only", "--no-renames", mergeBase }, cwd))
	end
	add(git({ "diff", "--name-only", "--no-renames", "HEAD" }, cwd))
	add(git({ "ls-files", "--others", "--exclude-standard" }, cwd))
	return out
end

return changed
