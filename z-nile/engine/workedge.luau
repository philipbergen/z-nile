--!strict
-- The worker's edge (c0253): builds the `World` workloop.luau runs on from `./zn` commands, the flock, the clock and the
-- state folder `.cache/work/` of the MAIN checkout, and holds `run`, `detach`, `stop` and `status`. It starts no model:
-- a pick is run by `./zn dispatch <id> --worker`, a child of this checkout's own engine, started with the starter's
-- markers and session ids cleared. Reading and writing live here (zz-arch rule 4); the order of the turns is workloop's.
local fs = require("@lune/fs")
local models = require("./models")
local process = require("@lune/process")
local runner = require("./runner")
local sh = require("../lib/sh")
local supervise = require("./supervise")
local task = require("@lune/task")
local workloop = require("./workloop")

local workedge = {}

workedge.DIR = ".cache/work"

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- The main checkout: `git worktree list`'s first entry (as c0252 resolves it), physical.
function workedge.mainRoot(): string
	local listed = sh.run("git", { "worktree", "list", "--porcelain" })
	local first = string.match(listed.stdout, "^worktree ([^\n]+)")
	if not listed.ok or not first then
		error("could not find the main checkout (git worktree list)", 0)
	end
	return trim(process.exec("sh", { "-c", 'cd "$1" && pwd -P', "_", first }).stdout)
end

local function here(): string
	return trim(process.exec("pwd", { "-P" }).stdout)
end

-- Inside a check run only a CLI under .cache may start; a `--detach` never starts in one (supervise.refusal).
local function checking(): boolean
	local ok, r = pcall(process.exec, "bash", {
		"-c",
		"[ -f z-nile/lib/fence.sh ] || exit 3; source z-nile/lib/fence.sh && pickman_checking",
	})
	return not (ok and r.ok and trim(r.stdout) == "free")
end

local function alive(pid: number): boolean
	return process.exec("kill", { "-0", tostring(pid) }).ok
end

local function dir(top: string): string
	return `{top}/{workedge.DIR}`
end

function workedge.readState(top: string): supervise.State?
	local path = `{dir(top)}/state`
	if not fs.isFile(path) then
		return nil
	end
	return supervise.parseState(fs.readFile(path))
end

-- The user's own host settings, outside the repository: ZN_HOST_CONFIG, else ~/.config/zn/host.toml.
local function hostText(): string?
	local path = process.env.ZN_HOST_CONFIG
	if path == nil or path == "" then
		path = `{process.env.HOME or ""}/.config/zn/host.toml`
	end
	return if fs.isFile(path :: string) then fs.readFile(path :: string) else nil
end

-- Each role the worker runs, with the CLIs it tries in order, from `.models.toml` as origin/main has it (never the working
-- tree, zz-arch rule 7). Only the repository root's file is read here; a closer file can only replace a field.
local function rolesTries(top: string): { [string]: { string } }
	local shown = process.exec("git", { "show", "origin/main:.models.toml" }, { cwd = top })
	local out: { [string]: { string } } = {}
	if not shown.ok then
		return out
	end
	local ok, layer = pcall(models.parse, shown.stdout, "origin/main:.models.toml")
	if not ok then
		return out
	end
	for _, role in { "implementation", "design", "raft" } do
		local resolved = pcall(models.resolveRole, { layer :: models.Layer }, role)
		if resolved then
			local r = models.resolveRole({ layer :: models.Layer }, role)
			out[role] = r.order
		end
	end
	return out
end

function workedge.statusLines(top: string): { string }
	local s = workedge.readState(top)
	if not s then
		return {}
	end
	local log = `{dir(top)}/log`
	local ended = fs.isFile(log) and string.find(fs.readFile(log), "worker stopped:", 1, true) ~= nil
	return { supervise.statusLine(s, s.state ~= "stopped" and alive(s.pid), ended) }
end

-- `./zn work stop`: ask the live supervisor to end after its current dispatch run.
function workedge.stop(top: string): string
	local s = workedge.readState(top)
	if not s or s.state == "stopped" or not alive(s.pid) then
		return "no supervisor runs in this checkout"
	end
	fs.writeDir(dir(top))
	fs.writeFile(`{dir(top)}/stop`, "stop\n")
	local held = if s.held ~= "" then `; {s.held} stays held, ./zn work run resumes it` else ""
	return `stop asked: supervisor pid {s.pid} ends after its current dispatch run{held}`
end

