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
local serde = require("@lune/serde")

local models = {}

models.FILE = ".models.toml"
-- The supported CLIs (the user's decision: `agent` is Cursor's), each with its two runtimes.
models.CLIS = { "claude", "grok", "agent" }
models.RUNTIMES = {
	claude = { "claude-cli", "claude-cloud" },
	grok = { "grok-cli", "grok-bot" },
	agent = { "cursor-cli", "cursor-app" },
} :: { [string]: { string } }
-- The merge gates the dispatcher may pass itself; the run's PR is never one of them.
models.GATES = { "prep", "raft" }
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
}
export type Settings = { autoMerge: { string }, stallSeconds: number, toolSeconds: number }
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
					if want == "count" and not count(v) then
						error(`{path}: {key}.{cli}.{field} is a whole number, at least 1`, 0)
					elseif want == "string" and (type(v) ~= "string" or v == "") then
						error(`{path}: {key}.{cli}.{field} is a non-empty string`, 0)
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
		}
		local why = models.reviewRule(skill, spec)
		if why then
			error(why, 0)
		end
		specs[cli] = spec
	end
	return { skill = skill, order = table.clone(order :: { string }), specs = specs, settings = settings }
end

-- The review model belongs to the CLI (the user's decision): Opus through `claude` or `agent`, grok-4.7 at xhigh
-- through `grok`. Returns why a zz-review spec breaks it, or nil.
function models.reviewRule(skill: string, spec: Spec): string?
	if skill ~= "zz-review" then
		return nil
	end
	if spec.cli == "grok" then
		if spec.model ~= "grok-4.7" or spec.effort ~= "xhigh" then
			return `zz-review.grok: a review through grok runs grok-4.7 at effort xhigh (grok-4.7-xhigh), not {models.id(
				spec
			)}`
		end
	elseif not string.match(spec.model, "^claude%-opus%-") then
		return `zz-review.{spec.cli}: a review through {spec.cli} runs on Opus (claude-opus-…), not {spec.model}`
	end
	return nil
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
		if r.specs[cli] then
			table.insert(out, r.specs[cli])
		end
	end
	if #out == 0 then
		error(`{r.skill}: no CLI in the order ({list(r.order)}) has a spec for it`, 0)
	end
	return out
end

-- The model id a spend row records: the model, and its effort when the spec sets one ("grok-4.7-xhigh").
function models.id(spec: Spec): string
	return if spec.effort then `{spec.model}-{spec.effort}` else spec.model
end

return models
