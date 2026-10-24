--!strict
-- c0121 AC2: serve.start in-process on 127.0.0.1 and a random port, with every effect a stub (the runner of ./zn, the
-- opener, gh, the clock, the model's key and the engine's hash): the page needs its token; a rebinding Host, a foreign
-- Origin, OPTIONS, a GET action and an unknown id are refused before any stub runs; stop and retry run ./zn dispatch
-- with an argument array; open opens the PR; /api/state fills PR and checks from gh at most once per 30 s, survives a
-- failing gh, reads a launched raft's spend from its worktree, rebuilds the model only when its key changes (or after
-- 60 s), and says when the engine changed; the last case stops the server. Fixture under .cache/c0121-server.
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local serve = require("@znile/engine/serve")
local t = require("@tests/lib/t")
local task = require("@lune/task")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local top = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local ROOT = `{top}/.cache/c0121-server`
local TOKEN = "t0k-c0121"
local REGISTRY = '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\nhome = "."\n'

local function write(path: string, text: string)
	local full = `{ROOT}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function item(path: string, front: { string })
	local id = string.match(path, "([^/]+)$") :: string
	write(
		`{path}/{id}.md`,
		"---\nid: " .. id .. "\n" .. table.concat(front, "\n") .. "\n---\n\n# " .. id .. "\n"
	)
end

local GH_JSON = [[
[{"number":7,"headRefName":"R0020-alpha","state":"OPEN","isDraft":true,"url":"https://example.invalid/pr/7",
  "statusCheckRollup":[{"conclusion":"SUCCESS"}]}]
]]

-- the stubs and what they saw
local clock = 1000000
local runs: { { string } } = {}
local opened: { string } = {}
local ghCalls = 0
local ghFails = false
local builds = 0
local key = "k1"
local hash = "engine-1"
local server: serve.Server? = nil
local PORT = 0

local function start()
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, s = pcall(serve.start, {
			root = ROOT,
			port = port,
			token = TOKEN,
			runner = function(args: { string }): serve.RunResult
				table.insert(runs, table.clone(args))
				return { ok = true, stdout = "stopped", stderr = "" }
			end,
			opener = function(target: string): boolean
				table.insert(opened, target)
				return true
			end,
			gh = function(): (string?, string?)
				ghCalls += 1
				if ghFails then
					return nil, "gh: not logged in"
				end
				return GH_JSON, nil
			end,
			now = function(): number
				return clock
			end,
			facts = function(_root: string): any
				return {
					asOf = nil,
					refs = { { name = "origin/R0020-alpha", at = clock } },
					worktrees = { { path = `{ROOT}/wt/R0020`, branch = "R0020-alpha" } },
					dispatch = {},
				}
			end,
			collect = function(root: string, facts: any): any
				builds += 1
				return require("@znile/engine/board").collect(nil, root, facts)
			end,
			keyOf = function(): string
				return key
			end,
			engineHash = function(): string?
				return hash
			end,
		})
		if ok then
			server, PORT = s, port
			return
		end
	end
	error("no free port in 30 tries")
end

local function url(path: string): string
	return `http://127.0.0.1:{PORT}{path}`
end
local function call(method: string, path: string, headers: { [string]: string }?, body: string?): any
	return (net.request :: any)({
		url = url(path),
		method = method :: any,
		headers = headers or { ["X-Zn-Token"] = TOKEN },
		body = body,
	})
end
local function action(body: string, extra: { [string]: string }?): any
	local h: { [string]: string } = { ["X-Zn-Token"] = TOKEN, ["Content-Type"] = "application/json" }
	for k, v in (extra or {}) :: { [string]: string } do
		h[k] = v
	end
	return call("POST", "/api/action", h, body)
end
-- a request sent raw, as a browser on a rebinding domain or a preflight sends it (net.request rewrites Host)
local function raw(lines: { string }): string
	local conn = net.tcp.connect("127.0.0.1", PORT)
	conn:write(table.concat(lines, "\r\n") .. "\r\nConnection: close\r\n\r\n")
	local reply = conn:read() or ""
	conn:close()
	return reply
end
local function state(): any
	local r = call("GET", "/api/state")
	t.expect(r.statusCode).toBe(200)
	return serde.decode("json", r.body)
end
local function byId(list: { any }): { [string]: any }
	local out = {}
	for _, x in list do
		out[x.id] = x
	end
	return out
end

