--!strict
-- Builds the place with Rojo and publishes it to the Pickman Beta experience. Configured by the
-- environment (ROBLOX_API_KEY, ROBLOX_BETA_UNIVERSE_ID, ROBLOX_BETA_PLACE_ID); when it isn't configured it
-- says so and succeeds, so a fork or a fresh clone isn't red. Prints `version=N` and, under GitHub
-- Actions, appends it to $GITHUB_OUTPUT.
local OpenCloud = require("@scripts/lib/opencloud")
local fs = require("@lune/fs")
local process = require("@lune/process")
local sh = require("@scripts/lib/sh")

local cfg = OpenCloud.configFromEnv(process.env)
if cfg == nil then
	print(
		"::warning::beta publish is not configured (ROBLOX_API_KEY, ROBLOX_BETA_UNIVERSE_ID, ROBLOX_BETA_PLACE_ID); skipped"
	)
	process.exit(0)
end

assert(cfg, "unreachable: process.exit above ended a missing config")
-- built outside the checkout: rojo writes through a symlink at its output path (R0210 review 006 F1)
local out = sh.must("mktemp", { "-d" }) .. "/beta.rbxl"
local built = process.exec("rojo", { "build", "-o", out })
if not built.ok then
	print(`rojo build failed:\n{built.stderr}{built.stdout}`)
	process.exit(1)
end
local ok, result = pcall(OpenCloud.publish, cfg, fs.readFile(out))
if not ok then
	print(tostring(result))
	process.exit(1)
end
print(`version={result}`)
local github = process.env.GITHUB_OUTPUT
if github and github ~= "" then
	local existing = if fs.isFile(github) then fs.readFile(github) else ""
	fs.writeFile(github, `{existing}version={result}\n`)
end
