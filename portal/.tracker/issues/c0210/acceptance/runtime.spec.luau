--!strict
-- c0210 AC5: scripts/runtime-test -- [--place <name>] <version> [files...] over a fixture experience (a manifest under
-- .cache/c0210-runtime), against a local fake of Roblox's Luau Execution API that passes a script with "PASS-ME" in it.
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = (string.gsub(process.cwd, "/+$", ""))
local script = `{root}/scripts/runtime-test`
local work = `{root}/.cache/c0210-runtime`
local KEY = "KEY-NOT-IN-OUTPUT"

type Seen = { method: string, path: string }

local function serve(): (number, { Seen }, () -> ())
	local seen: { Seen } = {}
	local sources: { [string]: string } = {}
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, handle = pcall(
			net.serve,
			port,
			function(req: any): any
				table.insert(seen, { method = req.method, path = req.path })
				if
					req.method == "POST" and string.find(req.path, "luau-execution-session-tasks", 1, true)
				then
					local n = tostring(#seen)
					sources[n] = (serde.decode("json" :: "json", req.body) :: any).script
					return {
						status = 200,
						body = serde.encode("json" :: "json", { path = `tasks/{n}`, state = "PROCESSING" }),
					}
				end
				local n = string.match(req.path, "^/cloud/v2/tasks/(%d+)$")
				if req.method == "GET" and n then
					local value = if string.find(sources[n] or "", "PASS-ME", 1, true) then "PASS" else "nope"
					return {
						status = 200,
						body = serde.encode(
							"json" :: "json",
							{ state = "COMPLETE", output = { results = { value } } }
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
    "pickman": { "project": "p.project.json", "runtime": "../suites/pickman" },
    "snake": { "project": "s.project.json" },
    "invaders": { "project": "i.project.json" },
    "asteroids": { "project": "a.project.json" },
    "start": { "project": "default.project.json", "runtime": "start-suite" }
  }
}
]]

local function run(args: { string }, extra: { [string]: string }, port: number?, cwd: string?)
	local argv = { "run", script, "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	local env: { [string]: string } = {
		ROBLOX_API_KEY = KEY,
		ROBLOX_BETA_UNIVERSE_ID = "111",
		ROBLOX_BETA_PLACE_ID = "222",
		OPENCLOUD_BASE = if port then `http://127.0.0.1:{port}` else "",
	}
	for k, v in extra do
		env[k] = v
	end
	return process.exec("lune", argv, { cwd = cwd or `{work}/experience`, env = env })
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function tasks(seen: { Seen }, id: string, version: string): number
	local n = 0
	for _, s in seen do
		if
			s.method == "POST" and has(s.path, `/places/{id}/versions/{version}/luau-execution-session-tasks`)
		then
			n += 1
		end
	end
	return n
end

