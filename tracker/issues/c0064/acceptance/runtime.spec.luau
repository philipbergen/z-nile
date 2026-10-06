--!strict
-- c0064 AC4: the runtime tests per place. The lobby's runtime scripts (tests/runtime/lobby) pass in the lobby
-- the deploy builds and fail in any other place, run here headlessly against the built places; and
-- scripts/runtime-test runs the game's scripts in the game place and, with --lobby, the lobby's in the start
-- place, against a local fake of Roblox's Luau Execution API.
local Beta = require("@scripts/lib/beta")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
local script = `{root}/scripts/runtime-test`
local work = `{root}/.cache/c0064-runtime`
local KEY = "KEY-NOT-IN-OUTPUT"

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function lobbyScripts(): { string }
	local out = {}
	for _, name in fs.readDir("tests/runtime/lobby") do
		if string.match(name, "%.luau$") then
			table.insert(out, `tests/runtime/lobby/{name}`)
		end
	end
	table.sort(out)
	return out
end

local function build(project: string): any
	local out = `{work}/{math.random(1, 1e9)}.rbxl`
	local r = process.exec("rojo", { "build", project, "-o", out })
	assert(r.ok, `rojo build {project} failed: {r.stderr}{r.stdout}`)
	local game = roblox.deserializePlace(fs.readFile(out))
	fs.removeFile(out)
	return game
end

-- runs a runtime script as Roblox would, with `game` the given place; returns (ok, result or error)
local function runIn(file: string, game: any): (boolean, any)
	local fn = luau.load(fs.readFile(file), { debugName = file, environment = { game = game } })
	return pcall(fn)
end

type Call = { method: string, place: string?, version: string?, script: string? }

-- a fake Luau Execution API for universe 111, any place and version: a task "passes" when its script has
-- PASS-ME in it
local function serve(): (number, { Call }, () -> ())
	local calls: { Call } = {}
	local scripts: { [string]: string } = {}
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, handle = pcall(
			net.serve,
			port,
			function(req: any): any
				local place, version = string.match(
					req.path,
					"^/cloud/v2/universes/111/places/(%d+)/versions/(%d+)/luau%-execution%-session%-tasks$"
				)
				if req.method == "POST" and place then
					local source = (serde.decode("json" :: "json", req.body) :: any).script
					table.insert(
						calls,
						{ method = "POST", place = place, version = version, script = source }
					)
					local n = tostring(#calls)
					scripts[n] = source
					return { status = 200, body = serde.encode("json" :: "json", { path = `tasks/{n}` }) }
				end
				local n = string.match(req.path, "^/cloud/v2/tasks/(%d+)$")
				if req.method == "GET" and n then
					table.insert(calls, { method = "GET" })
					local value = if has(scripts[n] or "", "PASS-ME") then "PASS" else "nope"
					return {
						status = 200,
						body = serde.encode(
							"json" :: "json",
							{ path = `tasks/{n}`, state = "COMPLETE", output = { results = { value } } }
						),
					}
				end
				return { status = 404, body = "unexpected" }
			end :: any
		)
		if ok then
			return port, calls, function()
				(handle :: any):stop()
			end
		end
	end
	error("no free port")
end

local function posts(calls: { Call }): { Call }
	local out = {}
	for _, c in calls do
		if c.method == "POST" then
			table.insert(out, c)
		end
	end
	return out
end

local function run(port: number, args: { string }, game: string?)
	local argv = { "run", script, "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("lune", argv, {
		cwd = root,
		env = {
			ROBLOX_API_KEY = KEY,
			ROBLOX_BETA_UNIVERSE_ID = "111",
			ROBLOX_BETA_PLACE_ID = "222",
			ROBLOX_BETA_GAME_PLACE_ID = game or "",
			OPENCLOUD_BASE = `http://127.0.0.1:{port}`,
		},
	})
end

