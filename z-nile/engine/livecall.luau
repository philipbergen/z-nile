--!strict
-- The one Luau caller of the live layer (f0424, Who emits what): it runs the `znlive` binary and nothing else here
-- knows how to reach the daemon. It is non-fatal by contract. Every function returns a result and never raises, whatever
-- the daemon does: absent (no binary: one stat, code 3), dying mid-call, or slow (a call is killed after `timeout`
-- seconds, 2 by default, and answers code 3). So an event or a poke never blocks or fails a tracker command.
--   livecall.run(op, args, timeout?) -> (code, reply?)   code is znlive's exit code (0 done, 1 refused, 2 usage,
--                                                          3 unavailable, 75 timed out); reply is the first stdout line
--                                                          as JSON, when it is one
--   livecall.emit(kind, fields) -> (code, ignored field names) / livecall.poke(reason, ref) -> code
--   (a code outside 0, 1, 2, 3 and 75, say a killed child's, is answered as 3)
--   livecall.snapshot() -> { ok, at, workers, claims } or { ok = false, reason }
-- ZN_LIVE=off turns the whole layer off in this process and its children: every call answers code 3 at once, with no
-- binary lookup and no process. The check fence sets it for every spec and every check.sh (lib/fence.sh), so a tracker
-- command run by a check never reaches a daemon; a spec of the live layer sets ZN_LIVE to nothing (tests/lib/live.luau).
-- The binary is ZN_LIVE_BIN, else <main checkout>/.cache/bin/znlive: the main checkout is ZN_LIVE_ROOT, else the first
-- folder with a .git found from ZN_TOP or the current folder (a worktree's .git file leads to the main checkout). A
-- caller never builds: `./zn live build` and `./zn live <op>` do.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local livecall = {}

export type Reply = { [string]: any }

livecall.UNAVAILABLE = 3
livecall.TIMEOUT = 75
livecall.ONE_SHOT = 2 -- seconds a one-shot op may take

local LIVE_ENV = {
	"ZN_LIVE_DIR",
	"ZN_LIVE_ROOT",
	"ZN_LIVE_BIN",
	"ZN_WORKER",
	"ZN_LIVE_LOST_AFTER",
	"ZN_LIVE_EXPIRE_AFTER",
	"ZN_LIVE_IDLE_EXIT",
	"ZN_LIVE_ALLOW_DEFAULT",
	"ZN_LIVE_SOCKDIR",
}

-- True when the layer is turned off here (ZN_LIVE=off).
function livecall.off(): boolean
	return process.env.ZN_LIVE == "off"
end

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- The main checkout above `start`: the first folder with a .git folder, or a .git file that leads to the main one.
local function mainCheckout(start: string): string?
	local dir = start
	-- a path has far fewer than 256 folders, so the climb is counted and cannot go on forever
	for _ = 1, 256 do
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
	return nil
end

-- The binary's path, or nil when it does not exist.
function livecall.binary(): string?
	if livecall.off() then
		return nil
	end
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
	-- the child gets the environment this process holds, edits included (an edit of process.env does not reach a Lune child
	-- by itself), so the binary sees every marker its own guards read (a check, a probe under ./zn run) without this file
	-- naming them
	local env: { [string]: string } = {}
	for name, v in process.env do
		if type(v) == "string" then
			env[name] = v
		end
	end
	for _, name in LIVE_ENV do
		local v = process.env[name]
		if v ~= nil then
			env[name] = v
		end
	end
	-- stdout goes to a file, not a pipe: a descendant of the binary that keeps the pipe open (a daemon it started) would keep a
	-- read blocked past the timeout; a file cannot, and the child itself is what the timeout kills
	local tmp = process.env.TMPDIR
	if tmp == nil or tmp == "" then
		tmp = "/tmp"
	end
	local outFile =
		`{string.gsub(tmp :: string, "/+$", "")}/zn-livecall-{os.time()}-{math.random(1, 1000000000)}`
	-- The time limit is the binary's own: it gets the budget in ZN_LIVE_CALL_BUDGET and ends itself with exit 3 when a call
	-- has not finished by then (a stopped daemon accepts a connection and never answers). Nothing here waits on a timer: Lune
	-- keeps a cancelled task.delay alive, so every command that made one call would wait out the whole timeout (f0424 E8),
	-- and Go ignores the SIGALRM of a perl wrapper.
	env.ZN_LIVE_CALL_BUDGET = string.format("%g", timeout)
	local shArgs = { "-c", 'out=$1; shift; exec "$@" >"$out"', "sh", outFile, bin }
	for _, a in argv do
		table.insert(shArgs, a)
	end
	local child = process.create(
		"sh",
		shArgs,
		{ env = env, stdio = { stdin = "none", stdout = "none", stderr = "none" } } :: any
	)
	local status = child:status()
	local readOk, out = pcall(fs.readFile, outFile)
	pcall(fs.removeFile, outFile)
	if not readOk then
		out = ""
	end
	local code = status.code
	if code ~= 0 and code ~= 1 and code ~= 2 and code ~= 3 and code ~= 75 then
		return livecall.UNAVAILABLE, nil -- killed, crashed or an exit nobody defined: the layer is unavailable
	end
	local reply: Reply? = nil
	local first = string.match(out, "^[^\n]+")
	if first ~= nil then
		local ok, decoded = pcall(serde.decode, "json" :: "json", first)
		if ok and type(decoded) == "table" then
			reply = decoded :: Reply
		end
	end
	if code == 1 and reply == nil then
		return livecall.UNAVAILABLE, nil -- a refusal always carries its JSON line; exit 1 without one is not the daemon's
	end
	return code, reply
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

-- The fields an emit may carry: the event fields the Design names (the daemon fills seq, at, host and the worker's cli).
livecall.FIELDS = {
	worker = true,
	cli = true,
	unit = true,
	activity = true,
	raft = true,
	project = true,
	tributary = true,
	risk = true,
	round = true,
	model = true,
	outcome = true,
	tokens = true,
	seconds = true,
	wall = true,
	ref = true,
} :: { [string]: boolean }

-- `emit <kind> --<field> <value>...`, fields in sorted order; a field with an empty value is left out, a number is rounded to
-- an integer (tokens and seconds are whole numbers), and a field that is not one of FIELDS is ignored. Returns the code and
-- the list of ignored field names (empty when none).
function livecall.emit(kind: string, fields: { [string]: any }?): (number, { string })
	local args = { kind }
	local given: { [string]: any } = fields or {}
	local names: { string } = {}
	local ignored: { string } = {}
	for name in given do
		table.insert(if livecall.FIELDS[name] then names else ignored, name)
	end
	table.sort(names)
	table.sort(ignored)
	for _, name in names do
		local v = given[name]
		if type(v) == "number" then
			v = string.format("%d", math.floor(v + 0.5))
		end
		if v ~= "" and v ~= nil then
			table.insert(args, `--{name}`)
			table.insert(args, tostring(v))
		end
	end
	local code = livecall.run("emit", args)
	return code, ignored
end

-- The daemon refuses free text over 500 bytes or with a control character: a reason is cleaned first (control characters
-- become spaces) and cut to 500 bytes at a character boundary, never inside a UTF-8 sequence.
function livecall.clip(text: string): string
	local clean = string.gsub(text, "%c", " ")
	if #clean <= 500 then
		return clean
	end
	local cut = 500
	-- a byte 0x80-0xBF continues the character before it: step back to where that character starts
	-- (a UTF-8 character has at most three continuation bytes)
	for _ = 1, 3 do
		local b = string.byte(clean, cut + 1)
		if b == nil or b < 0x80 or b >= 0xC0 then
			break
		end
		cut -= 1
	end
	return string.sub(clean, 1, cut)
end

-- A wake for every waiter: `poke --reason <r> --ref <sha>`. Never starts a daemon (znlive's own rule).
function livecall.poke(reason: string?, ref: string?): number
	local args: { string } = {}
	if reason ~= nil and reason ~= "" then
		table.insert(args, "--reason")
		table.insert(args, livecall.clip(reason))
	end
	if ref ~= nil and ref ~= "" then
		table.insert(args, "--ref")
		table.insert(args, ref)
	end
	local code = livecall.run("poke", args)
	return code
end

export type Snapshot = {
	ok: boolean,
	at: number?,
	workers: { any }?,
	claims: { any }?,
	losses: { any }?,
	reason: string?,
}

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
	-- an older daemon has no losses op: the list is then empty, the rest still shown
	local lcode, lost = livecall.run("losses", {})
	return {
		ok = true,
		at = os.time(),
		workers = workers.workers :: { any },
		claims = claims.claims :: { any },
		losses = if lcode == 0
				and lost ~= nil
				and type(lost.losses) == "table"
			then lost.losses :: { any }
			else {},
	}
end

return livecall
