--!strict
-- The spec runner's schedule (c0154): which spec file a free lane takes next. Pure: the runner reads the recorded
-- durations and passes them in.
-- Order: files with no recorded duration first (a new spec may be slow), then the recorded ones slowest first (the
-- longest-processing-time rule: a long file started late no longer holds the gate open at the end), ties by path.
local schedule = {}

export type Durations = { [string]: number }

-- the positions of `files` in the order lanes take them (a permutation of 1..#files; `files` is not changed). Positions,
-- not names: a file listed twice runs twice and keeps both outcomes (c0154 design review 001 F1)
function schedule.order(files: { string }, durations: Durations): { number }
	local out: { number } = {}
	for i in files do
		table.insert(out, i)
	end
	table.sort(out, function(i: number, j: number): boolean
		local a, b = files[i], files[j]
		local da, db = durations[a], durations[b]
		if (da == nil) ~= (db == nil) then
			return da == nil
		end
		if da ~= nil and db ~= nil and da ~= db then
			return da > db
		end
		if a ~= b then
			return a < b
		end
		return i < j
	end)
	return out
end

-- the recorded durations: one "<seconds>\t<path>" line each; nil for a file that isn't that, or is empty (the runner
-- then runs in path order, as before c0154)
function schedule.parse(text: string): Durations?
	if text == "" then
		return nil
	end
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

-- `old` with every file of `runs` replaced by its new duration, as text (sorted by path, so it diffs well); when
-- `keep` is given (a full run: every spec file of the home), a recorded file not in it is dropped (renamed or deleted)
function schedule.render(old: Durations, runs: Durations, keep: { [string]: boolean }?): string
	local merged: Durations = {}
	for path, secs in old do
		if keep == nil or keep[path] then
			merged[path] = secs
		end
	end
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

-- the wall time `lanes` lanes take over `durations` with files taken in `order` (positions into `files`; each free
-- lane takes the next)
function schedule.makespan(files: { string }, order: { number }, durations: Durations, lanes: number): number
	local free: { number } = table.create(lanes, 0)
	for _, i in order do
		local best = 1
		for l = 2, lanes do
			if free[l] < free[best] then
				best = l
			end
		end
		free[best] += durations[files[i]] or 0
	end
	local most = 0
	for _, t in free do
		most = math.max(most, t)
	end
	return most
end

return schedule