return t.spec("c0064 runtime tests per place", function(it)
	fs.writeDir(work)
	fs.writeFile(`{work}/good.luau`, 'return "PASS-ME"')
	fs.writeFile(
		`{work}/lobby.project.json`,
		Beta.project(fs.readFile(`{root}/lobby.project.json`), root, { GamePlaceId = 4815162342 })
	)
	local published = build(`{work}/lobby.project.json`)
	local unset = build(`{root}/lobby.project.json`)
	local gamePlace = build(`{root}/default.project.json`)

	it(
		"there is a lobby structure check, and every lobby script is strict, requires nothing and returns PASS",
		function()
			local files = lobbyScripts()
			t.expect(table.find(files, "tests/runtime/lobby/structure.luau") ~= nil).toBe(true)
			for _, file in files do
				local text = fs.readFile(file)
				t.expect(string.find(text, "^%-%-!strict") ~= nil).toBe(true)
				t.expect(string.find(text, "require%(") == nil).toBe(true)
				t.expect(string.find(text, 'return "PASS"%s*$') ~= nil).toBe(true)
			end
		end
	)

	it("every lobby script passes in the lobby the deploy builds", function()
		for _, file in lobbyScripts() do
			local ok, result = runIn(file, published)
			t.expect(ok).toBe(true)
			t.expect(result).toBe("PASS")
		end
	end)

	it("the lobby structure check fails in a lobby whose GamePlaceId was never set", function()
		local ok, err = runIn("tests/runtime/lobby/structure.luau", unset)
		t.expect(ok).toBe(false)
		t.expect(has(tostring(err), "GamePlaceId")).toBe(true)
	end)

	it("the lobby structure check fails in the game place, and the game's fails in the lobby", function()
		t.expect((runIn("tests/runtime/lobby/structure.luau", gamePlace))).toBe(false)
		t.expect((runIn("tests/runtime/structure.luau", published))).toBe(false)
		local ok, result = runIn("tests/runtime/structure.luau", gamePlace)
		t.expect(ok).toBe(true)
		t.expect(result).toBe("PASS")
	end)

	it("the lobby structure check fails when a lobby remote or script is missing", function()
		local noStatus = build(`{work}/lobby.project.json`)
		noStatus:GetService("ReplicatedStorage").Remotes.Status.Parent = nil
		t.expect((runIn("tests/runtime/lobby/structure.luau", noStatus))).toBe(false)
		local noMain = build(`{work}/lobby.project.json`)
		noMain:GetService("ServerScriptService").Lobby.Main.Parent = nil
		t.expect((runIn("tests/runtime/lobby/structure.luau", noMain))).toBe(false)
	end)

	it("the lobby structure check fails when the game's server scripts are in the lobby", function()
		local withServer = build(`{work}/lobby.project.json`)
		local folder = roblox.Instance.new("Folder")
		folder.Name = "Server"
		folder.Parent = withServer:GetService("ServerScriptService")
		t.expect((runIn("tests/runtime/lobby/structure.luau", withServer))).toBe(false)
	end)

	it("the lobby structure check fails when GamePlaceId is not a whole place id", function()
		for _, bad in { 1.5, -3 } do
			local odd = build(`{work}/lobby.project.json`)
			odd:GetService("ServerScriptService"):SetAttribute("GamePlaceId", bad)
			t.expect((runIn("tests/runtime/lobby/structure.luau", odd))).toBe(false)
		end
	end)

	it("the lobby structure check fails when characters load in the lobby", function()
		local characters = build(`{work}/lobby.project.json`)
		characters:GetService("Players").CharacterAutoLoads = true
		t.expect((runIn("tests/runtime/lobby/structure.luau", characters))).toBe(false)
	end)

	it("the lobby structure check fails without the StartGame remote", function()
		local noStart = build(`{work}/lobby.project.json`)
		noStart:GetService("ReplicatedStorage").Remotes.StartGame.Parent = nil
		t.expect((runIn("tests/runtime/lobby/structure.luau", noStart))).toBe(false)
	end)

	it(
		"with two places: the game's scripts run in the game place, by default all of tests/runtime",
		function()
			local port, calls, stop = serve()
			local r = run(port, { "5" }, "333")
			stop()
			local sent = posts(calls)
			t.expect(#sent >= 1).toBe(true)
			for _, c in sent do
				t.expect(c.place).toBe("333")
				t.expect(c.version).toBe("5")
			end
			t.expect(has(r.stdout, "tests/runtime/structure.luau")).toBe(true)
			t.expect(has(r.stdout, "tests/runtime/lobby/")).toBe(false)
			t.expect(has(r.stdout .. r.stderr, KEY)).toBe(false)
		end
	)

	it(
		"with --lobby: the lobby's scripts run in the start place, by default all of tests/runtime/lobby",
		function()
			local port, calls, stop = serve()
			local r = run(port, { "--lobby", "7" }, "333")
			stop()
			local sent = posts(calls)
			t.expect(#sent).toBe(#lobbyScripts())
			local sources = {}
			for _, file in lobbyScripts() do
				sources[fs.readFile(file)] = true
			end
			for _, c in sent do
				t.expect(c.place).toBe("222")
				t.expect(c.version).toBe("7")
				t.expect(sources[c.script or ""]).toBe(true) -- the lobby's scripts, not the game's
			end
			t.expect(has(r.stdout, "tests/runtime/lobby/structure.luau")).toBe(true)
			t.expect(has(r.stdout, "FAIL tests/runtime/structure.luau")).toBe(false)
		end
	)

	it("with --lobby and given files: those run in the start place, and pass", function()
		local port, calls, stop = serve()
		local r = run(port, { "--lobby", "7", `{work}/good.luau` }, "333")
		stop()
		t.expect(r.ok).toBe(true)
		t.expect(posts(calls)[1].place).toBe("222")
		t.expect(has(r.stdout, "1 passed, 0 failed")).toBe(true)
	end)

	it("without the game place's id: the game's scripts run in the start place, as before", function()
		local port, calls, stop = serve()
		local r = run(port, { "5", `{work}/good.luau` })
		stop()
		t.expect(r.ok).toBe(true)
		t.expect(posts(calls)[1].place).toBe("222")
	end)

	it(
		"without the game place's id, --lobby has no lobby to test: a warning, success, nothing sent",
		function()
			local port, calls, stop = serve()
			local r = run(port, { "--lobby", "7" })
			stop()
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "::warning::")).toBe(true)
			t.expect(#calls).toBe(0)
		end
	)

	it("--lobby needs a version: usage and exit 2", function()
		for _, args in { { "--lobby" }, { "--lobby", "abc" }, { "--lobby", "0" }, { "--lobby", "1.5" } } do
			local r = run(1, args, "333")
			t.expect(r.code).toBe(2)
			t.expect(has(r.stdout, "usage")).toBe(true)
		end
	end)

	it("a bad game place id fails before anything is sent, naming it", function()
		local port, calls, stop = serve()
		local r = run(port, { "5", `{work}/good.luau` }, "abc")
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(#calls).toBe(0)
		t.expect(has(r.stdout .. r.stderr, "ROBLOX_BETA_GAME_PLACE_ID")).toBe(true)
		t.expect(has(r.stdout .. r.stderr, KEY)).toBe(false)
	end)
end)
