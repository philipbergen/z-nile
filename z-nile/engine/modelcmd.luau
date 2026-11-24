--!strict
-- f0421 slice 2: `./zn model <activity|alias> [--risk <level> | --for <id>] [--cli <name>]` and `./zn model --can [--cli <name>]`.
-- The model an activity runs on for one CLI, in one line a shell or an agent can parse. Read-only: it publishes, locks and
-- writes nothing. It reads `.models.toml` as pinned on origin/main (models.walkAt), as `./zn rounds`, the dispatcher and
-- `work next` do, to the item's folder with `--for`. Exit 0 prints the line, exit 1 means the CLI cannot deliver (stderr
-- says why and what is waiting), exit 2 is a usage or configuration error.
local lightgit = require("./lightgit")
local models = require("./models")
local process = require("@lune/process")
local reviewrec = require("./reviewrec")
local rounds = require("./rounds")
local roundscmd = require("./roundscmd")
local sh = require("../lib/sh")
local stdio = require("@lune/stdio")
local store = require("./store")

local modelcmd = {}

local USAGE =
	"usage: ./zn model <activity|alias> [--risk easy|normal|risky | --for <id>] [--cli <name>]\n       ./zn model --can [--cli <name>]"

-- The Agent tool's model word on claude: the family of a claude model id.
function modelcmd.subagentWord(cli: string, model: string): string
	if cli ~= "claude" then
		return "-"
	end
	return string.match(model, "^claude%-(haiku)%-")
		or string.match(model, "^claude%-(sonnet)%-")
		or string.match(model, "^claude%-(opus)%-")
		or string.match(model, "^claude%-(fable)%-")
		or "-"
end

-- The one line: every field `key=value`, `-` for none.
-- A review whose writer's model is known ends with `same-model=yes` when it runs on that model (allowed, not preferred) and
-- `same-model=no` when it does not; a line whose writer is unknown has no such field.
function modelcmd.line(activity: string?, level: string?, spec: models.Spec, same: boolean?): string
	local fields = {
		`activity={activity or "-"}`,
		`level={level or "-"}`,
		`cli={spec.cli}`,
		`alias={spec.alias or "-"}`,
		`model={spec.model}`,
		`effort={spec.effort or "-"}`,
		`context={if spec.context then tostring(spec.context) else "-"}`,
		`subagent={modelcmd.subagentWord(spec.cli, spec.model)}`,
	}
	if same ~= nil then
		table.insert(fields, `same-model={if same then "yes" else "no"}`)
	end
	return table.concat(fields, " ")
end

-- The variable that names the model a session runs. Only a CLI with no subagents whose table holds several models reads it
-- (agy runs Gemini 4 Neon to write and Gemini 4 Argon to review, but one session runs one model); the runner clears it
-- (tests/lib/fence.luau CLI_VARS).
modelcmd.MODEL_VAR = "ZN_MODEL"
-- the CLIs that print the ids they run (`<cli> models`): a refusal names that command
local LISTS: { [string]: boolean } = { agent = true, agy = true, grok = true }

