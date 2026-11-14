--!strict
-- The measured slow tier: z-nile/tests/slow.tsv, a committed membership list. The same line
-- grammar as the durations hint (schedule.luau), but the seconds are only there so the line
-- parses. Membership is the set. The hint (<home>/.cache/spec-durations.tsv) is the live
-- packing order and is safe to delete; this file is not a cache. Ordinary collection and
-- `--exclude-slow` leave these files out. `--slow` runs only them. An explicitly named spec
-- with neither flag still runs.
local fs = require("@lune/fs")
local schedule = require("./schedule")

local slow = {}

-- `which` "fast" drops members, "slow" keeps only members.
function slow.keep(files: { string }, tiers: schedule.Durations, which: "fast" | "slow"): { string }
	local out: { string } = {}
	local wantSlow = which == "slow"
	for _, f in files do
		if (tiers[f] ~= nil) == wantSlow then
			table.insert(out, f)
		end
	end
	return out
end

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
