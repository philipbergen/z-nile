--!strict
-- c0154 JC1: slowest first against path order on 8 lanes, both from one recorded run's durations (schedule.makespan).
-- Usage, from the repository root: lune run <this file> -- <record> (a home's .cache/spec-durations.tsv, or a kept copy)
local fs = require("@lune/fs")
local process = require("@lune/process")
local schedule = require("@znile/tests/lib/schedule")
local path: string? = nil
for _, a in process.args do
	if a ~= "--" and path == nil then
		path = a
	end
end
local rec = schedule.parse(fs.readFile(path :: string)) :: schedule.Durations
local files = {}
for p in rec do
	table.insert(files, p)
end
table.sort(files)
local pathOrder = {}
for i in files do
	table.insert(pathOrder, i)
end
local before = schedule.makespan(files, pathOrder, rec, 8)
local after = schedule.makespan(files, schedule.order(files, rec), rec, 8)
print(
	string.format(
		"lines=%d path=%.1f slowest-first=%.1f gain=%.1f%%",
		#files,
		before,
		after,
		(1 - after / before) * 100
	)
)
