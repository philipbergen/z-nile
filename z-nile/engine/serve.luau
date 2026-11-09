--!strict
-- The board's local server (c0121): `./zn board --serve` serves the page `./zn board` writes, with live data and the
-- three actions (stop, retry, open). The guard, the action plan and the `gh` parse are pure; `serve.start` wires them to
-- net.serve with every effect injected (the runner of `./zn`, the opener, `gh`, the clock), so specs run it in-process.
local board = require("./board")
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local serve = {}

serve.PORT = 8417 -- the default --port
serve.TTL = 30 -- seconds a `gh` answer is reused
serve.REBUILD = 60 -- seconds a model is reused while nothing it reads has changed
serve.POLL = 5 -- seconds between the page's polls
serve.RETRY_WAIT = 1 -- seconds a retry is waited for before it is answered 202

export type Response = { status: number, headers: { [string]: string }?, body: string }
export type Request = {
	path: string,
	query: { [string]: string? },
	method: string,
	headers: { [string]: string },
	body: string,
}
export type Plan = { kind: "run", args: { string }, wait: boolean } | { kind: "open", target: string }
export type RunResult = { ok: boolean, stdout: string, stderr: string }
export type Pr = { number: number, url: string, state: string }
export type Checks = { state: string, url: string? }
export type Options = {
	root: string, -- the main checkout
	port: number,
	runner: (args: { string }) -> RunResult, -- runs `./zn <args>` in root, argument array only
	opener: (target: string) -> boolean, -- opens a URL or a folder
	gh: () -> (string?, string?), -- `gh pr list --json …` output, or nil and the reason
	now: () -> number,
	token: string?, -- default: 16 random bytes as hex
	collect: ((root: string, facts: board.Facts) -> board.Model)?,
	facts: ((root: string) -> board.Facts)?,
	keyOf: (() -> string)?, -- what the model reads; a change forces a rebuild
	engineHash: (() -> string?)?, -- the engine tree's hash now
	statsHtml: ((m: board.Model) -> string)?,
	listen: ((port: number, cfg: any) -> any)?, -- default: net.serve (a spec records the bind through it)
}
export type Server = { url: string, token: string, port: number, stop: () -> () }

local function text(status: number, body: string): Response
	return { status = status, headers = { ["Content-Type"] = "text/plain; charset=utf-8" }, body = body }
end
local function json(status: number, value: any): Response
	return { status = status, headers = { ["Content-Type"] = "application/json" }, body = board.encode(value) }
end

-- The guard, before any route (F3): a Host other than 127.0.0.1 or localhost (with this port, or none) (DNS rebinding), any
-- OPTIONS (no CORS: a cross-site preflight fails), a foreign Origin, the page without its token in the query, an /api/
-- call without its X-Zn-Token, an action that is not a POST with a JSON body. nil when the request may go on.
function serve.guard(req: Request, port: number, token: string): Response?
	local host = req.headers.host or ""
	-- browsers send the port; some clients (Lune's net.request) send the bare loopback name. A rebinding page sends
	-- its own domain, which neither form is.
	if
		host ~= `127.0.0.1:{port}`
		and host ~= `localhost:{port}`
		and host ~= "127.0.0.1"
		and host ~= "localhost"
	then
		return text(403, `refused: Host {host} is not this server`)
	end
	if req.method == "OPTIONS" then
		return text(403, "refused: no cross-origin requests")
	end
	local origin = req.headers.origin
	if origin and origin ~= `http://127.0.0.1:{port}` and origin ~= `http://localhost:{port}` then
		return text(403, `refused: Origin {origin}`)
	end
	if req.path == "/" then
		if req.method ~= "GET" then
			return text(405, "refused: the page is GET only")
		end
		if req.query.token ~= token then
			return text(403, "refused: open the URL ./zn board --serve printed (it carries the token)")
		end
		return nil
	end
	if string.sub(req.path, 1, 5) ~= "/api/" then
		return text(404, "no such page")
	end
	if req.headers["x-zn-token"] ~= token then
		return text(403, "refused: missing or wrong X-Zn-Token")
	end
	if req.path == "/api/action" then
		if req.method ~= "POST" then
			return text(405, "refused: actions are POST only")
		end
		local ct = req.headers["content-type"] or ""
		if string.sub(ct, 1, 16) ~= "application/json" then
			return text(415, "refused: actions take application/json")
		end
	elseif req.path == "/api/state" then
		if req.method ~= "GET" then
			return text(405, "refused: state is GET only")
		end
	else
		return text(404, "no such endpoint")
	end
	return nil
end

-- What an action does, from the model only (never from free text): stop and retry run c0117's dispatcher on an id the
-- model has (stop waits, retry is started and answered at once); open opens the item's PR (its own, else its raft's)
-- or else its raft's worktree. nil and the reason for anything else.
-- The dispatcher's state the model has for `id` (c0117's run state, read by c0118's board), or nil.
local function dispatchOf(m: board.Model, id: string): board.Dispatch?
	for _, r in m.rafts do
		if r.id == id then
			return r.dispatch
		end
	end
	for _, i in m.issues do
		if i.id == id then
			return i.dispatch
		end
	end
	return nil
