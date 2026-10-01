--!strict
-- Spec runner. Usage:
--   lune run tests/run            -- every tests/**/*.spec.luau
--   lune run tests/run -- a b     -- only the listed spec files (repo-relative paths)
-- Exits non-zero if any case fails or any spec fails to load.

local fs = require("@lune/fs")
local process = require("@lune/process")

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

local files: { string } = {}
for _, arg in process.args do
	if arg ~= "--" then
		-- accept absolute paths inside the repo (check.sh passes them)
		if string.sub(arg, 1, #process.cwd) == process.cwd then
			arg = string.sub(arg, #process.cwd + 1)
		end
		table.insert(files, arg)
	end
end
if #files == 0 then
	collect("tests", files)
end
table.sort(files)

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
