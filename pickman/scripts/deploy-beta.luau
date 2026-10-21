--!strict
-- Builds the places with Rojo and publishes them to the Pickman Beta experience (c0064: the plan is
-- scripts/lib/beta). Configured by the environment (ROBLOX_API_KEY, ROBLOX_BETA_UNIVERSE_ID, ROBLOX_BETA_PLACE_ID,
-- and ROBLOX_BETA_GAME_PLACE_ID for the game place once the lobby is the start place); when it isn't
-- configured it says so and succeeds, so a fork or a fresh clone isn't red. Every place is built before any
-- is published. Prints `version=N` (the game place) and, with the lobby, `lobby_version=N`, and under GitHub
-- Actions appends them to $GITHUB_OUTPUT, only once every publish succeeded.
local Beta = require("@scripts/lib/beta")
local OpenCloud = require("@scripts/lib/opencloud")
local fs = require("@lune/fs")
local process = require("@lune/process")
local sh = require("@znile/lib/sh")

local okPlan, planned = pcall(Beta.plan, process.env)
if not okPlan then
	print(tostring(planned))
	process.exit(1)
end
if planned == nil then
	print(
		"::warning::beta publish is not configured (ROBLOX_API_KEY, ROBLOX_BETA_UNIVERSE_ID, ROBLOX_BETA_PLACE_ID); skipped"
	)
	process.exit(0)
end
local plan = planned :: Beta.Plan
local cfg = OpenCloud.configFromEnv(process.env) :: OpenCloud.Config
if plan.notice then
	print(`::warning::{plan.notice}`)
end

-- built outside the checkout: rojo writes through a symlink at its output path (R0210 review 006 F1), and the
-- project copies must not be left in the checkout
local tmp = sh.must("mktemp", { "-d" })
-- same trim as Beta.project: Lune's cwd ends in `/`, and `{root}/{file}` would be `//`
local root = process.cwd
if #root > 1 and string.sub(root, -1) == "/" then
	root = string.sub(root, 1, -2)
end
local files: { string } = {}
for _, target in plan.targets do
	local source = `{root}/{target.project}`
	if not fs.isFile(source) then
		print(`rojo build failed ({target.project}): the project file is missing`)
		process.exit(1)
	end
	local okCopy, copy = pcall(Beta.project, fs.readFile(source), root, target.attributes)
	if not okCopy then
		print(`rojo build failed ({target.project}): {copy}`)
		process.exit(1)
	end
	local projectCopy = `{tmp}/{target.place}.project.json`
	fs.writeFile(projectCopy, copy)
	local out = `{tmp}/{target.place}.rbxl`
	local built = process.exec("rojo", { "build", projectCopy, "-o", out })
	if not built.ok then
		print(`rojo build failed ({target.project}):\n{built.stderr}{built.stdout}`)
		process.exit(1)
	end
	table.insert(files, out)
end

local lines: { string } = {}
for i, target in plan.targets do
	local placeCfg = table.clone(cfg)
	placeCfg.placeId = target.placeId
	local ok, result = pcall(OpenCloud.publish, placeCfg, fs.readFile(files[i]))
	if not ok then
		print(tostring(result))
		if #lines > 0 then
			print(`published before the failure: {table.concat(lines, ", ")}`)
		end
		process.exit(1)
	end
	print(`published the {target.place} place ({target.placeId}): version {result}`)
	table.insert(lines, `{target.output}={result}`)
end
for _, line in lines do
	print(line)
end
local github = process.env.GITHUB_OUTPUT
if github and github ~= "" then
	local existing = if fs.isFile(github) then fs.readFile(github) else ""
	fs.writeFile(github, `{existing}{table.concat(lines, "\n")}\n`)
end
