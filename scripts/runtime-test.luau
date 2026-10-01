--!strict
-- Runs each tests/runtime/*.luau in a real Roblox server of a published version, through Open Cloud's
-- Luau Execution API. A script passes when it returns "PASS"; anything else, or an error, fails.
-- Usage: lune run scripts/runtime-test -- <version> [script files...]
-- Not configured (no key or ids): says so and succeeds.
local OpenCloud = require("@scripts/lib/opencloud")
local fs = require("@lune/fs")
local process = require("@lune/process")

-- `lune run scripts/runtime-test -- 5` hands the `--` on as the first argument: skip it
local args: { string } = {}
for i, a in process.args do
	if not (i == 1 and a == "--") then
		table.insert(args, a)
	end
end

local version = tonumber(args[1])
if version == nil or version ~= math.floor(version) or version < 1 then
	print("usage: lune run scripts/runtime-test -- <version> [script files...]")
	process.exit(2)
end
local cfg = OpenCloud.configFromEnv(process.env)
if cfg == nil then
	print(
		"::warning::runtime tests are not configured (ROBLOX_API_KEY, ROBLOX_BETA_UNIVERSE_ID, ROBLOX_BETA_PLACE_ID); skipped"
	)
	process.exit(0)
end

assert(cfg and version, "unreachable: the checks above exit")
local files: { string } = {}
for i = 2, #args do
	table.insert(files, args[i])
end
if #files == 0 then
	for _, name in fs.readDir("tests/runtime") do
		if string.match(name, "%.luau$") then
			table.insert(files, `tests/runtime/{name}`)
		end
	end
	table.sort(files)
end

local scripts: { OpenCloud.Script } = {}
for _, file in files do
	table.insert(scripts, { name = file, source = fs.readFile(file) })
end
local suite = OpenCloud.runSuite(cfg, version, scripts)
for _, line in suite.lines do
	print(line)
end
print(`{suite.passed} passed, {suite.failed} failed, {#scripts} runtime scripts`)
process.exit(if suite.failed == 0 then 0 else 1)
