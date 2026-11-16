--!strict
-- c0210 AC4: Pickman's game place, published as before c0210, with the checked-in manifest and the real projects:
-- with either of its variables, the game goes first to its own id, built from pickman's project and told no GamePlaceId,
-- its version is `version`, every place's id is beside it, and --place Pickman runs its runtime scripts there. No
-- later item ends these pins (f0209 changes the start place, f0187 the way back: their own files).
local Experience = require("@scripts/lib/experience")
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = (string.gsub(process.cwd, "/+$", ""))
local KEY = "KEY-NOT-IN-OUTPUT"
local work = `{root}/.cache/c0210-pickman`

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

return t.spec("c0210 Pickman's game place, as before", function(it)
	fs.writeDir(work)

	for _, var in { "ROBLOX_BETA_GAME_PLACE_ID", "ROBLOX_BETA_PICKMAN_PLACE_ID" } do
		it(`with {var}: the game first, to its id, from pickman's project, its version as version`, function()
			local project = fs.readFile("../pickman/default.project.json")
			local r, seen = deploy(var)
			t.expect(r.ok).toBe(true)
			t.expect(#seen >= 1).toBe(true)
			t.expect(seen[1].path).toBe("/universes/v1/111/places/333/versions")
			local game = sss(seen[1].body)
			t.expect(game:FindFirstChild("Server") ~= nil).toBe(true)
			t.expect(game:GetAttribute("GamePlaceId")).toBe(nil)
			t.expect(game:GetAttribute("PortalPlaceId")).toBe(222)
			t.expect(game:GetAttribute("PickmanPlaceId")).toBe(333)
			t.expect(game:GetAttribute("SnakePlaceId")).toBe(0)
			t.expect(has(fs.readFile(`{work}/github-output`), "version=1333\n")).toBe(true)
			t.expect(has(r.stdout .. r.stderr, KEY)).toBe(false)
			t.expect(fs.readFile("../pickman/default.project.json")).toBe(project)
		end)
	end

	it("--place Pickman runs pickman's game scripts at its id", function()
		local port, seen, stop = serve()
		local game = process.exec(
			"lune",
			{ "run", "scripts/runtime-test", "--", "--place", "Pickman", "8" },
			{ cwd = root, env = env(port, { ROBLOX_BETA_GAME_PLACE_ID = "333" }) }
		)
		stop()
		t.expect(game.ok).toBe(true)
		local gameCount = luauFiles("../pickman/tests/runtime")
		t.expect(has(game.stdout, `{gameCount} passed, 0 failed, {gameCount} runtime scripts`)).toBe(true)
		local toGame = 0
		for _, s in seen do
			if s.method == "POST" and has(s.path, "/places/333/versions/8/luau-execution-session-tasks") then
				toGame += 1
			end
		end
		t.expect(toGame).toBe(gameCount)
	end)
end)
