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
local task = require("@lune/task")

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
				t.expect(string.find(page.stdout, '<script src="live.js"></script>', 1, true) ~= nil)
					.toBe(true)
				t.expect(
					string.find(string.lower(page.stdout), "x-content-type-options: nosniff", 1, true) ~= nil
				)
					.toBe(true)
				t.expect(string.find(string.lower(page.stdout), "x-frame-options: deny", 1, true) ~= nil)
					.toBe(true)
				local js = get(l, (url :: string) .. "live.js")
				t.expect(string.find(js.stdout, "HTTP/1.1 200", 1, true) ~= nil).toBe(true)
				t.expect(
					string.find(string.lower(js.stdout), "content-type: text/javascript", 1, true) ~= nil
				)
					.toBe(true)
				t.expect(string.find(js.stdout, "LiveApp", 1, true) ~= nil).toBe(true)
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
				-- a daemon restart keeps the address (the port of the last app is asked for first), so an open tab finds it again
				l:znRaw({ "shutdown" })
				for _ = 1, 100 do
					if #l:pids() == 0 then
						break
					end
					task.wait(0.05)
				end
				local after = app(l, {})
				t.expect(after.stdout).toBe(r.stdout)
				process.exec("kill", { tostring(pid) })
			end)
		end
	)

	it(
		"serves /api/approvals from the facts file in its state folder, and says so when there is none",
		function()
			live.with("f0437-app-approvals", nil, function(l)
				local r = app(l, {})
				t.expect(r.code).toBe(0)
				local url = string.match(r.stdout, "^(http://127%.0%.0%.1:%d+/)\n$") :: string
				local none = serde.decode("json" :: "json", body(get(l, url .. "api/approvals")))
				t.expect(none.state).toBe("absent")
				fs.writeFile(
					`{l.state}/approvals.json`,
					'{"version":1,"at":5,"run":"20261122T010203Z-a1b2","scope":"R0002","themes":[{"id":"alpha","title":"alpha","purpose":"","rafts":[{"id":"c0001","title":"T","single":true,"tickets":[{"id":"c0001","title":"T","why":"w","place":"origin/main","hash":"abc","idea":{"problem":"P","solution":"S"},"design":[],"guesses":[],"reviews":[],"links":{}}]}]}]}'
				)
				local got = get(l, url .. "api/approvals")
				t.expect(string.find(got.stdout, "HTTP/1.1 200", 1, true) ~= nil).toBe(true)
				local decoded = serde.decode("json" :: "json", body(got))
				t.expect(decoded.state).toBe("ok")
				t.expect(decoded.facts.scope).toBe("R0002")
				t.expect(decoded.facts.themes[1].rafts[1].tickets[1].hash).toBe("abc")
				local port = string.match(url, ":(%d+)/") :: string
				local wrong = get(l, url .. "api/approvals", { "-H", "Host: evil.example:" .. port })
				t.expect(string.find(wrong.stdout, "HTTP/1.1 403", 1, true) ~= nil).toBe(true)
			end)
		end
	)

	it(
		"serves /api/themes from the facts file in its state folder, and says so when there is none",
		function()
			live.with("f0437-app-themes", nil, function(l)
				local r = app(l, {})
				t.expect(r.code).toBe(0)
				local url = string.match(r.stdout, "^(http://127%.0%.0%.1:%d+/)\n$") :: string
				local none = serde.decode("json" :: "json", body(get(l, url .. "api/themes")))
				t.expect(none.state).toBe("absent")
				fs.writeFile(
					`{l.state}/themes.json`,
					'{"version":1,"at":5,"live":true,"approvalsScope":"","themes":[{"id":"alpha","project":"p","title":"alpha","purpose":"first","counts":{"done":1,"flight":1,"approval":0,"owner":0,"open":2},"workers":["claude w1"],"units":[{"id":"R0001","title":"T","stage":"code","phase":"flight","holder":"claude w1","since":3}]}]}'
				)
				local got = get(l, url .. "api/themes")
				t.expect(string.find(got.stdout, "HTTP/1.1 200", 1, true) ~= nil).toBe(true)
				local decoded = serde.decode("json" :: "json", body(got))
				t.expect(decoded.state).toBe("ok")
				t.expect(decoded.facts.themes[1].counts.flight).toBe(1)
				t.expect(decoded.facts.themes[1].units[1].stage).toBe("code")
				local port = string.match(url, ":(%d+)/") :: string
				local wrong = get(l, url .. "api/themes", { "-H", "Host: evil.example:" .. port })
				t.expect(string.find(wrong.stdout, "HTTP/1.1 403", 1, true) ~= nil).toBe(true)
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

	it("takes the user's --page=FILE as it is, and never appends a second page", function()
		live.with("f0437-app-pageflag", nil, function(l)
			local dir = `{l.base}/custom/z-nile/app`
			fs.writeDir(`{l.base}/custom`)
			fs.writeDir(`{l.base}/custom/z-nile`)
			fs.writeDir(dir)
			fs.writeFile(`{dir}/index.html`, "<p>custom</p>")
			fs.writeFile(`{dir}/live.js`, "var x;")
			local r = app(l, { `--page={dir}/index.html` })
			t.expect(r.code).toBe(0)
			local url = string.match(r.stdout, "^(http://127%.0%.0%.1:%d+/)\n$") :: string
			t.expect(body(get(l, url))).toBe("<p>custom</p>")
		end)
	end)

	it(
		"--open hands the URL to the system opener (open on macOS, xdg-open elsewhere) and plain app opens nothing",
		function()
			live.with("f0437-app-open", nil, function(l)
				local bin = `{l.base}/fakebin`
				fs.writeDir(bin)
				for _, name in { "open", "xdg-open" } do
					fs.writeFile(`{bin}/{name}`, `#!/bin/sh\necho "$1" > "{l.base}/opened.txt"\n`)
					process.exec("chmod", { "+x", `{bin}/{name}` })
				end
				local function withFakes(args: { string }): live.Result
					local argv = { `{l.root}/zn`, "app", "--idle-exit", "20", "--tick-every", "0.3" }
					for _, a in args do
						table.insert(argv, a)
					end
					local env = table.clone(l.env)
					env.PATH = `{bin}:{process.env.PATH or "/usr/bin:/bin"}`
					return fixture.exec(l.repo, "bash", argv, { env = env })
				end
				local plain = withFakes({})
				t.expect(plain.code).toBe(0)
				t.expect(fs.isFile(`{l.base}/opened.txt`)).toBe(false)
				local r = withFakes({ "--open" })
				t.expect(r.code).toBe(0)
				t.expect(fs.readFile(`{l.base}/opened.txt`)).toBe(r.stdout)
			end)
		end
	)

	it("runs the data layer against a stub page (node): rendering, escaping, file:, missing names", function()
		local which = process.exec("sh", { "-c", "command -v node" })
		if not which.ok then
			print("SKIPPED: node is not installed, so the data layer's render and escape tests did not run")
			return
		end
		local home = fixture.physical(".") :: string
		local r = process.exec("node", { `{home}/tests/tooling/app-live.node.js`, `{home}/app` })
		if not r.ok then
			error(`app-live.node.js failed:\n{r.stdout}{r.stderr}`, 0)
		end
	end)
end)
