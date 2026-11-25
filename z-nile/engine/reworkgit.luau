--!strict
-- f0449: the one read rework counting makes beyond history.read. history.read dates an arrival in done/ from `git log -p`,
-- which shows a merge commit no diff, so an item that reached done/ inside a raft's merge has no day there. The first-parent
-- line shows that merge (`-m`), and the day of the first commit on it that adds the item's done document is its done day.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./projects")
local rework = require("./rework")

local reworkgit = {}

-- The day `id` first arrived in done/ on `dir`'s first-parent line, or nil when it never did (or git cannot say).
function reworkgit.doneDay(dir: string, id: string): string?
	local ok, reg = pcall(projects.load, dir)
	if not ok then
		return nil
	end
	local args = { "log", "-m", "--first-parent", "--no-renames", "--diff-filter=A", "--reverse", "--format=%cI", "--" }
	for _, root in projects.allRoots(reg :: projects.Registry) do
		table.insert(args, `:(glob){root}/issues/done/{id}/{id}.md`)
		table.insert(args, `:(glob){root}/rafts/done/{id}/{id}.md`)
	end
	if not fs.isDir(dir) then
		return nil
	end
	local r = process.exec("git", args, { cwd = dir })
	return if r.ok then rework.firstDay(r.stdout) else nil
end

return reworkgit
