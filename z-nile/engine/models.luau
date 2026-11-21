--!strict
-- .models.toml (c0117): which model runs each stage, on which CLI, and which fallbacks follow it.
-- The files stack like .gitignore: from the repository root down to the work, a closer file replaces only the keys
-- it sets. Pure apart from `load`/`walk`, which read the files.
--
-- Contract for the Python port. One shape. A role names what belongs to the stage: `model`, `cli`, `runtime`,
-- `rank`, `max_tokens`, `effort`, and `fallbacks` (CLI names, in order). A fallback names what belongs to the
-- model: `[fallback.<cli>]` has `model`, `runtime`, and anything only that CLI needs (`max_calls` and
-- `max_minutes` for `agent`). A try is the role's rank, cap and effort on the fallback's model. A challenge
-- role sets `author` to the role that wrote the text; a try whose model id equals that author's is dropped,
-- and an empty list fails at resolve. A role or fallback that names an unknown model or CLI fails in `parse`
-- (when the file is loaded), not when the stage runs. There is no `order` and no `[<skill>.<cli>]` table.
--
--   [roles.idea]
--   model = "..."          -- a model id of `cli` (claude-…, grok-…, kimi-code-…, or the agent's id)
--   cli = "claude"
--   runtime = "claude-cli"
--   rank = 2
--   max_tokens = 300000
--   effort = "medium"      -- the stage's: the primary and every fallback try carry it
--   fallbacks = ["kimi", "grok", "agent"]
--   [roles.idea-challenge]
--   author = "idea"        -- never run this role on the author's model
--   [fallback.kimi]
--   model = "..."
--   runtime = "kimi-cli"
--   [fallback.agent]
--   model = "..."
--   runtime = "cursor-cli"
--   max_calls = 200
--   max_minutes = 240
--   [dispatch]
--   auto_merge = ["prep", "raft"]
--   stall_seconds = 300
local fs = require("@lune/fs")
local ledger = require("./ledger")
local rounds = require("./rounds")
local serde = require("@lune/serde")

local models = {}

models.FILE = ".models.toml"
-- The supported CLIs (the user's decision: `agent` is Cursor's), each with its one local runtime (the remote ones are c0142's).
models.CLIS = { "claude", "grok", "agent", "kimi" }
models.RUNTIMES = {
	-- the local runtimes only: the remote ones (claude-cloud, grok-bot, cursor-app) are c0142's (the user's G8)
	claude = { "claude-cli" },
	grok = { "grok-cli" },
	agent = { "cursor-cli" },
	kimi = { "kimi-cli" },
} :: { [string]: { string } }
-- A model id the CLI accepts. A role that names anything else fails when the file is loaded.
local MODEL_OF_CLI: { [string]: string } = {
	claude = "^claude%-[%w%._%-]+$",
	grok = "^grok%-[%w%._%-]+$",
	kimi = "^kimi%-code%-[%w%._%-]+$",
	agent = "^[%w%._%-]+$",
}
-- The merge gates the dispatcher may pass itself; the run's PR is never one of them.
models.GATES = { "prep", "raft" }
-- f0421 slice 2: the four aliases, weakest first; the activities a configuration sets (per level, or one setting for all);
-- and each writer with its reviewer (a reviewer never runs on the writer's model).
models.ALIASES = { "xlight", "light", "heavy", "ultra" } :: { string }
models.ACTIVITIES = {
	"idea",
	"idea-challenge",
	"design",
	"design-review",
	"raft",
	"raft-review",
	"code",
	"code-review",
	"final-review",
	"approve",
} :: { string }
local ONE_SETTING: { [string]: boolean } =
	{ idea = true, ["idea-challenge"] = true, ["final-review"] = true, approve = true }
models.PAIRS = {
	{ "idea", "idea-challenge" },
	{ "design", "design-review" },
	{ "raft", "raft-review" },
	{ "code", "code-review" },
	{ "code", "final-review" },
} :: { { string } }
-- these use the writer's setting (f0420's table)
local WRITER_OF: { [string]: string } = {
	["design-answer"] = "design",
	["code-answer"] = "code",
	["final-answer"] = "code",
	trace = "code",
	fix = "code",
}
-- a legacy walk (no [activities]): the role each activity comes from
local ROLE_OF: { [string]: string } = {
	idea = "idea",
	["idea-challenge"] = "idea-challenge",
	design = "design",
	["design-review"] = "design-challenge",
	raft = "raft",
	["raft-review"] = "raft",
	code = "implementation",
	["code-review"] = "code-review",
	["final-review"] = "final-review",
	approve = "approve",
}
models.STALL_SECONDS = 300
-- the stall limit while a tool call runs (a full gate is quiet for minutes)
models.TOOL_SECONDS = 900
local FIELDS = {
	model = "string",
	effort = "string",
	rank = "count",
	runtime = "string",
	max_tokens = "count",
	max_calls = "count",
	max_minutes = "count",
}
-- the CLIs whose stream has no running token count: their step stops after `max_calls` model calls (the user's decision,
-- 2026-10-21: "Cap model calls, record real total"); a spec of theirs without it is an error, never unlimited
models.CALL_CAPPED = { agent = true } :: { [string]: boolean }
local REQUIRED = { "model", "rank", "runtime", "max_tokens" }

export type Spec = {
	cli: string,
	model: string,
	effort: string?,
	rank: number,
	runtime: string,
	maxTokens: number,
	maxCalls: number?, -- the model-call cap of a CLI with no running token count (agent)
	maxMinutes: number?, -- its wall-time ceiling beside max_calls (review 003 F7: fail closed)
	alias: string?, -- f0421 slice 2: the alias the setting named (nil for a role's spec and for a specific model)
	context: number?, -- the context window in tokens (advisory except claude's `[1m]`)
}
-- f0421 slice 2: one setting: an alias name, or a model with its effort and context. In a CLI's table it is an alias's
-- definition (`model` set); in an activity's table it is `alias` or `model`.
export type Setting = { alias: string?, model: string?, effort: string?, context: number? }
export type Settings = { autoMerge: { string }, stallSeconds: number, toolSeconds: number }
-- One parsed file: its dispatch settings, its roles and its fallbacks.
export type Layer = {
	path: string,
	settings: { [string]: any },
	roles: { [string]: { [string]: any } },
	fallbacks: { [string]: { [string]: any } },
	rounds: { [string]: number }?, -- f0421: the [rounds] leaves this file sets (idea, design.easy, ...)
	clis: { [string]: { [string]: any } }, -- f0421 slice 2: [clis.<cli>]: aliases (Setting), models, runtime, max_calls, max_minutes
	activities: { [string]: { [string]: any } }, -- [activities.<a>]: max_tokens and easy/normal/risky/all (Setting)
	hasActivities: boolean, -- the file has an [activities] table: roles and fallbacks are then ignored
}
-- A skill resolved on one walk: the CLI order, the specs of the CLIs that name the skill, and the settings.
export type Resolved = {
	skill: string,
	order: { string },
	specs: { [string]: Spec },
	settings: Settings,
	authorModel: string?,
	fromRoles: boolean?,
}

local function isCli(name: string): boolean
	return table.find(models.CLIS, name) ~= nil
end

local function list(names: { string }): string
	return table.concat(names, ", ")
end

local function firstLine(e: any): string
	local text = tostring(e)
	local msg = string.match(text, "TOML parse error[^\n]*\n[^\n]*\n[^\n]*\n[^\n]*\n([^\n]+)")
	local where = string.match(text, "(TOML parse error at line %d+, column %d+)")
	return if where then `{where}: {msg or "?"}` else (string.match(text, "^[^\n]*") or text)
end

local function count(v: any): boolean
	return type(v) == "number" and v >= 1 and v == math.floor(v)
end

-- f0421 slice 2: a finite whole number from 1 to 10^9 (a context, a cap: never inf, NaN or a count nobody means).
local BOUND = 1000000000
local function sane(v: any): boolean
	return type(v) == "number" and v >= 1 and v <= BOUND and v == math.floor(v)
end
-- a real sequence: keys 1..n and nothing else
local function isList(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	local n = 0
	for k in v do
		if type(k) ~= "number" then
			return false
		end
		n += 1
	end
	for i = 1, n do
		if v[i] == nil then
			return false
		end
	end
	return true
end
local EFFORTS = { "low", "medium", "high", "xhigh", "max" }

-- A number of review rounds: a whole number from 1 to 99 (never inf, NaN or a count nobody means).
local function roundCount(v: any): boolean
	return type(v) == "number" and v >= 1 and v <= 99 and v == math.floor(v)
end

-- f0421 slice 2: one `{ model, effort?, context? }`. `cli` (when known) says which model ids are accepted.
local function parseDef(path: string, label: string, cli: string?, v: any): Setting
	if type(v) ~= "table" then
		error(
			`{path}: {label} is {if cli then "an alias" else "an alias name or a setting"} with a model, effort and context (a table)`,
			0
		)
	end
	local def: Setting = {}
	if v.model == nil then
		error(`{path}: {label} has no model`, 0)
	end
	for k, x in v do
		if k == "model" then
			if type(x) ~= "string" or not ledger.isModel(x) then
				error(`{path}: {label}.model is a model id (letters, digits, '.', '_', '-')`, 0)
			end
			if cli ~= nil and string.match(x, MODEL_OF_CLI[cli]) == nil then
				error(`{path}: {label}.model is {x}, not a model of cli {cli}`, 0)
			end
			def.model = x
		elseif k == "effort" then
			if type(x) ~= "string" or not table.find(EFFORTS, x) then
				error(`{path}: {label}.effort is {tostring(x)}: {list(EFFORTS)}`, 0)
			end
			def.effort = x
		elseif k == "context" then
			if not sane(x) then
				error(`{path}: {label}.context is {tostring(x)}: a whole number of tokens, 1 to {BOUND}`, 0)
			end
			def.context = x
		else
			error(`{path}: {label}.{tostring(k)} is not a field (model, effort, context)`, 0)
		end
	end
	return def
end

-- `[clis.<cli>]`: aliases, `models`, `runtime`, `max_calls`, `max_minutes`.
local function parseCli(path: string, name: string, fields: any): { [string]: any }
	if type(name) ~= "string" or not isCli(name) then
		error(`{path}: clis.{tostring(name)} is not a supported CLI ({list(models.CLIS)})`, 0)
	end
	if type(fields) ~= "table" then
		error(`{path}: [clis.{name}] is a table`, 0)
	end
	local out: { [string]: any } = {}
	for k, v in fields do
		if type(k) == "string" and table.find(models.ALIASES, k) then
			out[k] = parseDef(path, `clis.{name}.{k}`, name, v)
		elseif k == "models" then
			if not isList(v) then
				error(`{path}: clis.{name}.models is a list of model ids`, 0)
			end
			local ids: { string } = {}
			for _, m in v do
				if type(m) ~= "string" or not ledger.isModel(m) then
					error(`{path}: clis.{name}.models names {tostring(m)}, which is not a model id`, 0)
				end
				if string.match(m, MODEL_OF_CLI[name]) == nil then
					error(`{path}: clis.{name}.models names {m}, not a model of cli {name}`, 0)
				end
				table.insert(ids, m)
			end
			out.models = ids
		elseif k == "runtime" then
			if type(v) ~= "string" or not table.find(models.RUNTIMES[name], v) then
				error(
					`{path}: clis.{name}.runtime is {tostring(v)}, which is not a runtime of {name} ({list(
						models.RUNTIMES[name]
					)})`,
					0
				)
			end
			out.runtime = v
		elseif k == "max_calls" or k == "max_minutes" then
			if not sane(v) then
				error(`{path}: clis.{name}.{k} is {tostring(v)}: a whole number, 1 to {BOUND}`, 0)
			end
			out[k] = v
		else
			error(
				`{path}: clis.{name}.{tostring(k)} is not an alias or setting (xlight, light, heavy, ultra, models, runtime, max_calls, max_minutes)`,
				0
			)
		end
	end
	return out
end

-- `[activities.<a>]`: `max_tokens` and a setting for easy, normal, risky or all.
local function parseActivity(path: string, name: string, fields: any): { [string]: any }
	if type(name) ~= "string" or not table.find(models.ACTIVITIES, name) then
		error(`{path}: activities.{tostring(name)} is not an activity ({list(models.ACTIVITIES)})`, 0)
	end
	if type(fields) ~= "table" then
		error(`{path}: [activities.{name}] is a table`, 0)
	end
	local out: { [string]: any } = {}
	for k, v in fields do
		if k == "max_tokens" then
			if not sane(v) then
				error(
					`{path}: activities.{name}.max_tokens is {tostring(v)}: a whole number, 1 to {BOUND}`,
					0
				)
			end
			out.max_tokens = v
		elseif k == "easy" or k == "normal" or k == "risky" or k == "all" then
			if ONE_SETTING[name] and k ~= "all" then
				error(`{path}: activities.{name}.{k}: {name} has one setting for every level: write all`, 0)
			end
			if type(v) == "string" then
				if not table.find(models.ALIASES, v) then
					error(
						`{path}: activities.{name}.{k} names {v}, which is not an alias ({list(models.ALIASES)})`,
						0
					)
				end
				out[k] = { alias = v } :: Setting
			else
				out[k] = parseDef(path, `activities.{name}.{k}`, nil, v)
			end
		else
			error(
				`{path}: activities.{name}.{tostring(k)} is not max_tokens or a level (easy, normal, risky, all)`,
				0
			)
		end
	end
	return out
end

-- Parses one file's text. Every error names the file and the key: an unknown CLI, field or setting, a value of the
-- wrong type, a runtime of another CLI. A repeated table or key is the TOML reader's error (it refuses duplicates).
function models.parse(text: string, path: string): Layer
	local ok, decoded = pcall(function()
		return serde.decode("toml", text)
	end)
	if not ok then
		error(`{path}: {firstLine(decoded)}`, 0)
	end
	local layer: Layer = {
		path = path,
		settings = {},
		roles = {},
		fallbacks = {},
		clis = {},
		activities = {},
		hasActivities = false,
	}
	for key, value in decoded :: { [string]: any } do
		if key == "order" then
			error(`{path}: order is gone; a role names its cli, then its fallbacks`, 0)
		elseif key == "dispatch" then
			if type(value) ~= "table" then
				error(`{path}: [dispatch] is a table`, 0)
			end
			for k, v in value do
				if k == "auto_merge" then
					if type(v) ~= "table" then
						error(`{path}: dispatch.auto_merge is a list of gates ({list(models.GATES)})`, 0)
					end
					for _, g in v do
						if type(g) ~= "string" or not table.find(models.GATES, g) then
							error(
								`{path}: dispatch.auto_merge names {tostring(g)}: the dispatcher may merge only {list(
									models.GATES
								)} (the run's PR is a human's)`,
								0
							)
						end
					end
					layer.settings.autoMerge = table.clone(v)
				elseif k == "stall_seconds" or k == "tool_seconds" then
					if not count(v) then
						error(`{path}: dispatch.{k} is a whole number of seconds, at least 1`, 0)
					end
					layer.settings[if k == "stall_seconds" then "stallSeconds" else "toolSeconds"] = v
				else
					error(
						`{path}: dispatch.{k} is not a setting (auto_merge, stall_seconds, tool_seconds)`,
						0
					)
				end
			end
		elseif key == "rounds" then
			if type(value) ~= "table" then
				error(`{path}: [rounds] is a table`, 0)
			end
			local leaves: { [string]: number } = {}
			for k, v in value do
				if k == "idea" then
					if not roundCount(v) then
						error(`{path}: rounds.idea is a whole number, 1 to 99`, 0)
					end
					leaves.idea = v
				elseif k == "design" or k == "code" then
					if type(v) ~= "table" then
						error(`{path}: rounds.{k} is a table of levels ({list(rounds.LEVELS)})`, 0)
					end
					for lvl, n in v do
						if type(lvl) ~= "string" or not table.find(rounds.LEVELS, lvl) then
							error(
								`{path}: rounds.{k}.{tostring(lvl)} is not a level ({list(rounds.LEVELS)})`,
								0
							)
						end
						if not roundCount(n) then
							error(`{path}: rounds.{k}.{lvl} is a whole number, 1 to 99`, 0)
						end
						leaves[`{k}.{lvl}`] = n
					end
				else
					error(`{path}: rounds.{tostring(k)} is not a setting (idea, design, code)`, 0)
				end
			end
			layer.rounds = leaves
		elseif key == "clis" then
			if type(value) ~= "table" then
				error(`{path}: [clis] is a table`, 0)
			end
			for name, fields in value do
				layer.clis[name] = parseCli(path, name, fields)
			end
		elseif key == "activities" then
			if type(value) ~= "table" then
				error(`{path}: [activities] is a table`, 0)
			end
			layer.hasActivities = true
			for name, fields in value do
				layer.activities[name] = parseActivity(path, name, fields)
			end
		elseif key == "roles" or key == "fallback" then
			if type(value) ~= "table" then
				error(`{path}: [{key}] is a table`, 0)
			end
			for name, fields in value do
				if type(name) ~= "string" or type(fields) ~= "table" then
					error(`{path}: [{key}.{tostring(name)}] is a table`, 0)
				end
				local out: { [string]: any } = {}
				for field, v in fields do
					if key == "roles" and field == "fallbacks" then
						if type(v) ~= "table" then
							error(`{path}: roles.{name}.fallbacks is a list of CLIs`, 0)
						end
						local seen: { [string]: boolean } = {}
						for _, cli in v do
							if type(cli) ~= "string" or not isCli(cli) then
								error(
									`{path}: roles.{name}.fallbacks names {tostring(cli)}, which is not a supported CLI ({list(
										models.CLIS
									)})`,
									0
								)
							end
							if seen[cli] then
								error(`{path}: roles.{name}.fallbacks names {cli} twice`, 0)
							end
							seen[cli] = true
						end
						out.fallbacks = table.clone(v)
					elseif key == "roles" and field == "author" then
						if type(v) ~= "string" or v == "" then
							error(`{path}: roles.{name}.author is a role name`, 0)
						end
						out.author = v
					elseif key == "roles" and field == "cli" then
						if type(v) ~= "string" or not isCli(v) then
							error(
								`{path}: roles.{name}.cli is {tostring(v)}, which is not a supported CLI ({list(
									models.CLIS
								)})`,
								0
							)
						end
						out.cli = v
					elseif key == "fallback" and field == "cli" then
						error(`{path}: fallback.{name}.cli is the table name, not a field`, 0)
					elseif
						key == "fallback"
						and (field == "rank" or field == "max_tokens" or field == "effort")
					then
						error(`{path}: fallback.{name}.{field} belongs to the role, not the fallback`, 0)
					else
						local want = FIELDS[field]
						if not want then
							error(
								`{path}: {key}.{name}.{field} is not a field (model, effort, rank, runtime, max_tokens, max_calls, max_minutes{if key
										== "roles"
									then ", fallbacks, author"
									else ""})`,
								0
							)
						end
						if want == "count" and not count(v) then
							error(`{path}: {key}.{name}.{field} is a whole number, at least 1`, 0)
						elseif want == "string" and (type(v) ~= "string" or v == "") then
							error(`{path}: {key}.{name}.{field} is a non-empty string`, 0)
						end
						if (field == "model" or field == "effort") and not ledger.isModel(v) then
							error(
								`{path}: {key}.{name}.{field} is {v}, not a model id the ledger takes (letters, digits, '.', '_', '-')`,
								0
							)
						end
						out[field] = v
					end
				end
				if key == "roles" and out.cli ~= nil and not isCli(out.cli) then
					error(
						`{path}: roles.{name}.cli is {tostring(out.cli)}, which is not a supported CLI ({list(
							models.CLIS
						)})`,
						0
					)
				end
				if key == "fallback" and not isCli(name) then
					error(`{path}: [fallback.{name}]: {name} is not a supported CLI ({list(models.CLIS)})`, 0)
				end
				local boundCli = if key == "fallback" then name else out.cli
				if out.model ~= nil and type(boundCli) == "string" and isCli(boundCli) then
					if string.match(out.model, MODEL_OF_CLI[boundCli]) == nil then
						error(`{path}: {key}.{name}.model is {out.model}, not a model of cli {boundCli}`, 0)
					end
				end
				if out.runtime ~= nil and type(boundCli) == "string" and isCli(boundCli) then
					if not table.find(models.RUNTIMES[boundCli], out.runtime) then
						error(
							`{path}: {key}.{name}.runtime is {out.runtime}, which is not a runtime of {boundCli} ({list(
								models.RUNTIMES[boundCli]
							)})`,
							0
						)
					end
				end
				if key == "roles" then
					layer.roles[name] = out
				else
					layer.fallbacks[name] = out
				end
			end
		else
			error(
				`{path}: [{key}] is not read (the file has clis, activities, roles, fallback, dispatch and rounds; skill tables are gone)`,
				0
			)
		end
	end
	return layer
end

-- The folders from the repository root down to `dir` (repo-relative, "" or "." for the root itself), root first.
function models.folders(dir: string): { string }
	local out = { "." }
	local acc = ""
	for part in string.gmatch(dir, "[^/]+") do
		if part ~= "." then
			acc = if acc == "" then part else `{acc}/{part}`
			table.insert(out, acc)
		end
	end
	return out
end

-- Reads every .models.toml on the walk from `repo` down to `dir`, root first.
function models.walk(repo: string, dir: string): { Layer }
	local layers: { Layer } = {}
	for _, folder in models.folders(dir) do
		local rel = if folder == "." then models.FILE else `{folder}/{models.FILE}`
		local path = `{repo}/{rel}`
		if fs.isFile(path) then
			table.insert(layers, models.parse(fs.readFile(path), rel))
		end
	end
	return layers
end

-- The settings on a walk, each replaced by the closest file that sets it. An unset auto_merge is no auto-merge: a
-- merge the dispatcher makes itself must be asked for (c0117 review 001 F7).
function models.settings(layers: { Layer }): Settings
	local s: Settings =
		{ autoMerge = {}, stallSeconds = models.STALL_SECONDS, toolSeconds = models.TOOL_SECONDS }
	for _, layer in layers do
		for _, k in { "autoMerge", "stallSeconds", "toolSeconds" } do
			if layer.settings[k] ~= nil then
				(s :: any)[k] = layer.settings[k]
			end
		end
	end
	return s
end

-- f0421: the review round limits on a walk. They start from the seed and the closest file replaces only the leaves it sets.
function models.rounds(layers: { Layer }): rounds.Limits
	local out: rounds.Limits = {
		idea = rounds.DEFAULT.idea,
		design = table.clone(rounds.DEFAULT.design),
		code = table.clone(rounds.DEFAULT.code),
	}
	for _, layer in layers do
		local leaves: { [string]: number } = layer.rounds or {}
		for leaf, n in leaves do
			if leaf == "idea" then
				out.idea = n
			else
				local stage, lvl = string.match(leaf, "^(%a+)%.(%a+)$")
				if stage == "design" then
					out.design[lvl :: string] = n
				elseif stage == "code" then
					out.code[lvl :: string] = n
				end
			end
		end
	end
	return out
end

-- Every .models.toml on the walk to `dir` as tracked at a pinned commit, root first (design review 002 F5: settings,
-- caps and models never come from the working tree). `read(path)` gives the file's text at that commit, or nil;
-- `present(path)` says whether the working tree has one there. A working-tree file the commit doesn't track (new,
-- untracked or ignored) is an error: only committed model files count.
function models.walkAt(
	dir: string,
	read: (path: string) -> string?,
	present: (path: string) -> boolean
): { Layer }
	local layers: { Layer } = {}
	for _, folder in models.folders(dir) do
		local rel = if folder == "." then models.FILE else `{folder}/{models.FILE}`
		local text = read(rel)
		if text then
			table.insert(layers, models.parse(text :: string, rel))
		elseif present(rel) then
			error(
				`{rel} is not committed: only a .models.toml on main counts (commit it through a pull request)`,
				0
			)
		end
	end
	return layers
end

-- Which role runs a step. A review's mode picks its challenge; every other model step has one role.
function models.roleFor(skill: string, mode: string?): string?
	if skill == "zz-review" then
		if mode == "design" then
			return "design-challenge"
		elseif mode == "final" then
			return "final-review"
		elseif mode == "raft" then
			-- The raft and a review of it are both Opus in the owner's table, as design and
			-- design-challenge are. A challenge role with author = "raft" would drop Opus and
			-- the review would run a fallback, so the same-model stop is pointless here.
			return "raft"
		end
		return "code-review"
	end
	local named = {
		["z-ticket"] = "idea",
		["z-design"] = "design",
		["z-raft"] = "raft",
		["z-run"] = "implementation",
		idea = "idea",
		["idea-challenge"] = "idea-challenge",
	}
	return named[skill]
end

local function specFrom(cli: any, fields: { [string]: any }, path: string, label: string): Spec
	if type(cli) ~= "string" or cli == "" then
		error(`{path}: {label} has no cli`, 0)
	end
	for _, k in REQUIRED do
		if fields[k] == nil then
			error(`{path}: {label} has no {k} (every model has model, rank, runtime and max_tokens)`, 0)
		end
	end
	return {
		cli = cli,
		model = fields.model,
		effort = fields.effort,
		rank = fields.rank,
		runtime = fields.runtime,
		maxTokens = fields.max_tokens,
		maxCalls = fields.max_calls,
		maxMinutes = fields.max_minutes,
	}
end

-- A fallback try: the model's id and runtime (and the CLI's own caps), the stage's rank, cap and effort.
local function fallbackTry(
	cli: string,
	modelFields: { [string]: any },
	stage: { [string]: any },
	path: string,
	label: string
): Spec
	if modelFields.model == nil or modelFields.runtime == nil then
		error(`{path}: {label} has no model or runtime`, 0)
	end
	if stage.rank == nil or stage.max_tokens == nil then
		error(`{path}: {label} has no rank or max_tokens from its role`, 0)
	end
	if models.CALL_CAPPED[cli] and modelFields.max_calls == nil then
		error(
			`{path}: {label} has no max_calls ({cli} reports no running token count, so its step stops after max_calls model calls; calls are not tokens: tune it)`,
			0
		)
	end
	if models.CALL_CAPPED[cli] and modelFields.max_minutes == nil then
		error(
			`{path}: {label} has no max_minutes ({cli}'s call count can miss calls, so its step also stops at a wall-time ceiling)`,
			0
		)
	end
	return {
		cli = cli,
		model = modelFields.model,
		effort = stage.effort,
		rank = stage.rank,
		runtime = modelFields.runtime,
		maxTokens = stage.max_tokens,
		maxCalls = modelFields.max_calls,
		maxMinutes = modelFields.max_minutes,
	}
end

local function needsCallCap(spec: Spec, path: string, label: string)
	if not models.CALL_CAPPED[spec.cli] then
		return
	end
	if spec.maxCalls == nil then
		error(
			`{path}: {label} has no max_calls ({spec.cli} reports no running token count, so its step stops after max_calls model calls; calls are not tokens: tune it)`,
			0
		)
	end
	if spec.maxMinutes == nil then
		error(
			`{path}: {label} has no max_minutes ({spec.cli}'s call count can miss calls, so its step also stops at a wall-time ceiling)`,
			0
		)
	end
end

-- The role on a walk. A closer file replaces only the keys it sets. The try order is the role's CLI, then its
-- fallbacks. `author` names another role: that role's model is dropped from the tries.
function models.resolveRole(layers: { Layer }, role: string, authorRole: string?): Resolved
	if #layers == 0 then
		error(`no {models.FILE} on the walk: nothing defaults (add one at the repository root)`, 0)
	end
	local fields: { [string]: any } = {}
	local fallbacks: { [string]: { [string]: any } } = {}
	local named = false
	for _, layer in layers do
		local mine = layer.roles[role]
		if mine then
			named = true
			for k, v in mine do
				fields[k] = v
			end
		end
		for cli, f in layer.fallbacks do
			fallbacks[cli] = fallbacks[cli] or {}
			for k, v in f do
				fallbacks[cli][k] = v
			end
		end
	end
	if not named then
		error(`no {models.FILE} on the walk names role {role}`, 0)
	end
	local where = layers[#layers].path
	local primary = specFrom(fields.cli, fields, where, `roles.{role}`)
	needsCallCap(primary, where, `roles.{role}`)
	local order = { primary.cli }
	local specs: { [string]: Spec } = { [primary.cli] = primary }
	for _, cli in fields.fallbacks or {} do
		local fb = fallbacks[cli]
		if not fb then
			error(`{role}: fallback {cli} has no [fallback.{cli}] on the walk`, 0)
		end
		if specs[cli] == nil then
			local spec = fallbackTry(cli, fb, fields, where, `fallback.{cli}`)
			table.insert(order, cli)
			specs[cli] = spec
		end
	end
	local authorModel: string? = nil
	local authorName = authorRole or fields.author
	if authorName ~= nil then
		if authorName == role then
			error(`{role}: author is itself; a challenge cannot name its own role`, 0)
		end
		local author = models.resolveRole(layers, authorName)
		authorModel = models.id(author.specs[author.order[1]])
	end
	return {
		skill = role,
		order = order,
		specs = specs,
		settings = models.settings(layers),
		authorModel = authorModel,
		fromRoles = true,
	}
end

-- The role a step runs. A closer layer replaces only the keys it sets. Errors: no file on the walk, no role
-- for the step, a spec missing a field.
-- f0420 step 3: the final review of a raft that took the light path is the only review the code gets, so it is never
-- run on the model that wrote the code (`light`): the author exclusion code-review has.
function models.resolve(layers: { Layer }, skill: string, mode: string?, light: boolean?): Resolved
	local role = models.roleFor(skill, mode)
	if not role then
		error(`{skill} is not a model step`, 0)
	end
	return models.resolveRole(
		layers,
		role,
		if light == true and role == "final-review" then "implementation" else nil
	)
end

-- The more powerful of the specs, whole: the higher rank, then the larger max_tokens; a tie keeps the first.
function models.strongest(specs: { Spec }): Spec
	if #specs == 0 then
		error("strongest of no specs", 0)
	end
	local best = specs[1]
	for i = 2, #specs do
		local s = specs[i]
		if s.rank > best.rank or (s.rank == best.rank and s.maxTokens > best.maxTokens) then
			best = s
		end
	end
	return best
end

-- A raft's step: `order` and settings from the raft's own walk, and for each CLI the strongest of its members'
-- specs (rafts never cross projects, so the members share the walk down to their project).
function models.forRaft(own: Resolved, members: { Resolved }): Resolved
	if #members == 0 then
		error(`{own.skill}: a raft with no member has no spec`, 0)
	end
	local specs: { [string]: Spec } = {}
	for _, cli in models.CLIS do
		local candidates: { Spec } = {}
		for _, m in members do
			if m.specs[cli] then
				table.insert(candidates, m.specs[cli])
			end
		end
		if #candidates > 0 then
			specs[cli] = models.strongest(candidates)
		end
	end
	return { skill = own.skill, order = own.order, specs = specs, settings = own.settings }
end

-- The CLIs to try, in order: those of `order` that have a spec for the skill. Empty is an error naming the skill.
function models.tries(r: Resolved): { Spec }
	local out: { Spec } = {}
	for _, cli in r.order do
		local spec = r.specs[cli]
		if spec and (r.authorModel == nil or models.id(spec) ~= r.authorModel) then
			table.insert(out, spec)
		end
	end
	if #out == 0 and r.authorModel ~= nil then
		error(
			`{r.skill}: the only model left is the author's ({r.authorModel}); a challenge is never run by the model that wrote the text`,
			0
		)
	end
	if #out == 0 then
		error(`{r.skill}: no CLI in the order ({list(r.order)}) has a spec for it`, 0)
	end
	return out
end

-- The model id a spend row records: the model, and its effort when the spec sets one (model, then a hyphen, then the effort).
function models.id(spec: Spec): string
	return if spec.effort then `{spec.model}-{spec.effort}` else spec.model
end

-- ---------------------------------------------------------------------------------------------------------------
-- f0421 slice 2: aliases and models per activity. Pure: layers in, specs and problems out. `models.resolve` above is the
-- legacy role lookup the dispatcher still calls (step 6 moves it), so the activity lookup is `resolveActivity`.
-- ---------------------------------------------------------------------------------------------------------------

export type CliDef = {
	aliases: { [string]: Setting },
	models: { string },
	runtime: string,
	maxCalls: number?,
	maxMinutes: number?,
}
-- `legacy` is a walk with no [activities] in any file: `clis` and `activities` are empty and every lookup reads roles.
export type Config = {
	legacy: boolean,
	clis: { [string]: CliDef },
	activities: { [string]: { maxTokens: number?, settings: { [string]: Setting } } },
}

local ALIAS_RANK: { [string]: number } = { xlight = 1, light = 2, heavy = 3, ultra = 4 }
local EFFORT_SUFFIXES = { "-low", "-medium", "-high", "-xhigh", "-max" }

-- True when `a` and `b` are one model once a trailing effort suffix is removed (a ledger id carries the effort).
function models.sameModel(a: string, b: string?): boolean
	if b == nil then
		return false
	end
	local function bare(m: string): string
		for _, suffix in EFFORT_SUFFIXES do
			if #m > #suffix and string.sub(m, -#suffix) == suffix then
				return string.sub(m, 1, #m - #suffix)
			end
		end
		return m
	end
	return bare(string.lower(a)) == bare(string.lower(b))
end

function models.isActivity(name: string): boolean
	return table.find(models.ACTIVITIES, name) ~= nil or WRITER_OF[name] ~= nil
end

-- The activity whose setting `activity` uses (design-answer uses design's, and so on); every other activity is its own.
local function settingActivity(activity: string): string
	local named = WRITER_OF[activity] or activity
	if table.find(models.ACTIVITIES, named) == nil then
		error(`{activity} is not an activity ({list(models.ACTIVITIES)})`, 0)
	end
	return named
end

-- The activity a skill (and review mode) runs; nil for a skill that runs no model.
function models.activityFor(skill: string, mode: string?): string?
	if skill == "zz-review" then
		if mode == "design" then
			return "design-review"
		elseif mode == "raft" then
			return "raft-review"
		elseif mode == "final" then
			return "final-review"
		end
		return "code-review"
	end
	local named = {
		["z-ticket"] = "idea",
		idea = "idea",
		["idea-challenge"] = "idea-challenge",
		["z-design"] = "design",
		["z-raft"] = "raft",
		["z-run"] = "code",
		["z-approve"] = "approve",
		approve = "approve",
	}
	return named[skill]
end

-- The levels an activity sets: each of the three, or `all` for a one-setting activity.
local function levelsOf(activity: string): { string }
	return if ONE_SETTING[activity] then { "all" } else rounds.LEVELS
end

-- The setting an activity has at a level: the level's own key, else `all`.
local function settingAt(cfg: Config, activity: string, level: string): Setting?
	local a = cfg.activities[activity]
	if a == nil then
		return nil
	end
	return a.settings[level] or a.settings.all
end

local function needOf(setting: Setting): string
	if setting.alias then
		return setting.alias
	end
	local model = setting.model :: string
	return if setting.effort then `{model}-{setting.effort}` else model
end

-- One CLI's spec for a setting: an alias when the CLI defines it, a specific model when the CLI has it.
local function specFor(cli: string, def: CliDef?, setting: Setting, maxTokens: number): (Spec?, string?)
	local alias = setting.alias
	if alias ~= nil then
		local d = if def then def.aliases[alias] else nil
		if d == nil or def == nil then
			return nil, `{cli} does not define {alias}`
		end
		return {
			cli = cli,
			model = d.model :: string,
			effort = d.effort,
			context = d.context,
			alias = alias,
			rank = ALIAS_RANK[alias],
			runtime = def.runtime,
			maxTokens = maxTokens,
			maxCalls = def.maxCalls,
			maxMinutes = def.maxMinutes,
		},
			nil
	end
	local model = setting.model :: string
	local rank = 0
	local has = false
	if def then
		for a, d in def.aliases do
			if d.model == model then
				has = true
				rank = math.max(rank, ALIAS_RANK[a])
			end
		end
		if table.find(def.models, model) then
			has = true
		end
	end
	if not has or def == nil then
		return nil, `{cli} does not have {model}`
	end
	return {
		cli = cli,
		model = model,
		effort = setting.effort,
		context = setting.context,
		rank = rank,
		runtime = def.runtime,
		maxTokens = maxTokens,
		maxCalls = def.maxCalls,
		maxMinutes = def.maxMinutes,
	},
		nil
end

-- Merges a new-shape walk and runs the load checks. A closer file replaces an alias, a `models` list and a level's
-- setting whole, and `max_tokens`, `runtime`, `max_calls` and `max_minutes` singly. Within one file a level key beats that
-- file's `all`; across files a closer file's `all` replaces every level the farther files set (each file's `all` is
-- expanded into its three levels before the merge). An error names the file its faulty key is in.
local function mergeNew(layers: { Layer }): Config
	local last = #layers
	local function at(i: number?): string
		return layers[i or last].path
	end
	local clisRaw: { [string]: { [string]: any } } = {}
	local cliAt: { [string]: number } = {}
	local actsRaw: { [string]: { [string]: any } } = {}
	local actAt: { [string]: number } = {}
	local actSrc: { [string]: { [string]: number } } = {}
	for i, layer in layers do
		for cli, fields in layer.clis do
			clisRaw[cli] = clisRaw[cli] or {}
			cliAt[cli] = i
			for k, v in fields do
				clisRaw[cli][k] = v
			end
		end
		for act, fields in layer.activities do
			actsRaw[act] = actsRaw[act] or {}
			actSrc[act] = actSrc[act] or {}
			actAt[act] = i
			local expanded = table.clone(fields)
			if not ONE_SETTING[act] and fields.all ~= nil then
				for _, lvl in rounds.LEVELS do
					if expanded[lvl] == nil then
						expanded[lvl] = fields.all
					end
				end
				expanded.all = nil
			end
			for k, v in expanded do
				actsRaw[act][k] = v
				actSrc[act][k] = i
			end
		end
	end
	local cfg: Config = { legacy = false, clis = {}, activities = {} }
	for cli, raw: { [string]: any } in clisRaw do
		local def: CliDef = {
			aliases = {},
			models = raw.models or {},
			runtime = raw.runtime or models.RUNTIMES[cli][1],
			maxCalls = raw.max_calls,
			maxMinutes = raw.max_minutes,
		}
		for _, alias in models.ALIASES do
			if raw[alias] ~= nil then
				def.aliases[alias] = raw[alias]
			end
		end
		if models.CALL_CAPPED[cli] and def.maxCalls == nil then
			error(
				`{at(cliAt[cli])}: clis.{cli} has no max_calls ({cli} reports no running token count, so its step stops after max_calls model calls; calls are not tokens: tune it)`,
				0
			)
		end
		if models.CALL_CAPPED[cli] and def.maxMinutes == nil then
			error(
				`{at(cliAt[cli])}: clis.{cli} has no max_minutes ({cli}'s call count can miss calls, so its step also stops at a wall-time ceiling)`,
				0
			)
		end
		cfg.clis[cli] = def
	end
	for _, act in models.ACTIVITIES do
		local raw: { [string]: any } = actsRaw[act] or {}
		local settings: { [string]: Setting } = {}
		for _, k in { "easy", "normal", "risky", "all" } do
			if raw[k] ~= nil then
				settings[k] = raw[k]
			end
		end
		cfg.activities[act] = { maxTokens = raw.max_tokens, settings = settings }
		for _, lvl in levelsOf(act) do
			if settings[lvl] == nil and settings.all == nil then
				error(`{at(actAt[act])}: activities.{act} has no setting for {lvl}`, 0)
			end
		end
		if raw.max_tokens == nil then
			error(`{at(actAt[act])}: activities.{act} has no max_tokens`, 0)
		end
	end
	-- the walk index of the file that set an activity's setting at a level
	local function srcOf(act: string, lvl: string): number
		local src: { [string]: number } = actSrc[act] or {}
		return src[if ONE_SETTING[act] then "all" else lvl] or src.all or last
	end
	for _, act in models.ACTIVITIES do
		for _, lvl in levelsOf(act) do
			local setting = settingAt(cfg, act, if lvl == "all" then "normal" else lvl) :: Setting
			local delivered = false
			for _, cli in models.CLIS do
				if specFor(cli, cfg.clis[cli], setting, 1) ~= nil then
					delivered = true
					break
				end
			end
			if not delivered then
				error(
					`{at(srcOf(act, lvl))}: activities.{act}.{lvl} needs {needOf(setting)} and no CLI in [clis] delivers it`,
					0
				)
			end
		end
	end
	for _, lvl in rounds.LEVELS do
		for _, pair in models.PAIRS do
			local once = ONE_SETTING[pair[1]] and ONE_SETTING[pair[2]]
			if not once or lvl == "easy" then
				for _, cli in models.CLIS do
					local ws = settingAt(cfg, pair[1], lvl) :: Setting
					local rs = settingAt(cfg, pair[2], lvl) :: Setting
					local w = specFor(cli, cfg.clis[cli], ws, 1)
					local r = specFor(cli, cfg.clis[cli], rs, 1)
					if w and r and models.sameModel(w.model, r.model) then
						local when = if once then "at every level" else `at level {lvl}`
						error(
							`{at(math.max(srcOf(pair[1], lvl), srcOf(pair[2], lvl)))}: {when}, {pair[1]} and {pair[2]} both resolve to {w.model} on {cli}: a reviewer never runs on the writer's model`,
							0
						)
					end
				end
			end
		end
	end
	return cfg
end

-- The configuration of a walk: merged, and checked. Every function below calls it, so a bad file fails before any
-- activity starts. A walk with no [activities] in any file is legacy (roles and fallbacks, as before step 9).
function models.config(layers: { Layer }): Config
	if #layers == 0 then
		error(`no {models.FILE} on the walk: nothing defaults (add one at the repository root)`, 0)
	end
	for _, layer in layers do
		if layer.hasActivities then
			return mergeNew(layers)
		end
	end
	return { legacy = true, clis = {}, activities = {} }
end

local function legacySpec(layers: { Layer }, cli: string, activity: string): (Spec?, string?)
	local role = ROLE_OF[activity]
	local named = false
	for _, layer in layers do
		if layer.roles[role] then
			named = true
		end
	end
	if not named then
		return nil, `no {models.FILE} on the walk names role {role} ({activity} runs on it)`
	end
	local r = models.resolveRole(layers, role)
	local spec = r.specs[cli]
	if spec == nil then
		return nil, `{cli} is not the cli of role {role} or one of its fallbacks`
	end
	if r.authorModel ~= nil and models.id(spec) == r.authorModel then
		return nil, `{spec.model} wrote the text: a reviewer never runs on the writer's model`
	end
	return spec, nil
end

local function resolveIn(
	cfg: Config,
	layers: { Layer },
	cli: string,
	activity: string,
	level: string,
	author: string?
): (Spec?, string?)
	local act = settingActivity(activity)
	if not isCli(cli) then
		return nil, `{cli} is not a supported CLI ({list(models.CLIS)})`
	end
	local spec: Spec?
	local why: string?
	if cfg.legacy then
		spec, why = legacySpec(layers, cli, act)
	else
		local setting = settingAt(cfg, act, level) :: Setting
		spec, why = specFor(cli, cfg.clis[cli], setting, cfg.activities[act].maxTokens :: number)
	end
	if spec == nil then
		return nil, why
	end
	-- a legacy walk compares the caller's author with today's exact id (`tries`: model and effort), beside the role's own
	-- `author` (legacySpec); a new-shape walk compares the model alone, ignoring effort and case
	local same = if cfg.legacy
		then author ~= nil and models.id(spec) == author
		else models.sameModel(spec.model, author)
	if same then
		return nil, `{spec.model} wrote the text: a reviewer never runs on the writer's model`
	end
	return spec, nil
end

-- A level, or nil and the problem naming it (nil is normal).
local function checkedLevel(level: string?): (string?, string?)
	local l = level or "normal"
	if not table.find(rounds.LEVELS, l) then
		return nil, `{tostring(l)} is not a level ({list(rounds.LEVELS)})`
	end
	return l, nil
end

-- The spec `cli` runs `activity` on at `level` (nil is normal), or nil and why it cannot. A reviewer is refused on the
-- model `author` names (the model that wrote the text; effort ignored).
function models.resolveActivity(
	layers: { Layer },
	cli: string,
	activity: string,
	level: rounds.Level?,
	author: string?
): (Spec?, string?)
	local cfg = models.config(layers)
	local lvl, problem = checkedLevel(level)
	if lvl == nil then
		return nil, problem
	end
	return resolveIn(cfg, layers, cli, activity, lvl, author)
end

function models.can(layers: { Layer }, cli: string, activity: string, level: rounds.Level?): boolean
	return models.resolveActivity(layers, cli, activity, level, nil) ~= nil
end

-- Every `activity/level` pair `can` gives, in ACTIVITIES order and then easy, normal, risky. A one-setting activity
-- appears at each level, so a filter matches by plain membership.
function models.canList(layers: { Layer }, cli: string): { string }
	local cfg = models.config(layers)
	local out: { string } = {}
	for _, act in models.ACTIVITIES do
		for _, lvl in rounds.LEVELS do
			if resolveIn(cfg, layers, cli, act, lvl, nil) ~= nil then
				table.insert(out, `{act}/{lvl}`)
			end
		end
	end
	return out
end

-- The CLIs that can deliver `activity` at `level`, in CLIS order (a legacy walk: the role's CLI and its fallbacks).
function models.deliverers(layers: { Layer }, activity: string, level: rounds.Level?): { string }
	local cfg = models.config(layers)
	local lvl, problem = checkedLevel(level)
	if lvl == nil then
		error(problem :: string, 0)
	end
	local out: { string } = {}
	for _, cli in models.CLIS do
		if resolveIn(cfg, layers, cli, activity, lvl, nil) ~= nil then
			table.insert(out, cli)
		end
	end
	return out
end

-- What an activity needs at a level: the alias name, or a specific setting's id (model and effort). On a legacy walk,
-- the model id its role's own CLI runs.
function models.need(layers: { Layer }, activity: string, level: rounds.Level?): string
	local cfg = models.config(layers)
	local act = settingActivity(activity)
	local lvl, problem = checkedLevel(level)
	if lvl == nil then
		error(problem :: string, 0)
	end
	if cfg.legacy then
		local role = ROLE_OF[act]
		for _, layer in layers do
			if layer.roles[role] then
				local r = models.resolveRole(layers, role)
				return models.id(r.specs[r.order[1]])
			end
		end
		return `role {role}` -- the file has no such role: nothing delivers it
	end
	return needOf(settingAt(cfg, act, lvl) :: Setting)
end

-- f0421 step 6: the one CLI that runs an activity: `--cli`, then ZN_CLI, then on a legacy walk the role's own `cli` (today's
-- first try). A new-shape walk with neither names no CLI: the problem says so (`who` is the command: dispatch, idea, ...).
function models.cliFor(
	layers: { Layer },
	activity: string,
	flag: string?,
	named: string?,
	who: string
): (string?, string?)
	if flag ~= nil and flag ~= "" then
		return flag, nil
	end
	if named ~= nil and named ~= "" then
		return named, nil
	end
	local cfg = models.config(layers)
	local act = settingActivity(activity)
	if cfg.legacy then
		local role = ROLE_OF[act]
		for _, layer in layers do
			if layer.roles[role] then
				local r = models.resolveRole(layers, role)
				return r.order[1], nil
			end
		end
		return nil, `no {models.FILE} on the walk names role {role} ({activity} runs on it)`
	end
	return nil, `{who}: which CLI runs {activity}? pass --cli <name> or set ZN_CLI`
end

-- The refusal for a CLI that cannot deliver `activity` at `level` (`why` is the reason resolveActivity gave): it names the
-- activity, the CLI and what the activity needs (a legacy walk: the role's model), and what the person can do. No other
-- CLI is ever tried for it.
function models.refusal(
	layers: { Layer },
	cli: string,
	activity: string,
	level: rounds.Level?,
	why: string?
): string
	local lvl: rounds.Level = level or "normal"
	local need = models.need(layers, activity, lvl)
	local who = models.deliverers(layers, activity, lvl)
	local clis = if #who > 0 then table.concat(who, ", ") else "none"
	local author =
		string.match(why or "", "^(.+) wrote the text: a reviewer never runs on the writer's model$")
	if author ~= nil then
		-- the reviewer's own model is the writer's (today's wording of models.tries, kept)
		return `{activity}: the only model left is the author's ({author}); a challenge is never run by the model that wrote the text: start a worker whose CLI has {need} on another model ({clis}), or set --cli`
	end
	return `{cli} cannot deliver {activity}/{lvl} ({need}): {why or "it does not"}; start a worker whose CLI has {need} ({clis}), or set --cli`
end

-- The spec of one alias on a CLI (`./zn model light`): nil and why when the CLI does not define it, or when the walk is
-- legacy and defines no aliases at all.
function models.resolveAlias(layers: { Layer }, cli: string, alias: string): (Spec?, string?)
	local cfg = models.config(layers)
	if not isCli(cli) then
		return nil, `{cli} is not a supported CLI ({list(models.CLIS)})`
	end
	if cfg.legacy then
		return nil,
			`{cli} does not define {alias}: this walk has no [activities] yet, so it defines no aliases`
	end
	return specFor(cli, cfg.clis[cli], { alias = alias }, 1)
end

return models
