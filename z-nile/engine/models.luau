--!strict
-- .models.toml (c0117): which model runs each model step, on which CLI, and in which order the CLIs are tried.
-- The files stack like .gitignore: from the repository root down to the work, a closer file replaces only the keys
-- it sets. Pure apart from `load`/`walk`, which read the files.
--
--   order = ["claude", "grok", "agent"]        -- the CLI priority order, top first (a closer file replaces it whole)
--   [dispatch]                                 -- the dispatcher's settings
--   auto_merge = ["prep", "raft"]              -- merge gates the dispatcher may pass itself
--   stall_seconds = 300                        -- no output for this long kills the step
--   [z-design.claude]                          -- one table per skill and CLI
--   model = "claude-opus-5-5"
--   effort = "high"                            -- optional
--   rank = 3
--   runtime = "claude-cli"
--   max_tokens = 3000000
local fs = require("@lune/fs")
local ledger = require("./ledger")
local serde = require("@lune/serde")

local models = {}

models.FILE = ".models.toml"
-- The supported CLIs (the user's decision: `agent` is Cursor's), each with its one local runtime (the remote ones are c0142's).
models.CLIS = { "claude", "grok", "agent" }
models.RUNTIMES = {
	-- the local runtimes only: the remote ones (claude-cloud, grok-bot, cursor-app) are c0142's (the user's G8)
	claude = { "claude-cli" },
	grok = { "grok-cli" },
	agent = { "cursor-cli" },
} :: { [string]: { string } }
-- The merge gates the dispatcher may pass itself; the run's PR is never one of them.
models.GATES = { "prep", "raft" }
models.STALL_SECONDS = 300
-- the stall limit while a tool call runs (a full gate is quiet for minutes)
models.TOOL_SECONDS = 900
-- how long the chain waits at a gate for its checks (c0261), in minutes
models.WAIT_MINUTES = 60
local FIELDS = {
	model = "string",
	effort = "string",
	rank = "count",
	runtime = "string",
	max_tokens = "count",
	max_calls = "count",
	max_minutes = "count",
	fallback = "models",
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
	fallback: { string }?, -- the models of the same CLI to try, in order, when `model` is not available (c0261)
}
export type Settings =
	{ autoMerge: { string }, stallSeconds: number, toolSeconds: number, waitMinutes: number }
-- One parsed file: its order and settings when it sets them, and its skill tables (skill -> cli -> field -> value).
export type Layer = {
	path: string,
	order: { string }?,
	settings: { [string]: any },
	skills: { [string]: { [string]: { [string]: any } } },
}
-- A skill resolved on one walk: the CLI order, the specs of the CLIs that name the skill, and the settings.
export type Resolved = { skill: string, order: { string }, specs: { [string]: Spec }, settings: Settings }

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

