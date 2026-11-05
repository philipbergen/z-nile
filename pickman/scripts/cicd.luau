--!strict
-- Reserves the CICD places, publishes them, and runs both runtime suites (c0172).
-- Usage: lune run scripts/cicd -- [--config path] [--lease-file path] [status|release]
-- The default config is ~/.config/pickman/cicd.toml and the default token file is beside it.
-- deploy-beta and runtime-test are unchanged: this command runs them with the file's settings,
-- and drops any ROBLOX_* values it inherited. A missing file, a lost lease, a publish failure
-- or a runtime failure exits non-zero. The key is never printed.
local CicdConfig = require("@scripts/lib/cicdconfig")
local Lease = require("@scripts/lib/lease")
local LeaseFile = require("@scripts/lib/leasefile")
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

local function holder(): string
	local host = process.exec("hostname", {})
	local name = if host.ok then trim(host.stdout) else ""
	if name == "" then
		name = "unknown"
	end
	local pid = process.exec("/bin/sh", { "-c", "ps -o pid= -p $PPID" })
	local id = if pid.ok then trim(pid.stdout) else ""
	if id == "" then
		id = "?"
	end
	return `{name}:{id}`
end

local function token(): string
	return serde.hash("sha256", `{holder()}:{os.clock()}:{math.random(0, 2147483646)}`)
end

local args: { string } = {}
for index, arg in process.args do
	if not (index == 1 and arg == "--") then
		table.insert(args, arg)
	end
end

local home = process.env.HOME or ""
local configPath = if home ~= "" then `{home}/.config/pickman/cicd.toml` else ""
local leasePath = if home ~= "" then `{home}/.config/pickman/cicd.lease` else ""
local command = "run"
local index = 1
while index <= #args do
	local arg = args[index]
	if arg == "--config" or arg == "--lease-file" then
		local value = args[index + 1]
		if value == nil then
			print(`usage: lune run scripts/cicd -- [--config path] [--lease-file path] [status|release]`)
			process.exit(2)
		end
		if arg == "--config" then
			configPath = value
		else
			leasePath = value
		end
		index += 2
	elseif arg == "status" or arg == "release" then
		command = arg
		index += 1
	else
		print(`usage: lune run scripts/cicd -- [--config path] [--lease-file path] [status|release]`)
		process.exit(2)
	end
end

if configPath == "" or not fs.isFile(configPath) then
	print(`cicd: config not found: {configPath}`)
	process.exit(1)
end
if leasePath == "" then
	print("cicd: no lease file path")
	process.exit(1)
end

local parsed, parseErr = CicdConfig.parse(fs.readFile(configPath))
if parsed == nil then
	print(parseErr)
	process.exit(1)
end
local config = parsed :: CicdConfig.Config
local base, baseErr = CicdConfig.base(process.env)
if base == nil then
	print(baseErr)
	process.exit(1)
end

local leaseCfg: Lease.Config = {
	apiKey = config.apiKey,
	universeId = config.universeId,
	base = base :: string,
}

local function universe(): (string?, string?)
	local headers: { [string]: string } = { ["x-api-key"] = config.apiKey }
	local res = net.request({
		url = `{leaseCfg.base}/cloud/v2/universes/{config.universeId}`,
		method = "GET" :: any,
		headers = headers,
	})
	if res.statusCode ~= 200 then
		local body = res.body
		if string.find(body, config.apiKey, 1, true) ~= nil then
			body = "<redacted>"
		end
		return nil, `cicd: reading the universe failed with HTTP {res.statusCode}: {body}`
	end
	return CicdConfig.rootPlaceId(res.body)
end

local function runChild(
	script: string,
	childArgs: { string }
): { ok: boolean, stdout: string, stderr: string }
	local argv = { "run", script, "--" }
	for _, childArg in childArgs do
		table.insert(argv, childArg)
	end
	return process.exec("lune", argv, {
		cwd = (string.gsub(process.cwd, "/+$", "")),
		env = CicdConfig.childEnv(process.env, config),
	})
end

local function versions(stdout: string): (string?, string?)
	local game = string.match(stdout, "\nversion=(%d+)") or string.match(stdout, "^version=(%d+)")
	local lobby = string.match(stdout, "\nlobby_version=(%d+)")
		or string.match(stdout, "^lobby_version=(%d+)")
	return game, lobby
end

if command == "status" then
	local line, err = Lease.status(leaseCfg)
	print(if line then line else err)
	process.exit(if line then 0 else 1)
end

if command == "release" then
	local line, err = Lease.release(leaseCfg, LeaseFile.read(leasePath))
	if line == nil then
		print(err)
		process.exit(1)
	end
	if line == "released" or line == "free" then
		LeaseFile.remove(leasePath)
	end
	print(line)
	process.exit(0)
end

local rootId, rootErr = universe()
if rootId == nil then
	print(rootErr)
	process.exit(1)
end
if rootId == config.cicd or rootId == config.cicdGame then
	local which = if rootId == config.cicd then "places.cicd" else "places.cicd_game"
	print(`cicd: {which} is the experience start place`)
	process.exit(1)
end

local mine = token()
local who = holder()
local _version, takeErr = Lease.acquire(leaseCfg, who, mine)
if _version == nil then
	print(takeErr)
	process.exit(1)
end
-- write returns nothing, so pcall would be typed as one value and the error string would be lost
local wrote, writeErr = pcall(function(): string
	LeaseFile.write(leasePath, mine)
	return ""
end)
if not wrote then
	local _, releaseErr = Lease.release(leaseCfg, mine)
	print(writeErr)
	if releaseErr ~= nil then
		print(releaseErr)
	end
	process.exit(1)
end

local function finish(failed: string?)
	local line, releaseErr = Lease.release(leaseCfg, mine)
	if line ~= nil then
		LeaseFile.remove(leasePath)
	end
	if failed ~= nil then
		print(failed)
	end
	if releaseErr ~= nil then
		print(releaseErr)
		process.exit(1)
	end
	process.exit(if failed == nil then 0 else 1)
end

local published = runChild("scripts/deploy-beta", {})
print(published.stdout)
if published.stderr ~= "" then
	print(published.stderr)
end
if not published.ok then
	finish("cicd: the publish failed")
end
local gameVersion, lobbyVersion = versions(published.stdout)
if gameVersion == nil or lobbyVersion == nil then
	finish("cicd: the publish did not name both versions")
end

local function renewOrStop()
	local renewed, renewErr = Lease.renew(leaseCfg, who, mine)
	if renewed == nil then
		finish(renewErr)
	end
end

renewOrStop()
local game = runChild("scripts/runtime-test", { gameVersion :: string })
print(game.stdout)
if game.stderr ~= "" then
	print(game.stderr)
end
if not game.ok then
	finish("cicd: the game runtime suite failed")
end

renewOrStop()
local lobby = runChild("scripts/runtime-test", { "--lobby", lobbyVersion :: string })
print(lobby.stdout)
if lobby.stderr ~= "" then
	print(lobby.stderr)
end
if not lobby.ok then
	finish("cicd: the lobby runtime suite failed")
end

finish(nil)
