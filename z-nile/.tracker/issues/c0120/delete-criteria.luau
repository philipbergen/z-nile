--!strict
-- c0120, Guess 17 (decided with the user, 2026-10-21: "delete them"): removes the finished criteria in
-- rewrites.DELETED from their check.sh files, in a commit of its own after the finished rewrite's. Run once from the
-- repository root, after rewrite-finished.luau:
--   lune run z-nile/.tracker/issues/c0120/delete-criteria.luau
-- A file whose criteria are already gone is left as it is, so a second run changes nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")
local rewrites = require("./acceptance/rewrites")

local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local changed = 0
local files: { string } = {}
for file in rewrites.DELETED do
	table.insert(files, file)
end
table.sort(files)
for _, file in files do
	local text = fs.readFile(`{top}/{file}`)
	local new = rewrites.deleteCriteria(text, rewrites.DELETED[file])
	if new and new ~= text then
		fs.writeFile(`{top}/{file}`, new)
		changed += 1
		print(`{file}: {table.concat(rewrites.DELETED[file], ", ")} deleted`)
	end
end
print(`delete-criteria: {changed} of {#files} files changed`)
