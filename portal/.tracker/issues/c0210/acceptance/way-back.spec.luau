--!strict
-- c0210 AC10: until f0187, Pickman's game place is told LobbyPlaceId, the start place's id, as before c0210 (pickman's
-- game over reads it). f0187 switches pickman to PortalPlaceId and deletes the line that writes it; its chore removes
-- this file.
local Experience = require("@scripts/lib/experience")
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = (string.gsub(process.cwd, "/+$", ""))
local KEY = "KEY-NOT-IN-OUTPUT"
local work = `{root}/.cache/c0210-way-back`

type Seen = { method: string, path: string, body: string }

local function serve(): (number, { Seen }, () -> ())
	local seen: { Seen } = {}
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, handle = pcall(
			net.serve,
			port,
			function(req: any): any
				table.insert(seen, { method = req.method, path = req.path, body = req.body or "" })
				local id = string.match(req.path, "^/universes/v1/111/places/(%d+)/versions$")
				if id ~= nil then
					return { status = 200, body = `\{"versionNumber":{tonumber(id) :: number + 1000}\}` }
				end
				if
					req.method == "POST" and string.find(req.path, "luau-execution-session-tasks", 1, true)
				then
					return {
						status = 200,
						body = serde.encode(
							"json" :: "json",
							{ path = `tasks/{#seen}`, state = "PROCESSING" }
						),
					}
				end
				if req.method == "GET" and string.match(req.path, "^/cloud/v2/tasks/%d+$") then
					return {
						status = 200,
						body = serde.encode(
							"json" :: "json",
							{ state = "COMPLETE", output = { results = { "PASS" } } }
						),
					}
				end
				return { status = 404, body = "unexpected" }
			end :: any
		)
		if ok then
			return port, seen, function()
				(handle :: any):stop()
			end
		end
	end
	error("no free port")
end

-- c0210 design review 001 F2: every variable the checked-in manifest names is given, "" unless the case sets it, so a
-- caller's exported ROBLOX_BETA_*_PLACE_ID never reaches the command
local function env(port: number, extra: { [string]: string }): { [string]: string }
	local e: { [string]: string } = {}
	for _, place in (Experience.parse(fs.readFile("experience.json")) :: Experience.Manifest).places do
		for _, var in place.env do
			e[var] = ""
		end
	end
	e.ROBLOX_API_KEY = KEY
	e.ROBLOX_BETA_UNIVERSE_ID = "111"
	e.ROBLOX_BETA_PLACE_ID = "222"
	e.OPENCLOUD_BASE = `http://127.0.0.1:{port}`
	e.GITHUB_OUTPUT = `{work}/github-output`
	for k, v in extra do
		e[k] = v
	end
	return e
end

local function sss(body: string): any
	t.expect(string.sub(body, 1, 8)).toBe("<roblox!")
	return roblox.deserializePlace(body):GetService("ServerScriptService")
end

local function deploy(var: string): (any, { Seen })
	fs.writeFile(`{work}/github-output`, "")
	local port, seen, stop = serve()
	local r = process.exec(
		"lune",
		{ "run", "scripts/deploy-beta" },
		{ cwd = root, env = env(port, { [var] = "333" }) }
	)
	stop()
	return r, seen
end

return t.spec("c0210 Pickman's way back, until f0187", function(it)
	fs.writeDir(work)

	for _, var in { "ROBLOX_BETA_GAME_PLACE_ID", "ROBLOX_BETA_PICKMAN_PLACE_ID" } do
		it(`with {var}: the game is told LobbyPlaceId, the start place's id`, function()
			local r, seen = deploy(var)
			t.expect(r.ok).toBe(true)
			t.expect(seen[1].path).toBe("/universes/v1/111/places/333/versions")
			t.expect(sss(seen[1].body):GetAttribute("LobbyPlaceId")).toBe(222)
		end)
	end
end)
