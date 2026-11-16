--!strict
-- c0210 AC11: until f0209, the start place publishes pickman's lobby as before c0210, with the checked-in manifest and
-- the real projects: after the game, the lobby goes to the start place told GamePlaceId, the output is exactly
-- version and lobby_version, the checked-in lobby project is unchanged, and --place Portal runs the lobby's runtime
-- scripts at the start place. f0209 makes the start place publish the portal; its chore removes this file.
local Experience = require("@scripts/lib/experience")
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = (string.gsub(process.cwd, "/+$", ""))
local KEY = "KEY-NOT-IN-OUTPUT"
local work = `{root}/.cache/c0210-lobby-start`

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

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function luauFiles(dir: string): number
	local n = 0
	for _, name in fs.readDir(dir) do
		if string.match(name, "%.luau$") and fs.isFile(`{dir}/{name}`) then
			n += 1
		end
	end
	return n
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

return t.spec("c0210 pickman's lobby at the start place, until f0209", function(it)
	fs.writeDir(work)

	for _, var in { "ROBLOX_BETA_GAME_PLACE_ID", "ROBLOX_BETA_PICKMAN_PLACE_ID" } do
		it(
			`with {var}: the game then the lobby, told the game's id, to the start place, as before c0210`,
			function()
				local lobbyProject = fs.readFile("../pickman/lobby.project.json")
				local r, seen = deploy(var)
				t.expect(r.ok).toBe(true)
				t.expect(#seen).toBe(2)
				t.expect(seen[1].path).toBe("/universes/v1/111/places/333/versions")
				t.expect(seen[2].path).toBe("/universes/v1/111/places/222/versions")
				local lobby = sss(seen[2].body)
				t.expect(lobby:FindFirstChild("Lobby") ~= nil).toBe(true)
				t.expect(lobby:FindFirstChild("Server")).toBe(nil)
				t.expect(lobby:GetAttribute("GamePlaceId")).toBe(333)
				t.expect(lobby:GetAttribute("LobbyPlaceId")).toBe(nil)
				t.expect(lobby:GetAttribute("PortalPlaceId")).toBe(222)
				t.expect(lobby:GetAttribute("PickmanPlaceId")).toBe(333)
				t.expect(fs.readFile(`{work}/github-output`)).toBe("version=1333\nlobby_version=1222\n")
				t.expect(fs.readFile("../pickman/lobby.project.json")).toBe(lobbyProject)
			end
		)
	end

	it("--place Portal runs pickman's lobby scripts at the start place", function()
		local port, seen, stop = serve()
		local start = process.exec(
			"lune",
			{ "run", "scripts/runtime-test", "--", "--place", "Portal", "7" },
			{ cwd = root, env = env(port, { ROBLOX_BETA_GAME_PLACE_ID = "333" }) }
		)
		stop()
		t.expect(start.ok).toBe(true)
		local lobbyCount = luauFiles("../pickman/tests/runtime/lobby")
		t.expect(has(start.stdout, `{lobbyCount} passed, 0 failed, {lobbyCount} runtime scripts`)).toBe(true)
		t.expect(has(start.stdout, "PASS ../pickman/tests/runtime/lobby/")).toBe(true)
		local toStart = 0
		for _, s in seen do
			if s.method == "POST" and has(s.path, "/places/222/versions/7/luau-execution-session-tasks") then
				toStart += 1
			end
		end
		t.expect(toStart).toBe(lobbyCount)
	end)
end)