-- Parses one file's text. Every error names the file and the key: an unknown CLI, field or setting, a value of the
-- wrong type, a runtime of another CLI. A repeated table or key is the TOML reader's error (it refuses duplicates).
function models.parse(text: string, path: string): Layer
	local ok, decoded = pcall(function()
		return serde.decode("toml", text)
	end)
	if not ok then
		error(`{path}: {firstLine(decoded)}`, 0)
	end
	local layer: Layer = { path = path, order = nil, settings = {}, skills = {} }
	for key, value in decoded :: { [string]: any } do
		if key == "order" then
			if type(value) ~= "table" or #value == 0 then
				error(`{path}: order is a list of CLIs ({list(models.CLIS)})`, 0)
			end
			local seen: { [string]: boolean } = {}
			for _, cli in value do
				if type(cli) ~= "string" or not isCli(cli) then
					error(
						`{path}: order names {tostring(cli)}, which is not a supported CLI ({list(models.CLIS)})`,
						0
					)
				end
				if seen[cli] then
					error(`{path}: order names {cli} twice`, 0)
				end
				seen[cli] = true
			end
			layer.order = table.clone(value)
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
				elseif k == "wait_minutes" then
					if not count(v) then
						error(`{path}: dispatch.wait_minutes is a whole number of minutes, at least 1`, 0)
					end
					layer.settings.waitMinutes = v
				elseif k == "stall_seconds" or k == "tool_seconds" then
					if not count(v) then
						error(`{path}: dispatch.{k} is a whole number of seconds, at least 1`, 0)
					end
					layer.settings[if k == "stall_seconds" then "stallSeconds" else "toolSeconds"] = v
				else
					error(
						`{path}: dispatch.{k} is not a setting (auto_merge, stall_seconds, tool_seconds, wait_minutes)`,
						0
					)
				end
			end
		else
			if type(value) ~= "table" then
				error(`{path}: {key} is a skill table ([{key}.<cli>])`, 0)
			end
			local clis: { [string]: { [string]: any } } = {}
			for cli, fields in value do
				if not isCli(cli) then
					error(
						`{path}: [{key}.{cli}]: {cli} is not a supported CLI ({list(models.CLIS)}); a CLI the file does not list is not supported`,
						0
					)
				end
				if type(fields) ~= "table" then
					error(`{path}: [{key}.{cli}] is a table of fields`, 0)
				end
				local out: { [string]: any } = {}
				for field, v in fields do
					local want = FIELDS[field]
					if not want then
						error(
							`{path}: {key}.{cli}.{field} is not a field (model, effort, rank, runtime, max_tokens, max_calls, max_minutes)`,
							0
						)
					end
					if want == "models" then
						if type(v) ~= "table" or #v == 0 then
							error(`{path}: {key}.{cli}.{field} is a list of model ids`, 0)
						end
						for _, id in v do
							if type(id) ~= "string" or not ledger.isModel(id) then
								error(
									`{path}: {key}.{cli}.{field} names {tostring(id)}, not a model id the ledger takes`,
									0
								)
							end
						end
					elseif want == "count" and not count(v) then
						error(`{path}: {key}.{cli}.{field} is a whole number, at least 1`, 0)
					elseif want == "string" and (type(v) ~= "string" or v == "") then
						error(`{path}: {key}.{cli}.{field} is a non-empty string`, 0)
					end
					-- the id a spend row records is checked as the ledger checks it, one predicate (code review 001 F6)
					if (field == "model" or field == "effort") and not ledger.isModel(v) then
						error(
							`{path}: {key}.{cli}.{field} is {v}, not a model id the ledger takes (letters, digits, '.', '_', '-')`,
							0
						)
					end
					if field == "runtime" and not table.find(models.RUNTIMES[cli], v) then
						error(
							`{path}: {key}.{cli}.runtime is {v}, not a runtime of {cli} ({list(
								models.RUNTIMES[cli]
							)})`,
							0
						)
					end
					out[field] = v
				end
				clis[cli] = out
			end
			layer.skills[key] = clis
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
	local s: Settings = {
		autoMerge = {},
		stallSeconds = models.STALL_SECONDS,
		toolSeconds = models.TOOL_SECONDS,
		waitMinutes = models.WAIT_MINUTES,
	}
	for _, layer in layers do
		for _, k in { "autoMerge", "stallSeconds", "toolSeconds", "waitMinutes" } do
			if layer.settings[k] ~= nil then
				(s :: any)[k] = layer.settings[k]
			end
		end
	end
	return s
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

