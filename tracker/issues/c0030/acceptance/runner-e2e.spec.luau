--!strict
-- c0030 AC3 (end to end): scripts/runtime-test against a local fake of Roblox's Luau Execution API. The
-- fake "runs" a script by looking at its text; the command's exit code and report are what is checked.
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
local script = `{root}/scripts/runtime-test`
local work = `{root}/.cache/runner-e2e`
local KEY = "KEY-NOT-IN-OUTPUT"

-- a fake: creating a task answers with a path, and polling it completes at once with PASS when the script
-- text has "PASS-ME" in it, else with "nope"
local function serve(): (number, { string }, () -> ())
	local calls: { string } = {}
	local scriptsByTask: { [string]: string } = {}
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, handle = pcall(
			net.serve,
			port,
			function(req: any): any
				table.insert(calls, `{req.method} {req.path}`)
				local prefix = "/cloud/v2/universes/111/places/222/versions/5/luau-execution-session-tasks"
				if req.method == "POST" and req.path == prefix then
					local n = tostring(#calls)
					scriptsByTask[n] = (serde.decode("json" :: "json", req.body) :: any).script
					return {
						status = 200,
						body = serde.encode("json" :: "json", { path = `tasks/{n}`, state = "PROCESSING" }),
					}
				end
				local n = string.match(req.path, "^/cloud/v2/tasks/(%d+)$")
				if req.method == "GET" and n then
					local value = if string.find(scriptsByTask[n] or "", "PASS-ME", 1, true) then "PASS" else "nope"
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

local function run(port: number, args: { string }, cwd: string?)
	local argv = { "run", script, "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("lune", argv, {
		cwd = cwd or work,
		env = {
			ROBLOX_API_KEY = KEY,
			ROBLOX_BETA_UNIVERSE_ID = "111",
			ROBLOX_BETA_PLACE_ID = "222",
			OPENCLOUD_BASE = `http://127.0.0.1:{port}`,
		},
	})
end

return t.spec("c0030 scripts/runtime-test end to end", function(it)
	fs.writeDir(work)
	fs.writeFile(`{work}/good.luau`, 'return "PASS-ME"')
	fs.writeFile(`{work}/bad.luau`, 'return "something else"')

	it("all scripts passing: exit 0 and a report", function()
		local port, calls, stop = serve()
		local r = run(port, { "5", `{work}/good.luau` })
		stop()
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, `PASS {work}/good.luau`, 1, true) ~= nil).toBe(true)
		t.expect(string.find(r.stdout, "1 passed, 0 failed", 1, true) ~= nil).toBe(true)
		t.expect(#calls >= 2).toBe(true)
		t.expect((string.find(r.stdout .. r.stderr, KEY, 1, true))).toBe(nil)
	end)

	it("one script that doesn't pass fails the command, names it, and the others still run", function()
		local port, _, stop = serve()
		local r = run(port, { "5", `{work}/good.luau`, `{work}/bad.luau`, `{work}/good.luau` })
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stdout, `FAIL {work}/bad.luau: returned nope`, 1, true) ~= nil).toBe(true)
		t.expect(string.find(r.stdout, "2 passed, 1 failed", 1, true) ~= nil).toBe(true)
	end)

	it("with no files it runs everything under tests/runtime", function()
		local port, _, stop = serve()
		local r = run(port, { "5" }, root)
		stop()
		-- the checked-in structure script has no PASS-ME marker, so against this fake it fails, by name
		t.expect(string.find(r.stdout, "FAIL tests/runtime/structure.luau", 1, true) ~= nil).toBe(true)
	end)

	it("the version is part of the request: a different one is not found", function()
		local port, _, stop = serve()
		local r = run(port, { "6", `{work}/good.luau` })
		stop()
		t.expect(r.ok).toBe(false) -- the fake only knows version 5
	end)
end)
