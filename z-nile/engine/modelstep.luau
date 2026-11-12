--!strict
-- The one start of a model CLI. `launch` runs one CLI under runner.luau: the supervisor, the
-- role's caps, the stall limit and the lifeline. `drive` is the try loop the idea stage uses:
-- the role's CLI, then its fallbacks, moving on when the call fails, the CLI is missing, or
-- the quota is gone. A stall, a cap or a stop ends the loop. The dispatcher calls `launch`
-- from its own loop, which adds the broker and the tripwire around the same start.
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
	resolved: models.Resolved,
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

local function childEnv(path: string, runtime: string): { [string]: string }
	local env = table.clone(process.env)
	env.PATH = path
	local extra = adapters.STEP_ENV[runtime]
	if extra then
		for k, v in extra do
			env[k] = v
		end
	end
	return env :: { [string]: string }
end

-- The role's tries, in order. `accept` says whether an ok answer is usable; a no is a failed
-- call and the next model runs. The last attempt's outcome is the result when none is ok.
function modelstep.drive(d: Drive): Driven
	local tries = models.tries(d.resolved)
	local attempts: { Attempt } = {}
	local outcome, detail, prose, model = "failed", "no model produced a usable answer", "", ""
	for i, spec in tries do
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
		if not bin then
			outcome, detail, model = "missing", `{argv[1]} is not installed (the {spec.cli} CLI)`, modelId
			table.insert(attempts, {
				spec = spec,
				outcome = outcome,
				detail = detail,
				tokens = 0,
				prose = "",
			})
			continue
		end
		if d.guard then
			local why = d.guard(bin :: string)
			if why then
				outcome, detail, model = "failed", why, modelId
				table.insert(attempts, {
					spec = spec,
					outcome = "failed",
					detail = why,
					tokens = 0,
					prose = "",
				})
				break
			end
		end
		argv[1] = bin :: string
		local result, text = modelstep.launch({
			argv = argv,
			cwd = d.cwd,
			env = childEnv(d.path, spec.runtime),
			stdin = nil,
			adapter = adapter,
			cap = spec.maxTokens,
			maxCalls = if adapter.callCapped then spec.maxCalls else nil,
			maxSeconds = if adapter.callCapped and spec.maxMinutes
				then (spec.maxMinutes :: number) * 60
				else nil,
			stallSeconds = d.resolved.settings.stallSeconds,
			toolSeconds = d.resolved.settings.toolSeconds,
			stateDir = `{d.stateDir}/{i}`,
		})
		outcome, detail, prose, model = result.outcome, result.detail, text, modelId
		if outcome == "ok" and d.accept and not d.accept(text) then
			outcome, detail = "failed", "the answer was not in the required shape"
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
		if outcome == "ok" then
			break
		end
		if outcome ~= "quota" and outcome ~= "failed" and outcome ~= "missing" then
			break
		end
	end
	return {
		outcome = outcome,
		detail = detail,
		model = model,
		prose = prose,
		attempts = attempts,
	}
end

return modelstep