-- The skill on a walk of layers: a closer layer replaces only the keys it sets (the order whole, each setting, each
-- field of each skill and CLI). Errors: no file on the walk, no order, no CLI naming the skill, a spec missing a
-- field, and the review rule (models.reviewRule).
function models.resolve(layers: { Layer }, skill: string): Resolved
	if #layers == 0 then
		error(`no {models.FILE} on the walk: nothing defaults (add one at the repository root)`, 0)
	end
	local order: { string }? = nil
	local settings = models.settings(layers)
	local fields: { [string]: { [string]: any } } = {}
	local named = false
	for _, layer in layers do
		if layer.order then
			order = layer.order
		end
		local mine = layer.skills[skill]
		if mine then
			named = true
			for cli, f in mine do
				fields[cli] = fields[cli] or {}
				for k, v in f do
					fields[cli][k] = v
				end
			end
		end
	end
	if not order then
		error(`no order on the walk ({layers[1].path} and below): name the CLIs to try, top first`, 0)
	end
	if not named then
		error(`no {models.FILE} on the walk names {skill}`, 0)
	end
	local specs: { [string]: Spec } = {}
	for cli, f in fields do
		for _, k in REQUIRED do
			if f[k] == nil then
				error(`{skill}.{cli}: no {k} (every model has model, rank, runtime and max_tokens)`, 0)
			end
		end
		if models.CALL_CAPPED[cli] and f.max_calls == nil then
			error(
				`{skill}.{cli}: no max_calls ({cli} reports no running token count, so its step stops after max_calls model calls; calls are not tokens: tune it)`,
				0
			)
		end
		if models.CALL_CAPPED[cli] and f.max_minutes == nil then
			error(
				`{skill}.{cli}: no max_minutes ({cli}'s call count can miss calls, so its step also stops at a wall-time ceiling)`,
				0
			)
		end
		local spec: Spec = {
			cli = cli,
			model = f.model,
			effort = f.effort,
			rank = f.rank,
			runtime = f.runtime,
			maxTokens = f.max_tokens,
			maxCalls = f.max_calls,
			maxMinutes = f.max_minutes,
			fallback = f.fallback,
		}
		local why = models.reviewRule(skill, spec)
		if why then
			error(why, 0)
		end
		specs[cli] = spec
	end
	return { skill = skill, order = table.clone(order :: { string }), specs = specs, settings = settings }
end

-- The kinds of model a final review may run on, per CLI family, defined once (c0261, the user 2026-11-08): by shape, not
-- by exact id, so a new Opus id in .models.toml needs no change here and an item in flight is never locked out by an
-- upgrade. Lua patterns on the id a spend row records (models.id): any Opus, K3.1 Pro and K3-256k at high or max
-- (the kimi CLI's ids; the agent CLI's kimi-k3-high and kimi-k3-max stand in), never -low or kimi-for-coding, any grok model at xhigh.
models.FINAL_SHAPES = {
	claude = { "^claude%-opus%-" },
	grok = { "^grok%-.+%-xhigh$" },
	agent = {
		"^claude%-opus%-",
		"^kimi%-k3%-high$",
		"^kimi%-k3%-max$", -- the agent CLI's kimi ids (K3): the stand-ins for "kimi 3.1 pro" until it lists one
		"^kimi%-k3%.1%-pro%-high$",
		"^kimi%-k3%.1%-pro%-max$",
		"^grok%-.+%-xhigh$",
	},
	-- the kimi CLI's own ids (c0175), as models.id writes them (model, then effort): K3.1 Pro (better) and K3-256k (good) at
	-- high or max; not low, not plain K3, not kimi-for-coding (K2.8 Preview: low-complexity work, never a final review)
	kimi = { "^k3%.1%-pro%-high$", "^k3%.1%-pro%-max$", "^k3%-256k%-high$", "^k3%-256k%-max$" },
} :: { [string]: { string } }

-- Whether a recorded model id is of a final-review kind on any CLI.
function models.isFinalModel(id: string): boolean
	for _, shapes in models.FINAL_SHAPES do
		for _, shape in shapes do
			if string.match(id, shape) then
				return true
			end
		end
	end
	return false
end

local function shapeOk(cli: string, id: string): boolean
	local shapes: { string } = models.FINAL_SHAPES[cli] or {}
	for _, shape in shapes do
		if string.match(id, shape) then
			return true
		end
	end
	return false
end