-- The model this session runs, or nil, and the one plain line when it must be named and is not (or is not the CLI's).
-- A CLI with one model, or with subagents, needs nothing: the variable is ignored.
function modelcmd.sessionModel(
	env: { [string]: string? },
	layers: { models.Layer },
	cli: string
): (string?, string?)
	if not models.needsSession(layers, cli) then
		return nil, nil
	end
	local held = models.modelsOf(layers, cli)
	local named = env[modelcmd.MODEL_VAR]
	-- f0421 slice 3: the person names the model when they start the CLI; an agent never sets or changes the variable
	local which = if LISTS[cli]
		then `the id \`{cli} models\` prints for the model it runs`
		else "the id of the model it runs"
	local ask =
		`ask the person to start {cli} with {modelcmd.MODEL_VAR} set to {which} (an agent never sets or changes {modelcmd.MODEL_VAR})`
	if named == nil or named == "" then
		return nil, `{cli} runs more than one model ({table.concat(held, ", ")}): {ask}`
	end
	if named == "auto" then
		return nil,
			`{modelcmd.MODEL_VAR} auto lets {cli} pick its own model, which nobody can name: ask the person to start {cli} on a named model, with {modelcmd.MODEL_VAR} set to {if LISTS[cli]
				then `the id \`{cli} models\` prints for it`
				else "its id"}`
	end
	if not table.find(held, named) then
		return nil, `{modelcmd.MODEL_VAR} {named} is not a model of {cli} ({table.concat(held, ", ")}): {ask}`
	end
	return named, nil
end

-- The session variables that name a CLI, the one definition (the spec runner clears them, tests/lib/fence.luau CLI_VARS).
modelcmd.SESSION_VARS = {
	{ "CLAUDE_CODE_SESSION_ID", "claude" },
	{ "KIMI_SESSION_ID", "kimi" },
	{ "GROK_SESSION_ID", "grok" },
}

-- The CLI: `--cli`, then ZN_CLI, then the session's own variable (CLAUDE_CODE_SESSION_ID is claude, KIMI_SESSION_ID is
-- kimi, GROK_SESSION_ID is grok). A CLI started from another's shell inherits that one's variable too, so with more than
-- one set the answer is a problem naming them, never a guess. Returns the CLI, or nil and why not.
function modelcmd.cliOf(flag: string?, env: { [string]: string? }): (string?, string?)
	if flag ~= nil and flag ~= "" then
		return flag, nil
	end
	local named = env.ZN_CLI
	if named ~= nil and named ~= "" then
		return named, nil
	end
	local found: { string } = {}
	local vars: { string } = {}
	for _, pair in modelcmd.SESSION_VARS do
		if (env[pair[1]] or "") ~= "" then
			table.insert(vars, pair[1])
			table.insert(found, pair[2])
		end
	end
	if #found == 1 then
		return found[1], nil
	elseif #found > 1 then
		local names = if #vars == 2
			then `{vars[1]} and {vars[2]} are both set`
			else `{table.concat(vars, ", ", 1, #vars - 1)} and {vars[#vars]} are all set`
		return nil, `{names} (a CLI started from another's shell): pass --cli <name> or set ZN_CLI`
	end
	return nil, nil
end

-- f0421 slice 3: the mark a row carries when its model is the one the session declared in ZN_MODEL and no session file the
-- engine reads names it (models.SESSION_READ): `(declared)`, or nil. `env` is the command's environment.
function modelcmd.declaredNote(model: string?, env: { [string]: string? }): string?
	local named = env[modelcmd.MODEL_VAR]
	if model == nil or named == nil or named == "" or string.lower(model) ~= string.lower(named) then
		return nil
	end
	local cli = modelcmd.cliOf(nil, env)
	if cli == nil or models.SESSION_READ[cli] then
		return nil
	end
	return "(declared)"
end

local function die(code: number, message: string): never
	stdio.ewrite(`{message}\n`)
	return process.exit(code)
end

local function envNow(): { [string]: string? }
	return {
		ZN_CLI = process.env.ZN_CLI,
		CLAUDE_CODE_SESSION_ID = process.env.CLAUDE_CODE_SESSION_ID,
		KIMI_SESSION_ID = process.env.KIMI_SESSION_ID,
		GROK_SESSION_ID = process.env.GROK_SESSION_ID,
		ZN_MODEL = process.env.ZN_MODEL,
	}
end

function modelcmd.run(pos: { string }, opts: { [string]: { string } })
	for k in opts do
		if k ~= "--risk" and k ~= "--for" and k ~= "--cli" and k ~= "--can" then
			die(2, `model: unknown option {k}\n{USAGE}`)
		end
	end
	local can = opts["--can"] ~= nil
	local target = pos[1]
	if
		(can and (target ~= nil or opts["--risk"] ~= nil or opts["--for"] ~= nil))
		or (not can and target == nil)
		or #pos > 1
	then
		die(2, `model: {if can then "--can takes only --cli" else "name an activity or an alias"}\n{USAGE}`)
	end
	if opts["--risk"] ~= nil and opts["--for"] ~= nil then
		die(2, `model: --risk and --for both name the level: pass one\n{USAGE}`)
	end
	local found, clash = modelcmd.cliOf(if opts["--cli"] then opts["--cli"][1] else nil, envNow())
	local cli: string = found
		or die(
			2,
			if clash
				then `model: {clash}`
				else "model: which CLI is this? pass --cli <name> or set ZN_CLI (claude, grok, agent, kimi, agy)"
		)
	if not table.find(models.CLIS, cli) then
		die(2, `model: {cli} is not a supported CLI ({table.concat(models.CLIS, ", ")})`)
	end
	local isAlias = target ~= nil and table.find(models.ALIASES, target) ~= nil
	if target ~= nil and not isAlias and not models.isActivity(target) then
		die(
			2,
			`model: {target} is not an activity or an alias ({table.concat(models.ACTIVITIES, ", ")}; {table.concat(
				models.ALIASES,
				", "
			)})`
		)
	end
	local function go(): ()
		-- the item's folder (the root alone without --for), and the level: --risk, else the item's, else normal
		local dir = "."
		local level: rounds.Level = "normal"
		local forItem: store.Item? = nil
		local lightRaft = false -- f0420: --for names a raft marked light: its final review is the only review
		if opts["--for"] ~= nil then
			local id = opts["--for"][1]
			local item = store.get(id)
			dir = item.dir
			forItem = item
			level = roundscmd.levelOf(item, ".")
			lightRaft = item.kind == "raft" and lightgit.markedAt(item.doc)
		elseif opts["--risk"] ~= nil then
			local lvl, problem = rounds.level(opts["--risk"][1])
			if lvl == nil or opts["--risk"][1] == "" then
				die(2, `model: --risk: {problem or "risk is empty: easy, normal or risky"}`)
			end
			level = lvl :: rounds.Level
		end
		if not sh.run("git", { "rev-parse", "--verify", "-q", "origin/main" }).ok then
			die(2, "model: cannot read .models.toml from origin/main: fetch, or check the remote")
		end
		local layers = models.walkAt(dir, function(rel: string): string?
			local shown = sh.run("git", { "show", `origin/main:{rel}` })
			return if shown.ok then shown.stdout else nil
		end, function(): boolean
			return false
		end)
		local session, sessionProblem = modelcmd.sessionModel(envNow(), layers, cli)
		if sessionProblem ~= nil then
			die(2, `model: {sessionProblem}`)
		end
		if can then
			print(table.concat(models.canList(layers, cli, session), ","))
			return
		end
		local name = target :: string
		if isAlias then
			local spec, why = models.resolveAlias(layers, cli, name)
			if spec == nil then
				die(1, `model: {cli} cannot deliver {name}: {why}`)
			end
			if session ~= nil and (spec :: models.Spec).model ~= session then
				die(
					1,
					`model: {cli} cannot deliver {name}: this session runs {session}, and {name} on {cli} is {(
						spec :: models.Spec
					).model}`
				)
			end
			print(modelcmd.line(nil, nil, spec :: models.Spec))
			if models.config(layers).legacy then
				stdio.ewrite(
					`model: this walk has no [activities] yet: {name} is the implementation role's model on {cli}\n`
				)
			end
			return
		end
		local activity = name
		-- the models that wrote the text a review reads: the spend rows of the item `--for` names. A marked light raft's final
		-- review is the only review of the code; when no row names its builder, the builder is only guessed and nothing is
		-- reported against the guess
		local authors: { string } = {}
		local authorNote: string? = nil
		local phase = reviewrec.WRITER_PHASE[activity]
		if forItem ~= nil and phase ~= nil then
			local wrote, unread = reviewrec.spendWriters(forItem, phase, ".")
			authors = wrote
			if unread ~= nil then
				authorNote =
					`model: the writer's model could not be read ({unread}): same-model is not reported`
			end
		end
		if lightRaft and activity == "final-review" and #authors == 0 then
			local guess = models.builderGuess(layers, cli, level)
			authorNote = if guess ~= nil
				then `model: this raft took the light path, so its final review is the only review of the code, and the builder's model is a guess ({guess}: what code resolves to on {cli}; no spend row names it): same-model is not reported`
				else `model: this raft took the light path, but the builder's model could not be read: same-model is not reported`
		end
		local spec, why = models.resolveReview(layers, cli, activity, level, authors, session)
		if spec == nil then
			local need = models.need(layers, activity, level)
			local what = `{activity}/{level} ({need})`
			local waiting = models.waiting(layers, activity, level)
			die(1, `model: {cli} cannot deliver {what}: {why}; waiting for a worker with {waiting}`)
		end
		local spec2 = spec :: models.Spec
		print(modelcmd.line(activity, level, spec2, if #authors > 0 then spec2.sameAsAuthor == true else nil))
		if authorNote then
			stdio.ewrite(authorNote .. "\n")
		end
	end
	local ok, err = pcall(go :: () -> any)
	if not ok then
		die(2, `model: {err}`)
	end
end

return modelcmd
