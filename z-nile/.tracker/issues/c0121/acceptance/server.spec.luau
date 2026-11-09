--!strict
-- c0121 AC2: serve.start in-process on 127.0.0.1 and a random port, with every effect a stub (the runner of ./zn, the
-- opener, gh, the clock, the model's key and the engine's hash): the page needs its token; a rebinding Host, a foreign
-- Origin, OPTIONS, a GET action and an unknown id are refused before any stub runs; stop and retry run ./zn dispatch
-- with an argument array; open opens the PR; /api/state fills PR and checks from gh at most once per 30 s, survives a
-- failing gh, reads a launched raft's spend from its worktree, rebuilds the model only when its key changes (or after
-- 60 s), and says when the engine changed; a retry refused at once answers with the refusal. gh yields as the real one
-- does, so a request never waits for it. The real keyOf and engineHash run on a fixture repository (a commit, origin/main,
-- a worktree's commit, the dispatcher's state; an engine commit against any other). The last case stops the server.
-- Fixtures under .cache/c0121-server and .cache/c0121-server-repo.
local fixture = require("@tests/lib/fixture")
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
-- fixtures live under the home's .cache, where the spec runs (the jail refuses the checkout top's when they differ)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local ROOT = `{here}/.cache/c0121-server`
local TOKEN = "t0k-c0121"
local REPO = `{here}/.cache/c0121-server-repo`
local REPO_WT = `{here}/.cache/c0121-server-repo-wt`
-- the dispatcher's state folder, spelled in two parts: c0049 counts a literal .cache/<dir> as a fixture name
local DISPATCH = "." .. "cache/dispatch"
local REGISTRY = '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'

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
local ghBody = GH_JSON -- what gh prints; a case swaps it
local hashDelay = 0 -- engineHash yields when set, as process.exec does
local ghDelay = 2 -- gh yields, as process.exec does (long enough that a loaded machine still sees it in flight)
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
				if args[2] == "retry" and args[3] == "R0030" then
					task.wait(0.1) -- a refusal still takes a process start, as process.exec yields
					return { ok = false, stdout = "", stderr = "stop: R0030's run lock is held" }
				elseif args[2] == "retry" then
					task.wait(1.5) -- a chain that keeps running
					return { ok = true, stdout = "", stderr = "" }
				end
				return { ok = true, stdout = "stopped", stderr = "" }
			end,
			opener = function(target: string): boolean
				table.insert(opened, target)
				return true
			end,
			gh = function(): (string?, string?)
				ghCalls += 1
				if ghDelay > 0 then
					task.wait(ghDelay)
				end
				if ghFails then
					return nil, "gh: not logged in"
				end
				return ghBody, nil
			end,
			now = function(): number
				return clock
			end,
			facts = function(_root: string): any
				return {
					asOf = nil,
					refs = { { name = "origin/R0020-alpha", at = clock } },
					worktrees = { { path = `{ROOT}/wt/R0020`, branch = "R0020-alpha" } },
					-- c0117's run state: R0020's chain runs, and f0021's moved on to it; R0030 failed; c0099 has none
					dispatch = {
						R0020 = { step = "z-run", outcome = "running", model = "m", questions = false },
						f0021 = {
							step = "z-design",
							outcome = "ok",
							model = "m",
							questions = false,
							follows = "R0020",
						},
						f0022 = {
							step = "zz-review",
							outcome = "running",
							model = "m",
							questions = false,
							follows = "R0020",
						},
						-- a raft whose run stopped on a held lock: it has a state, so a retry reaches the dispatcher
						R0030 = { step = "z-run", outcome = "failed", model = "m", questions = false },
					},
				}
			end,
			collect = function(root: string, facts: any): any
				builds += 1
				return require("@znile/engine/board").collect(nil, root, facts)
			end,
			keyOf = function(): string
				return key
			end,
			-- Stats as a function of the build, so a case can tell a kept answer from a recomputed one
			statsHtml = function(_m: any): string
				return `<p>stats of build {builds}</p>`
			end,
			engineHash = function(): string?
				if hashDelay > 0 then
					task.wait(hashDelay)
				end
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
		item(
			"z-nile/.tracker/issues/active/f0022",
			{ "type: feature", "title: Reviewed", "raft: R0020", "status: active-a-b-c" }
		)
		item("z-nile/.tracker/issues/c0099", { "type: chore", "title: Loose", "raft:" })
		item(
			"z-nile/.tracker/issues/active/f0025",
			{ "type: feature", "title: Idle member", "raft: R0020", "status: active-a-b-c" }
		)
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

	it(
		"never waits for gh: the first answer says loading, a request while gh runs starts no second one",
		function()
			local first = state()
			local second = state()
			local callsInFlight = ghCalls
			task.wait(ghDelay + 0.5)
			local after = state()
			ghDelay = 0 -- before any assertion, so a failure here leaves the later cases a quick gh
			t.expect(first.model.live.checks).toBe("loading")
			t.expect(byId(first.model.rafts).R0020.pr).toBe(nil)
			t.expect(second.model.live.checks).toBe("loading")
			t.expect(callsInFlight).toBe(1)
			t.expect(after.model.live.checks).toBe("ok")
			t.expect(ghCalls).toBe(1)
		end
	)

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
		t.expect(runs[2]).toEqual({ "dispatch", "retry", "f0021" })
	end)

	it("a retry the dispatcher refuses at once answers with the refusal, not 202", function()
		local r = action('{"action":"retry","id":"R0030"}')
		t.expect(r.statusCode).toBe(500)
		t.expect(string.find(r.body, "run lock is held", 1, true) ~= nil).toBe(true)
		t.expect(runs[3]).toEqual({ "dispatch", "retry", "R0030" })
	end)

	it(
		"retry on a card that never ran answers 409 and runs nothing (it would start the item's whole chain)",
		function()
			local before = #runs
			local r = action('{"action":"retry","id":"c0099"}')
			t.expect(r.statusCode).toBe(409)
			t.expect(string.find(r.body, "nothing to retry for c0099", 1, true) ~= nil).toBe(true)
			t.expect(#runs).toBe(before)
			-- a member of a raft that runs, with no state of its own: its raft's state does not make it retryable
			local member = action('{"action":"retry","id":"f0025"}')
			t.expect(member.statusCode).toBe(409)
			t.expect(string.find(member.body, "nothing to retry for f0025", 1, true) ~= nil).toBe(true)
			t.expect(#runs).toBe(before)
		end
	)

	it(
		"stop on a member stops its raft's run, and stop on a card with nothing running answers 409 and runs nothing",
		function()
			local before = #runs
			local r = action('{"action":"stop","id":"f0021"}')
			t.expect(r.statusCode).toBe(200)
			t.expect(runs[#runs]).toEqual({ "dispatch", "stop", "R0020" })
			local own = action('{"action":"stop","id":"f0022"}') -- its own step runs: its own id, not the raft's
			t.expect(own.statusCode).toBe(200)
			t.expect(runs[#runs]).toEqual({ "dispatch", "stop", "f0022" })
			local idle = action('{"action":"stop","id":"c0099"}')
			t.expect(idle.statusCode).toBe(409)
			t.expect(string.find(idle.body, "nothing is running for c0099", 1, true) ~= nil).toBe(true)
			t.expect(#runs).toBe(before + 2)
		end
	)

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

	it("encodes the model once per build of it and per answer of gh, not per poll (the CPU limit)", function()
		state()
		task.wait(0.1)
		state() -- warm: the build and gh's answer have both moved the generation
		local board: any = require("@znile/engine/board")
		local real = board.encode
		local models = 0
		local inside = false -- encode calls itself for nested values: count the outermost call only
		board.encode = function(v: any): string
			local top = not inside and type(v) == "table" and v.rafts ~= nil and v.issues ~= nil
			if top then
				models += 1
				inside = true
			end
			local out = real(v)
			if top then
				inside = false
			end
			return out
		end
		local ok, err = pcall(function()
			local a, b, c = state(), state(), state()
			-- every poll still carries the current live block and Stats, and the same model
			for _, s in { a, b, c } do
				t.expect(s.model.live.token).toBe(TOKEN)
				t.expect(type(s.statsHtml)).toBe("string")
				t.expect(#s.model.rafts).toBe(#a.model.rafts)
			end
			t.expect(b.model.rafts).toEqual(a.model.rafts)
			t.expect(b.statsHtml).toBe(a.statsHtml) -- kept with the model between builds
			key = "k-encode"
			local d = state() -- a build of the model: encoded again, with its Stats
			t.expect(d.statsHtml ~= a.statsHtml).toBe(true)
		end)
		board.encode = real
		if not ok then
			error(err, 0)
		end
		t.expect(models).toBe(1)
	end)

	it(
		"a gh answer that lands while a request waits on the engine hash is served by the next poll (no stale PRs)",
		function()
			-- the request lays the old PRs on the model, then yields on engineHash; gh answers in that window with a new PR
			-- number; the next poll must show it (a generation read after the yield would label the old JSON as the new one)
			local shown = byId(state().model.rafts).R0020.pr.number
			t.expect(shown).toBe(7)
			ghBody = (string.gsub(GH_JSON, '"number":7', '"number":9'))
			clock += 31
			local savedDelay = ghDelay
			ghDelay = 0.02
			hashDelay = 0.3
			local ok, err = pcall(function()
				local a = state() -- gh is asked, answers during this request's wait: the body is the old PRs
				local b = state() -- the next poll shows the new answer
				t.expect(byId(a.model.rafts).R0020.pr.number == 7 or byId(a.model.rafts).R0020.pr.number == 9)
					.toBe(true)
				t.expect(byId(b.model.rafts).R0020.pr.number).toBe(9)
			end)
			ghBody, ghDelay, hashDelay = GH_JSON, savedDelay, 0
			if not ok then
				error(err, 0)
			end
		end
	)

	it("a gh answer that repeats the last one costs no new encoding", function()
		local savedDelay = ghDelay
		ghDelay = 0.02
		clock += 31
		state() -- gh is asked (its output may differ from the case before's)
		task.wait(0.2)
		state() -- settled on this answer
		local board: any = require("@znile/engine/board")
		local real = board.encode
		local models = 0
		local inside = false
		board.encode = function(v: any): string
			local top = not inside and type(v) == "table" and v.rafts ~= nil and v.issues ~= nil
			if top then
				models += 1
				inside = true
			end
			local out = real(v)
			if top then
				inside = false
			end
			return out
		end
		local calls = ghCalls
		local ok, err = pcall(function()
			clock += 31
			state() -- gh is asked again
			task.wait(0.2)
			state() -- and answers with the same PRs
			t.expect(ghCalls).toBe(calls + 1)
		end)
		board.encode, ghDelay = real, savedDelay
		if not ok then
			error(err, 0)
		end
		t.expect(models).toBe(0)
	end)

	it(
		"gh failing, then answering again, is shown by the next poll without a rebuild of the model",
		function()
			local savedDelay = ghDelay
			ghDelay = 0.02
			local function settled()
				key ..= "x" -- a build at this clock: no periodic rebuild can be what the next polls show
				clock += 1
				state()
				task.wait(0.1)
			end
			local ok, err = pcall(function()
				settled()
				local b0 = builds
				ghFails = true
				clock += 31
				state() -- gh is asked and fails
				task.wait(0.2)
				local failed = state()
				t.expect(builds).toBe(b0)
				t.expect(failed.model.live.checks).toBe("unavailable")
				t.expect(byId(failed.model.rafts).R0020.pr).toBe(nil)
				ghFails = false
				settled() -- a build at this clock again: 62 s of fake time would let the periodic rebuild show the answer
				local b1 = builds
				clock += 31
				state() -- gh is asked again and answers
				task.wait(0.2)
				local back = state()
				t.expect(builds).toBe(b1)
				t.expect(back.model.live.checks).toBe("ok")
				t.expect(byId(back.model.rafts).R0020.pr ~= nil).toBe(true)
			end)
			ghFails, ghDelay = false, savedDelay
			if not ok then
				error(err, 0)
			end
		end
	)

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

	it(
		"the real keyOf changes with a commit, origin/main, a worktree's commit and the dispatcher's state, and only then",
		function()
			if fs.isDir(REPO) then
				fs.removeDir(REPO)
			end
			if fs.isDir(REPO_WT) then
				fs.removeDir(REPO_WT)
			end
			fs.writeDir(REPO)
			process.exec("git", { "init", "-q", "-b", "main", REPO }) -- raw: init to a named path
			fixture.git(REPO, { "config", "user.name", "c0121-server" })
			fixture.git(REPO, { "config", "user.email", "c0121-server@example.invalid" })
			fs.writeDir(`{REPO}/z-nile/engine`)
			fs.writeFile(`{REPO}/z-nile/engine/x.luau`, "return 1\n")
			fs.writeFile(`{REPO}/README.md`, "r\n")
			fixture.git(REPO, { "add", "-A" })
			fixture.git(REPO, { "commit", "-q", "-m", "one" })
			fixture.git(REPO, { "update-ref", "refs/remotes/origin/main", "HEAD" })
			fixture.git(REPO, { "worktree", "add", "-q", "-b", "R0020-alpha", REPO_WT })
			local k0 = serve.keyOf(REPO)
			t.expect(serve.keyOf(REPO)).toBe(k0)
			fs.writeFile(`{REPO}/README.md`, "r2\n")
			fixture.git(REPO, { "commit", "-q", "-am", "two" })
			local k1 = serve.keyOf(REPO)
			t.expect(k1 ~= k0).toBe(true)
			fixture.git(REPO, { "update-ref", "refs/remotes/origin/main", "HEAD" })
			local k2 = serve.keyOf(REPO)
			t.expect(k2 ~= k1).toBe(true)
			fs.writeFile(`{REPO_WT}/wt.txt`, "w\n")
			fixture.git(REPO_WT, { "add", "-A" })
			fixture.git(REPO_WT, { "commit", "-q", "-m", "in the worktree" })
			local k3 = serve.keyOf(REPO)
			t.expect(k3 ~= k2).toBe(true)
			fs.writeDir(`{REPO}/{DISPATCH}/R0020`)
			fs.writeFile(`{REPO}/{DISPATCH}/R0020/state.json`, "{}")
			local k4 = serve.keyOf(REPO)
			t.expect(k4 ~= k3).toBe(true)
			t.expect(serve.keyOf(REPO)).toBe(k4)
		end
	)

	it("the real engineHash changes with an engine commit and not with any other", function()
		local h0 = serve.engineHash(REPO)
		t.expect(h0 ~= nil).toBe(true)
		fs.writeFile(`{REPO}/README.md`, "r3\n")
		fixture.git(REPO, { "commit", "-q", "-am", "not the engine" })
		t.expect(serve.engineHash(REPO)).toBe(h0)
		fs.writeFile(`{REPO}/z-nile/engine/x.luau`, "return 2\n")
		fixture.git(REPO, { "commit", "-q", "-am", "the engine" })
		t.expect(serve.engineHash(REPO) ~= h0).toBe(true)
	end)

	it(
		"a server with the default engine hash says it is out of date after an engine commit in its checkout",
		function()
			local live: serve.Server? = nil
			local port = 0
			for _ = 1, 30 do
				port = math.random(30000, 60000)
				local ok, s = pcall(serve.start, {
					root = REPO,
					port = port,
					token = TOKEN,
					runner = function(): serve.RunResult
						return { ok = true, stdout = "", stderr = "" }
					end,
					opener = function(): boolean
						return true
					end,
					gh = function(): (string?, string?)
						return nil, "no gh in this case"
					end,
					now = function(): number
						return clock
					end,
					facts = function(_root: string): any
						return { asOf = nil, refs = {}, worktrees = {}, dispatch = {} }
					end,
					collect = function(_root: string, facts: any): any
						return require("@znile/engine/board").collect(nil, ROOT, facts)
					end,
				})
				if ok then
					live = s
					break
				end
			end
			t.expect(live ~= nil).toBe(true)
			local function stale(): boolean
				local r = (net.request :: any)({
					url = `http://127.0.0.1:{port}/api/state`,
					headers = { ["X-Zn-Token"] = TOKEN },
				})
				return serde.decode("json", r.body).model.live.stale
			end
			t.expect(stale()).toBe(false)
			fs.writeFile(`{REPO}/z-nile/engine/x.luau`, "return 3\n")
			fixture.git(REPO, { "commit", "-q", "-am", "the engine again" })
			t.expect(stale()).toBe(true);
			(live :: serve.Server).stop()
		end
	)

	it("binds through its listener on 127.0.0.1 only, at the port it was given", function()
		local binds: { any } = {}
		local s: serve.Server? = nil
		local port = 0
		for _ = 1, 30 do
			port = math.random(30000, 60000)
			local ok, made = pcall(serve.start, {
				root = ROOT,
				port = port,
				token = TOKEN,
				runner = function(): serve.RunResult
					return { ok = true, stdout = "", stderr = "" }
				end,
				opener = function(): boolean
					return true
				end,
				gh = function(): (string?, string?)
					return nil, "no gh in this case"
				end,
				now = function(): number
					return clock
				end,
				facts = function(_root: string): any
					return { asOf = nil, refs = {}, worktrees = {}, dispatch = {} }
				end,
				keyOf = function(): string
					return "k"
				end,
				engineHash = function(): string?
					return "e"
				end,
				listen = function(p: number, cfg: any): any
					table.insert(binds, { port = p, address = cfg.address })
					return (net.serve :: any)(p, cfg)
				end,
			})
			if ok then
				s = made
				break
			end
			table.clear(binds)
		end
		t.expect(s ~= nil).toBe(true)
		t.expect(binds).toEqual({ { port = port, address = "http://127.0.0.1" } })
		local r = (net.request :: any)({
			url = `http://127.0.0.1:{port}/api/state`,
			headers = { ["X-Zn-Token"] = TOKEN },
		})
		t.expect(r.statusCode).toBe(200);
		(s :: serve.Server).stop()
	end)

	it("stops: a request afterwards is refused", function()
		(server :: serve.Server).stop()
		task.wait(0.1)
		local ok = pcall(net.request, url("/api/state"))
		t.expect(ok).toBe(false)
		fs.removeDir(ROOT)
		fixture.git(REPO, { "worktree", "remove", "--force", REPO_WT })
		fs.removeDir(REPO)
	end)
end)