-- The review rule binds every review activity but the ones on the way (models.ON_THE_WAY): a model of a final-review
-- kind of its CLI. Through
-- `agent` the first choice is Opus (the user: Opus 5.5 high if available) and only its fallbacks may be a kimi-k3 or a
-- grok model at xhigh; a fallback is allowed through `agent` only, where the ids carry their effort. A layer's code
-- review and a stream review take any model, and so does every other command. Returns why a review spec breaks it, or nil.
function models.reviewRule(skill: string, spec: Spec): string?
	if not models.isFinalActivity(skill) then
		return nil
	end
	local id = models.id(spec)
	if spec.fallback and spec.cli ~= "agent" then
		return `{skill}.{spec.cli}: a fallback is allowed through agent only (its ids carry their effort), not through {spec.cli}`
	end
	if spec.cli == "agent" then
		if not string.match(spec.model, "^claude%-opus%-") then
			return `{skill}.agent: a final review through agent first runs on Opus (claude-opus-…), not {spec.model}; kimi and grok at xhigh are its fallbacks`
		end
		local fbs: { string } = spec.fallback or {}
		for _, fb in fbs do
			if not shapeOk("agent", fb) then
				return `{skill}.agent: a fallback of a final review through agent is Opus, a kimi model of a final-review kind or a grok model at xhigh (grok-…-xhigh), not {fb}`
			end
		end
	elseif spec.cli == "grok" then
		if not shapeOk("grok", id) then
			return `{skill}.grok: a final review through grok runs a grok model at effort xhigh (grok-…-xhigh), not {id}`
		end
	elseif not shapeOk("claude", id) then
		return `{skill}.{spec.cli}: a final review through {spec.cli} runs on Opus (claude-opus-…), not {spec.model}`
	end
	return nil
end

-- The review activities that run on the way (c0261): a layer's code review (the final review of the whole stack follows
-- it) and a stream review. Every other review activity (`zz-review` and each `zz-review-<x>`: design, raft, final, idea,
-- and any mode added later) is a final review: expensive, and bound by the review rule by default. A plain `zz-review`
-- table is the expensive base every review activity falls back to.
models.ON_THE_WAY = { "zz-review-stream" } :: { string }

-- Whether `activity` is a review activity the review rule binds.
function models.isFinalActivity(activity: string): boolean
	if activity ~= "zz-review" and string.sub(activity, 1, 10) ~= "zz-review-" then
		return false
	end
	return table.find(models.ON_THE_WAY, activity) == nil
end

-- An activity's resolved spec: its own table when a file names one, else (a review activity) the zz-review table.
function models.resolveActivity(layers: { Layer }, activity: string): Resolved
	for _, layer in layers do
		if layer.skills[activity] then
			return models.resolve(layers, activity)
		end
	end
	if string.sub(activity, 1, 10) == "zz-review-" then
		return models.resolve(layers, "zz-review")
	end
	return models.resolve(layers, activity)
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
		if spec then
			table.insert(out, spec)
			-- the models of the same CLI to fall back to, in order, on the same runtime and budget (c0261)
			local fbs: { string } = spec.fallback or {}
			for _, fb in fbs do
				local alt = table.clone(spec)
				alt.model, alt.effort, alt.fallback = fb, nil, nil
				table.insert(out, alt)
			end
		end
	end
	if #out == 0 then
		error(`{r.skill}: no CLI in the order ({list(r.order)}) has a spec for it`, 0)
	end
	return out
end

-- Whether a try's model is one its CLI lists (`agent --list-models`, `grok models`): `listed` is nil for a CLI with no
-- list command (assumed available), else the ids it printed. A try that is not listed is skipped and named, like a CLI
-- that is not installed. Pure; the dispatcher reads the list at the edge.
function models.available(spec: Spec, listed: { string }?): boolean
	if listed == nil then
		return true
	end
	return table.find(listed, spec.model) ~= nil
end

-- The model id a spend row records: the model, and its effort when the spec sets one ("grok-4.7-xhigh").
function models.id(spec: Spec): string
	return if spec.effort then `{spec.model}-{spec.effort}` else spec.model
end

return models
