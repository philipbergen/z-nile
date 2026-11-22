--!strict
-- f0420 (the worker uses the live layer): a worker session registers itself in the live layer, beats at every
-- `./zn work next`, takes the claim of the unit its action names and gives it up at its next action. Everything here is
-- best effort and silent: with the layer off, absent, refusing or slow, `work next` answers exactly what it always did.
-- (livecall never raises and never waits past its budget; the first call of a process that fails ends the attempt, so a
-- dead layer costs one call, not one per step.)
--
-- Who the worker is, and nothing else is read to find out:
--   cli      ZN_CLI, else the one session variable a CLI sets (modelcmd.cliOf).
--   pid      ZN_WORKER_PID (the owner's word for ONE terminal: never export it for several), else the nearest ancestor process that is the CLI (found with `ps`, one hop at a time).
--   account  ZN_ACCOUNT, a short label the owner sets per terminal (`ZN_ACCOUNT=work claude`). It is checked against a
--            short safe pattern and dropped when it does not fit. It is never looked up: no token, no config file of the
--            CLI, no e-mail address is read to learn which account a terminal is.
--   can      what `./zn model --can` gives that CLI (models.canList).
-- The worker's id is the daemon's own, `<cli>-<pid>@<host>`: two terminals, or two accounts on one machine, run two
-- processes, so they are two workers.
--
-- The live claim and the durable claim. The durable claim (the `ready` commit, the `preparing` status, pushed to main) is
-- what says who owns a unit, across machines and restarts, and it always wins: the walk applies it first, and this module
-- only claims what the walk handed out, so a unit the durable claim denies is never claimed here. The live claim is the
-- fast and visible one of one machine: it keeps two workers on that machine from taking the same unit at once and shows
-- who is doing what; it is lost with the worker's process and never overrides the durable one.
local livecall = require("./livecall")
local liveemit = require("./liveemit")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local workerlive = {}

-- A worker's account label: a short word. The daemon checks the same pattern.
workerlive.LABEL = "^[A-Za-z0-9][A-Za-z0-9._-]*$"
workerlive.LABEL_MAX = 32

-- Processes between a worker's pid and `./zn` that are never the CLI: shells and the tools that start them.
local WRAPPERS: { [string]: boolean } = {
	sh = true,
	bash = true,
	zsh = true,
	dash = true,
	fish = true,
	ksh = true,
	lune = true,
	zn = true,
	env = true,
	perl = true,
	timeout = true,
	script = true,
	python = true,
	python3 = true,
	ps = true,
}

-- A process that finds the layer unusable stops asking it: the memory is liveemit's (one minute), shared, so one command
-- pays one failed budget however many of its steps talk to the layer.
local told: { [string]: boolean } = {} -- the hints this process has printed

-- One line on stderr, once per process per text.
local function say(text: string)
	if not told[text] then
		told[text] = true
		stdio.ewrite(`zn: {text}\n`)
	end
end

-- The label, or nil when it is empty or not a short safe word.
function workerlive.label(raw: string?): string?
	if
		raw == nil
		or raw == ""
		or #raw > workerlive.LABEL_MAX
		or string.match(raw, workerlive.LABEL) == nil
	then
		return nil
	end
	return raw
end

-- Processes that several terminals share: a pid taken from one of them would merge many panes into one worker.
local SHARED = {
	"tmux",
	"screen",
	"login",
	"sshd",
	"terminal",
	"iterm",
	"zellij",
	"ghostty",
	"kitty",
	"alacritty",
	"wezterm",
	"konsole",
	"xterm",
	"gnome-terminal",
	"launchd",
	"systemd",
	"init",
}

local function baseOf(name: string): string
	local base = string.lower(string.match(name, "([^/]+)$") or name)
	return (string.gsub(base, "^%-", "")) :: string
end

-- The pid of the CLI among `chain` (the nearest ancestor first): the first process named for the CLI, else the first that
-- is no shell or wrapper. When that one is a multiplexer, a terminal or a login (several terminals share it) there is no
-- pid, and the name is the second answer. Pure.
function workerlive.pickPid(chain: { { pid: number, name: string } }, cli: string): (number?, string?)
	for _, p in chain do
		local base = baseOf(p.name)
		if base == cli or string.find(base, cli, 1, true) ~= nil then
			return p.pid, nil
		end
	end
	for _, p in chain do
		local base = baseOf(p.name)
		if WRAPPERS[base] == nil then
			for _, shared in SHARED do
				if string.sub(base, 1, #shared) == shared then
					return nil, p.name
				end
			end
			return p.pid, nil
		end
	end
	return nil, nil
end

-- The chain of ancestors of this process, nearest first, at most twelve (a counted loop: a pid chain ends at 1).
local function ancestors(): { { pid: number, name: string } }
	local out: { { pid: number, name: string } } = {}
	local r = process.exec("sh", { "-c", "echo $PPID" })
	local pid = if r.ok then tonumber((string.match(r.stdout, "%d+"))) else nil
	for _ = 1, 12 do
		if pid == nil or pid <= 1 then
			break
		end
		local ps = process.exec("ps", { "-o", "ppid=,comm=", "-p", tostring(pid) })
		if not ps.ok then
			break
		end
		local parent, name = string.match(ps.stdout, "^%s*(%d+)%s+(.-)%s*$")
		if parent == nil or name == nil then
			break
		end
		table.insert(out, { pid = pid, name = name })
		pid = tonumber(parent)
	end
	return out
end

-- Who this session is, or nil when it cannot be told (no CLI named, no process to watch, a nested CLI of ./zn dispatch, a
-- process several terminals share): then it is not a worker. The second answer is a one-line hint for stderr, or nil.
export type Identity = { cli: string, pid: number, account: string? }

local function currentEnv(): { [string]: string? }
	return {
		ZN_CLI = process.env.ZN_CLI,
		CLAUDE_CODE_SESSION_ID = process.env.CLAUDE_CODE_SESSION_ID,
		KIMI_SESSION_ID = process.env.KIMI_SESSION_ID,
		GROK_SESSION_ID = process.env.GROK_SESSION_ID,
		ZN_ACCOUNT = process.env.ZN_ACCOUNT,
		ZN_WORKER_PID = process.env.ZN_WORKER_PID,
		ZN_DISPATCH = process.env.ZN_DISPATCH,
	}
end

-- `env` and `chain` are given by a spec; a command passes neither.
function workerlive.identify(
	env: { [string]: any }?,
	chain: { { pid: number, name: string } }?
): (Identity?, string?)
	local e = env or currentEnv()
	if (e.ZN_DISPATCH or "") ~= "" then
		return nil, nil -- a CLI ./zn dispatch started is the dispatching worker's step, not a worker of its own
	end
	local modelcmd = require("./modelcmd")
	local cli = modelcmd.cliOf(nil, e)
	if cli == nil or string.match(cli, workerlive.LABEL) == nil then
		return nil, nil
	end
	local pid: number? = nil
	local given = e.ZN_WORKER_PID
	if given ~= nil and given ~= "" then
		local n = tonumber(given)
		if n ~= nil and n >= 2 and n == math.floor(n) then
			pid = n
		end
	else
		local refused: string?
		pid, refused = workerlive.pickPid(chain or ancestors(), cli)
		if refused ~= nil then
			return nil,
				`this session's process looks like {refused}, which several terminals share, so it is not a worker. To make it one set ZN_WORKER_PID=<the pid of this terminal's {cli}> (one terminal only, never exported to several).`
		end
	end
	if pid == nil then
		return nil, nil
	end
	local raw = e.ZN_ACCOUNT
	local account = workerlive.label(raw)
	local hint: string? = nil
	if raw ~= nil and raw ~= "" and account == nil then
		hint =
			`ZN_ACCOUNT is not a short label (letters, digits, dot, dash or underscore, at most {workerlive.LABEL_MAX}): this terminal shows no account.`
	end
	return { cli = cli, pid = pid, account = account }, hint
end

-- The activity/level pairs this CLI can deliver (what `./zn model --can` prints), or none when the models file cannot be read.
local function canOf(cli: string): { string }
	local ok, list = pcall(function(): { string }
		local models = require("./models")
		local sh = require("../lib/sh")
		local layers = models.walkAt(".", function(rel: string): string?
			local shown = sh.run("git", { "show", `origin/main:{rel}` })
			return if shown.ok then shown.stdout else nil
		end, function(): boolean
			return false
		end)
		return models.canList(layers, cli)
	end)
	return if ok then list else {}
end

-- One call; the first that fails ends the attempt for this process (and, through liveemit, for its other layer calls).
local function call(op: string, args: { string }): (number, livecall.Reply?)
	if not liveemit.available() then
		return livecall.UNAVAILABLE, nil
	end
	local code, reply = livecall.run(op, args)
	if code == livecall.UNAVAILABLE or code == livecall.TIMEOUT or code == 2 then
		liveemit.markGone()
	end
	return code, reply
end

export type Me = {
	worker: string,
	others: { [string]: string }, -- unit -> the other worker that holds it
	mine: { unit: string, activity: string }?, -- what this worker holds now
}

-- Registers this session (idempotent) and returns its id, or nil. The binary is looked for before anything is run (ps, git).
function workerlive.register(): string?
	if livecall.off() or not liveemit.available() then
		return nil
	end
	local ok, id = pcall(function(): string?
		local me, hint = workerlive.identify()
		if hint ~= nil then
			say(hint)
		end
		if me == nil then
			return nil
		end
		local args = { "--cli", me.cli, "--pid", tostring(me.pid), "--mode", "session" }
		local can = canOf(me.cli)
		if #can > 0 then
			table.insert(args, "--can")
			table.insert(args, table.concat(can, ","))
		end
		local withLabel = table.clone(args)
		if me.account ~= nil then
			table.insert(withLabel, "--account")
			table.insert(withLabel, me.account)
		end
		local code, reply = livecall.run("register", withLabel)
		if code == 2 and me.account ~= nil then
			-- an older daemon binary does not know --account: register without the label and say how to rebuild
			say(
				"the live daemon is older than ZN_ACCOUNT: this terminal is registered without its account. Rebuild it with ./zn live build."
			)
			code, reply = livecall.run("register", args)
		end
		if code ~= 0 or reply == nil or type(reply.worker) ~= "string" then
			liveemit.markGone()
			return nil
		end
		return reply.worker :: string
	end)
	return if ok then id :: string? else nil
end

-- The worker id a dispatching worker handed this session (ZN_WORKER): the session is that worker's step, so it registers
-- nothing and beats, claims and releases under that id. nil when none is given or it is not a plain id.
function workerlive.assigned(): string?
	local given = process.env.ZN_WORKER
	if
		given == nil
		or given == ""
		or #given > 128
		or string.match(given, "^[A-Za-z0-9][A-Za-z0-9._@:/-]*$") == nil
	then
		return nil
	end
	return given
end

-- Registers, beats the heartbeat and reads who holds what. nil: this session is not a worker, or the layer did not answer.
function workerlive.join(): Me?
	local ok, me = pcall(function(): Me?
		local id = workerlive.assigned() or workerlive.register()
		if id == nil then
			return nil
		end
		call("beat", { "--worker", id })
		local code, reply = call("claims", {})
		if code ~= 0 or reply == nil or type(reply.claims) ~= "table" then
			return nil
		end
		local out: Me = { worker = id, others = {} }
		for _, c in reply.claims :: { any } do
			if type(c) == "table" and type(c.unit) == "string" and type(c.worker) == "string" then
				if c.worker == id then
					out.mine = {
						unit = c.unit :: string,
						activity = if type(c.activity) == "string" then c.activity else "",
					}
				else
					out.others[c.unit :: string] = c.worker :: string
				end
			end
		end
		return out
	end)
	return if ok then me :: Me? else nil
end

-- The unit and the activity an answer asks the worker to hold; nil for a stop, a wait or a nothing.
function workerlive.claimable(
	d: { raft: string, ticket: string, action: string, owed: any? }
): (string?, string?)
	local idle = d.action == "end" or d.action == "wait" or d.action == "none" or d.action == "release"
	if idle or d.owed ~= nil then
		return nil, nil
	end
	local unit = if d.raft ~= "" then d.raft else d.ticket
	if unit == "" or string.match(d.action, "^[A-Za-z0-9][A-Za-z0-9._-]*$") == nil then
		return nil, nil
	end
	return unit, d.action
end

local function release(me: Me, outcome: string)
	if me.mine ~= nil then
		call("release", { "--worker", me.worker, "--outcome", outcome })
		me.mine = nil
	end
end

local MAX_TRIES = 4 -- another worker may win the same unit more than once in a row: bounded, never a loop that waits

-- `work.decide(input)` for a worker of the live layer: the units other workers hold are left to them, the unit the answer
-- names is claimed before it is printed, and the claim of the worker's previous action is given up. Without the layer it
-- is `work.decide(input)` itself.
function workerlive.decide(workLib: any, input: any): any
	local me = workerlive.join()
	if me == nil then
		return workLib.decide(input)
	end
	local held = me.others
	local ok, decision = pcall(function(): any
		local named = input.asked ~= nil and input.asked ~= ""
		local lastHolder: string? = nil
		for _ = 1, MAX_TRIES do
			-- the units others hold go in as claims: not candidates, but still facts (a missing fact reads as landed)
			if next(held) ~= nil then
				input.claims = held
			end
			local d = workLib.decide(input)
			local unit, activity = workerlive.claimable(d)
			if unit == nil or activity == nil then
				release(me, "done")
				if d.owed == nil and next(held) ~= nil and (d.action == "none" or d.action == "wait") then
					-- nothing for this worker: say who holds what, and how a gone worker's unit is freed
					local live = require("./liveview").slim(livecall.snapshot())
					if live ~= nil then
						local lines = require("./liveview").heldLines(live, me.worker, false)
						if #lines > 0 and not string.find(d.why, " is held by ", 1, true) then
							d.why = `{d.why} Held by other workers: {table.concat(lines, "; ")}.`
						end
					end
				end
				return d
			end
			local holder = held[unit]
			if holder == nil then
				if me.mine ~= nil and (me.mine.unit ~= unit or me.mine.activity ~= activity) then
					release(me, "done")
				end
				local args = { "--worker", me.worker, "--unit", unit, "--activity", activity }
				if d.raft ~= "" then
					table.insert(args, "--raft")
					table.insert(args, d.raft)
				end
				if d.layer ~= "" then
					table.insert(args, "--step")
					table.insert(args, d.layer)
				end
				local code, reply = call("claim", args)
				if code == 0 then
					return d
				elseif
					code == 1
					and reply ~= nil
					and reply.refused == "held"
					and type(reply.holder) == "string"
				then
					holder = reply.holder :: string
					held[unit] = holder
				else
					return d -- the layer could not say: the answer stands, as it always did
				end
			end
			lastHolder = holder
			if named and (input.asked == unit or input.one) then
				break -- the one unit asked for is held: nothing else is on offer
			end
		end
		release(me, "done")
		local unit = ""
		for u, w in held do
			if w == lastHolder then
				unit = u
			end
		end
		return {
			raft = unit,
			layer = "",
			ticket = "",
			action = "wait",
			why = `{unit} is held by {lastHolder or "another worker"}: ask again when it has finished`,
		}
	end)
	input.claims = nil
	if not ok then
		return workLib.decide(input)
	end
	return decision
end

-- The heartbeat of a worker's other zn commands (a long build runs many): one call, only when this session is a worker, never
-- when the layer is off or failed, never starting a daemon, never failing the command.
function workerlive.beat()
	if livecall.off() or not liveemit.available() then
		return
	end
	pcall(function()
		local args: { string }
		local id = workerlive.assigned()
		if id ~= nil then
			args = { "--worker", id }
		else
			local me = workerlive.identify()
			if me == nil then
				return
			end
			args = { "--cli", me.cli, "--pid", tostring(me.pid) }
		end
		-- A side call must not write to the layer-is-down memory the command's real work reads (its events, its release): the
		-- beat never starts a daemon, and a refusal, an older binary or a missing daemon is nothing it reports.
		local before = process.env.ZN_LIVE_NO_START
		process.env.ZN_LIVE_NO_START = "1"
		local ok = pcall(livecall.run, "beat", args)
		process.env.ZN_LIVE_NO_START = before
		if not ok then
			return
		end
	end)
end

-- Gives up the live claim on `unit` (a raft landed, a raft or an issue stopped), whoever holds it. Never raises.
function workerlive.releaseUnit(unit: string, outcome: string)
	if livecall.off() or not liveemit.available() then
		return
	end
	pcall(function()
		local code, reply = call("claims", {})
		if code ~= 0 or reply == nil or type(reply.claims) ~= "table" then
			return
		end
		for _, c in reply.claims :: { any } do
			if type(c) == "table" and c.unit == unit and type(c.worker) == "string" then
				call("release", { "--worker", c.worker :: string, "--unit", unit, "--outcome", outcome })
			end
		end
	end)
end

return workerlive
