--!strict
-- The live layer's spec helper (f0424). Every daemon a spec starts lives in the spec's own fixture under .cache: its state
-- directory is <fixture>/repo/.cache/live, its binary is this checkout's own build (ZN_LIVE_BIN; the gate makes it, and
-- the helper refuses naming `./zn live build` when it is missing), its idle limit is short (a flag, never an
-- environment variable), and ZN_LIVE_DIR is set in every command, so a missing argument can never reach the real
-- repository's live state. `live.with` always shuts the daemon down and waits for it, and fails the spec when a znlive
-- process that was started for the fixture is still alive afterwards.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")

local live = {}

export type Result = fixture.Result
export type Live = {
	root: string, -- the checkout under test
	base: string, -- <home>/.cache/<name>
	repo: string, -- a fixture git repository: the cwd of every op
	state: string, -- the state directory
	bin: string, -- the built znlive
	env: { [string]: string },
	zn: (self: Live, args: { string }, cwd: string?) -> Result, -- `./zn live <args>` with the short flags
	znRaw: (self: Live, args: { string }, cwd: string?, env: { [string]: string }?) -> Result, -- `./zn live <args>` as given
	together: (self: Live, jobs: { { string } }) -> { Result }, -- the jobs, started at the same instant
	pids: (self: Live) -> { number }, -- znlive processes started for this fixture
	started: { number }, -- every daemon pid seen (for the leak check)
}

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)

-- The binary the gate builds for this checkout. Raises naming the fix when it is missing.
function live.binary(): string
	local bin = `{root}/.cache/bin/znlive`
	if not fs.isFile(bin) then
		error(`live spec: {bin} is not built: run ./zn live build (the gate does it)`, 3)
	end
	return bin
end

local function alive(pid: number): boolean
	return process.exec("kill", { "-0", tostring(pid) }).ok
end

-- The pids of znlive processes whose command line names this fixture's base folder. `pgrep`, not `ps`: the spec jail
-- cannot run ps (a setuid program), and the daemon itself reads the kernel's process table for that reason.
local function daemonsOf(base: string): { number }
	local pattern = "znlive.* " .. (string.gsub(base, "[^%w/_%-]", "\\%0"))
	local r = process.exec("pgrep", { "-f", pattern })
	local out: { number } = {}
	for line in string.gmatch(r.stdout, "%d+") do
		table.insert(out, tonumber(line) :: number)
	end
	return out
end

-- The environment of every op: the checkout's own binary, the fixture's state, and nothing that changes the daemon's timing.
local function baseEnv(bin: string, state: string): { [string]: string }
	return {
		ZN_LIVE_BIN = bin,
		ZN_LIVE_DIR = state,
		ZN_LIVE_ROOT = "",
		ZN_LIVE_SOCKDIR = "",
		ZN_LIVE_DIR_IS_DEFAULT = "",
		ZN_WORKER = "",
		ZN_LIVE_LOST_AFTER = "",
		ZN_LIVE_IDLE_EXIT = "",
		CLAUDE_CODE_SESSION_ID = "",
		KIMI_SESSION_ID = "",
		GROK_SESSION_ID = "",
	}
end

-- A fixture named `name` (no other spec file uses it): an empty git repository with the state beside it, under .cache.
function live.new(name: string, opts: { noDirEnv: boolean? }?): Live
	local bin = live.binary()
	local home = fixture.physical(".") :: string
	local base = `{home}/.cache/{name}`
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(base)
	local repo = `{base}/repo`
	fs.writeDir(repo)
	local init = process.exec("git", { "init", "-q", "-b", "main", repo })
	if not init.ok then
		error(`git init {repo} failed: {init.stderr}`, 2)
	end
	fixture.git(repo, { "config", "user.name", name })
	fixture.git(repo, { "config", "user.email", `{name}@example.invalid` })
	local state = `{repo}/.cache/live`
	local env = baseEnv(bin, state)
	if opts and opts.noDirEnv then
		env.ZN_LIVE_DIR = "" -- the daemon finds <repo>/.cache/live from the folder it is run in: inside the fixture
		-- that is the default state directory, whose socket would go to the user's temp folder, closed in the jail: it stays
		-- in this run's TMPDIR (the test-only switch), and the timing flags are refused for it (the daemon's own limits apply)
		env.ZN_LIVE_SOCKDIR = process.env.TMPDIR or "/tmp"
	end
	local self: Live = {
		root = root,
		base = base,
		repo = repo,
		state = state,
		bin = bin,
		env = env,
		started = {},
	} :: any
	function self.znRaw(this: Live, args: { string }, cwd: string?, extra: { [string]: string }?): Result
		local argv = { `{root}/zn`, "live" }
		for _, a in args do
			table.insert(argv, a)
		end
		local e = table.clone(this.env)
		local more: { [string]: string } = extra or {}
		for k, v in more do
			e[k] = v
		end
		return fixture.exec(cwd or this.repo, "bash", argv, { env = e })
	end
	function self.zn(this: Live, args: { string }, cwd: string?): Result
		local argv = table.clone(args)
		if this.env.ZN_LIVE_DIR ~= "" then -- a named state directory takes the short limits; the default one refuses them
			table.insert(argv, "--idle-exit")
			table.insert(argv, "20")
			table.insert(argv, "--tick-every")
			table.insert(argv, "0.3")
		end
		local r = this:znRaw(argv, cwd)
		for _, p in daemonsOf(this.base) do
			if not table.find(this.started, p) then
				table.insert(this.started, p)
			end
		end
		return r
	end
	function self.together(this: Live, jobs: { { string } }): { Result }
		local results: { Result } = {}
		local left = #jobs
		local co = coroutine.running()
		for i, args in jobs do
			task.spawn(function()
				local ok, r = pcall(this.zn, this, args)
				results[i] = if ok then r else { ok = false, code = -1, stdout = "", stderr = tostring(r) }
				left -= 1
				if left == 0 then
					task.spawn(co)
				end
			end)
		end
		if left > 0 then
			coroutine.yield()
		end
		return results
	end
	function self.pids(this: Live): { number }
		return daemonsOf(this.base)
	end
	return self
end

-- Runs `body` on a fresh fixture; whatever it does, the daemon is shut down and waited for. A daemon still alive after
-- that fails the spec (and is killed). `body`'s own error is raised after the cleanup.
function live.with(name: string, opts: { noDirEnv: boolean? }?, body: (Live) -> ())
	local l = live.new(name, opts)
	local ok, err = pcall(body :: (Live) -> any, l)
	-- a clean stop first, then whatever is left
	pcall(l.znRaw, l, { "shutdown" })
	for _ = 1, 100 do
		if #l:pids() == 0 then
			break
		end
		task.wait(0.05)
	end
	local left = l:pids()
	for _, pid in left do
		process.exec("kill", { "-9", tostring(pid) })
	end
	for _, pid in l.started do
		if alive(pid) and not table.find(left, pid) then
			process.exec("kill", { "-9", tostring(pid) })
			table.insert(left, pid)
		end
	end
	if not ok then
		error(err, 0)
	end
	if #left > 0 then
		error(
			`live spec {name}: a znlive process was still alive after shutdown: {table.concat(
				left :: any,
				", "
			)}`,
			0
		)
	end
end

return live
