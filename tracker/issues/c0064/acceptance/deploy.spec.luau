--!strict
-- c0064 AC3 (end to end): scripts/deploy-beta with two places, against a local fake of Roblox, with the real
-- Rojo on a fixture with a game and a lobby project. What reaches the fake (which place, in which order, and the
-- built place itself), what the command prints and what it appends to $GITHUB_OUTPUT is checked.
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local t = require("@tests/lib/t")

local root = string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
local script = `{root}/scripts/deploy-beta`
local work = `{root}/.cache/c0064-deploy`
local KEY = "KEY-NOT-IN-OUTPUT"
local GAME_PATH = "/universes/v1/111/places/333/versions"
local LOBBY_PATH = "/universes/v1/111/places/222/versions"

type Seen = { path: string, body: string }

-- a fake Roblox: each path answers with its own (status, body); `seen` collects the publishes in order
local function serve(answers: { [string]: { status: number, body: string } }): (number, { Seen }, () -> ())
	local seen: { Seen } = {}
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, handle = pcall(
			net.serve,
			port,
			function(req: any): any
				table.insert(seen, { path = req.path, body = req.body or "" })
				local a = answers[req.path]
				if a == nil then
					return { status = 404, body = "unexpected" }
				end
				return { status = a.status, body = a.body }
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

local BOTH = {
	[GAME_PATH] = { status = 200, body = '{"versionNumber":41}' },
	[LOBBY_PATH] = { status = 200, body = '{"versionNumber":42}' },
}

local function run(dir: string, port: number, game: string?, output: string?)
	return process.exec("lune", { "run", script }, {
		cwd = dir,
		env = {
			ROBLOX_API_KEY = KEY,
			ROBLOX_BETA_UNIVERSE_ID = "111",
			ROBLOX_BETA_PLACE_ID = "222",
			ROBLOX_BETA_GAME_PLACE_ID = game or "",
			OPENCLOUD_BASE = `http://127.0.0.1:{port}`,
			GITHUB_OUTPUT = output or "",
		},
	})
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

-- a fixture checkout: a game project and a lobby project, each with a script folder (relative $paths)
local function fixture(name: string, lobby: string?): string
	local dir = `{work}/{name}`
	fs.writeDir(`{dir}/game`)
	fs.writeDir(`{dir}/lobby`)
	fs.writeFile(`{dir}/game/Main.server.luau`, 'print("game")')
	fs.writeFile(`{dir}/lobby/Main.server.luau`, 'print("lobby")')
	fs.writeFile(
		`{dir}/default.project.json`,
		'{"name":"g","tree":{"$className":"DataModel","ServerScriptService":{"Server":{"$path":"game"}}}}'
	)
	if lobby ~= "" then
		fs.writeFile(
			`{dir}/lobby.project.json`,
			lobby
				or '{"name":"l","tree":{"$className":"DataModel","ServerScriptService":{"$attributes":{"GamePlaceId":0},"Lobby":{"$path":"lobby"}}}}'
		)
	end
	return dir
end

local function listing(dir: string): { string }
	local names = fs.readDir(dir)
	table.sort(names)
	return names
end

local function sss(body: string): any
	t.expect(string.sub(body, 1, 8)).toBe("<roblox!")
	return roblox.deserializePlace(body):GetService("ServerScriptService")
end

return t.spec("c0064 scripts/deploy-beta with two places", function(it)
	fs.writeDir(work)
	local good = fixture("good")
	local out = `{work}/github-output`

	it("publishes the game to its place, then the lobby, told the game's id, to the start place", function()
		fs.writeFile(out, "existing=1\n")
		local before = listing(good)
		local port, seen, stop = serve(BOTH)
		local r = run(good, port, "333", out)
		stop()
		t.expect(r.ok).toBe(true)
		t.expect(#seen).toBe(2)
		t.expect(seen[1].path).toBe(GAME_PATH)
		t.expect(seen[2].path).toBe(LOBBY_PATH)
		local game, lobby = sss(seen[1].body), sss(seen[2].body)
		t.expect(game:FindFirstChild("Server") ~= nil).toBe(true)
		t.expect(game:GetAttribute("GamePlaceId")).toBe(nil)
		t.expect(game:GetAttribute("LobbyPlaceId")).toBe(222) -- the way back (f0065)
		t.expect(lobby:FindFirstChild("Lobby") ~= nil).toBe(true)
		t.expect(lobby:FindFirstChild("Server")).toBe(nil)
		t.expect(lobby:GetAttribute("GamePlaceId")).toBe(333)
		t.expect(has(r.stdout, "version=41")).toBe(true)
		t.expect(has(r.stdout, "lobby_version=42")).toBe(true)
		t.expect(fs.readFile(out)).toBe("existing=1\nversion=41\nlobby_version=42\n")
		t.expect(has(r.stdout .. r.stderr, KEY)).toBe(false)
		t.expect(listing(good)).toEqual(before) -- no project copy or build left in the checkout
		t.expect(fs.readFile(`{good}/lobby.project.json`)).toBe(
			'{"name":"l","tree":{"$className":"DataModel","ServerScriptService":{"$attributes":{"GamePlaceId":0},"Lobby":{"$path":"lobby"}}}}'
		)
	end)

	it(
		"without the game place's id: the game to the start place as before, a warning, and no lobby",
		function()
			fs.writeFile(out, "")
			local port, seen, stop = serve({ [LOBBY_PATH] = { status = 200, body = '{"versionNumber":7}' } })
			local r = run(good, port, nil, out)
			stop()
			t.expect(r.ok).toBe(true)
			t.expect(#seen).toBe(1)
			t.expect(seen[1].path).toBe(LOBBY_PATH) -- the start place
			local legacy = sss(seen[1].body)
			t.expect(legacy:FindFirstChild("Server") ~= nil).toBe(true) -- carrying the game
			t.expect(legacy:GetAttribute("LobbyPlaceId")).toBe(nil) -- no lobby to go back to
			t.expect(has(r.stdout, "::warning::")).toBe(true)
			t.expect(has(r.stdout, "ROBLOX_BETA_GAME_PLACE_ID")).toBe(true)
			t.expect(fs.readFile(out)).toBe("version=7\n")
		end
	)

	it("a lobby that does not build stops everything before anything is published", function()
		local broken = fixture(
			"broken",
			'{"name":"l","tree":{"$className":"DataModel","ServerScriptService":{"Lobby":{"$path":"missing"}}}}'
		)
		fs.writeFile(out, "")
		local port, seen, stop = serve(BOTH)
		local r = run(broken, port, "333", out)
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(#seen).toBe(0)
		t.expect(has(r.stdout, "rojo build failed")).toBe(true)
		t.expect(has(r.stdout, "lobby.project.json")).toBe(true)
		t.expect(fs.readFile(out)).toBe("")
	end)

	it("a missing lobby project stops everything before anything is published", function()
		local nolobby = fixture("nolobby", "")
		local port, seen, stop = serve(BOTH)
		local r = run(nolobby, port, "333")
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(#seen).toBe(0)
		t.expect(has(r.stdout, "lobby.project.json")).toBe(true)
	end)

	it("a refused game publish fails before the lobby is sent, and reports no version", function()
		fs.writeFile(out, "")
		local port, seen, stop = serve({
			[GAME_PATH] = { status = 403, body = "Forbidden for the game place" },
			[LOBBY_PATH] = { status = 200, body = '{"versionNumber":42}' },
		})
		local r = run(good, port, "333", out)
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(#seen).toBe(1)
		t.expect(has(r.stdout, "403")).toBe(true)
		t.expect(fs.readFile(out)).toBe("")
	end)

	it("a refused lobby publish fails, says the game was published, and writes no version", function()
		fs.writeFile(out, "")
		local port, seen, stop = serve({
			[GAME_PATH] = { status = 200, body = '{"versionNumber":41}' },
			[LOBBY_PATH] = { status = 403, body = "Forbidden for the lobby" },
		})
		local r = run(good, port, "333", out)
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(#seen).toBe(2)
		t.expect(has(r.stdout, "Forbidden for the lobby")).toBe(true)
		t.expect(has(r.stdout, "published before the failure: version=41")).toBe(true) -- the human learns the game went out
		t.expect(has(r.stdout, "lobby_version=")).toBe(false)
		t.expect(fs.readFile(out)).toBe("")
	end)

	it("a bad game place id fails before anything is built or sent, naming it, never the key", function()
		for _, bad in { "abc", "0", "222" } do
			local port, seen, stop = serve(BOTH)
			local r = run(good, port, bad)
			stop()
			t.expect(r.ok).toBe(false)
			t.expect(#seen).toBe(0)
			t.expect(has(r.stdout .. r.stderr, "ROBLOX_BETA_GAME_PLACE_ID")).toBe(true)
			t.expect(has(r.stdout .. r.stderr, KEY)).toBe(false)
		end
	end)
end)