end

-- An action on a card as a plan, or why not and its status (409 for a Stop with nothing running, else 400).
function serve.plan(m: board.Model, action: string, id: string): (Plan?, string?, number?)
	if type(id) ~= "string" or m.home[id] == nil then
		return nil, `unknown id {tostring(id)}`, 400
	end
	if action == "stop" then
		-- the run the card belongs to: its own while a step of its own runs, else the one its chain follows (issue to
		-- raft), else its own; never an id with no
		-- run state, which `./zn dispatch stop` would create
		local own = dispatchOf(m, id)
		if own == nil then
			return nil, `nothing is running for {id}`, 409
		end
		-- c0117 writes `follows` once and never clears it, so the card's own outcome decides: running is a step of its
		-- own (stop it), anything else means its chain moved on (stop the run it follows, if that one has state)
		local target = id
		local follows = own.follows
		if own.outcome ~= "running" and follows and dispatchOf(m, follows) ~= nil then
			target = follows
		end
		return { kind = "run", args = { "dispatch", "stop", target }, wait = true }, nil
	elseif action == "retry" then
		return { kind = "run", args = { "dispatch", "retry", id }, wait = false }, nil
	elseif action ~= "open" then
		return nil, `unknown action {tostring(action)}`
	end
	local raft: board.Raft? = nil
	local issuePr: board.Pr? = nil
	for _, r in m.rafts do
		if r.id == id then
			raft = r
		end
	end
	if not raft then
		for _, i in m.issues do
			if i.id == id then
				issuePr = i.pr
				for _, r in m.rafts do
					if r.id == i.raft then
						raft = r
					end
				end
			end
		end
	end
	local pr = issuePr or (if raft then raft.pr else nil)
	if pr then
		return { kind = "open", target = pr.url }, nil
	elseif raft and raft.worktree then
		return { kind = "open", target = raft.worktree }, nil
	end
	return nil, `{id} has no PR and no worktree to open`
end

local function summary(rollup: any): string
	if type(rollup) ~= "table" or #rollup == 0 then
		return "none"
	end
	local pending = false
	for _, c in rollup do
		local v = string.upper(tostring(c.conclusion or c.state or ""))
		if
			v == "FAILURE"
			or v == "ERROR"
			or v == "CANCELLED"
			or v == "TIMED_OUT"
			or v == "ACTION_REQUIRED"
		then
			return "failing"
		elseif v ~= "SUCCESS" and v ~= "NEUTRAL" and v ~= "SKIPPED" then
			pending = true
		end
	end
	return if pending then "pending" else "passing"
end

-- `gh pr list --json number,headRefName,state,isDraft,url,statusCheckRollup,isCrossRepository` output as PR and checks
-- by branch name. A branch with several PRs keeps an open (or draft) one over a merged or closed one, then the highest
-- number, whatever the order gh lists them in; a PR from another repository (a fork whose branch has the same name) is
-- skipped. nil when it is not that JSON.
function serve.parsePrs(out: string): { [string]: { pr: Pr, checks: Checks } }?
	local ok, decoded = pcall(serde.decode, "json" :: "json", out)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local byBranch: { [string]: { pr: Pr, checks: Checks } } = {}
	local function rank(pr: Pr): number
		return (if pr.state == "open" or pr.state == "draft" then 1e9 else 0) + pr.number
	end
	for _, p in decoded :: { any } do
		if
			type(p) == "table"
			and type(p.headRefName) == "string"
			and type(p.number) == "number"
			and p.isCrossRepository ~= true
		then
			local state = string.lower(tostring(p.state or ""))
			if p.isDraft == true and state == "open" then
				state = "draft"
			end
			local entry = {
				pr = { number = p.number, url = tostring(p.url or ""), state = state },
				checks = {
					state = summary(p.statusCheckRollup),
					url = if p.url then `{p.url}/checks` else nil,
				},
			}
			local held = byBranch[p.headRefName]
			if not held or rank(entry.pr) > rank(held.pr) then
				byBranch[p.headRefName] = entry
			end
		end
	end
	return byBranch
