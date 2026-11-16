--!strict
-- c0210 AC3 (end to end): scripts/deploy-beta over a fixture experience (a manifest and five tiny projects under
-- .cache/c0210-deploy), against a local fake of Roblox, with the real Rojo. What reaches the fake (which places, in
-- which order, and each built place), what the command prints and what it appends to $GITHUB_OUTPUT is checked.
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local t = require("@tests/lib/t")

local root = (string.gsub(process.cwd, "/+$", ""))
local script = `{root}/scripts/deploy-beta`
local work = `{root}/.cache/c0210-deploy`
local KEY = "KEY-NOT-IN-OUTPUT"

local function path(id: string): string
	return `/universes/v1/111/places/{id}/versions`
end

type Seen = { path: string, body: string }

-- a fake Roblox: a publish to place <id> answers version <id> + 1000 unless `refuse` names the id
local function serve(refuse: string?): (number, { Seen }, () -> ())
	local seen: { Seen } = {}
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, handle = pcall(
			net.serve,
			port,
			function(req: any): any
				table.insert(seen, { path = req.path, body = req.body or "" })
				local id = string.match(req.path, "^/universes/v1/111/places/(%d+)/versions$")
				if id == nil then
					return { status = 404, body = "unexpected" }
				end
				if id == refuse then
					return { status = 403, body = `Forbidden for {id}` }
				end
				return { status = 200, body = `\{"versionNumber":{tonumber(id) :: number + 1000}\}` }
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

local MANIFEST = [[
{
  "places": [
    { "name": "Pickman", "env": ["ROBLOX_BETA_PICKMAN_PLACE_ID", "ROBLOX_BETA_GAME_PLACE_ID"], "build": "pickman", "output": "version" },
    { "name": "Snake", "env": ["ROBLOX_BETA_SNAKE_PLACE_ID"], "build": "snake", "output": "snake_version" },
    { "name": "Invaders", "env": ["ROBLOX_BETA_INVADERS_PLACE_ID"], "build": "invaders", "output": "invaders_version" },
    { "name": "Asteroids", "env": ["ROBLOX_BETA_ASTEROIDS_PLACE_ID"], "build": "asteroids", "output": "asteroids_version" },
    { "name": "Portal", "env": ["ROBLOX_BETA_PLACE_ID"], "build": "start", "output": "lobby_version" }
  ],
  "builds": {
    "pickman": { "project": "../homes/pickman/default.project.json", "attributes": { "LobbyPlaceId": "Portal" } },
    "snake": { "project": "../homes/snake/default.project.json" },
    "invaders": { "project": "../homes/invaders/default.project.json" },
    "asteroids": { "project": "../homes/asteroids/BROKEN.project.json" },
    "start": { "project": "default.project.json", "attributes": { "GamePlaceId": "Pickman" } }
  }
}
]]

local function project(dir: string, folder: string, attributes: string?)
	fs.writeDir(`{dir}/{folder}`)
	fs.writeFile(`{dir}/{folder}/Main.server.luau`, `print("{folder}")`)
	local attrs = if attributes then `"$attributes":{attributes},` else ""
	fs.writeFile(
		`{dir}/default.project.json`,
		`\{"name":"{folder}","tree":\{"$className":"DataModel","ServerScriptService":\{{attrs}"{folder}":\{"$path":"{folder}"\}\}\}\}`
	)
end

-- the fixture: <work>/<name>/start (the manifest and the start place's project, the folder the command runs in) and
-- <work>/<name>/homes/<game> (each game's project, reached by "../"); Asteroids' project does not build
local function fixture(name: string, manifest: string?): string
	local base = `{work}/{name}`
	local start = `{base}/start`
	project(start, "Start", '{"GamePlaceId":0}')
	project(`{base}/homes/pickman`, "Pickman", '{"LobbyPlaceId":0}')
	project(`{base}/homes/snake`, "Snake")
	project(`{base}/homes/invaders`, "Invaders")
	fs.writeDir(`{base}/homes/asteroids`)
	fs.writeFile(
		`{base}/homes/asteroids/BROKEN.project.json`,
		'{"name":"a","tree":{"$className":"DataModel","X":{"$path":"missing"}}}'
	)
	if manifest ~= "" then
		fs.writeFile(`{start}/experience.json`, manifest or MANIFEST)
	end
	return start
end

local function run(dir: string, port: number, extra: { [string]: string }, output: string?)
	local env: { [string]: string } = {
		ROBLOX_API_KEY = KEY,
		ROBLOX_BETA_UNIVERSE_ID = "111",
		ROBLOX_BETA_PLACE_ID = "222",
		OPENCLOUD_BASE = `http://127.0.0.1:{port}`,
		GITHUB_OUTPUT = output or "",
	}
	for k, v in extra do
		env[k] = v
	end
	return process.exec("lune", { "run", script }, { cwd = dir, env = env })
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function sss(body: string): any
	t.expect(string.sub(body, 1, 8)).toBe("<roblox!")
	return roblox.deserializePlace(body):GetService("ServerScriptService")
end

local function listing(dir: string): { string }
	local names = fs.readDir(dir)
	table.sort(names)
	return names
end

return t.spec("c0210 scripts/deploy-beta over the experience's manifest", function(it)
	fs.writeDir(work)
	local good = fixture("good")
	local out = `{work}/github-output`

	it(
		"publishes every place whose variable is set, the games first and the start place last, each told every id",
		function()
			fs.writeFile(out, "existing=1\n")
			local before = listing(good)
			local port, seen, stop = serve()
			local r = run(
				good,
				port,
				{ ROBLOX_BETA_SNAKE_PLACE_ID = "444", ROBLOX_BETA_PICKMAN_PLACE_ID = "333" },
				out
			)
			stop()
			t.expect(r.ok).toBe(true)
			t.expect(#seen).toBe(3)
			t.expect(seen[1].path).toBe(path("333"))
			t.expect(seen[2].path).toBe(path("444"))
			t.expect(seen[3].path).toBe(path("222"))
			local pickman, snake, start = sss(seen[1].body), sss(seen[2].body), sss(seen[3].body)
			t.expect(pickman:FindFirstChild("Pickman") ~= nil).toBe(true)
			t.expect(snake:FindFirstChild("Snake") ~= nil).toBe(true)
			t.expect(start:FindFirstChild("Start") ~= nil).toBe(true)
			for _, place in { pickman, snake, start } do
				t.expect(place:GetAttribute("PortalPlaceId")).toBe(222)
				t.expect(place:GetAttribute("PickmanPlaceId")).toBe(333)
				t.expect(place:GetAttribute("SnakePlaceId")).toBe(444)
				t.expect(place:GetAttribute("InvadersPlaceId")).toBe(0)
				t.expect(place:GetAttribute("AsteroidsPlaceId")).toBe(0)
				t.expect(place:GetAttribute("PaidPlay")).toBe("test")
				t.expect(place:GetAttribute("PlayProductId")).toBe(0)
				t.expect(place:GetAttribute("SnakeReviveProductId")).toBe(0)
			end
			t.expect(pickman:GetAttribute("LobbyPlaceId")).toBe(222)
			t.expect(start:GetAttribute("GamePlaceId")).toBe(333)
			t.expect(snake:GetAttribute("GamePlaceId")).toBe(nil)
			t.expect(has(r.stdout, "the Invaders place is not published: set ROBLOX_BETA_INVADERS_PLACE_ID"))
				.toBe(true)
			t.expect(has(r.stdout, "published the Snake place (444): version 1444")).toBe(true)
			t.expect(fs.readFile(out))
				.toBe("existing=1\nversion=1333\nsnake_version=1444\nlobby_version=1222\n")
			t.expect(has(r.stdout .. r.stderr, KEY)).toBe(false)
			t.expect(listing(good)).toEqual(before) -- no project copy or build left beside the manifest
			t.expect(fs.readFile(`{good}/default.project.json`)).toBe(
				'{"name":"Start","tree":{"$className":"DataModel","ServerScriptService":{"$attributes":{"GamePlaceId":0},"Start":{"$path":"Start"}}}}'
			)
		end
	)

	it(
		"a place not published is not built: an Asteroids project that cannot build stops nothing while unset",
		function()
			local port, seen, stop = serve()
			local r = run(good, port, {})
			stop()
			t.expect(r.ok).toBe(true)
			t.expect(#seen).toBe(1)
			t.expect(seen[1].path).toBe(path("222"))
		end
	)

	it("one place that does not build stops every publish, naming its project", function()
		local port, seen, stop = serve()
		local r = run(
			good,
			port,
			{ ROBLOX_BETA_PICKMAN_PLACE_ID = "333", ROBLOX_BETA_ASTEROIDS_PLACE_ID = "666" },
			out
		)
		stop()
		fs.writeFile(out, "")
		t.expect(r.ok).toBe(false)
		t.expect(#seen).toBe(0)
		t.expect(has(r.stdout, "rojo build failed")).toBe(true)
		t.expect(has(r.stdout, "BROKEN.project.json")).toBe(true)
	end)

	it("a refused publish stops the rest, says which went out, and writes no version", function()
		fs.writeFile(out, "")
		local port, seen, stop = serve("444")
		local r =
			run(good, port, { ROBLOX_BETA_SNAKE_PLACE_ID = "444", ROBLOX_BETA_PICKMAN_PLACE_ID = "333" }, out)
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(#seen).toBe(2) -- the start place is not sent
		t.expect(has(r.stdout, "Forbidden for 444")).toBe(true)
		t.expect(has(r.stdout, "published before the failure: version=1333")).toBe(true)
		t.expect(has(r.stdout, "lobby_version=")).toBe(false)
		t.expect(fs.readFile(out)).toBe("")
	end)

	it("bad ids stop it before anything is built or sent, naming the variable, never the key", function()
		local bad: { { [string]: string } } = {
			{ ROBLOX_BETA_SNAKE_PLACE_ID = "12a" },
			{ ROBLOX_BETA_SNAKE_PLACE_ID = "333", ROBLOX_BETA_PICKMAN_PLACE_ID = "333" },
			{ ROBLOX_BETA_GAME_PLACE_ID = "333", ROBLOX_BETA_PICKMAN_PLACE_ID = "334" },
		}
		for _, extra in bad do
			local port, seen, stop = serve()
			local r = run(good, port, extra)
			stop()
			t.expect(r.ok).toBe(false)
			t.expect(#seen).toBe(0)
			t.expect(has(r.stdout .. r.stderr, "ROBLOX_BETA_")).toBe(true)
			t.expect(has(r.stdout .. r.stderr, KEY)).toBe(false)
		end
	end)

	it("a missing manifest fails, and a broken one fails naming the rule, before anything is sent", function()
		local none = fixture("none", "")
		local port, seen, stop = serve()
		local r = run(none, port, {})
		local broken = fixture("broken", (string.gsub(MANIFEST, '"Snake"', '"Pong"', 1)))
		local b = run(broken, port, {})
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "experience.json")).toBe(true)
		t.expect(b.ok).toBe(false)
		t.expect(has(b.stdout, "experience.json: place 2: name must be one of Places.NAMES")).toBe(true)
		t.expect(#seen).toBe(0)
	end)

	it("not configured: a warning and success, with no manifest needed", function()
		local none = fixture("unconfigured", "")
		local r = process.exec("lune", { "run", script }, {
			cwd = none,
			env = { ROBLOX_API_KEY = "", ROBLOX_BETA_UNIVERSE_ID = "111", ROBLOX_BETA_PLACE_ID = "222" },
		})
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "::warning::")).toBe(true)
		t.expect(has(r.stdout, "not configured")).toBe(true)
	end)
end)
