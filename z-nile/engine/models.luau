--!strict
-- .models.toml (c0117): which model runs each stage, on which CLI, and which fallbacks follow it.
-- The files stack like .gitignore: from the repository root down to the work, a closer file replaces only the keys
-- it sets. Pure apart from `load`/`walk`, which read the files.
--
-- Contract for the Python port. One shape. A role names what belongs to the stage: `model`, `cli`, `runtime`,
-- `rank`, `max_tokens`, `effort`, and `fallbacks` (CLI names, in order). A fallback names what belongs to the
-- model: `[fallback.<cli>]` has `model`, `runtime`, and anything only that CLI needs (`max_calls` and
-- `max_minutes` for `agent`). A try is the role's rank, cap and effort on the fallback's model. A challenge
-- role sets `author` to the role that wrote the text; a try whose model id equals that author's comes after the others
-- (allowed, not preferred), and an empty list fails at resolve. A role or fallback that names an unknown model or CLI fails in `parse`
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
--   author = "idea"        -- prefer another model than the author's (its own is tried last)
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
local skillsLib = require("./skills")

local models = {}

models.FILE = ".models.toml"
-- The supported CLIs (the user's decision: `agent` is Cursor's), each with its one local runtime (the remote ones are c0142's).
models.CLIS = { "claude", "grok", "agent", "kimi", "agy" }
-- Only claude can start a subagent on another model (modelcmd.subagentWord): any other CLI's session runs one model.
function models.hasSubagents(cli: string): boolean
	return cli == "claude"
end
models.RUNTIMES = {
	-- the local runtimes only: the remote ones (claude-cloud, grok-bot, cursor-app) are c0142's (the user's G8)
	claude = { "claude-cli" },
	grok = { "grok-cli" },
	agent = { "cursor-cli" },
	kimi = { "kimi-cli" },
	agy = { "agy-cli" },
} :: { [string]: { string } }
-- A model id the CLI accepts, by its patterns. A role that names anything else fails when the file is loaded. agy runs
-- Gemini, Claude Opus, Claude Sonnet and GPT-OSS (`agy models`, tests/fixtures/models/agy-models.txt; f0421 slice 3).
local MODEL_OF_CLI: { [string]: { string } } = {
	claude = { "^claude%-[%w%._%-]+$" },
	grok = { "^grok%-[%w%._%-]+$" },
	kimi = { "^kimi%-code%-[%w%._%-]+$" },
	agy = {
		"^gemini%-[%w%._%-]+$",
		"^claude%-opus%-[%w%._%-]+$",
		"^claude%-sonnet%-[%w%._%-]+$",
		"^gpt%-oss%-[%w%._%-]+$",
	},
	agent = { "^[%w%._%-]+$" },
}
-- whether `id` is a model of `cli` by its id rule
local function ofCli(cli: string, id: string): boolean
	for _, pattern in MODEL_OF_CLI[cli] do
		if string.match(id, pattern) ~= nil then
			return true
		end
	end
	return false
end
-- The merge gates the dispatcher may pass itself; the run's PR is never one of them.
models.GATES = { "prep", "raft" }
-- f0421 slice 2: the four aliases, weakest first; the activities a configuration sets (per level, or one setting for all);
-- and each writer with its reviewer (a reviewer on another model is preferred; its own model is allowed, owner, 2026-11-24).
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
-- The review activities, from the pairs above (the one definition): a CLI's `[clis.<cli>.review]` aliases serve these.
local REVIEW_ACTIVITY: { [string]: boolean } = {}
for _, pair in models.PAIRS do
	REVIEW_ACTIVITY[pair[2]] = true
