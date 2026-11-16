--!strict
-- .models.toml (c0117): which model runs each stage, on which CLI, and which fallbacks follow it.
-- The files stack like .gitignore: from the repository root down to the work, a closer file replaces only the keys
-- it sets. Pure apart from `load`/`walk`, which read the files.
--
-- Contract for the Python port. One shape. A role names what belongs to the stage: `model`, `cli`, `runtime`,
-- `rank`, `max_tokens`, `effort`, and `fallbacks` (CLI names, in order). A fallback names what belongs to the
-- model: `[fallback.<cli>]` has `model`, `runtime`, and anything only that CLI needs (`max_calls` and
-- `max_minutes` for `agent`). A try is the role's rank, cap and effort on the fallback's model. A role's pool may
-- hold several models on one CLI (c0251): `[member.<name>]` has `cli`, `model`, `runtime` (and the caps), and a
-- role's `pool = [names]` lists them, tried after the role's own model and before its CLI `fallbacks`. `[families]`
-- maps a model line to its id prefixes (family.luau). A role with `rotate = true` is ordered by the picker
-- (reviewpool.luau); `author` is only the stand-in for the model that wrote the text when no record says
-- (authorship.luau): no try is dropped for it and the chain never stops on it. A role, fallback or member that
-- names an unknown model or CLI fails in `parse` (when the file is loaded), not when the stage runs. There is no
-- `order` and no `[<skill>.<cli>]` table.
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
--   author = "idea"        -- the role whose first choice stands in for the text's writer
--   rotate = true          -- order the tries by family away from the writer (reviewpool)
--   pool = ["fable"]       -- more models on a CLI, after the role's own, before its fallbacks
--   [member.fable]
--   cli = "claude"
--   model = "claude-fable-5-2"
--   runtime = "claude-cli"
--   [families]
--   opus = ["claude-opus-"]
--   [fallback.kimi]
--   model = "..."
--   runtime = "kimi-cli"
--   [fallback.agent]
--   model = "..."
--   runtime = "cursor-cli"
--   max_calls = 200
--   max_minutes = 240
--   [dispatch]
--   auto_merge = ["prep", "raft", "run"]   -- run: the dispatcher lands a green stack with `./zn done` (c0252)
--   merge_attempts = 2    -- worker tries after a fixable landing check fails, before the raft blocks
--   stall_seconds = 300
local family = require("./family")
--   quota_cap_hours = 24   -- c0253's worker blocks the raft with `quota` when every CLI stays out past this
local fs = require("@lune/fs")
local ledger = require("./ledger")
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
models.GATES = { "prep", "raft", "run" }
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
	member: string?, -- c0251: the `[member.<name>]` this try came from
}
export type Settings = { autoMerge: { string }, stallSeconds: number, toolSeconds: number }
-- One parsed file: its dispatch settings, its roles, its fallbacks, its pool members and its families.
export type Layer = {
	path: string,
	settings: { [string]: any },
	roles: { [string]: { [string]: any } },
	fallbacks: { [string]: { [string]: any } },
	members: { [string]: { [string]: any } },
	families: family.Families,
}
-- A skill resolved on one walk: the tries in order (`pool`), the per-CLI view of them (`order`: the CLIs in the order of
-- their first try; `specs`: each CLI's first try), and the settings.
export type Resolved = {
	skill: string,
	order: { string },
	specs: { [string]: Spec },
	pool: { Spec },
	settings: Settings,
	authorModel: string?,
	fromRoles: boolean?,
	rotate: boolean?, -- c0251: order the tries by family (reviewpool)
	families: family.Families?, -- the walk's family table, for the picker
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

-- Parses one file's text. Every error names the file and the key: an unknown CLI, field or setting, a value of the
-- wrong type, a runtime of another CLI. A repeated table or key is the TOML reader's error (it refuses duplicates).
function models.parse(text: string, path: string): Layer
	local ok, decoded = pcall(function()
		return serde.decode("toml", text)
	end)
	if not ok then
		error(`{path}: {firstLine(decoded)}`, 0)
	end
	local layer: Layer =
		{ path = path, settings = {}, roles = {}, fallbacks = {}, members = {}, families = {} }
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
								)} (run is the landing of a green stack: the dispatcher's own ./zn done)`,
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
				elseif k == "merge_attempts" then
					if not count(v) then
						error(`{path}: dispatch.merge_attempts is a whole number of tries, at least 1`, 0)
					end
					layer.settings.mergeAttempts = v
				elseif k == "quota_cap_hours" then
					if not count(v) then
						error(`{path}: dispatch.quota_cap_hours is a whole number of hours, at least 1`, 0)
					end
					layer.settings.quotaCapHours = v
				else
					error(
						`{path}: dispatch.{k} is not a setting (auto_merge, stall_seconds, tool_seconds, quota_cap_hours, merge_attempts)`,
						0
					)
				end
			end
		elseif key == "families" then
			if type(value) ~= "table" then
				error(`{path}: [families] is a table of family = [id prefixes]`, 0)
			end
			local owner: { [string]: string } = {}
			for name, prefixes in value do
				if type(name) ~= "string" or name == "" then
					error(`{path}: families has a family with no name`, 0)
				end
				if type(prefixes) ~= "table" or #(prefixes :: { any }) == 0 then
					error(`{path}: families.{name} is a list of id prefixes`, 0)
				end
				local out: { string } = {}
				for _, prefix in prefixes :: { any } do
					if type(prefix) ~= "string" or prefix == "" then
						error(`{path}: families.{name} has an empty or non-string prefix`, 0)
					end
					if owner[prefix] ~= nil then
						error(
							`{path}: families.{name} lists the prefix {prefix}, which families.{owner[prefix]} already lists`,
							0
						)
					end
					owner[prefix] = name
					table.insert(out, prefix)
				end
				layer.families[name] = out
			end
		elseif key == "roles" or key == "fallback" or key == "member" then
			if type(value) ~= "table" then
				error(`{path}: [{key}] is a table`, 0)
			end
			for name, fields in value do
				if type(name) ~= "string" or type(fields) ~= "table" then
					error(`{path}: [{key}.{tostring(name)}] is a table`, 0)
				end
				local out: { [string]: any } = {}
				for field, v in fields do
					if key == "roles" and field == "rotate" then
						if type(v) ~= "boolean" then
							error(`{path}: roles.{name}.rotate is true or false`, 0)
						end
						out.rotate = v
					elseif key == "roles" and field == "pool" then
						if type(v) ~= "table" then
							error(`{path}: roles.{name}.pool is a list of [member.<name>] names`, 0)
						end
						local seenMember: { [string]: boolean } = {}
						for _, member in v do
							if type(member) ~= "string" or member == "" then
								error(`{path}: roles.{name}.pool names a member that is not a name`, 0)
							end
							if seenMember[member] then
								error(`{path}: roles.{name}.pool names {member} twice`, 0)
							end
							seenMember[member] = true
						end
						out.pool = table.clone(v)
					elseif key == "roles" and field == "fallbacks" then
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
					elseif key == "member" and field == "cli" then
						if type(v) ~= "string" or not isCli(v) then
							error(
								`{path}: member.{name}.cli is {tostring(v)}, which is not a supported CLI ({list(
									models.CLIS
								)})`,
								0
							)
						end
						out.cli = v
					elseif key == "fallback" and field == "cli" then
						error(`{path}: fallback.{name}.cli is the table name, not a field`, 0)
					elseif
						(key == "fallback" or key == "member")
						and (field == "rank" or field == "max_tokens" or field == "effort")
					then
						error(`{path}: {key}.{name}.{field} belongs to the role, not the {key}`, 0)
					else
						local want = FIELDS[field]
						if not want then
							error(
								`{path}: {key}.{name}.{field} is not a field (model, effort, rank, runtime, max_tokens, max_calls, max_minutes{if key
										== "roles"
									then ", fallbacks, author, rotate, pool"
									else if key == "member" then ", cli" else ""})`,
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
				if key == "member" then
					if isCli(name) then
						error(
							`{path}: [member.{name}]: {name} is a CLI name; a member has a name of its own (a [fallback.{name}] is the CLI's)`,
							0
						)
					end
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
				elseif key == "member" then
					layer.members[name] = out
				else
					layer.fallbacks[name] = out
				end
			end
		else
			error(
				`{path}: [{key}] is not read (the file has roles, fallback, member, families and dispatch; skill tables are gone)`,
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

-- c0252: how many times the dispatcher runs the worker again after a landing check it can fix fails, before it blocks the
-- raft (a real second attempt by default).
models.MERGE_ATTEMPTS = 2
function models.mergeAttempts(layers: { Layer }): number
	local n: number = models.MERGE_ATTEMPTS
	for _, layer in layers do
		if layer.settings.mergeAttempts ~= nil then
			n = layer.settings.mergeAttempts
		end
	end
	return n
end

-- c0250: the cap, in whole hours, on how long every CLI may stay out of quota before c0253's worker blocks the raft
-- with `quota`; nil when no layer sets it.
function models.quotaCapHours(layers: { Layer }): number?
	local cap: number? = nil
	for _, layer in layers do
		if layer.settings.quotaCapHours ~= nil then
			cap = layer.settings.quotaCapHours
		end
	end
	return cap
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
			-- design-challenge are; the picker (reviewpool) rotates the review away from the writer.
			return "raft"
		elseif mode == "stream" then
			-- c0251: a stream review is the one cheap review, on a role of its own
			return "stream-review"
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

-- c0251: the family table of a walk: a closer file replaces only the family keys it sets.
function models.families(layers: { Layer }): family.Families
	local out: family.Families = {}
	for _, layer in layers do
		for name, prefixes in layer.families do
			out[name] = table.clone(prefixes)
		end
	end
	return out
end

-- The role on a walk. A closer file replaces only the keys it sets. The tries are the role's own model, the `pool`
-- members in the order listed, then the `fallbacks` CLIs in order. `order` and `specs` are the per-CLI view of them
-- (the CLIs in the order of their first try, and each CLI's first try). `author` names another role whose first choice
-- stands in for the model that wrote the text (authorship): no try is dropped for it.
function models.resolveRole(layers: { Layer }, role: string, authoring: boolean?): Resolved
	if #layers == 0 then
		error(`no {models.FILE} on the walk: nothing defaults (add one at the repository root)`, 0)
	end
	local fields: { [string]: any } = {}
	local fallbacks: { [string]: { [string]: any } } = {}
	local members: { [string]: { [string]: any } } = {}
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
		for name, f in layer.members do
			members[name] = members[name] or {}
			for k, v in f do
				members[name][k] = v
			end
		end
	end
	if not named then
		error(`no {models.FILE} on the walk names role {role}`, 0)
	end
	local where = layers[#layers].path
	local primary = specFrom(fields.cli, fields, where, `roles.{role}`)
	needsCallCap(primary, where, `roles.{role}`)
	local pool: { Spec } = { primary }
	local function add(spec: Spec, label: string)
		for _, had in pool do
			if had.cli == spec.cli and had.model == spec.model then
				error(
					`{where}: {role}: {label} repeats {spec.cli} {spec.model}, which another try of the role already is`,
					0
				)
			end
		end
		table.insert(pool, spec)
	end
	-- c0251: pool members and rotation are for review steps; an authoring step of the same role (z-raft on `raft`) is tried as
	-- before, the role's model and then its fallbacks
	local reviewing = authoring ~= true
	for _, name in if reviewing then (fields.pool or {}) else {} do
		local m = members[name]
		if not m then
			error(`{where}: {role}: pool names {name}, which has no [member.{name}] on the walk`, 0)
		end
		if m.cli == nil then
			error(`{where}: member.{name} has no cli`, 0)
		end
		local spec = fallbackTry(m.cli, m, fields, where, `member.{name}`)
		spec.member = name
		add(spec, `member.{name}`)
	end
	for _, cli in fields.fallbacks or {} do
		local fb = fallbacks[cli]
		if not fb then
			error(`{role}: fallback {cli} has no [fallback.{cli}] on the walk`, 0)
		end
		if cli ~= primary.cli then
			add(fallbackTry(cli, fb, fields, where, `fallback.{cli}`), `fallback.{cli}`)
		end
	end
	local order: { string } = {}
	local specs: { [string]: Spec } = {}
	for _, spec in pool do
		if specs[spec.cli] == nil then
			specs[spec.cli] = spec
			table.insert(order, spec.cli)
		end
	end
	local authorModel: string? = nil
	if fields.author ~= nil then
		if fields.author == role then
			error(`{role}: author is itself; a challenge cannot name its own role`, 0)
		end
		local author = models.resolveRole(layers, fields.author)
		authorModel = models.id(author.specs[author.order[1]])
	end
	local families = models.families(layers)
	if fields.rotate == true and reviewing then
		for _, spec in pool do
			if family.of(spec.model, families) == nil then
				error(
					`{where}: {role} has rotate = true and {spec.model} belongs to no family: add its id prefix to [families]`,
					0
				)
			end
		end
	end
	return {
		skill = role,
		order = order,
		specs = specs,
		pool = pool,
		settings = models.settings(layers),
		authorModel = authorModel,
		fromRoles = true,
		rotate = fields.rotate == true and reviewing,
		families = families,
	}
end

-- The role a step runs. A closer layer replaces only the keys it sets. Errors: no file on the walk, no role
-- for the step, a spec missing a field.
function models.resolve(layers: { Layer }, skill: string, mode: string?): Resolved
	local role = models.roleFor(skill, mode)
	if not role then
		error(`{skill} is not a model step`, 0)
	end
	-- a review step (zz-review, the idea challenge) uses the role's pool and rotation; every other step authors
	return models.resolveRole(layers, role, skill ~= "zz-review" and skill ~= "idea-challenge")
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

-- A raft's step: `order`, `pool` and settings from the raft's own walk, and for each try (keyed by CLI and model) the
-- strongest of its members' same-keyed specs (rafts never cross projects, so the members share the walk down to their
-- project). A try only a member has is ignored, as a CLI only a member has is.
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
	local pool: { Spec } = {}
	for _, spec in own.pool do
		local candidates: { Spec } = {}
		for _, m in members do
			for _, theirs in m.pool do
				if theirs.cli == spec.cli and theirs.model == spec.model then
					table.insert(candidates, theirs)
				end
			end
		end
		if #candidates > 0 then
			table.insert(pool, models.strongest(candidates))
		elseif specs[spec.cli] ~= nil then
			table.insert(pool, spec)
		end -- a CLI no member has is not tried, as before
	end
	return {
		skill = own.skill,
		order = own.order,
		specs = specs,
		pool = pool,
		settings = own.settings,
		rotate = own.rotate,
		families = own.families,
	}
end

-- The tries, in order: the role's pool (its own model, its members, its CLI fallbacks). Empty is an error naming the
-- skill. c0251: no try is dropped for the model that wrote the text, and the chain never stops on it; a role with
-- `rotate` is ordered by reviewpool.order over this list.
function models.tries(r: Resolved): { Spec }
	if #r.pool == 0 then
		error(`{r.skill}: no CLI in the order ({list(r.order)}) has a spec for it`, 0)
	end
	return table.clone(r.pool)
end

-- The model id a spend row records: the model, and its effort when the spec sets one (model, then a hyphen, then the effort).
function models.id(spec: Spec): string
	return if spec.effort then `{spec.model}-{spec.effort}` else spec.model
end

-- c0325: the model with one trailing context marker `[...]` removed (`claude-opus-5-5[1m]` is `claude-opus-5-5`: the same
-- model with a longer window, so it shares the same blind spots). `[1m][2m]` keeps `[1m]`.
function models.bareModel(model: string): string
	return (string.gsub(model, "%[[^%[%]]*%]$", ""))
end

-- c0325: every `model` any role or fallback of the walk names, bare, each once, sorted.
function models.knownModels(layers: { Layer }): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, layer in layers do
		for _, group in { layer.roles, layer.fallbacks, layer.members } do
			for _, fields in group do
				local model = fields.model
				if type(model) == "string" and model ~= "" then
					local bare = models.bareModel(model)
					if not seen[bare] then
						seen[bare] = true
						table.insert(out, bare)
					end
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- c0325: the bare model of a record of the model that wrote a text (a spend row's `<model>-<effort>`, a bare id,
-- either with a context marker). The longest known model `m` such that the record is `m`, or `m`, an optional one
-- marker and `-<any effort word>`. An effort word may hold a hyphen, so the record is never split at its last hyphen.
-- No known model fits: the record with one trailing marker removed.
function models.modelOf(recorded: string, known: { string }): string
	local best: string? = nil
	for _, m in known do
		local bare = models.bareModel(m)
		if string.sub(recorded, 1, #bare) == bare and (best == nil or #bare > #(best :: string)) then
			local rest = string.sub(recorded, #bare + 1)
			rest = string.gsub(rest, "^%[[^%[%]]*%]", "")
			if rest == "" or (string.sub(rest, 1, 1) == "-" and #rest > 1) then
				best = bare
			end
		end
	end
	return best or models.bareModel(recorded)
end

return models
