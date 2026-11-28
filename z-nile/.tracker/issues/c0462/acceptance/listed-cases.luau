--!strict
-- c0462 AC8 helper: `lune run listed-cases.luau <rewrite-list.txt> <home> <results.json>` exits 1 and names every
-- `file :: case` of the list for <home> that the run's PICKMAN_RESULTS file does not hold as passed.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local listPath, home, resultsPath = process.args[1], process.args[2], process.args[3]
if listPath == nil or home == nil or resultsPath == nil then
	print("usage: listed-cases <list> <home> <results.json>")
	process.exit(2)
end
local doc: any = serde.decode("json" :: "json", fs.readFile(resultsPath))
local passed: { [string]: boolean } = {}
for _, f in doc.files do
	for _, c in f.cases do
		passed[`{f.file} :: {c.name}`] = c.ok
	end
end
local wanted, missing = 0, 0
for line in string.gmatch(fs.readFile(listPath), "[^\n]+") do
	local h, rest = string.match(line, "^([%w%-]+): (.+)$")
	if h == home and string.sub(line, 1, 1) ~= "#" then
		wanted += 1
		if passed[rest :: string] ~= true then
			missing += 1
			print(`not run, renamed, deleted or failing: {home}: {rest}`)
		end
	end
end
if wanted == 0 then
	print(`the list names no case for {home}`)
	process.exit(1)
end
process.exit(if missing == 0 then 0 else 1)
