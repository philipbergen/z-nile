--!strict
-- What the fixture helpers cost a spec file (c0178): files written and processes started. Each helper counts the
-- processes it starts with tally.started and the files it makes with tally.files; the runner flushes each spec file's
-- counts into the run's tally folder and prints the sums beside `slowest:`. A lower bound: the processes a fixture's own
-- commands start (tracker.sh, ./zn and everything they run) are not counted.
local fs = require("@lune/fs")
local process = require("@lune/process")

local tally = {}

local started, written = 0, 0

-- Adds `n` processes started: a helper calls this beside each process it starts itself.
function tally.started(n: number)
	started += n
end

-- Adds `n` files written.
function tally.files(n: number)
	written += n
end

-- The number of regular files under `dir` (links are not followed or counted), by one `find`: not a helper's own
-- process, so not counted as one.
function tally.count(dir: string): number
	local r = process.exec("find", { dir, "-type", "f" })
	if not r.ok then
		return 0
	end
	local n = 0
	for _ in string.gmatch(r.stdout, "[^\n]+") do
		n += 1
	end
	return n
end

-- This process's counts so far, as (files, processes).
function tally.read(): (number, number)
	return written, started
end

-- The folder this run's counts are flushed into: made by tally.begin in the runner that prints them, or handed down to
-- a worker through PICKMAN_TALLY.
local current: string? = nil

local function folder(): string?
	if current then
		return current
	end
	local given = process.env.PICKMAN_TALLY
	if given ~= nil and given ~= "" then
		return given
	end
	return nil
end

-- Starts a tally for this run: a fresh folder in the run's temp folder, which workers are given in PICKMAN_TALLY.
-- Returns it, or nil when there is no run temp folder (nothing is counted then).
function tally.begin(): string?
	local tmp = process.env.TMPDIR
	if tmp == nil or tmp == "" then
		return nil
	end
	local dir =
		`{string.gsub(tmp, "/+$", "")}/tally/{math.random(1, 1e9)}-{string.format("%.0f", os.clock() * 1e6)}`
	fs.writeDir(dir)
	current = dir
	return dir
end

-- Writes this process's counts, if any, as one file of the run's tally, and starts again from zero.
function tally.flush()
	local dir = folder()
	if dir and (written > 0 or started > 0) then
		fs.writeDir(dir)
		fs.writeFile(
			`{dir}/{math.random(1, 1e9)}-{string.format("%.0f", os.clock() * 1e6)}`,
			`{written} {started}\n`
		)
	end
	written, started = 0, 0
end

-- The sums of everything flushed into the run's tally, as (files, processes).
function tally.total(): (number, number)
	local dir = folder()
	local files, procs = 0, 0
	if dir and fs.isDir(dir) then
		for _, name in fs.readDir(dir) do
			local a, b = string.match(fs.readFile(`{dir}/{name}`), "^(%d+) (%d+)")
			files += tonumber(a) or 0
			procs += tonumber(b) or 0
		end
	end
	return files, procs
end

return tally
