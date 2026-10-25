--!strict
-- Runs each tests/runtime/*.luau in a real Roblox server of a published version, through Open Cloud's
-- Luau Execution API. A script passes when it returns "PASS"; anything else, or an error, fails.
-- Usage: lune run scripts/runtime-test -- [--lobby] <version> [script files...]
-- Without --lobby the scripts (default tests/runtime/*.luau) run in the game place, ROBLOX_BETA_GAME_PLACE_ID once
-- it is set, else ROBLOX_BETA_PLACE_ID; with --lobby (default tests/runtime/lobby/*.luau) in the lobby, the start
-- place (scripts/lib/beta, c0064). Not configured (no key or ids, or --lobby with no lobby): says so and succeeds.
local Beta = require("@scripts/lib/beta")
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

local place: Beta.Place = "game"
if args[1] == "--lobby" then
	place = "lobby"
	table.remove(args, 1)
end
local version = tonumber(args[1])
if version == nil or version ~= math.floor(version) or version < 1 then
	print("usage: lune run scripts/runtime-test -- [--lobby] <version> [script files...]")
	process.exit(2)
end
local okPlan, planned = pcall(Beta.plan, process.env)
if not okPlan then
	print(tostring(planned))
	process.exit(1)
end
if planned == nil then
	print(
		"::warning::runtime tests are not configured (ROBLOX_API_KEY, ROBLOX_BETA_UNIVERSE_ID, ROBLOX_BETA_PLACE_ID); skipped"
	)
	process.exit(0)
end
local target = Beta.target(planned :: Beta.Plan, place)
if target == nil then
	print(`::warning::runtime tests of the {place} place are not configured ({Beta.GAME_PLACE_VAR}); skipped`)
	process.exit(0)
end

assert(version and target, "unreachable: the checks above exit")
local cfg = OpenCloud.configFromEnv(process.env) :: OpenCloud.Config
cfg.placeId = target.placeId
local files: { string } = {}
for i = 2, #args do
	table.insert(files, args[i])
end
if #files == 0 then
	for _, name in fs.readDir(target.runtime) do
		if string.match(name, "%.luau$") and fs.isFile(`{target.runtime}/{name}`) then
			table.insert(files, `{target.runtime}/{name}`)
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
