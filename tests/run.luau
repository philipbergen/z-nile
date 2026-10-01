--!strict
-- Spec runner. Usage:
--   lune run tests/run            -- every tests/**/*.spec.luau
--   lune run tests/run -- a b     -- only the listed spec files (repo-relative paths)
--   --jobs N / PICKMAN_JOBS=N     -- run spec files in N concurrent workers (default min(max(cpus, 2), 8);
--                                    1 or a single file runs in-process). --jobs wins over the environment.
-- Exits non-zero if any case fails or any spec fails to load.

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

type Spec = { name: string, cases: { { name: string, fn: () -> () } } }

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
if #files == 0 then
	collect("tests", files)
end
table.sort(files)

type Outcome = { file: string, seconds: number, code: number, stdout: string, stderr: string }

-- Coordinator: `jobs` lanes pull the next file and run it as a one-file, one-job runner process.
local function runConcurrently()
	local outcomes: { Outcome } = {}
	local nextIndex, running = 1, jobs
	for _ = 1, jobs do
		task.spawn(function()
			while nextIndex <= #files do
				local index = nextIndex
				nextIndex += 1
				local file = files[index]
				local started = os.clock()
				local r = process.exec("lune", { "run", "tests/run", "--", "--jobs", "1", file })
				outcomes[index] = {
					file = file,
					seconds = os.clock() - started,
					code = r.code,
					stdout = r.stdout,
					stderr = r.stderr,
				}
			end
			running -= 1
		end)
	end
	while running > 0 do
		task.wait(0.005)
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
for _, file in files do
	-- require paths are relative to this file (tests/run.luau)
	local modPath = "../" .. string.gsub(file, "%.luau$", "")
	local ok, spec = pcall(require, modPath)
	if not ok or type(spec) ~= "table" or type((spec :: any).cases) ~= "table" then
		failed += 1
		print(`FAIL {file}: could not load spec: {spec}`)
		continue
	end
	for _, case in (spec :: Spec).cases do
		local err: any = nil
		local cOk = xpcall(case.fn, function(e: any)
			err = e
		end)
		if cOk then
			passed += 1
		else
			failed += 1
			print(`FAIL {file} :: {case.name}\n     {err}`)
		end
	end
end

print(`{passed} passed, {failed} failed, {#files} spec files`)
process.exit(if failed == 0 then 0 else 1)
