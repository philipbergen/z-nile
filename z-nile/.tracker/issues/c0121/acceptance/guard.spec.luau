--!strict
-- c0121 AC1: the server's pure rules. serve.guard refuses DNS rebinding (a foreign Host), CSRF (OPTIONS, a foreign
-- Origin, no token, an action that is not a JSON POST) and lets the rest through; serve.plan turns an action on an id
-- the model has into an argument array or an open target, and refuses anything else; serve.parsePrs reads `gh pr list`.
local serve = require("@znile/engine/serve")
local t = require("@tests/lib/t")

local PORT, TOKEN = 41234, "t0k"
local function req(o: { [string]: any }): serve.Request
	return {
		path = o.path or "/api/state",
		query = o.query or {},
		method = o.method or "GET",
		headers = o.headers or { host = `127.0.0.1:{PORT}`, ["x-zn-token"] = TOKEN },
		body = o.body or "",
	}
end
local function status(r: serve.Request): number?
	local res = serve.guard(r, PORT, TOKEN)
	return if res then res.status else nil
end
local function headers(extra: { [string]: string }): { [string]: string }
	local h: { [string]: string } = { host = `127.0.0.1:{PORT}`, ["x-zn-token"] = TOKEN }
	for k, v in extra do
		h[k] = v
	end
	return h
end

local MODEL: any = {
	home = {
		R0020 = "R0020",
		R0030 = "R0030",
		f0021 = "f0021",
		f0022 = "f0022",
		f0031 = "f0031",
		c0099 = "c0099",
	},
	rafts = {
		{
			id = "R0020",
			pr = { number = 7, url = "https://example.invalid/pr/7", state = "draft" },
			worktree = "/w/R0020",
			dispatch = { step = "z-run", outcome = "running", model = "m", questions = false },
		},
		{ id = "R0030", worktree = "/w/R0030" },
	} :: { any },
	issues = {
		{
			id = "f0021",
			raft = "R0020",
			-- its chain moved on to its raft: c0117 writes `follows` once and leaves the last step's outcome (ok)
			dispatch = {
				step = "z-design",
				outcome = "ok",
				model = "m",
				questions = false,
				follows = "R0020",
			},
		},
		{
			id = "f0031",
			raft = "R0030",
			-- a stale follow: R0030 has no run state
			dispatch = {
				step = "z-design",
				outcome = "ok",
				model = "m",
				questions = false,
				follows = "R0030",
			},
			pr = { number = 9, url = "https://example.invalid/pr/9", state = "open" },
		},
		{
			id = "f0022",
			raft = "R0020",
			-- a step of its own runs on the same state after its chain followed R0020 (follows is never cleared)
			dispatch = {
				step = "zz-review",
				outcome = "running",
				model = "m",
				questions = false,
				follows = "R0020",
			},
		},
		{ id = "c0099" },
	} :: { any },
}

