--!strict
-- f0209 AC3: the start place's runtime tests are the portal's. portal/tests/runtime holds a structure check that, run
-- as Roblox runs it (headlessly here, against the places the deploy builds), passes in the portal published at the start
-- place and fails in a portal the publish told nothing, in pickman's lobby and in pickman's game; and
-- `runtime-test --place Portal` (what the merge's cicd runs for the start place) runs exactly those scripts at the
-- start place's id. Runs from portal/.
local Beta = require("@scripts/lib/beta")
local Experience = require("@scripts/lib/experience")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = (string.gsub(process.cwd, "/+$", ""))
local work = `{root}/.cache/f0209-runtime`
local STRUCTURE = "tests/runtime/structure.luau"

local ENV: { [string]: string? } = {
	ROBLOX_API_KEY = "KEY",
	ROBLOX_BETA_UNIVERSE_ID = "111",
	ROBLOX_BETA_PLACE_ID = "222",
	ROBLOX_BETA_GAME_PLACE_ID = "333",
}

local function scripts(): { string }
	local out: { string } = {}
	for _, name in fs.readDir("tests/runtime") do
		if string.match(name, "%.luau$") and fs.isFile(`tests/runtime/{name}`) then
			table.insert(out, `tests/runtime/{name}`)
		end
	end
	table.sort(out)
	return out
end

-- a project of the manifest built as the deploy builds it (Beta.project's copy, with the given attributes)
local function build(key: string, project: string, attributes: { [string]: Beta.Value }?): any
	local source = `{root}/{project}`
	local dir = string.match(source, "^(.*)/[^/]+$") :: string
	local text = fs.readFile(source)
	local copy = `{work}/{key}.project.json`
	fs.writeFile(
		copy,
		if attributes then Beta.project(text, dir, attributes) else Beta.project(text, dir, {})
	)
	local out = `{work}/{key}.rbxl`
	local r = process.exec("rojo", { "build", copy, "-o", out })
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

type Call = { place: string, version: string, script: string }

-- a fake Luau Execution API for universe 111: every task completes, answering PASS
local function serve(): (number, { Call }, () -> ())
	local calls: { Call } = {}
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
					table.insert(calls, { place = place, version = version :: string, script = source })
					return {
						status = 200,
						body = serde.encode(
							"json" :: "json",
							{ path = `tasks/{#calls}`, state = "PROCESSING" }
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
			return port, calls, function()
				(handle :: any):stop()
			end
		end
	end
	error("no free port")
end

return t.spec("f0209 the start place's runtime tests are the portal's", function(it)
	fs.writeDir(work)
	local manifest = Experience.parse(fs.readFile("experience.json"), root) :: Experience.Manifest
	local plan = Beta.plan(ENV, manifest) :: Beta.Plan
	local start = Beta.target(plan, "Portal") :: Beta.Target
	local game = Beta.target(plan, "Pickman") :: Beta.Target
	local published = build("portal", start.project, start.attributes)
	local untold = build("portal-untold", "default.project.json", nil)
	-- pickman's lobby, while it exists (c0188 deletes it)
	local LOBBY = "../pickman/lobby.project.json"
	local lobby = if fs.isFile(LOBBY) then build("lobby", LOBBY, start.attributes) else nil
	local pickman = build("pickman", game.project, game.attributes)

	it("there is a structure check, and every script is strict, requires nothing and returns PASS", function()
		local files = scripts()
		t.expect(table.find(files, STRUCTURE) ~= nil).toBe(true)
		for _, file in files do
			local text = fs.readFile(file)
			t.expect(`{file}: {string.find(text, "^%-%-!strict") ~= nil}`).toBe(`{file}: true`)
			t.expect(`{file}: {string.find(text, "require%(") == nil}`).toBe(`{file}: true`)
			t.expect(`{file}: {string.find(text, 'return "PASS"%s*$') ~= nil}`).toBe(`{file}: true`)
		end
	end)

	it("every script passes in the portal the deploy publishes at the start place", function()
		for _, file in scripts() do
			local ok, result = runIn(file, published)
			t.expect(`{file}: {ok} {tostring(result)}`).toBe(`{file}: true PASS`)
		end
	end)

	it(
		"the structure check fails, naming what is missing, for each thing the publish or the project gives the start place",
		function()
			local sss = published:GetService("ServerScriptService")
			local rs = published:GetService("ReplicatedStorage")
			local players = published:GetService("Players")
			-- each change returns the undo that puts the published place back as it was
			local function attribute(name: string, value: any): () -> () -> ()
				return function()
					local was = sss:GetAttribute(name)
					sss:SetAttribute(name, value)
					return function()
						sss:SetAttribute(name, was)
					end
				end
			end
			local function unparent(parent: any, name: string): () -> () -> ()
				return function()
					local child = parent:FindFirstChild(name)
					assert(child, `the published place has no {name} to take away`)
					child.Parent = nil
					return function()
						child.Parent = parent
					end
				end
			end
			local function add(parent: any, class: string, name: string): () -> () -> ()
				return function()
					local extra = roblox.Instance.new(class)
					extra.Name = name
					extra.Parent = parent
					return function()
						extra.Parent = nil
					end
				end
			end
			local CHANGES: { { label: string, needle: string, change: () -> () -> () } } = {
				{
					label = "PortalPlaceId unset",
					needle = "PortalPlaceId",
					change = attribute("PortalPlaceId", nil),
				},
				{
					label = "PortalPlaceId 0",
					needle = "PortalPlaceId",
					change = attribute("PortalPlaceId", 0),
				},
				{
					label = "PortalPlaceId 1.5",
					needle = "PortalPlaceId",
					change = attribute("PortalPlaceId", 1.5),
				},
				{
					label = "PickmanPlaceId 0",
					needle = "PickmanPlaceId",
					change = attribute("PickmanPlaceId", 0),
				},
				{ label = "PaidPlay unset", needle = "PaidPlay", change = attribute("PaidPlay", nil) },
				{
					label = "CharacterAutoLoads true",
					needle = "CharacterAutoLoads",
					change = function()
						players.CharacterAutoLoads = true
						return function()
							players.CharacterAutoLoads = false
						end
					end,
				},
				{
					label = "no ReplicatedStorage.Arcade",
					needle = "ReplicatedStorage.Arcade",
					change = unparent(rs, "Arcade"),
				},
				{
					label = "no ServerStorage.Arcade",
					needle = "ServerStorage.Arcade",
					change = unparent(published:GetService("ServerStorage"), "Arcade"),
				},
				{
					label = "no ServerScriptService.Server",
					needle = "ServerScriptService.Server",
					change = unparent(sss, "Server"),
				},
				{
					label = "no ReplicatedStorage.Remotes",
					needle = "ReplicatedStorage.Remotes",
					change = unparent(rs, "Remotes"),
				},
				{
					label = "a Lobby beside the portal's server",
					needle = "ServerScriptService.Lobby",
					change = add(sss, "Folder", "Lobby"),
				},
				{
					label = "pickman's Snapshot among the remotes",
					needle = "Remotes.Snapshot",
					change = add(rs:FindFirstChild("Remotes"), "RemoteEvent", "Snapshot"),
				},
			}
			for _, row in CHANGES do
				local undo = row.change()
				local ok, err = runIn(STRUCTURE, published)
				undo()
				local named = string.find(tostring(err), row.needle, 1, true) ~= nil
				t.expect(`{row.label}: {ok} {named}`).toBe(`{row.label}: false true`)
			end
			-- every change was undone: the published place passes again
			local ok, result = runIn(STRUCTURE, published)
			t.expect(`{ok} {tostring(result)}`).toBe("true PASS")
		end
	)

	it("the structure check fails in a portal the publish told nothing, naming Pickman's id", function()
		local ok, err = runIn(STRUCTURE, untold)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "PickmanPlaceId", 1, true) ~= nil).toBe(true)
	end)

	it(
		"the structure check fails in pickman's lobby and in pickman's game, as the deploy builds them",
		function()
			if lobby ~= nil then
				t.expect((runIn(STRUCTURE, lobby))).toBe(false)
			end
			t.expect((runIn(STRUCTURE, pickman))).toBe(false)
		end
	)

	it(
		"runtime-test --place Portal runs exactly the portal's runtime scripts at the start place's id",
		function()
			local port, calls, stop = serve()
			-- every variable of the manifest given, "" unless ENV sets it, so the caller's shell never reaches the run
			local env: { [string]: string } = { OPENCLOUD_BASE = `http://127.0.0.1:{port}` }
			for _, p in manifest.places do
				for _, var in p.env do
					env[var] = ""
				end
			end
			for k, v in ENV do
				env[k] = v :: string
			end
			local r = process.exec(
				"lune",
				{ "run", "scripts/runtime-test", "--", "--place", "Portal", "7" },
				{
					cwd = root,
					env = env,
				}
			)
			stop()
			t.expect(r.ok).toBe(true)
			local files = scripts()
			t.expect(#calls).toBe(#files)
			local sent: { string } = {}
			for _, call in calls do
				t.expect(`{call.place} {call.version}`).toBe("222 7")
				table.insert(sent, call.script)
			end
			local expected: { string } = {}
			for _, file in files do
				table.insert(expected, fs.readFile(file))
			end
			table.sort(sent)
			table.sort(expected)
			t.expect(sent).toEqual(expected)
			t.expect(
				string.find(r.stdout, `{#files} passed, 0 failed, {#files} runtime scripts`, 1, true) ~= nil
			)
				.toBe(true)
		end
	)
end)
