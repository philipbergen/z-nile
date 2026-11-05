--!strict
-- Spec runner. Usage, from a project's home (c0120: every other home's `tests/run.luau`, `pickman/tests/run.luau`, is this
-- runner, run there), which is then the folder specs run in and whose .cache holds their fixtures:
--   lune run tests/run            -- every tests/**/*.spec.luau under the current folder
--   lune run tests/run -- a b     -- only the listed spec files (paths relative to the current folder)
--   --jobs N / PICKMAN_JOBS=N     -- run spec files in N concurrent workers (default min(max(cpus, 2), 8);
--                                    1 or a single file runs in-process). --jobs wins over the environment.
-- Lanes take the files with no recorded duration first, then the recorded ones slowest first (c0154), from
-- .cache/spec-durations.tsv in the home, which every concurrent run updates; the report stays in path order.
-- Exits non-zero if any case fails or any spec fails to load.

local fs = require("@lune/fs")
local process = require("@lune/process")
local schedule = require("./lib/schedule")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

type Spec = { name: string, cases: { { name: string, fn: () -> () } } }

-- Where this file is (z-nile/tests/run.luau), and so the repository root, two folders above its own: every project's
-- home requires it from its own tests/run.luau, and specs are loaded relative to this file, so a spec path relative to
-- the current folder needs the current folder's place under the root in front of it ("pickman/", "z-nile/").
local fenceLib = require("./lib/fence")
-- normalized: `lune run ../z-nile/tests/run` from a home keeps the `..` in debug.info (code review 004 F6)
local RUNNER_DIR = string.match(fenceLib.normalize(debug.info(1, "s")), "^(.*)/[^/]+$") or "."
local ROOT = string.match(RUNNER_DIR, "^(.*)/[^/]+/[^/]+$") or "."
local HERE = (string.gsub(process.cwd, "/+$", ""))
-- specs run from a project's home, a folder of the registry at the top of the repository (c0120: the root belongs to
-- no project; code review 004 F6: any other top-level folder refuses too)
local HOME = if string.sub(HERE, 1, #ROOT + 1) == ROOT .. "/" then string.sub(HERE, #ROOT + 2) else nil
local known = fenceLib.homes()
if
	HOME == nil
	or HOME == ""
	or (
		if known
			then not table.find(known, HOME :: string)
			else string.find(HOME :: string, "/", 1, true) ~= nil
	)
then
	stdio.ewrite(
		"tests/run: "
			.. HERE
			.. " is no project's home (z-nile/projects.toml): run specs from a project's folder (pickman/, z-nile/), as cd pickman && lune run tests/run\n"
	)
	process.exit(2)
end
local HOME_PREFIX = (HOME :: string) .. "/"

local function collect(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(name, "%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

-- List mode (AC_LIST) makes check.sh only list its checks, so a spec run at the top of a check.sh
-- must not run either: refuse before collecting anything.
local listMode = process.env.AC_LIST
if listMode ~= nil and listMode ~= "" then
	print("AC_LIST is set: specs are not run in list mode (unset it to run them)")
	process.exit(1)
end

-- Guard the repository this runs in (the fence module, fence.luau in tests' lib folder): lock, fence and ref guard,
-- tripwire. This call stays alone on its line: c0660's check removes exactly that line to run specs unguarded.
require("./lib/fence").enter()

-- Browser guard: no spec may start a real browser (`tracker.sh board` opens one unless given -O). The outermost runner
-- puts recording `open` and `xdg-open` stubs first on PATH and runs itself again as a child with that PATH (Lune can't
-- change its own environment for children). Workers and nested runners see PICKMAN_OPEN_GUARD and run normally, so
-- every opener call in the whole run lands in one log; a non-empty log fails the run. A spec that tests opening
-- puts its own stubs before these.
local guard = process.env.PICKMAN_OPEN_GUARD
-- nested only when the marker names a live guard (its `open` stub exists): a stale or stray value can't switch it off
if guard == nil or guard == "" or not fs.isFile(`{guard}/open`) then
	-- under $TMPDIR explicitly: macOS mktemp -d ignores TMPDIR without a template
	local base = string.gsub(process.env.TMPDIR or "", "/+$", "")
	local made =
		process.exec("mktemp", { "-d", `{if base == "" then "/tmp" else base}/pickman-guard.XXXXXX` })
	if not made.ok then
		stdio.ewrite(`tests/run: mktemp failed: {made.stderr}\n`)
		process.exit(1)
	end
	local dir = (string.gsub(made.stdout, "%s+$", ""))
	for _, name in { "open", "xdg-open" } do
		fs.writeFile(`{dir}/{name}`, `#!/bin/sh\necho "{name} $*" >> "{dir}/opened.log"\n`)
		process.exec("chmod", { "+x", `{dir}/{name}` })
	end
	local args = { "run", "tests/run", "--" }
	for _, a in process.args do
		if a ~= "--" then
			table.insert(args, a)
		end
	end
	local ok, r = pcall(function()
		return process.exec("lune", args, {
			env = { PATH = `{dir}:{process.env.PATH or ""}`, PICKMAN_OPEN_GUARD = dir },
			stdio = { stdout = "forward", stderr = "forward" },
		})
	end)
	if not ok then
		fs.removeDir(dir)
		stdio.ewrite(`tests/run: could not re-run itself with the browser guard (is lune on PATH?): {r}\n`)
		process.exit(1)
	end
	local log = if fs.isFile(`{dir}/opened.log`) then fs.readFile(`{dir}/opened.log`) else ""
	fs.removeDir(dir)
	if log ~= "" then
		print(`FAIL a spec started a browser (tracker.sh board without -O, or an unstubbed opener):\n{log}`)
		process.exit(1)
	end
	process.exit(r.code)
end

local USAGE = "usage: lune run tests/run [--jobs N] [spec files]"

local function usageError(name: string)
	stdio.ewrite(`{USAGE}\nbad value for {name}\n`)
	process.exit(2)
end

local function parseJobs(value: string?, name: string): number?
	if value == nil then
		return nil
	end
	if not string.match(value, "^%d+$") or (tonumber(value) :: number) < 1 then
		usageError(name)
	end
	return tonumber(value)
end

local function cpuCount(): number
	local r = if process.os == "macos"
		then process.exec("sysctl", { "-n", "hw.ncpu" })
		else process.exec("nproc")
	return if r.ok then tonumber((string.gsub(r.stdout, "%s+", ""))) or 4 else 4
end

local files: { string } = {}
local flagJobs: number? = nil
do
	local args = process.args
	local i = 1
	while i <= #args do
		local arg = args[i]
		if arg == "--jobs" then
			i += 1
			if args[i] == nil then
				usageError("--jobs")
			end
			flagJobs = parseJobs(args[i], "--jobs")
		elseif arg ~= "--" then
			-- accept absolute paths inside the repo (check.sh passes them)
			if string.sub(arg, 1, #process.cwd) == process.cwd then
				arg = string.sub(arg, #process.cwd + 1)
			end
			table.insert(files, arg)
		end
		i += 1
	end
end
local jobs: number
if flagJobs ~= nil then
	jobs = flagJobs
else
	local env = process.env.PICKMAN_JOBS
	if env == "" then
		env = nil
	end
	jobs = parseJobs(env, "PICKMAN_JOBS") or math.min(math.max(cpuCount(), 2), 8)
end
local fullRun = #files == 0
if fullRun then
	collect("tests", files)
end
table.sort(files)

type Outcome = { file: string, seconds: number, code: number, stdout: string, stderr: string }

-- c0165: with PICKMAN_RESULTS set, this run records every file's cases and results (the orchestrator specs.luau reads
-- them; a run without the variable is exactly as before). A path outside this home's .cache is never written.
type FileResult = {
	file: string,
	loaded: boolean,
	cases: { { name: string, ok: boolean } },
	detail: string,
	seconds: number,
}
local function resultsPath(): string?
	local p = process.env.PICKMAN_RESULTS
	if p == nil or p == "" then
		return nil
	end
	local prefix = HERE .. "/.cache/"
	if string.sub(p, 1, #prefix) ~= prefix or string.find(p, "..", 1, true) then
		return nil
	end
	return p
end
local function writeResults(path: string, list: { FileResult })
	pcall(function()
		local tmp = `{path}.{math.random(1, 1e9)}.tmp`
		fs.writeFile(
			tmp,
			serde.encode("json" :: "json", { jail = process.env.PICKMAN_TEST_JAIL or "", files = list })
		)
		fs.move(tmp, path, true)
	end)
end

-- the recorded durations of this home's spec files (c0154); an unreadable record is no record (path order)
local DURATIONS = ".cache/spec-durations.tsv"
local function recorded(): schedule.Durations
	local ok, text = pcall(fs.readFile, DURATIONS)
	return (if ok then schedule.parse(text :: string) else nil) or {}
end

-- Coordinator: `jobs` lanes pull the next file in schedule order and run it as a one-file, one-job runner process.
local function runConcurrently()
	local outcomes: { Outcome } = {}
	local resultsFile = resultsPath()
	local queue = schedule.order(files, recorded())
	local nextIndex, running = 1, math.min(jobs, #files)
	for _ = 1, math.min(jobs, #files) do
		task.spawn(function()
			while nextIndex <= #queue do
				local index = queue[nextIndex]
				nextIndex += 1
				local file = files[index]
				local started = os.clock()
				local part = if resultsFile then `{resultsFile}.{index}` else nil
				local ok, r = pcall(
					process.exec,
					"lune",
					{ "run", "tests/run", "--", "--jobs", "1", file },
					if part then { env = { PICKMAN_RESULTS = part } } else nil
				)
				outcomes[index] = {
					file = file,
					seconds = os.clock() - started,
					code = if ok then r.code else -1,
					stdout = if ok then r.stdout else "",
					stderr = if ok then r.stderr else tostring(r),
				}
			end
			running -= 1
		end)
	end
	while running > 0 do
		task.wait(0.005)
	end

	-- record this run's durations, merged over what an earlier run recorded; written to a temporary file and renamed
	-- over the record, so a concurrent reader sees the old record or the new one, never a truncated one (design review
	-- 001 F5); not written when the run had none of the home's files. A failure to write costs only the order.
	do
		local runs: schedule.Durations = {}
		local any = false
		for _, o in outcomes do
			-- the home's own spec files only: a spec's nested run of a fixture's files (under .cache) is not this home's
			if string.sub(o.file, 1, 6) == "tests/" then
				runs[o.file] = o.seconds
				any = true
			end
		end
		if any then
			-- a full run (no files named) knows every spec file of the home: lines for files gone since are dropped
			local keep: { [string]: boolean }? = nil
			if fullRun then
				local k: { [string]: boolean } = {}
				for _, f in files do
					k[f] = true
				end
				keep = k
			end
			pcall(function()
				fs.writeDir(".cache")
				local tmp = `{DURATIONS}.{math.random(1, 1e9)}{string.format("%.0f", os.clock() * 1e6)}.tmp`
				fs.writeFile(tmp, schedule.render(recorded(), runs, keep))
				fs.move(tmp, DURATIONS, true)
			end)
		end
	end

	-- the workers' part files, merged in file order and removed; a worker that died left none: its file is not loaded
	if resultsFile then
		local merged: { FileResult } = {}
		for index, o in outcomes do
			local part = `{resultsFile}.{index}`
			local got: FileResult? = nil
			local readOk, text = pcall(fs.readFile, part)
			if readOk then
				local decOk, doc = pcall(serde.decode, "json" :: "json", text :: string)
				if decOk and type(doc) == "table" and type((doc :: any).files) == "table" then
					got = (doc :: any).files[1]
				end
				pcall(fs.removeFile, part)
			end
			table.insert(merged, got or {
				file = o.file,
				loaded = false,
				cases = {},
				detail = `FAIL {o.file}: worker exited with code {o.code}`,
				seconds = o.seconds,
			})
		end
		writeResults(resultsFile, merged)
	end

	-- merge in sorted file order, never in finish order
	local passed, failed = 0, 0
	for _, o in outcomes do
		local lines = {}
		for line in string.gmatch(o.stdout, "[^\n]+") do
			table.insert(lines, line)
		end
		local last = lines[#lines]
		local p, f = string.match(last or "", "^(%d+) passed, (%d+) failed, 1 spec files$")
		if p ~= nil and f ~= nil and not (o.code ~= 0 and tonumber(f) == 0) then
			passed += tonumber(p) :: number
			failed += tonumber(f) :: number
			table.remove(lines)
			if #lines > 0 then
				print(table.concat(lines, "\n"))
			end
		else
			failed += 1
			local all = {}
			for line in string.gmatch(o.stdout .. o.stderr, "[^\n]+") do
				table.insert(all, line)
			end
			local tail = table.concat(all, "\n", math.max(1, #all - 24), #all)
			print(`FAIL {o.file}: worker exited with code {o.code}` .. if tail ~= "" then `\n{tail}` else "")
			o.stderr = ""
		end
		if o.stderr ~= "" then
			stdio.ewrite(o.stderr)
		end
	end

	local bySpeed = table.clone(outcomes)
	table.sort(bySpeed, function(a, b)
		return a.seconds > b.seconds
	end)
	local slowest = {}
	for i = 1, math.min(3, #bySpeed) do
		table.insert(slowest, string.format("%s %.1fs", bySpeed[i].file, bySpeed[i].seconds))
	end
	print(`slowest: {table.concat(slowest, ", ")}`)
	print(`{passed} passed, {failed} failed, {#files} spec files`)
	process.exit(if failed == 0 then 0 else 1)
end

if jobs > 1 and #files >= 2 then
	runConcurrently()
end

local passed, failed = 0, 0
local results: { FileResult } = {}
for _, file in files do
	-- require paths are relative to this file (z-nile/tests/run.luau); a spec path is relative to the folder the run
	-- started in (a project's home, c0120)
	local started = os.clock()
	local modPath = "../../" .. HOME_PREFIX .. string.gsub(file, "%.luau$", "")
	local ok, spec = pcall(require, modPath)
	if not ok or type(spec) ~= "table" or type((spec :: any).cases) ~= "table" then
		failed += 1
		local line = `FAIL {file}: could not load spec: {spec}`
		print(line)
		table.insert(
			results,
			{ file = file, loaded = false, cases = {}, detail = line, seconds = os.clock() - started }
		)
		continue
	end
	local record: FileResult = { file = file, loaded = true, cases = {}, detail = "", seconds = 0 }
	for _, case in (spec :: Spec).cases do
		local err: any = nil
		local cOk = xpcall(case.fn, function(e: any)
			err = e
		end)
		table.insert(record.cases, { name = case.name, ok = cOk })
		if cOk then
			passed += 1
		else
			failed += 1
			local line = `FAIL {file} :: {case.name}\n     {err}`
			print(line)
			record.detail ..= (if record.detail == "" then "" else "\n") .. line
		end
	end
	record.seconds = os.clock() - started
	table.insert(results, record)
end
local resultsFile = resultsPath()
if resultsFile then
	writeResults(resultsFile, results)
end

print(`{passed} passed, {failed} failed, {#files} spec files`)
process.exit(if failed == 0 then 0 else 1)
-- a project home requires this file as its own runner (pickman/tests/run.luau, c0120); a module returns one value
return nil
