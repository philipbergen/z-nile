--!strict
-- The measured slow tier. Ordinary collection excludes these files; an explicitly named spec still runs.
local fs = require("@lune/fs")
local schedule = require("./schedule")

local slow = {}

function slow.load(root: string): schedule.Durations
	local path = `{root}/z-nile/tests/slow.tsv`
	local ok, text = pcall(fs.readFile, path)
	if not ok then
		return {}
	end
	local durations = schedule.parse(text :: string)
	if durations == nil then
		error(`invalid slow-tier manifest: {path}`)
	end
	return durations :: schedule.Durations
end

return slow