-- Starts the supervisor detached (Q12): the same command without --detach, in a session of its own, its output in
-- `.cache/work/log`. The supervisor's own CPU limit is `ZN_ENGINE_CPU` (zn's default 1800 s): it sleeps almost always, so
-- that is weeks of waiting (G13).
function workedge.detach(top: string, raw: { string }): string
	fs.writeDir(dir(top))
	local argv = supervise.detachArgv(`{top}/zn`, raw, `{dir(top)}/log`, process.env :: { [string]: string? })
	local cmd = table.remove(argv, 1) :: string
	local r = process.exec(cmd, argv, { cwd = top })
	if not r.ok then
		error(`could not start the supervisor: {trim(r.stderr)}`, 0)
	end
	return `supervisor started, detached: ./zn work status shows it, ./zn work stop ends it, its log is {workedge.DIR}/log`
end

local function sleepSlices(state: string, seconds: number)
	local left = seconds
	for _ = 1, math.ceil(seconds) do
		if fs.isFile(`{state}/stop`) then
			return
		end
		task.wait(math.min(1, left))
		left -= 1
	end
end

-- The World of the main checkout `top`.
function workedge.world(top: string, cli: string?, noRun: boolean, held: string): workloop.World
	local state = dir(top)
	fs.writeDir(state)
	local locks: { [string]: any } = {}
	local started = os.date("%Y-%m-%d %H:%M:%S") :: string
	local pid = tonumber(trim(process.exec("sh", { "-c", "echo $PPID" }).stdout)) or 0
	local function zn(args: { string }, forward: boolean): process.ExecResult
		local argv = supervise.cleanArgv(process.env :: { [string]: string? }, `{top}/zn`, args)
		local cmd = table.remove(argv, 1) :: string
		if forward then
			return process.exec(cmd, argv, { cwd = top, stdio = { stdout = "forward", stderr = "forward" } })
		end
		return process.exec(cmd, argv, { cwd = top })
	end
	return {
		next = function()
			local r = zn({ "next" }, false)
			return r.stdout, r.stderr, r.code
		end,
		dispatch = function(args: { string }): number
			return zn(args, true).code
		end,
		lock = function(id: string): boolean
			local got = runner.holdLock(`{state}/{id}.lock`)
			if got then
				locks[id] = got
				return true
			end
			return false
		end,
		unlock = function(id: string)
			local got = locks[id]
			if got then
				got:kill()
				locks[id] = nil
			end
		end,
		now = function(): number
			return os.time()
		end,
		sleep = function(seconds: number)
			sleepSlices(state, seconds)
		end,
		stopped = function(): boolean
			return fs.isFile(`{state}/stop`)
		end,
		state = function(s: supervise.State)
			local filled = table.clone(s)
			filled.pid = pid
			filled.since = started
			pcall(sh.writeReplacing, `{state}/state`, supervise.stateText(filled))
		end,
		say = function(line: string)
			print(line)
		end,
		held = held,
		cli = cli,
		noRun = noRun,
		idleSeconds = nil,
	}
end

-- Runs the supervisor in the foreground, in the main checkout. Returns the summary, or the reason it did not start.
function workedge.run(
	opts: workloop.Options & { cli: string?, detach: boolean }
): (supervise.Summary?, string?)
	local top = workedge.mainRoot()
	local refused = supervise.refusal({
		headless = process.env.ZN_HEADLESS,
		dispatch = process.env.ZN_DISPATCH,
		checking = checking(),
		detach = opts.detach,
		here = here(),
		main = top,
	})
	if refused then
		return nil, refused
	end
	local cli = opts.cli or supervise.starterCli(process.env :: { [string]: string? })
	if cli and cli ~= "" then
		if not supervise.RESUME[cli] then
			return nil, `--cli {cli} is not a supported CLI ({table.concat(models.CLIS, ", ")})`
		end
		local problem = supervise.cliProblem(cli, rolesTries(top))
		if problem then
			return nil, problem
		end
	end
	fs.writeDir(dir(top))
	local lock = runner.holdLock(`{dir(top)}/supervisor.lock`)
	if not lock then
		return nil, "a supervisor already runs in this clone (./zn work status, ./zn work stop)"
	end
	pcall(fs.removeFile, `{dir(top)}/stop`)
	local before = workedge.readState(top)
	local held = if before then before.held else ""
	local world = workedge.world(top, cli, not supervise.hostLand(hostText()), held)
	local summary = workloop.run(world, { once = opts.once, maxItems = opts.maxItems })
	lock:kill()
	return summary, nil
end

return workedge