end

-- The real effects `./zn board --serve` passes to serve.start, with the process runner injected (process.exec in the
-- CLI): `<top>/zn <args>` in top, an argument array; `open` (macOS) or `xdg-open` on the target; and one `gh pr list`.
export type Exec = (cmd: string, args: { string }, opts: { cwd: string }?) -> RunResult
serve.GH_ARGS = {
	"pr",
	"list",
	"--state",
	"all",
	"--limit",
	"200",
	"--json",
	"number,headRefName,state,isDraft,url,statusCheckRollup,isCrossRepository",
}
function serve.effects(
	top: string,
	exec: Exec,
	osName: string
): {
	runner: (args: { string }) -> RunResult,
	opener: (target: string) -> boolean,
	gh: () -> (string?, string?),
}
	return {
		runner = function(args: { string }): RunResult
			local r = exec(`{top}/zn`, args, { cwd = top })
			return { ok = r.ok, stdout = r.stdout, stderr = r.stderr }
		end,
		opener = function(target: string): boolean
			return exec(if osName == "macos" then "open" else "xdg-open", { target }, nil).ok
		end,
		gh = function(): (string?, string?)
			local ok, r = pcall(exec, "gh", serve.GH_ARGS, { cwd = top })
			if not ok then
				return nil, "gh is not installed"
			end
			if not r.ok then
				return nil, (string.gsub(r.stderr, "%s+$", ""))
			end
			return r.stdout, nil
		end,
	}
end

-- What `./zn board --serve` says when serve.start fails: a taken port by name, anything else as it is.
function serve.startError(err: string, port: number): string
	if string.find(err, "Address already in use", 1, true) or string.find(err, "address in use", 1, true) then
		return `board --serve: port {port} is taken (already serving?); pick another with --port`
	end
	return `board --serve could not start: {err}`
end

function serve.newToken(): string
	local r = process.exec("od", { "-An", "-tx1", "-N16", "/dev/urandom" })
	local hex = string.gsub(r.stdout, "%s", "")
	if not r.ok or #hex ~= 32 then
		error("board --serve: could not read 16 random bytes for the session token", 0)
	end
	return hex
end

-- The default key: HEAD, origin/main, every worktree's HEAD, and each dispatcher state file's change time.
function serve.keyOf(root: string): string
	local parts: { string } = {}
	for _, args in { { "rev-parse", "HEAD", "origin/main" }, { "worktree", "list", "--porcelain" } } do
		local r = process.exec("git", args, { cwd = root })
		table.insert(parts, r.stdout)
	end
	local home = `{root}/.cache/dispatch`
	if fs.isDir(home) then
		local names = fs.readDir(home)
		table.sort(names)
		for _, name in names do
			local file = `{home}/{name}/state.json`
			if fs.isFile(file) then
				local meta = fs.metadata(file)
				table.insert(parts, `{name} {meta.modifiedAt and meta.modifiedAt.unixTimestampMillis or 0}`)
			end
		end
	end
	return table.concat(parts, "\n")
end

function serve.engineHash(root: string): string?
	local r = process.exec("git", { "rev-parse", "HEAD:z-nile/engine" }, { cwd = root })
	return if r.ok then (string.gsub(r.stdout, "%s", "")) else nil
end

