--!strict
-- f0421 slice 2: `./zn model <activity|alias> [--risk <level> | --for <id>] [--cli <name>]` and `./zn model --can [--cli <name>]`.
-- The model an activity runs on for one CLI, in one line a shell or an agent can parse. Read-only: it publishes, locks and
-- writes nothing. It reads `.models.toml` as pinned on origin/main (models.walkAt), as `./zn rounds`, the dispatcher and
-- `work next` do, to the item's folder with `--for`. Exit 0 prints the line, exit 1 means the CLI cannot deliver (stderr
-- says why and what is waiting), exit 2 is a usage or configuration error.
local models = require("./models")
local process = require("@lune/process")
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
function modelcmd.line(activity: string?, level: string?, spec: models.Spec): string
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
	return table.concat(fields, " ")
end

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
	for _, pair in
		{
			{ "CLAUDE_CODE_SESSION_ID", "claude" },
			{ "KIMI_SESSION_ID", "kimi" },
			{ "GROK_SESSION_ID", "grok" },
		}
	do
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
				else "model: which CLI is this? pass --cli <name> or set ZN_CLI (claude, grok, agent, kimi)"
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
		if opts["--for"] ~= nil then
			local id = opts["--for"][1]
			local item = store.get(id)
			dir = item.dir
			level = roundscmd.levelOf(item, ".")
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
		if can then
			print(table.concat(models.canList(layers, cli), ","))
			return
		end
		local name = target :: string
		if isAlias then
			local spec, why = models.resolveAlias(layers, cli, name)
			if spec == nil then
				die(1, `model: {cli} cannot deliver {name}: {why}`)
			end
			print(modelcmd.line(nil, nil, spec :: models.Spec))
			return
		end
		local activity = name
		local spec, why = models.resolveActivity(layers, cli, activity, level, nil)
		if spec == nil then
			local need = models.need(layers, activity, level)
			local what = `{activity}/{level} ({need})`
			local who = models.deliverers(layers, activity, level)
			local waiting =
				`{activity}/{level} ({need}: {if #who > 0 then table.concat(who, ", ") else "none"})`
			die(1, `model: {cli} cannot deliver {what}: {why}; waiting for a worker with {waiting}`)
		end
		print(modelcmd.line(activity, level, spec :: models.Spec))
	end
	local ok, err = pcall(go :: () -> any)
	if not ok then
		die(2, `model: {err}`)
	end
end

return modelcmd