end
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
	sameAsAuthor: boolean?, -- set on a review's spec when its model is the one that wrote the text (allowed, not preferred)
	writer: string?, -- with sameAsAuthor: the writer's model that matched, as the record names it
}
-- f0421 slice 2: one setting: an alias name, or a model with its effort and context. In a CLI's table it is an alias's
-- definition (`model` set); in an activity's table it is `alias` or `model`.
-- f0421 slice 3: an entry of a catalog level or of a CLI's list also carries the family it states (`family`), and the first
-- entry of a list carries the entries after it (`rest`), which S1a reads and checks but does not deliver.
export type Setting = {
	alias: string?,
	model: string?,
	effort: string?,
	context: number?,
	family: string?,
	rest: { Setting }?,
	listed: boolean?, -- an entry of a level's list (not the single form): its id rule is checked at the merge
}
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
	catalog: { [string]: { Setting } }?, -- f0421 slice 3: [catalog], every known model per level (the root file only)
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

-- f0421 slice 3: a model's identity, the one definition. An id is a family, then an effort word, then on agent's spelling a
-- `-fast`: `identity` removes a trailing `-fast`, then one effort word (the CLIs' lists also use `none` and `minimal`), and
-- what is left is the family. `sameModel` compares families. A table entry whose family still holds a marker word (`unsplit`)
-- must state its family: the CLIs spell thinking, extra and the effort in other places for some families
-- (tests/tooling/models-identity.spec.luau pins every such id the CLIs list).
local ALIAS_RANK: { [string]: number } = { xlight = 1, light = 2, heavy = 3, ultra = 4 }
local EFFORT_WORDS = { "none", "minimal", "low", "medium", "high", "xhigh", "max" }
local MARKERS: { [string]: boolean } = { fast = true, thinking = true, extra = true }
export type Identity = { family: string, effort: string?, fast: boolean }
function models.identity(id: string): Identity
	local s = string.lower(id)
	local fast = false
	if #s > 5 and string.sub(s, -5) == "-fast" then
		fast = true
		s = string.sub(s, 1, #s - 5)
	end
	for _, word in EFFORT_WORDS do
		local suffix = `-{word}`
		if #s > #suffix and string.sub(s, -#suffix) == suffix then
			return { family = string.sub(s, 1, #s - #suffix), effort = word, fast = fast }
		end
	end
	return { family = s, effort = nil, fast = fast }
end
-- The marker word a family still holds (fast, thinking, extra or an effort word), or nil when it split cleanly.
function models.unsplit(family: string): string?
	for part in string.gmatch(family, "[^-]+") do
		if MARKERS[part] or table.find(EFFORT_WORDS, part) then
			return part
		end
	end
	return nil
end
-- The CLIs whose session files name the model the session runs (sessions.luau reads claude's and grok's): a model a session
-- of any other CLI names in ZN_MODEL is only declared.
models.SESSION_READ = { claude = true, grok = true } :: { [string]: boolean }
-- an entry's id: its model, and its effort when the entry states one apart (the ledger's id, `models.id`)
local function entryId(s: Setting): string
	local model = s.model :: string
	return if s.effort then `{model}-{s.effort}` else model
end
-- what makes two entries one: the id, case and agent's `-fast` ignored (review-005 F3: a stated family is data for the
-- same-model question only, never the key a rank check trusts)
local function entryKey(s: Setting): string
	local id = string.lower(entryId(s))
	if #id > 5 and string.sub(id, -5) == "-fast" then
		return string.sub(id, 1, #id - 5)
	end
	return id
end
-- the CLIs that take the effort as a flag beside a bare model (adapters.luau: claude --effort, grok --reasoning-effort)
local EFFORT_FLAG: { [string]: boolean } = { claude = true, grok = true }
-- whether `offers` (ids, and prefixes ending in `-`) holds `id`: an id is that id only
function models.offered(offers: { string }, id: string): boolean
	local low = string.lower(id)
	for _, o in offers do
		local p = string.lower(o)
		if p == low or (string.sub(p, -1) == "-" and string.sub(low, 1, #p) == p) then
			return true
		end
	end
	return false
end

-- A number of review rounds: a whole number from 1 to 99 (never inf, NaN or a count nobody means).
local function roundCount(v: any): boolean
	return type(v) == "number" and v >= 1 and v <= 99 and v == math.floor(v)
end

-- f0421 slice 2: one `{ model, effort?, context? }`. `cli` (when known) says which model ids are accepted: its id rule (a
-- CLI's `offers`, when stated, narrow that at the merge and never widen it).
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
			if cli ~= nil and not ofCli(cli, x) then
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

-- f0421 slice 3: one entry of a catalog level (`cli` nil) or of a CLI's list: an id, `{ id, family?, context? }`, or (a list
-- only) today's `{ model, effort?, context? }`. A list entry's id is checked against the CLI's offers or id rule when the walk
-- is merged (a closer file's entry meets the merged offers); here only what one file shows is checked.
local function parseEntry(path: string, label: string, i: number, v: any, cli: string?): Setting
	local at = `{label}[{i}]`
	local s: Setting
	if type(v) == "string" then
		if not ledger.isModel(v) then
			error(`{path}: {label} names {v}, which is not a model id`, 0)
		end
		s = { model = v }
	elseif type(v) == "table" and not isList(v) and (v.id ~= nil or cli == nil) then
		s = {}
		for k, x in v do
			if k == "family" and cli ~= nil then
				error(
					`{path}: {at}.family is stated in [catalog] only: a CLI's list names an entry by its id`,
					0
				)
			elseif k == "id" or k == "family" then
				if type(x) ~= "string" or not ledger.isModel(x) then
					error(`{path}: {at}.{k} is a model id (letters, digits, '.', '_', '-')`, 0)
				end
				if k == "id" then
					s.model = x
				else
					s.family = x
				end
			elseif k == "context" then
				if not sane(x) then
					error(`{path}: {at}.context is {tostring(x)}: a whole number of tokens, 1 to {BOUND}`, 0)
				end
				s.context = x
			else
				error(`{path}: {at}.{tostring(k)} is not a field (id, family, context)`, 0)
			end
		end
		if s.model == nil then
			error(`{path}: {at} has no id`, 0)
		end
	elseif type(v) == "table" and not isList(v) then
		-- the single form inside a list; its model meets the CLI's rule at the merge, as every list entry does
		s = parseDef(path, at, nil, v)
		if s.effort ~= nil and models.identity(s.model :: string).effort ~= nil then
			error(`{path}: {at} names its effort twice ({s.model} and effort = {s.effort})`, 0)
		end
	else
		error(
			`{path}: {at} is a model id or {if cli
				then "{ id, family?, context? } or { model, effort?, context? }"
				else "{ id, family?, context? }"}`,
			0
		)
	end
	local id = entryId(s)
	local ident = models.identity(id)
	if ident.fast and s.family == nil then
		if cli == nil then
			error(
				`{path}: {label} names {id}: the catalog names the plain id ({string.sub(id, 1, #id - 5)}), and -fast is a CLI's spelling`,
				0
			)
		elseif cli ~= "agent" then
			error(
				`{path}: {label} names {id}: -fast is a spelling only agent takes (state its family to use it on {cli})`,
				0
			)
		end
	end
	-- a catalog entry states its family when the rule cannot split its id; a list entry is checked at the merge, where the
	-- catalog that would state it is known
	local marker = if s.family == nil and cli == nil then models.unsplit(ident.family) else nil
	if marker ~= nil then
		error(
			`{path}: {label} names {id}, whose family still holds {marker} once its effort is removed: state its family ({"{"} id = "{id}", family = "..." {"}"})`,
			0
		)
	end
	-- review-005 F6: on a CLI that takes the effort as a flag, an id that carries one is the model and that effort, the very
	-- Setting the single form gives
	if cli ~= nil and EFFORT_FLAG[cli] and s.effort == nil and ident.effort ~= nil then
		local effort = ident.effort :: string
		if not table.find(EFFORTS, effort) then
			error(
				`{path}: {label} names {id}: {cli} takes its effort as a flag, and {effort} is not one ({list(
					EFFORTS
				)})`,
				0
			)
		end
		s.model = string.sub(id, 1, #id - #effort - 1)
		s.effort = effort
	end
	if cli ~= nil then
		s.listed = true
	end
	return s
end

-- f0421 slice 3: a level of a CLI's table: today's single `{ model, effort?, context? }`, or an ordered list of entries (the
-- first is what S1a resolves; the rest ride on it as `rest`).
local function parseLevel(path: string, label: string, cli: string, v: any): Setting
	if type(v) ~= "table" or not isList(v) then
		return parseDef(path, label, cli, v)
	end
	if #v == 0 then
		error(`{path}: {label} is empty: name at least one model`, 0)
	end
	local entries: { Setting } = {}
	local seen: { [string]: string } = {}
	for i, item in v do
		local entry = parseEntry(path, label, i, item, cli)
		local key = entryKey(entry)
		if seen[key] ~= nil then
			error(`{path}: {label} names {seen[key]} twice`, 0)
		end
		seen[key] = entryId(entry)
		table.insert(entries, entry)
	end
	local first = entries[1]
	if #entries > 1 then
		first.rest = { table.unpack(entries, 2) }
	end
	return first
end

-- `[clis.<cli>]`: aliases, `models`, `offers`, `runtime`, `max_calls`, `max_minutes`.
local function parseCli(path: string, name: string, fields: any): { [string]: any }
	if type(name) ~= "string" or not isCli(name) then
		error(`{path}: clis.{tostring(name)} is not a supported CLI ({list(models.CLIS)})`, 0)
	end
	if type(fields) ~= "table" then
		error(`{path}: [clis.{name}] is a table`, 0)
	end
	local out: { [string]: any } = {}
	-- f0421 slice 3: the ids and prefixes the CLI runs: read and checked here, and at the merge every entry of the CLI must be
	-- one of them; the CLI's id rule still holds (offers never widen it)
	if fields.offers ~= nil then
		local v = fields.offers
		if type(v) ~= "table" or not isList(v) then
			error(`{path}: clis.{name}.offers is a list of ids and prefixes ending in -`, 0)
		end
		if #v == 0 then
			error(
				`{path}: clis.{name}.offers is empty: name the ids, or prefixes ending in -, that the CLI runs`,
				0
			)
		end
		local ids: { string } = {}
		for _, o in v do
			if type(o) ~= "string" or not ledger.isModel(o) then
				error(`{path}: clis.{name}.offers names {tostring(o)}, which is not an id or a prefix`, 0)
			end
			table.insert(ids, o)
		end
		out.offers = ids
	end
	for k, v in fields do
		if type(k) == "string" and table.find(models.ALIASES, k) then
			out[k] = parseLevel(path, `clis.{name}.{k}`, name, v)
		elseif k == "offers" then
			continue -- read above
		elseif k == "review" then
			-- f0421: the same aliases as the plain ones, as resolved for the review activities
			if type(v) ~= "table" or isList(v) and #v > 0 then
				error(`{path}: clis.{name}.review is a table of aliases (xlight, light, heavy, ultra)`, 0)
			end
			if next(v) == nil then
				error(
					`{path}: clis.{name}.review is empty: name an alias (xlight, light, heavy, ultra) or drop it`,
					0
				)
			end
			local review: { [string]: any } = {}
			for rk, rv in v do
				if type(rk) ~= "string" or not table.find(models.ALIASES, rk) then
					error(
						`{path}: clis.{name}.review.{tostring(rk)} is not an alias ({list(models.ALIASES)})`,
						0
					)
				end
				review[rk] = parseLevel(path, `clis.{name}.review.{rk}`, name, rv)
			end
			out.review = review
		elseif k == "models" then
			if not isList(v) then
				error(`{path}: clis.{name}.models is a list of model ids`, 0)
			end
			local ids: { string } = {}
			for _, m in v do
				if type(m) ~= "string" or not ledger.isModel(m) then
					error(`{path}: clis.{name}.models names {tostring(m)}, which is not a model id`, 0)
				end
				if not ofCli(name, m) then
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
				`{path}: clis.{name}.{tostring(k)} is not an alias or setting (xlight, light, heavy, ultra, review, models, offers, runtime, max_calls, max_minutes)`,
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
		elseif key == "catalog" then
			-- f0421 slice 3: every known model, one ordered list per level; an entry sits at one level only
			if type(value) ~= "table" or (isList(value) and #value > 0) then
				error(`{path}: [catalog] is a table of levels ({list(models.ALIASES)})`, 0)
			end
			for k in value do
				if type(k) ~= "string" or not table.find(models.ALIASES, k) then
					error(`{path}: catalog.{tostring(k)} is not a level ({list(models.ALIASES)})`, 0)
				end
			end
			local catalog: { [string]: { Setting } } = {}
			local placed: { [string]: string } = {}
			local placedId: { [string]: string } = {}
			for _, level in models.ALIASES do
				local v = value[level]
				if v ~= nil then
					if type(v) ~= "table" or not isList(v) then
						error(`{path}: catalog.{level} is a list of model ids`, 0)
					end
					if #v == 0 then
						error(`{path}: catalog.{level} is empty: name at least one model`, 0)
					end
					local entries: { Setting } = {}
					for i, item in v do
						local entry = parseEntry(path, `catalog.{level}`, i, item, nil)
						local k = entryKey(entry)
						if placed[k] == level then
							error(`{path}: catalog.{level} names {placedId[k]} twice`, 0)
						elseif placed[k] ~= nil then
							error(
								`{path}: catalog places {placedId[k]} at {placed[k]} and at {level}: an entry has one level`,
								0
							)
						end
						placed[k] = level
						placedId[k] = string.lower(entryId(entry))
						table.insert(entries, entry)
					end
					catalog[level] = entries
				end
			end
			layer.catalog = catalog
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
					if not ofCli(boundCli, out.model) then
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
				`{path}: [{key}] is not read (the file has catalog, clis, activities, roles, fallback, dispatch and rounds; skill tables are gone)`,
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

-- c0436: a renamed skill answers as the alias it was stored under (the one table is skills.MOVED): z-code is z-run.
local function storedKey(skill: string): string
	for old, new in skillsLib.MOVED do
		if new == skill then
			return old
		end
	end
	return skill
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
	return named[storedKey(skill)]
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
-- fallbacks. `author` names another role: that role's model is tried last.
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

-- The CLIs to try, in order: those of `order` that have a spec for the skill. A try on the author's model comes after every
-- other try (a review on the writer's own model is allowed, not preferred), and carries `sameAsAuthor`. Empty is an error
-- naming the skill.
function models.tries(r: Resolved): { Spec }
	local out: { Spec } = {}
	local same: { Spec } = {}
	for _, cli in r.order do
		local spec = r.specs[cli]
		if spec then
			if r.authorModel ~= nil and models.id(spec) == r.authorModel then
				local marked = table.clone(spec)
				marked.sameAsAuthor = true
				marked.writer = r.authorModel
				table.insert(same, marked)
			else
				table.insert(out, spec)
			end
		end
	end
	for _, spec in same do
		table.insert(out, spec)
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
	review: { [string]: Setting }, -- the aliases as resolved for review activities (where the CLI defines them)
	models: { string },
	offers: { string }?, -- f0421 slice 3: the ids and prefixes (ending in -) the CLI runs, when the table states them
	runtime: string,
	maxCalls: number?,
	maxMinutes: number?,
}
-- `legacy` is a walk with no [activities] in any file: `clis` and `activities` are empty and every lookup reads roles.
export type Config = {
	legacy: boolean,
	clis: { [string]: CliDef },
	activities: { [string]: { maxTokens: number?, settings: { [string]: Setting } } },
	catalog: { [string]: { Setting } }?, -- f0421 slice 3: the root file's [catalog]; read and checked, not acted on (S1a)
}

-- True when `a` and `b` are one model: one family once `-fast` and the effort are removed (models.identity; a ledger id
-- carries the effort, and agent spells a faster serving of the same model `-fast`).
function models.sameModel(a: string, b: string?): boolean
	if b == nil then
		return false
	end
	return models.identity(a).family == models.identity(b).family
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
	return named[storedKey(skill)]
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
local function specFor(
	cli: string,
	def: CliDef?,
	setting: Setting,
	maxTokens: number,
	review: boolean?
): (Spec?, string?)
	local alias = setting.alias
	if alias ~= nil then
		local d = if def then (if review then def.review[alias] else nil) or def.aliases[alias] else nil
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
		if review then
			for a, d in def.review do
				if d.model == model then
					has = true
					rank = math.max(rank, ALIAS_RANK[a])
				end
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
	-- the walk index of the file that set each key of a CLI's table (`review.<alias>` for a review alias)
	local keyAt: { [string]: { [string]: number } } = {}
	local actsRaw: { [string]: { [string]: any } } = {}
	local actAt: { [string]: number } = {}
	local actSrc: { [string]: { [string]: number } } = {}
	for i, layer in layers do
		for cli, fields in layer.clis do
			clisRaw[cli] = clisRaw[cli] or {}
			keyAt[cli] = keyAt[cli] or {}
			cliAt[cli] = i
			for k, v in fields do
				if k == "review" and type(v) == "table" then
					-- a closer file's review table merges per alias, as the plain aliases do
					local merged: { [string]: any } = table.clone(clisRaw[cli].review or {})
					for alias, def in v do
						merged[alias] = def
						keyAt[cli][`review.{alias}`] = i
					end
					clisRaw[cli].review = merged
				else
					clisRaw[cli][k] = v
					keyAt[cli][k] = i
				end
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
			review = raw.review or {},
			models = raw.models or {},
			offers = raw.offers,
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
	-- f0421 slice 3: the root file's catalog, and the checks the merged walk alone can make: every entry of a CLI's lists meets
	-- the CLI's merged offers (or, with none stated, its id rule), and with a catalog sits at its catalog level or lower
	for _, layer in layers do
		if layer.catalog ~= nil then
			cfg.catalog = layer.catalog
		end
	end
	local levelOf: { [string]: string } = {}
	local placedLevels: { [string]: { Setting } } = cfg.catalog or {}
	for level, entries in placedLevels do
		for _, entry in entries do
			levelOf[entryKey(entry)] = level
		end
	end
	for _, cli in models.CLIS do
		local def = cfg.clis[cli]
		if def ~= nil then
			local src: { [string]: number } = keyAt[cli] or {}
			local offers = def.offers
			-- the spelling a CLI's own listing shows: the bare model on a CLI that takes the effort as a flag, else the id
			local function notOffered(label: string, key: string, spelled: string)
				if offers ~= nil and not models.offered(offers, spelled) then
					error(
						`{at(src[key])}: {label} names {spelled}, which clis.{cli}.offers (set in {at(
							src.offers
						)}) does not hold`,
						0
					)
				end
			end
			for _, m in def.models do
				notOffered(`clis.{cli}.models`, "models", m)
			end
			for _, kind in { "", "review." } do
				local levels = if kind == "" then def.aliases else def.review
				for _, alias in models.ALIASES do
					local first = levels[alias]
					if first ~= nil then
						local key = `{kind}{alias}`
						local label = `clis.{cli}.{key}`
						local file = at(src[key])
						local entries: { Setting } = { first }
						local rest: { Setting } = first.rest or {}
						for _, e in rest do
							table.insert(entries, e)
						end
						for _, entry in entries do
							local model = entry.model :: string
							local id = entryId(entry)
							if entry.listed and not ofCli(cli, model) then
								error(`{file}: {label} names {model}, not a model of cli {cli}`, 0)
							end
							notOffered(label, key, if EFFORT_FLAG[cli] then model else id)
							if cfg.catalog ~= nil then
								local placedAt = levelOf[entryKey(entry)]
								if placedAt == nil then
									error(
										`{file}: {label} names {id}, which is not placed: place it in [catalog] first`,
										0
									)
								elseif ALIAS_RANK[placedAt] < ALIAS_RANK[alias] then
									error(
										`{file}: {label} names {id}, which [catalog] places at {placedAt}: a CLI's list holds an entry at its catalog level or lower, never higher`,
										0
									)
								end
							elseif entry.listed then
								local marker = models.unsplit(models.identity(id).family)
								if marker ~= nil then
									error(
										`{file}: {label} names {id}, whose family still holds {marker} once its effort is removed: place it in [catalog] with its family ({"{"} id = "{id}", family = "..." {"}"})`,
										0
									)
								end
							end
						end
					end
				end
			end
		end
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
				if specFor(cli, cfg.clis[cli], setting, 1, REVIEW_ACTIVITY[act]) ~= nil then
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
	return cfg
end

-- The configuration of a walk: merged, and checked. Every function below calls it, so a bad file fails before any
-- activity starts. A walk with no [activities] in any file is legacy (roles and fallbacks, as before step 9).
function models.config(layers: { Layer }): Config
	if #layers == 0 then
		error(`no {models.FILE} on the walk: nothing defaults (add one at the repository root)`, 0)
	end
	for _, layer in layers do
		-- f0421 slice 3: rank is decided once, at the root, so a closer file cannot move a model up
		if layer.catalog ~= nil and layer.path ~= models.FILE then
			error(
				`{layer.path}: [catalog] is read from the root {models.FILE} only: a closer file cannot change a model's rank`,
				0
			)
		end
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
		local marked = table.clone(spec)
		marked.sameAsAuthor = true
		marked.writer = r.authorModel
		return marked, nil
	end
	return spec, nil
end

local modelsIn: (cfg: Config, layers: { Layer }, cli: string) -> { string }

local function resolveIn(
	cfg: Config,
	layers: { Layer },
	cli: string,
	activity: string,
	level: string,
	author: string?,
	session: string?
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
		spec, why = specFor(
			cli,
			cfg.clis[cli],
			setting,
			cfg.activities[act].maxTokens :: number,
			REVIEW_ACTIVITY[act]
		)
	end
	if spec == nil then
		return nil, why
	end
	-- the author's own model is allowed, not preferred (owner, 2026-11-24): the spec says so. A legacy walk compares the
	-- caller's author with today's exact id (`tries`: model and effort), beside the role's own `author` (legacySpec); a
	-- new-shape walk compares the model alone, ignoring effort and case
	local same = if cfg.legacy
		then author ~= nil and models.id(spec) == author
		else models.sameModel(spec.model, author)
	if same and not spec.sameAsAuthor then
		spec = table.clone(spec)
		spec.sameAsAuthor = true
		spec.writer = author
	end
	-- a CLI with no subagents runs one model per session: of several models it holds, only the session's own is delivered
	if
		session ~= nil
		and not cfg.legacy
		and not models.hasSubagents(cli)
		and spec.model ~= session
		and #modelsIn(cfg, layers, cli) > 1
	then
		return nil, `this session runs {session}, and {activity} on {cli} needs {spec.model}`
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

-- The spec `cli` runs `activity` on at `level` (nil is normal), or nil and why it cannot. A review on the model `author`
-- names (the model that wrote the text; effort ignored) is allowed, not preferred: the spec says so. `session` is the model
-- a no-subagent CLI's session runs: of several models, only that one is delivered.
function models.resolveActivity(
	layers: { Layer },
	cli: string,
	activity: string,
	level: rounds.Level?,
	author: string?,
	session: string?
): (Spec?, string?)
	local cfg = models.config(layers)
	local lvl, problem = checkedLevel(level)
	if lvl == nil then
		return nil, problem
	end
	return resolveIn(cfg, layers, cli, activity, lvl, author, session)
end

-- The distinct models a CLI's table resolves to over every activity and level, sorted (none on a legacy walk).
modelsIn = function(cfg: Config, layers: { Layer }, cli: string): { string }
	local out: { string } = {}
	if cfg.legacy then
		return out
	end
	for _, act in models.ACTIVITIES do
		for _, lvl in rounds.LEVELS do
			local spec = resolveIn(cfg, layers, cli, act, lvl, nil, nil)
			if spec ~= nil and not table.find(out, spec.model) then
				table.insert(out, spec.model)
			end
		end
	end
	table.sort(out)
	return out
end

function models.modelsOf(layers: { Layer }, cli: string): { string }
	return modelsIn(models.config(layers), layers, cli)
end

-- True when the CLI has no subagents and its table holds more than one model: its session must say which one it runs.
function models.needsSession(layers: { Layer }, cli: string): boolean
	return not models.hasSubagents(cli) and #models.modelsOf(layers, cli) > 1
end

-- `resolveActivity` for a review whose text was written on any of `authors` (the models that wrote it, each once): the spec
-- is the one the CLI resolves whatever wrote the text, and `sameAsAuthor` says it is one of the authors' own models (allowed,
-- not preferred: the record says so).
function models.resolveReview(
	layers: { Layer },
	cli: string,
	activity: string,
	level: rounds.Level?,
	authors: { string },
	session: string?
): (Spec?, string?)
	local spec, why = models.resolveActivity(layers, cli, activity, level, nil, session)
	if spec == nil then
		return nil, why
	end
	for _, author in authors do
		local again = models.resolveActivity(layers, cli, activity, level, author)
		if again ~= nil and again.sameAsAuthor then
			local marked = table.clone(spec)
			marked.sameAsAuthor = true
			marked.writer = again.writer
			return marked, nil
		end
	end
	return spec, nil
end

-- The model a light raft's builder most likely wrote with: what `code` resolves to on this CLI. Only a guess: no spend row
-- names it, so nothing that records a same-model fact may rest on it. nil when the walk cannot say.
function models.builderGuess(layers: { Layer }, cli: string, level: rounds.Level?): string?
	local spec = models.resolveActivity(layers, cli, "code", level, nil)
	if spec == nil then
		return nil
	end
	return if models.config(layers).legacy then models.id(spec) else spec.model
end

function models.can(
	layers: { Layer },
	cli: string,
	activity: string,
	level: rounds.Level?,
	session: string?
): boolean
	return models.resolveActivity(layers, cli, activity, level, nil, session) ~= nil
end

-- Every `activity/level` pair `can` gives, in ACTIVITIES order and then easy, normal, risky. A one-setting activity
-- appears at each level, so a filter matches by plain membership.
function models.canList(layers: { Layer }, cli: string, session: string?): { string }
	local cfg = models.config(layers)
	local out: { string } = {}
	for _, act in models.ACTIVITIES do
		for _, lvl in rounds.LEVELS do
			if resolveIn(cfg, layers, cli, act, lvl, nil, session) ~= nil then
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

-- The need of an activity at a level, as the waiting line words it: `code-review/normal (heavy: claude, agent, kimi)`. One
-- wording for ./zn model's exit 1 and for `work next`'s wait.
function models.waiting(layers: { Layer }, activity: string, level: rounds.Level?): string
	local lvl: rounds.Level = level or "normal"
	local cfg = models.config(layers)
	local who: { string } = {}
	for _, cli in models.deliverers(layers, activity, lvl) do
		-- a CLI that runs several models, one per session, is a worker running the model this activity needs
		local spec = if cfg.legacy then nil else resolveIn(cfg, layers, cli, activity, lvl, nil, nil)
		if spec ~= nil and not models.hasSubagents(cli) and #modelsIn(cfg, layers, cli) > 1 then
			table.insert(who, `{cli} running {spec.model}`)
		else
			table.insert(who, cli)
		end
	end
	return `{activity}/{lvl} ({models.need(layers, activity, lvl)}: {if #who > 0
		then table.concat(who, ", ")
		else "none"})`
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
		-- step 6: a helper subagent asks for `light`; until the file has [activities] that is the implementation role's model
		-- (on the role's CLI or one of its fallbacks), and every other alias is still undefined
		if alias == "light" then
			local spec, why = legacySpec(layers, cli, "code")
			if spec ~= nil then
				local copy = table.clone(spec)
				copy.alias = "light"
				return copy, nil
			end
			return nil, `{cli} does not define light: {why or "the implementation role is not there"}`
		end
		return nil,
			`{cli} does not define {alias}: this walk has no [activities] yet, so it defines no aliases (only light, the implementation role's model)`
	end
	return specFor(cli, cfg.clis[cli], { alias = alias }, 1)
end

return models
