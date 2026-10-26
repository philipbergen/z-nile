--!strict
-- The spec runner's schedule (c0154): which spec file a free lane takes next. Pure: the runner reads the recorded
-- durations and passes them in.
-- Order: files with no recorded duration first (a new spec may be slow), then the recorded ones slowest first (the
-- longest-processing-time rule: a long file started late no longer holds the gate open at the end), ties by path.
local schedule = {}

export type Durations = { [string]: number }

-- `files` in the order lanes take them (a permutation of `files`, which is not changed)
function schedule.order(files: { string }, durations: Durations): { string }
	local out = table.clone(files)
	table.sort(out, function(a: string, b: string): boolean
		local da, db = durations[a], durations[b]
		if (da == nil) ~= (db == nil) then
			return da == nil
		end
		if da ~= nil and db ~= nil and da ~= db then
			return da > db
		end
		return a < b
	end)
	return out
end

-- the recorded durations: one "<seconds>\t<path>" line each; nil for a file that isn't that (the runner then runs in
-- path order, as before c0154)
function schedule.parse(text: string): Durations?
	local out: Durations = {}
	for line in string.gmatch(text, "[^\n]+") do
		local secs, path = string.match(line, "^([%d%.]+)\t(%S+)$")
		local n = tonumber(secs)
		if n == nil or path == nil then
			return nil
		end
		out[path :: string] = n
	end
	return out
end

-- `old` with every file of `runs` replaced by its new duration, as text (sorted by path, so it diffs well)
function schedule.render(old: Durations, runs: Durations): string
	local merged = table.clone(old)
	for path, secs in runs do
		merged[path] = secs
	end
	local paths = {}
	for path in merged do
		table.insert(paths, path)
	end
	table.sort(paths)
	local lines = {}
	for _, path in paths do
		table.insert(lines, string.format("%.2f\t%s", merged[path], path))
	end
	return table.concat(lines, "\n") .. "\n"
end

-- the wall time `lanes` lanes take over `durations` in `files` order (each free lane takes the next file)
function schedule.makespan(files: { string }, durations: Durations, lanes: number): number
	local free: { number } = table.create(lanes, 0)
	for _, f in files do
		local best = 1
		for i = 2, lanes do
			if free[i] < free[best] then
				best = i
			end
		end
		free[best] += durations[f] or 0
	end
	local most = 0
	for _, t in free do
		most = math.max(most, t)
	end
	return most
end

return schedule
