--!strict
-- The one start of a model CLI. `launch` runs one CLI under runner.luau: the supervisor, the
-- role's caps, the stall limit and the lifeline. `drive` is the one try the idea stage makes
-- on the CLI that runs it (f0421: no fallback to another CLI). The dispatcher calls `launch`
-- from its own step, which adds the broker and the tripwire around the same start.
--
-- Contract for the Python port: a model is started only here. The measured row (wall, CPU,
-- tokens, the model id) is written by the caller from the result `launch` returns.
local adapters = require("./adapters")
local models = require("./models")
local process = require("@lune/process")
local runner = require("./runner")

local modelstep = {}

export type Attempt = {
	spec: models.Spec,
	outcome: string,
	detail: string,
	tokens: number,
	wall: number?,
	cpu: number?,
	prose: string,
}

export type Drive = {
	spec: models.Spec,
	settings: models.Settings,
	prompt: string,
	cwd: string,
	stateDir: string,
	path: string,
	guard: ((bin: string) -> string?)?,
	accept: ((prose: string) -> boolean)?,
}

export type Driven = {
	outcome: string,
	detail: string,
	model: string,
	prose: string,
	attempts: { Attempt },
}

local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end

-- One CLI under the supervisor. Returns the runner's result and the lines it printed.
function modelstep.launch(r: runner.Request): (runner.Result, string)
	local lines: { string } = {}
	local inner = r.adapter
	local wrapped: adapters.Adapter = {
		cli = inner.cli,
		runtime = inner.runtime,
		callCapped = inner.callCapped,
		argv = inner.argv,
		feed = function(acc, line)
			table.insert(lines, line)
			inner.feed(acc, line)
			if r.onLine and acc.note ~= "" then
				r.onLine(acc.note, acc.live)
			end
		end,
	}
	local req = table.clone(r)
	req.adapter = wrapped
	return runner.run(req), table.concat(lines, "\n")
end

local function resolveBin(name: string, path: string): string?
	local r = process.exec("sh", { "-c", 'command -v "$1"', "_", name }, { env = { PATH = path } })
	if not r.ok or trim(r.stdout) == "" then
		return nil
	end
	local real = process.exec("perl", { "-MCwd", "-e", "print Cwd::realpath($ARGV[0])", trim(r.stdout) })
	return if real.ok and real.stdout ~= "" then real.stdout else trim(r.stdout)
end

local function childEnv(path: string, runtime: string, cli: string): { [string]: string }
	local env = table.clone(process.env)
	env.PATH = path
	env.ZN_CLI = cli -- the CLI that runs this step (f0421 step 6; on fence.STEP_VARS)
	local extra = adapters.STEP_ENV[runtime]
	if extra then
		for k, v in extra do
			env[k] = v
		end
	end
	return env :: { [string]: string }
end

-- The activity's one try: the spec the CLI that runs it resolved (f0421 step 6: no fallback, no other CLI). `accept` says
-- whether an ok answer is usable; a no is a failed call, and the step ends with it. A failure, a quota outcome, a missing CLI,
-- a stall, a cap or a stop all end the drive, each with its own outcome.
function modelstep.drive(d: Drive): Driven
	local attempts: { Attempt } = {}
	local spec = d.spec
	local adapter = adapters.get(spec.runtime)
	local session = trim(process.exec("uuidgen", {}).stdout)
	local argv = adapter.argv({
		prompt = d.prompt,
		model = spec.model,
		effort = spec.effort,
		cwd = d.cwd,
		session = session,
	})
	local bin = resolveBin(argv[1], d.path)
	local modelId = models.id(spec)
	local function ended(outcome: string, detail: string, prose: string): Driven
		return { outcome = outcome, detail = detail, model = modelId, prose = prose, attempts = attempts }
	end
	if not bin then
		local detail = `{argv[1]} is not installed (the {spec.cli} CLI)`
		table.insert(attempts, { spec = spec, outcome = "missing", detail = detail, tokens = 0, prose = "" })
		return ended("missing", detail, "")
	end
	if d.guard then
		local why = d.guard(bin :: string)
		if why then
			table.insert(attempts, { spec = spec, outcome = "failed", detail = why, tokens = 0, prose = "" })
			return ended("failed", why, "")
		end
	end
	-- the resolved file runs under the CLI's own name (d0439): the session-end reaper knows a session's process by the
	-- name `claude`, and a nested session listed by its real path would make its end stop the outer session's commands
	local result, text = modelstep.launch({
		argv = argv,
		program = bin :: string,
		cwd = d.cwd,
		env = childEnv(d.path, spec.runtime, spec.cli),
		stdin = nil,
		adapter = adapter,
		cap = spec.maxTokens,
		maxCalls = if adapter.callCapped then spec.maxCalls else nil,
		maxSeconds = if adapter.callCapped and spec.maxMinutes then (spec.maxMinutes :: number) * 60 else nil,
		stallSeconds = d.settings.stallSeconds,
		toolSeconds = d.settings.toolSeconds,
		stateDir = `{d.stateDir}/1`,
	})
	local outcome, detail = result.outcome, result.detail
	if outcome == "ok" and d.accept and not d.accept(text) then
		outcome, detail = "failed", "the answer was not in the required shape"
	end
	-- the quota seam (f0420's `work run` releases the work with this reason)
	if outcome == "quota" then
		detail = `{spec.cli} is out of quota ({detail})`
	end
	table.insert(attempts, {
		spec = spec,
		outcome = outcome,
		detail = detail,
		tokens = result.tokens,
		wall = result.wall,
		cpu = result.cpu,
		prose = text,
	})
	return ended(outcome, detail, text)
end

return modelstep