return t.spec("c0210 scripts/runtime-test --place", function(it)
	fs.writeDir(`{work}/experience/start-suite`)
	fs.writeDir(`{work}/suites/pickman`)
	fs.writeFile(`{work}/experience/experience.json`, MANIFEST)
	fs.writeFile(`{work}/experience/start-suite/a.luau`, 'return "PASS-ME start"')
	fs.writeFile(`{work}/experience/start-suite/notes.txt`, "not a script")
	fs.writeFile(`{work}/suites/pickman/b.luau`, 'return "PASS-ME pickman b"')
	fs.writeFile(`{work}/suites/pickman/a.luau`, 'return "PASS-ME pickman a"')
	fs.writeFile(`{work}/one.luau`, 'return "PASS-ME one"')

	it("usage, exit 2: --place with no name, a version that is not a whole number >= 1", function()
		for _, args in { { "--place" }, { "--place", "Snake" }, { "--place", "Snake", "0" }, { "1.5" }, {} } do
			local r = run(args, {})
			t.expect(r.code).toBe(2)
			t.expect(has(r.stdout, "usage: lune run scripts/runtime-test -- [--place <name>] <version>"))
				.toBe(true)
		end
	end)

	it("a name that is no place of the manifest: exit 2, naming it", function()
		local r = run({ "--place", "Pong", "5" }, {})
		t.expect(r.code).toBe(2)
		t.expect(has(r.stdout, "Pong is not a place of experience.json")).toBe(true)
		local lobby = run({ "--lobby", "5" }, {})
		t.expect(lobby.code).toBe(2)
	end)

	it("not configured: a warning and success", function()
		local r = run({ "--place", "Portal", "5" }, { ROBLOX_API_KEY = "" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "::warning::runtime tests are not configured")).toBe(true)
	end)

	it("a place whose variable is unset: a warning and success, nothing sent", function()
		local port, seen, stop = serve()
		local r = run({ "--place", "Snake", "5" }, {}, port)
		stop()
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "::warning::runtime tests of the Snake place are not configured")).toBe(true)
		t.expect(#seen).toBe(0)
	end)

	it(
		"a published place with no runtime folder and no files: a warning and success, nothing sent",
		function()
			local port, seen, stop = serve()
			local r = run({ "--place", "Snake", "5" }, { ROBLOX_BETA_SNAKE_PLACE_ID = "444" }, port)
			stop()
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "::warning::the Snake place has no runtime scripts")).toBe(true)
			t.expect(#seen).toBe(0)
		end
	)

	it("the files given run at that place's id and version", function()
		local port, seen, stop = serve()
		local r = run(
			{ "--place", "Snake", "9", `{work}/one.luau` },
			{ ROBLOX_BETA_SNAKE_PLACE_ID = "444" },
			port
		)
		stop()
		t.expect(r.ok).toBe(true)
		t.expect(tasks(seen, "444", "9")).toBe(1)
		t.expect(has(r.stdout, "1 passed, 0 failed, 1 runtime scripts")).toBe(true)
		t.expect(has(r.stdout .. r.stderr, KEY)).toBe(false)
	end)

	it(
		"with no files, the build's runtime folder's *.luau in order, named relative to the manifest's folder",
		function()
			local port, seen, stop = serve()
			local r = run({ "--place", "Portal", "5" }, {}, port)
			stop()
			t.expect(r.ok).toBe(true)
			t.expect(tasks(seen, "222", "5")).toBe(1)
			t.expect(has(r.stdout, "PASS start-suite/a.luau")).toBe(true)
			local port2, seen2, stop2 = serve()
			local p = run({ "--place", "Pickman", "6" }, { ROBLOX_BETA_GAME_PLACE_ID = "333" }, port2)
			stop2()
			t.expect(p.ok).toBe(true)
			t.expect(tasks(seen2, "333", "6")).toBe(2)
			local a = string.find(p.stdout, "PASS ../suites/pickman/a.luau", 1, true)
			local b = string.find(p.stdout, "PASS ../suites/pickman/b.luau", 1, true)
			t.expect(a ~= nil and b ~= nil and (a :: number) < (b :: number)).toBe(true)
		end
	)

	it("without --place it is Pickman's place", function()
		local port, seen, stop = serve()
		local r = run({ "6" }, { ROBLOX_BETA_PICKMAN_PLACE_ID = "333" }, port)
		stop()
		t.expect(r.ok).toBe(true)
		t.expect(tasks(seen, "333", "6")).toBe(2)
		t.expect(tasks(seen, "222", "6")).toBe(0)
	end)

	it("a script that does not pass fails the command", function()
		fs.writeFile(`{work}/bad.luau`, 'return "nope"')
		local port, _, stop = serve()
		local r = run({ "--place", "Portal", "5", `{work}/bad.luau` }, {}, port)
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "0 passed, 1 failed")).toBe(true)
	end)

	it("a bad id or a missing manifest fails before anything is sent", function()
		local port, seen, stop = serve()
		local bad = run({ "--place", "Portal", "5" }, { ROBLOX_BETA_SNAKE_PLACE_ID = "x" }, port)
		local missing = run({ "--place", "Portal", "5" }, {}, port, work)
		stop()
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stdout, "ROBLOX_BETA_SNAKE_PLACE_ID")).toBe(true)
		t.expect(missing.ok).toBe(false)
		t.expect(has(missing.stdout, "experience.json is missing")).toBe(true)
		t.expect(#seen).toBe(0)
	end)
end)