return t.spec("c0121 board server", function(it)
	it("starts on 127.0.0.1 with a fixture tracker and a worktree's spend", function()
		if fs.isDir(ROOT) then
			fs.removeDir(ROOT)
		end
		write("z-nile/projects.toml", REGISTRY)
		item(
			"z-nile/.tracker/rafts/active/R0020",
			{ "type: feature", "title: Running", "design: ready", "status: active-a-b-c" }
		)
		item(
			"z-nile/.tracker/issues/active/f0021",
			{ "type: feature", "title: Runs", "raft: R0020", "status: active-a-b-c" }
		)
		item(
			"z-nile/.tracker/rafts/R0030",
			{ "type: chore", "title: Prepared", "design: ready", "status: prepared-a-b-c" }
		)
		item("z-nile/.tracker/issues/c0099", { "type: chore", "title: Loose", "raft:" })
		write(
			"wt/R0020/z-nile/.tracker/issues/active/f0021/spend.md",
			"# Spend: f0021 x\n\n| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens | model |\n"
				.. "|---|---|---|---|---|---|---|---|---|---|\n"
				.. "| 1 | 2026-10-24 10:00 | s | 3 | 1 | 4.0 | raft | code-review | 777 | grok-y |\n"
		)
		start()
		t.expect(server ~= nil).toBe(true)
		t.expect((server :: serve.Server).url).toBe(`http://127.0.0.1:{PORT}/?token={TOKEN}`)
	end)

	it("serves the page with its token and the live settings, and refuses it without the token", function()
		local ok = call("GET", `/?token={TOKEN}`, {})
		t.expect(ok.statusCode).toBe(200)
		t.expect(string.find(ok.body, `"token":"{TOKEN}"`, 1, true) ~= nil).toBe(true)
		t.expect(string.find(ok.body, '"live":', 1, true) ~= nil).toBe(true)
		t.expect(call("GET", "/", {}).statusCode).toBe(403)
		t.expect(call("GET", "/?token=nope", {}).statusCode).toBe(403)
	end)

	it("refuses a DNS-rebinding Host before any stub runs", function()
		local reply = raw({
			"POST /api/action HTTP/1.1",
			"Host: evil.example",
			`X-Zn-Token: {TOKEN}`,
			"Content-Type: application/json",
			'Content-Length: 31\r\n\r\n{"action":"stop","id":"R0020"}',
		})
		t.expect(string.find(reply, "HTTP/1.1 403", 1, true) ~= nil).toBe(true)
		t.expect(#runs).toBe(0)
	end)

	it("refuses a foreign Origin, an OPTIONS preflight and a GET action, running nothing", function()
		t.expect(action('{"action":"stop","id":"R0020"}', { Origin = "http://evil.example" }).statusCode)
			.toBe(403)
		local pre =
			raw({ "OPTIONS /api/action HTTP/1.1", `Host: 127.0.0.1:{PORT}`, "Origin: http://evil.example" })
		t.expect(string.find(pre, "HTTP/1.1 403", 1, true) ~= nil).toBe(true)
		t.expect((string.find(string.lower(pre), "access-control-allow", 1, true))).toBe(nil)
		t.expect(call("GET", "/api/action?action=stop&id=R0020").statusCode).toBe(405)
		t.expect(action('{"action":"stop","id":"R0020"}', { ["X-Zn-Token"] = "wrong" }).statusCode).toBe(403)
		t.expect(#runs).toBe(0)
	end)

	it("refuses an unknown id or shell text before any process runs", function()
		t.expect(action('{"action":"stop","id":"R9999"}').statusCode).toBe(400)
		t.expect(action('{"action":"retry","id":"R0020 && touch x"}').statusCode).toBe(400)
		t.expect(action("not json").statusCode).toBe(400)
		t.expect(#runs).toBe(0)
	end)

	it("stop runs ./zn dispatch stop <id> as an argument array and answers with its output", function()
		local r = action('{"action":"stop","id":"R0020"}')
		t.expect(r.statusCode).toBe(200)
		t.expect(string.find(r.body, "stopped", 1, true) ~= nil).toBe(true)
		t.expect(runs).toEqual({ { "dispatch", "stop", "R0020" } })
	end)

	it("retry is answered at once and runs ./zn dispatch retry <id>", function()
		local r = action('{"action":"retry","id":"f0021"}')
		t.expect(r.statusCode).toBe(202)
		task.wait(0.2)
		t.expect(runs[2]).toEqual({ "dispatch", "retry", "f0021" })
	end)

	it("state fills PR and checks from gh, calling it once in its 30 s window and again after", function()
		local s1 = state()
		task.wait(0.1)
		local s2 = state()
		t.expect(ghCalls).toBe(1)
		local r = byId(s2.model.rafts).R0020
		t.expect(r.pr).toEqual({ number = 7, url = "https://example.invalid/pr/7", state = "draft" })
		t.expect(r.checks.state).toBe("passing")
		t.expect(s2.model.live.checks).toBe("ok")
		t.expect(s1.model.live.token).toBe(TOKEN)
		t.expect(type(s2.statsHtml)).toBe("string")
		clock += 31
		state()
		t.expect(ghCalls).toBe(2)
	end)

	it("open opens the card's PR, and refuses an item with nothing to open", function()
		t.expect(action('{"action":"open","id":"f0021"}').statusCode).toBe(200)
		t.expect(opened).toEqual({ "https://example.invalid/pr/7" })
		t.expect(action('{"action":"open","id":"c0099"}').statusCode).toBe(400)
		t.expect(#opened).toBe(1)
	end)

	it("reads a launched raft's member spend from its worktree", function()
		local f = byId(state().model.issues).f0021
		t.expect(f.spend.tokens).toBe(777)
		t.expect(f.spend.models).toEqual({ "grok-y" })
	end)

	it("rebuilds the model only when its key changes, or after 60 s", function()
		local before = builds
		state()
		state()
		t.expect(builds).toBe(before)
		key = "k2"
		state()
		t.expect(builds).toBe(before + 1)
		clock += 61
		state()
		t.expect(builds).toBe(before + 2)
	end)

	it("a failing gh still gives 200, with checks unavailable", function()
		ghFails = true
		clock += 31
		state()
		task.wait(0.1)
		local s = state()
		t.expect(s.model.live.checks).toBe("unavailable")
		t.expect(byId(s.model.rafts).R0020.pr).toBe(nil)
	end)

	it("says the server is out of date once the engine changed since it started", function()
		t.expect(state().model.live.stale).toBe(false)
		hash = "engine-2"
		t.expect(state().model.live.stale).toBe(true)
	end)

	it("stops: a request afterwards is refused", function()
		(server :: serve.Server).stop()
		task.wait(0.1)
		local ok = pcall(net.request, url("/api/state"))
		t.expect(ok).toBe(false)
		fs.removeDir(ROOT)
	end)
end)
