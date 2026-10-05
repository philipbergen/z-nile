--!strict
-- c0140 AC3 (end to end): scripts/deploy-beta against a local fake of Roblox. The real command runs with the
-- real Rojo on a tiny fixture project, and what reaches the fake server, what the command prints and what it
-- appends to $GITHUB_OUTPUT is checked. This is the glue the unit specs of OpenCloud can't see.
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
local script = `{root}/scripts/deploy-beta`
local work = `{root}/.cache/deploy-e2e`
local KEY = "KEY-NOT-IN-OUTPUT"

type Seen = {
	method: string,
	path: string,
	query: { [string]: string },
	key: string?,
	contentType: string?,
	body: string,
}

-- a fake Roblox answering every request with (status, body); `seen` collects the requests
local function serve(status: number, body: string): (number, { Seen }, () -> ())
	local seen: { Seen } = {}
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, handle = pcall(
			net.serve,
			port,
			function(req: any): any
				table.insert(seen, {
					method = req.method,
					path = req.path,
					query = req.query,
					key = req.headers["x-api-key"],
					contentType = req.headers["content-type"],
					body = req.body or "",
				})
				return { status = status, body = body }
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

local function run(port: number, extra: { [string]: string }?)
	local env: { [string]: string } = {
		ROBLOX_API_KEY = KEY,
		ROBLOX_BETA_UNIVERSE_ID = "111",
		ROBLOX_BETA_PLACE_ID = "222",
		OPENCLOUD_BASE = `http://127.0.0.1:{port}`,
		GITHUB_OUTPUT = "",
	}
	if extra then
		for k, v in extra do
			env[k] = v
		end
	end
	return process.exec("lune", { "run", script }, { env = env, cwd = work })
end

return t.spec("c0140 scripts/deploy-beta end to end", function(it)
	fs.writeDir(work)
	fs.writeFile(
		`{work}/default.project.json`,
		'{"name":"fixture","tree":{"$className":"DataModel","ReplicatedStorage":{"$className":"ReplicatedStorage"}}}'
	)
	local out = `{work}/github-output`

	it("builds the place and publishes it with the right request, then reports the version", function()
		fs.writeFile(out, "existing=1\n")
		local port, seen, stop = serve(200, '{"versionNumber":42}')
		local r = run(port, { GITHUB_OUTPUT = out })
		stop()
		t.expect(r.ok).toBe(true)
		t.expect(#seen).toBe(1)
		t.expect(seen[1].method).toBe("POST")
		t.expect(seen[1].path).toBe("/universes/v1/111/places/222/versions")
		t.expect(seen[1].query.versionType).toBe("Published")
		t.expect(seen[1].key).toBe(KEY)
		t.expect(seen[1].contentType).toBe("application/octet-stream")
		t.expect(string.sub(seen[1].body, 1, 8)).toBe("<roblox!") -- a real built place, not text
		t.expect(string.find(r.stdout, "version=42", 1, true) ~= nil).toBe(true)
		t.expect((string.find(r.stdout .. r.stderr, KEY, 1, true))).toBe(nil)
		t.expect(fs.readFile(out)).toBe("existing=1\nversion=42\n") -- appended, nothing lost
	end)

	it("without GITHUB_OUTPUT it still prints the version and writes no file", function()
		local port, _, stop = serve(200, '{"versionNumber":7}')
		local r = run(port)
		stop()
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, "version=7", 1, true) ~= nil).toBe(true)
	end)

	it("a refusal fails the command, shows the status and body, and reports no version", function()
		fs.writeFile(out, "")
		local port, seen, stop = serve(403, '{"errors":[{"code":9009,"message":"WAF Blocked Request"}]}')
		local r = run(port, { GITHUB_OUTPUT = out })
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(#seen).toBe(1) -- not retried
		t.expect(string.find(r.stdout, "403", 1, true) ~= nil).toBe(true)
		t.expect(string.find(r.stdout, "WAF Blocked Request", 1, true) ~= nil).toBe(true)
		t.expect((string.find(r.stdout, "version=", 1, true))).toBe(nil)
		t.expect((string.find(r.stdout .. r.stderr, KEY, 1, true))).toBe(nil)
		t.expect(fs.readFile(out)).toBe("")
	end)

	it("a 200 without a version fails and writes nothing", function()
		fs.writeFile(out, "")
		local port, _, stop = serve(200, "{}")
		local r = run(port, { GITHUB_OUTPUT = out })
		stop()
		t.expect(r.ok).toBe(false)
		t.expect(fs.readFile(out)).toBe("")
	end)

	it("a base that is not loopback is refused before anything is built or sent", function()
		local r = run(1, { OPENCLOUD_BASE = "https://evil.example" })
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stdout .. r.stderr, "loopback", 1, true) ~= nil).toBe(true)
		t.expect((string.find(r.stdout .. r.stderr, KEY, 1, true))).toBe(nil)
	end)
end)
