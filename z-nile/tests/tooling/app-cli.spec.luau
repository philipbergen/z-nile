--!strict
-- f0437 step 1: `./zn app` against a real daemon the helper starts inside the spec's fixture (tests/lib/live.luau: its own
-- state, a short idle limit, shut down at the end). The live layer is opted in for the fixture by the helper's environment.
-- The HTTP side is spoken to with curl, the way a browser would.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local live = require("@tests/lib/live")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- A long-lived process of its own (the fixture's "worker"): returns its pid.
local function sleeper(): number
	local r = process.exec("sh", { "-c", "sleep 60 </dev/null >/dev/null 2>&1 & echo $!" })
	return tonumber((string.gsub(r.stdout, "%s+", ""))) :: number
end

-- `./zn app <args>` as a person types it, in the fixture repository, with the short daemon limits of a named state folder.
local function app(l: live.Live, args: { string }): live.Result
	local argv = { `{l.root}/zn`, "app", "--idle-exit", "20", "--tick-every", "0.3" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(l.repo, "bash", argv, { env = l.env })
end

local function get(l: live.Live, url: string, extra: { string }?): live.Result
	local argv = { "-sS", "--max-time", "5", "-i" }
	local more: { string } = extra or {}
	for _, a in more do
		table.insert(argv, a)
	end
	table.insert(argv, url)
	return fixture.exec(l.repo, "curl", argv, { env = l.env })
end

local function body(r: live.Result): string
	return (string.gsub(r.stdout, "^.-\r\n\r\n", "", 1))
end

return t.spec("f0437 ./zn app: the daemon serves the app page and the real workers", function(it)
	it(
		"prints one loopback URL, serves the page and the registered worker, and prints the same URL again",
		function()
			live.with("f0437-app-cli", nil, function(l)
				local pid = sleeper()
				local reg = l:zn({
					"register",
					"--worker",
					"fixture-1",
					"--cli",
					"fake",
					"--pid",
					tostring(pid),
					"--can",
					"code/light",
				})
				t.expect(reg.code).toBe(0)
				local r = app(l, {})
				if r.code ~= 0 then
					error(`./zn app: exit {r.code}: {r.stdout}{r.stderr}`, 0)
				end
				local url = string.match(r.stdout, "^(http://127%.0%.0%.1:%d+/)\n$")
				t.expect(url ~= nil).toBe(true)
				local page = get(l, url :: string)
				t.expect(string.find(page.stdout, "HTTP/1.1 200", 1, true) ~= nil).toBe(true)
				t.expect(string.find(page.stdout, 'id="live-data"', 1, true) ~= nil).toBe(true)
				local state = get(l, (url :: string) .. "api/state")
				local decoded = serde.decode("json" :: "json", body(state))
				local workers = decoded.workers :: { any }
				t.expect(#workers).toBe(1)
				t.expect(workers[1].id).toBe("fixture-1")
				t.expect(workers[1].cli).toBe("fake")
				t.expect(workers[1].state).toBe("idle")
				-- another Host or origin gets no data, and no CORS header is sent
				local port = string.match(url :: string, ":(%d+)/") :: string
				local wrongHost =
					get(l, (url :: string) .. "api/state", { "-H", "Host: evil.example:" .. port })
				t.expect(string.find(wrongHost.stdout, "HTTP/1.1 403", 1, true) ~= nil).toBe(true)
				t.expect(string.find(wrongHost.stdout, "fixture-1", 1, true) == nil).toBe(true)
				local wrongOrigin =
					get(l, (url :: string) .. "api/state", { "-H", "Origin: http://evil.example" })
				t.expect(string.find(wrongOrigin.stdout, "HTTP/1.1 403", 1, true) ~= nil).toBe(true)
				t.expect(string.find(string.lower(state.stdout), "access-control", 1, true) == nil).toBe(true)
				local again = app(l, {})
				t.expect(again.stdout).toBe(r.stdout)
				process.exec("kill", { tostring(pid) })
			end)
		end
	)

	it("opens no port for a daemon that a write op starts", function()
		live.with("f0437-app-off", nil, function(l)
			local r = l:zn({ "emit", "review-filed" })
			t.expect(r.code).toBe(0)
			t.expect(fs.isFile(`{l.state}/http`)).toBe(false)
		end)
	end)

	it("refuses with the path when the page is missing", function()
		live.with("f0437-app-nopage", nil, function(l)
			local r = app(l, { "--page", `{l.base}/missing.html` })
			t.expect(r.code).toBe(3)
			t.expect(string.find(r.stderr, "missing.html", 1, true) ~= nil).toBe(true)
		end)
	end)

	it("ships a data layer that is valid JavaScript, when node is installed", function()
		local home = fixture.physical(".") :: string
		local src = fs.readFile(`{home}/app/index.html`)
		local from = string.find(src, '<script id="live-data">', 1, true)
		t.expect(from ~= nil).toBe(true)
		local code = string.match(src, '<script id="live%-data">(.-)</script>', from :: number)
		t.expect(code ~= nil and #(code :: string) > 1000).toBe(true)
		local which = process.exec("sh", { "-c", "command -v node" })
		if not which.ok then
			return
		end
		local dir = `{home}/.cache/f0437-app-js`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		fs.writeFile(`{dir}/live.js`, code :: string)
		local r = process.exec("node", { "--check", `{dir}/live.js` })
		t.expect(r.ok).toBe(true)
		fs.removeDir(dir)
	end)
end)
