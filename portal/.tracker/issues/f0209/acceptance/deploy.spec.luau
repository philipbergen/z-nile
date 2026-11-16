--!strict
-- f0209 AC2: the Beta deploy, with the checked-in manifest and the real projects, publishes the portal to the start
-- place: two publishes for the variables GitHub has, Pickman's game to its id and then the portal to
-- ROBLOX_BETA_PLACE_ID, never pickman's lobby. The place published at the start place holds the portal's own server
-- (every script of portal/src/server) and no lobby, told Pickman's and its own id and paid play's test mode; Pickman's
-- game is told the start place's id as its way back. Against a local fake of Open Cloud. Runs from portal/.
local Experience = require("@scripts/lib/experience")
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local t = require("@tests/lib/t")

local root = (string.gsub(process.cwd, "/+$", ""))
local KEY = "KEY-NOT-IN-OUTPUT"
local work = `{root}/.cache/f0209-deploy`

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

-- every variable the checked-in manifest names: a child's environment adds to the caller's, so each is given, as ""
-- when the case does not set it, and a variable exported in the shell that runs the specs never reaches the deploy
local function variables(): { string }
	local m = Experience.parse(fs.readFile("experience.json"), root) :: Experience.Manifest
	local out: { string } = {}
	for _, p in m.places do
		for _, var in p.env do
			table.insert(out, var)
		end
	end
	table.sort(out)
	return out
end

local function childEnv(port: number, extra: { [string]: string }): { [string]: string }
	local e: { [string]: string } = {}
	for _, var in variables() do
		e[var] = ""
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

local function deploy(extra: { [string]: string }): (any, { Seen })
	fs.writeFile(`{work}/github-output`, "")
	local port, seen, stop = serve()
	local r = process.exec(
		"lune",
		{ "run", "scripts/deploy-beta" },
		{ cwd = root, env = childEnv(port, extra) }
	)
	stop()
	return r, seen
end

local function place(body: string): any
	t.expect(string.sub(body, 1, 8)).toBe("<roblox!")
	return roblox.deserializePlace(body)
end

-- the names Rojo gives portal/src/server's entries: a folder by its name, a .luau file by its stem (Main.server.luau
-- is the Script "Main"); any other file kind is not read
local function portalServer(): { string }
	local out: { string } = {}
	for _, entry in fs.readDir("src/server") do
		local name = if fs.isDir(`src/server/{entry}`)
			then entry
			else string.match(entry, "^(.-)%.server%.luau$") or string.match(entry, "^(.-)%.luau$")
		if name ~= nil then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- every name of portal/src/server is a child of the published place's ServerScriptService.Server (the rule, not the
-- set: a child Rojo adds from another file kind does not fail it)
local function holdsPortalServer(server: any): string
	if server == nil then
		return "no ServerScriptService.Server"
	end
	local missing: { string } = {}
	for _, name in portalServer() do
		if server:FindFirstChild(name) == nil then
			table.insert(missing, name)
		end
	end
	return if #missing == 0 then "the portal's server" else `missing {table.concat(missing, ", ")}`
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("f0209 the deploy publishes the portal at the start place", function(it)
	fs.writeDir(work)

	for _, var in { "ROBLOX_BETA_GAME_PLACE_ID", "ROBLOX_BETA_PICKMAN_PLACE_ID" } do
		it(
			`with {var}: Pickman's game to its id, then the portal to the start place, and no lobby`,
			function()
				local projects = {
					fs.readFile("default.project.json"),
					fs.readFile("../pickman/default.project.json"),
				}
				local r, seen = deploy({ [var] = "333" })
				t.expect(r.ok).toBe(true)
				t.expect(#seen).toBe(2)
				t.expect(seen[1].path).toBe("/universes/v1/111/places/333/versions")
				t.expect(seen[2].path).toBe("/universes/v1/111/places/222/versions")
				local start = place(seen[2].body)
				local sss = start:GetService("ServerScriptService")
				-- the portal's own server, and nothing of pickman's lobby
				t.expect(sss:FindFirstChild("Lobby")).toBe(nil)
				t.expect(sss:FindFirstChild("Server") ~= nil).toBe(true)
				t.expect(holdsPortalServer(sss:FindFirstChild("Server"))).toBe("the portal's server")
				t.expect(start:GetService("ReplicatedStorage"):FindFirstChild("Arcade") ~= nil).toBe(true)
				-- told where Pickman is and that it is the start place; paid play's test mode
				t.expect(sss:GetAttribute("PickmanPlaceId")).toBe(333)
				t.expect(sss:GetAttribute("PortalPlaceId")).toBe(222)
				t.expect(sss:GetAttribute("PaidPlay")).toBe("test")
				t.expect(sss:GetAttribute("GamePlaceId")).toBe(nil)
				-- Pickman's game: its way back is the start place's id, the portal's
				local game = place(seen[1].body):GetService("ServerScriptService")
				t.expect(game:GetAttribute("PortalPlaceId")).toBe(222)
				local back = game:GetAttribute("LobbyPlaceId")
				t.expect(back == nil or back == 222).toBe(true)
				t.expect(fs.readFile(`{work}/github-output`)).toBe("version=1333\nlobby_version=1222\n")
				t.expect(has(r.stdout .. r.stderr, KEY)).toBe(false)
				t.expect(fs.readFile("default.project.json")).toBe(projects[1])
				t.expect(fs.readFile("../pickman/default.project.json")).toBe(projects[2])
			end
		)
	end

	it(
		"the deploy's environment names every variable of the manifest, empty unless the case sets it",
		function()
			local e = childEnv(1, { ROBLOX_BETA_GAME_PLACE_ID = "333" })
			local vars = variables()
			t.expect(#vars >= 5).toBe(true)
			for _, var in vars do
				local want = if var == "ROBLOX_BETA_GAME_PLACE_ID"
					then "333"
					elseif var == "ROBLOX_BETA_PLACE_ID" then "222"
					else ""
				t.expect(`{var}={e[var]}`).toBe(`{var}={want}`)
			end
		end
	)

	it("with only the start place set, the portal alone is published there, every game's id 0", function()
		local r, seen = deploy({})
		t.expect(r.ok).toBe(true)
		t.expect(#seen).toBe(1)
		t.expect(seen[1].path).toBe("/universes/v1/111/places/222/versions")
		local sss = place(seen[1].body):GetService("ServerScriptService")
		t.expect(holdsPortalServer(sss:FindFirstChild("Server"))).toBe("the portal's server")
		t.expect(sss:FindFirstChild("Lobby")).toBe(nil)
		t.expect(sss:GetAttribute("PickmanPlaceId")).toBe(0)
		t.expect(fs.readFile(`{work}/github-output`)).toBe("lobby_version=1222\n")
	end)
end)