return t.spec("c0121 server rules", function(it)
	it("lets a same-host request with the token through, by 127.0.0.1 or localhost", function()
		t.expect(status(req({}))).toBe(nil)
		t.expect(status(req({ headers = { host = `localhost:{PORT}`, ["x-zn-token"] = TOKEN } }))).toBe(nil)
		-- some clients send the bare loopback name, without the port
		t.expect(status(req({ headers = { host = "127.0.0.1", ["x-zn-token"] = TOKEN } }))).toBe(nil)
	end)

	it("refuses a foreign Host (DNS rebinding), another port, and no Host", function()
		t.expect(status(req({ headers = headers({ host = "evil.example" }) }))).toBe(403)
		t.expect(status(req({ headers = headers({ host = `evil.example:{PORT}` }) }))).toBe(403)
		t.expect(status(req({ headers = headers({ host = "127.0.0.1:1" }) }))).toBe(403)
		t.expect(status(req({ headers = { ["x-zn-token"] = TOKEN } }))).toBe(403)
		t.expect(status(req({ headers = headers({ host = "localhost.evil.example" }) }))).toBe(403)
	end)

	it("refuses every OPTIONS, with no CORS header, so a cross-site preflight fails", function()
		local res = serve.guard(req({ method = "OPTIONS", path = "/api/action" }), PORT, TOKEN)
		t.expect(res ~= nil and res.status).toBe(403)
		for k in (res :: any).headers or {} do
			t.expect((string.find(string.lower(k), "access-control", 1, true))).toBe(nil)
		end
	end)

	it("refuses a foreign Origin, and lets the server's own through", function()
		t.expect(status(req({ headers = headers({ origin = "http://evil.example" }) }))).toBe(403)
		t.expect(status(req({ headers = headers({ origin = `http://127.0.0.1:{PORT + 1}` }) }))).toBe(403)
		t.expect(status(req({ headers = headers({ origin = `http://127.0.0.1:{PORT}` }) }))).toBe(nil)
		t.expect(status(req({ headers = headers({ origin = `http://localhost:{PORT}` }) }))).toBe(nil)
	end)

	it("serves the page only as a GET with the token in its query", function()
		local h = { host = `127.0.0.1:{PORT}` }
		t.expect(status(req({ path = "/", headers = h }))).toBe(403)
		t.expect(status(req({ path = "/", headers = h, query = { token = "wrong" } }))).toBe(403)
		t.expect(status(req({ path = "/", headers = h, query = { token = TOKEN } }))).toBe(nil)
		t.expect(status(req({ path = "/", method = "POST", headers = h, query = { token = TOKEN } })))
			.toBe(405)
	end)

	it("refuses an /api/ call without the token or with a wrong one", function()
		t.expect(status(req({ headers = { host = `127.0.0.1:{PORT}` } }))).toBe(403)
		t.expect(status(req({ headers = headers({ ["x-zn-token"] = "t0k2" }) }))).toBe(403)
		t.expect(status(req({ headers = headers({ ["x-zn-token"] = "" }) }))).toBe(403)
	end)

	it("takes an action only as a POST with a JSON body; a GET never acts", function()
		t.expect(status(req({ path = "/api/action", method = "GET" }))).toBe(405)
		t.expect(status(req({
			path = "/api/action",
			method = "POST",
			headers = headers({ ["content-type"] = "text/plain" }),
		}))).toBe(415)
		t.expect(status(req({ path = "/api/action", method = "POST" }))).toBe(415) -- no Content-Type
		t.expect(status(req({
			path = "/api/action",
			method = "POST",
			headers = headers({ ["content-type"] = "application/json" }),
		}))).toBe(nil)
		t.expect(status(req({ path = "/api/state", method = "POST" }))).toBe(405)
	end)

	it("answers 404 for any other path", function()
		t.expect(status(req({ path = "/api/other" }))).toBe(404)
		t.expect(status(req({ path = "/etc/passwd" }))).toBe(404)
	end)

	it(
		"plans stop (waited) and retry (started) as argument arrays for ./zn dispatch, on ids the model has",
		function()
			t.expect((serve.plan(MODEL, "stop", "R0020")))
				.toEqual({ kind = "run", args = { "dispatch", "stop", "R0020" }, wait = true })
			t.expect((serve.plan(MODEL, "retry", "f0021")))
				.toEqual({ kind = "run", args = { "dispatch", "retry", "f0021" }, wait = false })
		end
	)

	it(
		"stop on a member whose run follows its raft stops the raft's run; a stale follow, or a step of its own running, stops the card's own",
		function()
			t.expect((serve.plan(MODEL, "stop", "f0021")))
				.toEqual({ kind = "run", args = { "dispatch", "stop", "R0020" }, wait = true })
			t.expect((serve.plan(MODEL, "stop", "f0031")))
				.toEqual({ kind = "run", args = { "dispatch", "stop", "f0031" }, wait = true })
			-- an own step running: stop the card's own run, never the raft's (design review 004 F1)
			t.expect((serve.plan(MODEL, "stop", "f0022")))
				.toEqual({ kind = "run", args = { "dispatch", "stop", "f0022" }, wait = true })
			-- retry keeps the card's own id: its chain follows by itself
			t.expect((serve.plan(MODEL, "retry", "f0021")))
				.toEqual({ kind = "run", args = { "dispatch", "retry", "f0021" }, wait = false })
		end
	)

	it("stop on a card with no run state plans nothing and answers 409", function()
		local plan, why, code = serve.plan(MODEL, "stop", "c0099")
		t.expect(plan).toBe(nil)
		t.expect(string.find(why :: string, "nothing is running for c0099", 1, true) ~= nil).toBe(true)
		t.expect(code).toBe(409)
		local _, _, unknown = serve.plan(MODEL, "stop", "R9999")
		t.expect(unknown == nil or unknown == 400).toBe(true)
	end)

	it(
		"refuses an unknown id, an id with shell text, a non-string id and an unknown action, naming why",
		function()
			local p1, why1 = serve.plan(MODEL, "stop", "R9999")
			t.expect(p1).toBe(nil)
			t.expect(string.find(why1 :: string, "unknown id", 1, true) ~= nil).toBe(true)
			t.expect((serve.plan(MODEL, "stop", "R0020; rm -rf ~"))).toBe(nil)
			t.expect((serve.plan(MODEL, "stop", 42 :: any))).toBe(nil)
			local p2, why2 = serve.plan(MODEL, "delete", "R0020")
			t.expect(p2).toBe(nil)
			t.expect(string.find(why2 :: string, "unknown action", 1, true) ~= nil).toBe(true)
		end
	)

	it("opens an item's own PR, else its raft's PR, else its raft's worktree, and nothing else", function()
		t.expect((serve.plan(MODEL, "open", "f0031")))
			.toEqual({ kind = "open", target = "https://example.invalid/pr/9" })
		t.expect((serve.plan(MODEL, "open", "f0021")))
			.toEqual({ kind = "open", target = "https://example.invalid/pr/7" })
		t.expect((serve.plan(MODEL, "open", "R0020")))
			.toEqual({ kind = "open", target = "https://example.invalid/pr/7" })
		t.expect((serve.plan(MODEL, "open", "R0030"))).toEqual({ kind = "open", target = "/w/R0030" })
		local p, why = serve.plan(MODEL, "open", "c0099")
		t.expect(p).toBe(nil)
		t.expect(string.find(why :: string, "no PR and no worktree", 1, true) ~= nil).toBe(true)
	end)

	it("reads gh pr list: drafts, and checks as passing, failing, pending or none", function()
		local prs = serve.parsePrs([[
[{"number":7,"headRefName":"R0020-alpha","state":"OPEN","isDraft":true,"url":"https://example.invalid/pr/7",
  "statusCheckRollup":[{"conclusion":"SUCCESS"},{"state":"SUCCESS"}]},
 {"number":8,"headRefName":"R0030-beta","state":"OPEN","isDraft":false,"url":"u8",
  "statusCheckRollup":[{"conclusion":"SUCCESS"},{"conclusion":"FAILURE"}]},
 {"number":9,"headRefName":"R0040-gamma","state":"MERGED","isDraft":false,"url":"u9",
  "statusCheckRollup":[{"conclusion":"SUCCESS"},{"status":"IN_PROGRESS","conclusion":""}]},
 {"number":10,"headRefName":"R0050-delta","state":"CLOSED","isDraft":false,"url":"u10","statusCheckRollup":[]},
 {"headRefName":"no-number"}]
]]) :: any
		t.expect(prs["R0020-alpha"].pr)
			.toEqual({ number = 7, url = "https://example.invalid/pr/7", state = "draft" })
		t.expect(prs["R0020-alpha"].checks.state).toBe("passing")
		t.expect(prs["R0030-beta"].pr.state).toBe("open")
		t.expect(prs["R0030-beta"].checks.state).toBe("failing")
		t.expect(prs["R0040-gamma"].pr.state).toBe("merged")
		t.expect(prs["R0040-gamma"].checks.state).toBe("pending")
		t.expect(prs["R0050-delta"].checks.state).toBe("none")
		t.expect(prs["no-number"]).toBe(nil)
		t.expect(serve.parsePrs("gh: not logged in")).toBe(nil)
	end)

	it(
		"keeps one PR per branch: open or draft over merged or closed, then the highest number, in any order",
		function()
			local a =
				[[{"number":5,"headRefName":"R0020-a","state":"CLOSED","isDraft":false,"url":"u5","statusCheckRollup":[]}]]
			local b =
				[[{"number":12,"headRefName":"R0020-a","state":"OPEN","isDraft":false,"url":"u12","statusCheckRollup":[{"conclusion":"FAILURE"}]}]]
			local c =
				[[{"number":3,"headRefName":"R0030-b","state":"MERGED","isDraft":false,"url":"u3","statusCheckRollup":[]}]]
			local d =
				[[{"number":9,"headRefName":"R0030-b","state":"CLOSED","isDraft":false,"url":"u9","statusCheckRollup":[]}]]
			local fork =
				[[{"number":20,"headRefName":"R0020-a","state":"OPEN","isDraft":false,"url":"u20","isCrossRepository":true,"statusCheckRollup":[]}]]
			for _, list in { `[{b},{a},{c},{d},{fork}]`, `[{fork},{a},{b},{d},{c}]` } do
				local prs = serve.parsePrs(list) :: any
				t.expect(prs["R0020-a"].pr.number).toBe(12) -- the open one, over the closed one and the fork's
				t.expect(prs["R0020-a"].checks.state).toBe("failing")
				t.expect(prs["R0030-b"].pr.number).toBe(9) -- neither open: the higher number
			end
			local draft =
				[[{"number":5,"headRefName":"R0040-c","state":"OPEN","isDraft":true,"url":"u5d","statusCheckRollup":[]}]]
			local closed =
				[[{"number":9,"headRefName":"R0040-c","state":"CLOSED","isDraft":false,"url":"u9c","statusCheckRollup":[]}]]
			for _, list in { `[{draft},{closed}]`, `[{closed},{draft}]` } do
				local prs = serve.parsePrs(list) :: any
				t.expect(prs["R0040-c"].pr).toEqual({ number = 5, url = "u5d", state = "draft" }) -- a draft beats a higher closed one
			end
		end
	)

	it("names a taken port, and says what else failed when the server could not start", function()
		t.expect(serve.startError("Address already in use (os error 48)", 8417))
			.toBe("board --serve: port 8417 is taken (already serving?); pick another with --port")
		t.expect(
			serve.startError("board --serve: could not read 16 random bytes for the session token", 8417)
		)
			.toBe(
				"board --serve could not start: board --serve: could not read 16 random bytes for the session token"
			)
	end)

	it(
		"the CLI's effects run <top>/zn by argument array, open or xdg-open, and gh pr list with its exact arguments",
		function()
			local calls: { any } = {}
			local answer: any = { ok = true, stdout = "[]", stderr = "" }
			local function exec(cmd: string, args: { string }, opts: any): any
				table.insert(calls, { cmd = cmd, args = args, cwd = opts and opts.cwd })
				return answer
			end
			local mac = serve.effects("/top", exec :: any, "macos")
			mac.runner({ "dispatch", "stop", "R0020" })
			mac.opener("https://example.invalid/pr/7")
			t.expect((mac.gh())).toBe("[]")
			serve.effects("/top", exec :: any, "linux").opener("/w/R0020")
			t.expect(calls[1])
				.toEqual({ cmd = "/top/zn", args = { "dispatch", "stop", "R0020" }, cwd = "/top" })
			t.expect(calls[2]).toEqual({ cmd = "open", args = { "https://example.invalid/pr/7" } })
			t.expect(calls[3]).toEqual({
				cmd = "gh",
				args = {
					"pr",
					"list",
					"--state",
					"all",
					"--limit",
					"200",
					"--json",
					"number,headRefName,state,isDraft,url,statusCheckRollup,isCrossRepository",
				},
				cwd = "/top",
			})
			t.expect(calls[4]).toEqual({ cmd = "xdg-open", args = { "/w/R0020" } })
			answer = { ok = false, stdout = "", stderr = "gh: not logged in\n" }
			local out, why = mac.gh()
			t.expect(out).toBe(nil)
			t.expect(why).toBe("gh: not logged in")
			local missing = serve.effects(
				"/top",
				function(): any
					error("no such file")
				end :: any,
				"macos"
			)
			local out2, why2 = missing.gh()
			t.expect(out2).toBe(nil)
			t.expect(why2).toBe("gh is not installed")
		end
	)

	it("makes a session token of 32 hex digits, new each time", function()
		local a, b = serve.newToken(), serve.newToken()
		t.expect(string.match(a, "^%x+$") ~= nil and #a == 32).toBe(true)
		t.expect(a ~= b).toBe(true)
	end)
end)
