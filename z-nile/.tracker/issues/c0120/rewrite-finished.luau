--!strict
-- c0120, Implementation step 10: rewrites every finished item's check.sh (decided with the user, 2026-10-21: "Rewrite
-- them too") with acceptance/rewrites.luau, in the edits commit, never the renames-only one. Run once from the
-- repository root, after the moves are committed:
--   lune run z-nile/.tracker/issues/c0120/rewrite-finished.luau
-- It writes only finished check.sh files, prints each one it changed and a count, and changes nothing when run again.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local rewrites = require("./acceptance/rewrites")

local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local pre, why = rewrites.premove(top)
if not pre then
	error(`rewrite-finished: {why}`)
end
local world = rewrites.world(top, pre)
local reg = projects.load(top, true)

local changed, read = 0, 0
for _, root in projects.roots(reg) do
	for _, kind in { "issues", "rafts" } do
		local dir = `{top}/{root}/{kind}/done`
		if fs.isDir(dir) then
			for _, id in fs.readDir(dir) do
				local file = `{root}/{kind}/done/{id}/check.sh`
				if string.match(id, "^[fdcR]%d%d%d%d$") and fs.isFile(`{top}/{file}`) then
					read += 1
					local text = fs.readFile(`{top}/{file}`)
					local new = rewrites.rewrite(text, projects.homeOf(reg, file), world)
					if new ~= text then
						fs.writeFile(`{top}/{file}`, new)
						changed += 1
						print(file)
					end
				end
			end
		end
	end
end
print(
	`rewrite-finished: {changed} of {read} finished check.sh files rewritten (the tree before the move: {pre})`
)
