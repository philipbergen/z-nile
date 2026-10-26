--!strict
-- c0139: tools that rewrite tracked files refuse to run over a merge conflict. A checkout with unmerged paths (a merge,
-- rebase or cherry-pick stopped on conflicts), or a tracked file under the project roots or the skills folders that
-- holds a whole conflict (a `<<<<<<< ` line, then a `>>>>>>> ` line, each at the start of a line: one committed by
-- mistake), stops the command before it writes anything, naming each path to resolve. Reads only.
local sh = require("../lib/sh")

local conflicts = {}

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

-- the paths git reports as unmerged in the checkout at `top`, sorted and unique
function conflicts.unmerged(top: string): { string }
	local r = sh.run("git", { "-C", top, "diff", "--name-only", "--diff-filter=U" })
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for p in string.gmatch(r.stdout, "[^\n]+") do
		if not seen[p] then
			seen[p] = true
			table.insert(out, p)
		end
	end
	table.sort(out)
	return out
end

-- tracked files under `folders` (repository-relative) whose text holds a whole conflict: "<path>:<line>"
function conflicts.marked(top: string, folders: { string }): { string }
	local args = { "-C", top, "grep", "-l", "-I", "-e", "^<<<<<<< ", "--" }
	for _, f in folders do
		table.insert(args, f)
	end
	local r = sh.run("git", args)
	local out: { string } = {}
	for p in string.gmatch(r.stdout, "[^\n]+") do
		local shown = sh.run("git", { "-C", top, "show", `:{p}` })
		local at = if shown.ok then conflicts.markerLine(shown.stdout) else nil
		if at then
			table.insert(out, `{p}:{at}`)
		end
	end
	table.sort(out)
	return out
end

-- why `tool` must not run in the checkout at `top`, or nil: unmerged paths first, then committed conflicts
function conflicts.refusal(top: string, tool: string, folders: { string }): string?
	local u = conflicts.unmerged(top)
	if #u > 0 then
		return `{tool}: refusing to run while the checkout has unmerged paths; resolve them first:\n  {table.concat(
			u,
			"\n  "
		)}`
	end
	local m = conflicts.marked(top, folders)
	if #m > 0 then
		return `{tool}: refusing to run: these tracked files hold merge-conflict markers; resolve them first:\n  {table.concat(
			m,
			"\n  "
		)}`
	end
	return nil
end

return conflicts
