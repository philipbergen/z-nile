--!strict
-- The one Luau caller of the live layer (f0424, Who emits what): it runs the `znlive` binary and nothing else here
-- knows how to reach the daemon. It is non-fatal by contract. Every function returns a result and never raises, whatever
-- the daemon does: absent (no binary: one stat, code 3), dying mid-call, or slow (a call is killed after `timeout`
-- seconds, 2 by default, and answers code 3). So an event or a poke never blocks or fails a tracker command.
--   livecall.run(op, args, timeout?) -> (code, reply?)   code is znlive's exit code (0 done, 1 refused, 2 usage,
--                                                          3 unavailable, 75 timed out); reply is the first stdout line
--                                                          as JSON, when it is one
--   livecall.emit(kind, fields) / livecall.poke(reason, ref) -> code
--   livecall.snapshot() -> { ok, at, workers, claims } or { ok = false, reason }
-- The binary is ZN_LIVE_BIN, else <main checkout>/.cache/bin/znlive: the main checkout is ZN_LIVE_ROOT, else the first
-- folder with a .git found from ZN_TOP or the current folder (a worktree's .git file leads to the main checkout). A
-- caller never builds: `./zn live build` and `./zn live <op>` do.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local livecall = {}

export type Reply = { [string]: any }

livecall.UNAVAILABLE = 3
livecall.TIMEOUT = 75
livecall.ONE_SHOT = 2 -- seconds a one-shot op may take

local LIVE_ENV =
	{ "ZN_LIVE_DIR", "ZN_LIVE_ROOT", "ZN_LIVE_BIN", "ZN_WORKER", "ZN_LIVE_LOST_AFTER", "ZN_LIVE_IDLE_EXIT" }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- The main checkout above `start`: the first folder with a .git folder, or a .git file that leads to the main one.
local function mainCheckout(start: string): string?
	local dir = start
	while true do
		local git = `{dir}/.git`
		if fs.isDir(git) then
			return dir
		end
		if fs.isFile(git) then
			local gitdir = string.match(fs.readFile(git), "gitdir:%s*([^\n]+)")
			if gitdir == nil then
				return nil
			end
			gitdir = trim(gitdir)
			if string.sub(gitdir, 1, 1) ~= "/" then
				gitdir = `{dir}/{gitdir}`
			end
			local common = trim(fs.readFile(`{gitdir}/commondir`))
			if string.sub(common, 1, 1) ~= "/" then
				common = `{gitdir}/{common}`
			end
			return (string.match(common, "^(.*)/[^/]+/?$")) -- the folder that holds the common .git
		end
		local up = string.match(dir, "^(.*)/[^/]+$")
		if up == nil or up == dir then
			return nil
		end
		dir = up
	end
end

-- The binary's path, or nil when it does not exist.
function livecall.binary(): string?
	local ok, found = pcall(function(): string?
		local given = process.env.ZN_LIVE_BIN
		if given ~= nil and given ~= "" then
			return if fs.isFile(given) then given else nil
		end
		local root = process.env.ZN_LIVE_ROOT
		if root == nil or root == "" then
			local start = process.env.ZN_TOP
			if start == nil or start == "" then
				start = process.cwd
			end
			root = mainCheckout((string.gsub(start :: string, "/+$", "")))
		end
		if root == nil then
			return nil
		end
		local bin = `{root}/.cache/bin/znlive`
		return if fs.isFile(bin) then bin else nil
	end)
	return if ok then found else nil
end

local function runUnsafe(op: string, args: { string }, timeout: number): (number, Reply?)
	local bin = livecall.binary()
	if bin == nil then
		return livecall.UNAVAILABLE, nil
	end
	local argv = { op }
	for _, a in args do
		table.insert(argv, a)
	end
	-- the variables znlive reads, passed as this process holds them (an edit of process.env does not reach a child by itself)
	local env: { [string]: string } = {}
	for _, name in LIVE_ENV do
		local v = process.env[name]
		if v ~= nil then
			env[name] = v
		end
	end
	local child = process.create(bin, argv, { env = env, stdio = { stdin = "none", stderr = "none" } } :: any)
	local timedOut = false
	local timer = task.delay(timeout, function()
		timedOut = true
		child:kill()
	end)
	local out = child.stdout:readToEnd()
	local status = child:status()
	task.cancel(timer)
	if timedOut then
		return livecall.UNAVAILABLE, nil
	end
	local reply: Reply? = nil
	local first = string.match(out, "^[^\n]+")
	if first ~= nil then
		local ok, decoded = pcall(serde.decode, "json" :: "json", first)
		if ok and type(decoded) == "table" then
			reply = decoded :: Reply
		end
	end
	return status.code, reply
end

-- Runs one op; never raises. Code 3 for no binary, a call that took longer than `timeout` seconds, or any failure
-- of this module's own.
function livecall.run(op: string, args: { string }, timeout: number?): (number, Reply?)
	local ok, code, reply = pcall(runUnsafe, op, args, timeout or livecall.ONE_SHOT)
	if not ok then
		return livecall.UNAVAILABLE, nil
	end
	return code :: number, reply :: Reply?
end

-- `emit <kind> --<field> <value>...`, fields in sorted order; a field with a nil or empty value is left out.
function livecall.emit(kind: string, fields: { [string]: any }?): number
	local args = { kind }
	local given: { [string]: any } = fields or {}
	local names: { string } = {}
	for name in given do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local v = given[name]
		if v ~= "" then
			table.insert(args, `--{name}`)
			table.insert(args, tostring(v))
		end
	end
	local code = livecall.run("emit", args)
	return code
end

-- A wake for every waiter: `poke --reason <r> --ref <sha>`. Never starts a daemon (znlive's own rule).
function livecall.poke(reason: string?, ref: string?): number
	local args: { string } = {}
	if reason ~= nil and reason ~= "" then
		table.insert(args, "--reason")
		table.insert(args, reason)
	end
	if ref ~= nil and ref ~= "" then
		table.insert(args, "--ref")
		table.insert(args, ref)
	end
	local code = livecall.run("poke", args)
	return code
end

export type Snapshot = { ok: boolean, at: number?, workers: { any }?, claims: { any }?, reason: string? }

-- The workers and the claims as the daemon holds them, and the time they were taken; or why they are unavailable.
function livecall.snapshot(): Snapshot
	local wcode, workers = livecall.run("workers", {})
	if wcode ~= 0 or workers == nil or type(workers.workers) ~= "table" then
		return { ok = false, reason = "live layer not running" }
	end
	local ccode, claims = livecall.run("claims", {})
	if ccode ~= 0 or claims == nil or type(claims.claims) ~= "table" then
		return { ok = false, reason = "live layer not running" }
	end
	return {
		ok = true,
		at = os.time(),
		workers = workers.workers :: { any },
		claims = claims.claims :: { any },
	}
end

return livecall