-- Starts the server on 127.0.0.1:<port>; errors when the port is taken.
function serve.start(o: Options): Server
	local token = o.token or serve.newToken()
	local collect = o.collect
		or function(root: string, facts: board.Facts): board.Model
			return board.collect(nil, root, facts)
		end
	local factsOf = o.facts or board.readFacts
	local keyOf = o.keyOf or function(): string
		return serve.keyOf(o.root)
	end
	local engineHash: () -> string? = if o.engineHash
		then o.engineHash
		else function(): string?
			return serve.engineHash(o.root)
		end
	local startHash = engineHash()
	local statsOf = o.statsHtml or board.statsHtml

	local cache: { model: board.Model?, key: string?, at: number } =
		{ model = nil, key = nil, at = -math.huge }
	local gh: { at: number, data: { [string]: { pr: Pr, checks: Checks } }?, err: string?, busy: boolean } =
		{ at = -math.huge, data = nil, err = nil, busy = false }

	-- `gh` runs in a task of its own, never on the request path, at most once per TTL (F8)
	local function refreshGh()
		if gh.busy or o.now() - gh.at < serve.TTL then
			return
		end
		gh.busy = true
		gh.at = o.now()
		task.spawn(function()
			local ok, out, why = pcall(o.gh)
			local parsed = if ok and out then serve.parsePrs(out :: string) else nil
			if parsed then
				gh.data, gh.err = parsed, nil
			else
				gh.data, gh.err = nil, if not ok then tostring(out) else (why or "gh gave no PR list")
			end
			gh.busy = false
		end)
	end

	local function model(): board.Model
		local key = keyOf()
		if not cache.model or key ~= cache.key or o.now() - cache.at >= serve.REBUILD then
			local facts = factsOf(o.root)
			facts.asOf = o.now()
			facts.worktreeSpend = true
			cache.model, cache.key, cache.at = collect(o.root, facts), key, o.now()
		end
		local m = cache.model :: board.Model
		local data = gh.data
		for _, r in m.rafts do
			local hit = if data and r.branch then data[r.branch] else nil
			r.pr = if hit then hit.pr else nil
			r.checks = if hit then hit.checks else nil
		end
		m.live = {
			token = token,
			poll = serve.POLL,
			checks = if gh.err then "unavailable" elseif gh.data then "ok" else "loading",
			checksAge = if gh.data or gh.err then math.max(0, o.now() - gh.at) else nil,
			stale = engineHash() ~= startHash,
		}
		return m
	end

	local function act(req: Request): Response
		local ok, body = pcall(serde.decode, "json" :: "json", req.body)
		if not ok or type(body) ~= "table" then
			return text(400, "refused: the body is not a JSON object")
		end
		local plan, why, code = serve.plan(model(), (body :: any).action, (body :: any).id)
		if not plan then
			return text(code or 400, `refused: {why}`)
		end
		if plan.kind == "open" then
			local opened = o.opener(plan.target)
			return json(if opened then 200 else 500, { opened = plan.target, ok = opened })
		end
		if plan.wait then
			local r = o.runner(plan.args)
			return json(if r.ok then 200 else 500, { ok = r.ok, output = r.stdout .. r.stderr })
		end
		-- retry: started in a task of its own; a dispatcher that refuses at once (a held lock) answers within 1 s with its
		-- output, and a chain that keeps running is answered 202
		local done: RunResult? = nil
		task.spawn(function()
			done = o.runner(plan.args)
		end)
		local waited = 0
		while done == nil and waited < serve.RETRY_WAIT do
			task.wait(0.05)
			waited += 0.05
		end
		local r = done :: RunResult?
		if r then
			return json(if r.ok then 200 else 500, { ok = r.ok, output = r.stdout .. r.stderr })
		end
		return json(202, { started = table.concat(plan.args, " ") })
	end

	local function handle(req: Request): Response
		local deny = serve.guard(req, o.port, token)
		if deny then
			return deny
		end
		if req.path == "/" then
			refreshGh()
			local markedJs = fs.readFile(`{board.TOP}/{board.MARKED_PATH}`) -- from the checkout, wherever it runs (c0120)
			return {
				status = 200,
				headers = { ["Content-Type"] = "text/html; charset=utf-8" },
				body = board.render(model(), markedJs),
			}
		elseif req.path == "/api/state" then
			refreshGh()
			local m = model()
			return json(200, { model = m, statsHtml = statsOf(m) })
		end
		return act(req)
	end

	local listen: (number, any) -> any = o.listen or (net.serve :: any)
	local handleRef = listen(o.port, {
		address = "http://127.0.0.1",
		handleRequest = function(req: any): any
			local ok, res = pcall(handle, req)
			if not ok then
				return text(500, `board --serve: {res}`)
			end
			return res
		end,
	})
	return {
		url = `http://127.0.0.1:{o.port}/?token={token}`,
		token = token,
		port = o.port,
		stop = function()
			(handleRef :: any):stop()
		end,
	}
end

return serve
