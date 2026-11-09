--!strict
-- c0263: the record of who decided what on a ticket. `provenance.md` in an item's folder, append-only rows
-- `| when | event | actor | detail |` with no row numbers (so two appends merge). Pure over texts: the callers read the
-- files, the environment and git, and hand texts here (zz-arch).

export type Hint = { agent: boolean, effort: string? }
export type Row = { when: string, event: string, actor: string, detail: string }

local provenance = {}

-- every event a record may hold; the later layers (c0282, c0283) write rafted, delivered and approved
provenance.EVENTS = { "approved", "unblocked", "confirmed", "ranked", "rafted", "delivered" }
-- what `./zn record` may publish (the other events are written in a pull request, by their own commands)
provenance.PUBLISHED = { "unblocked", "confirmed", "ranked" }

-- lower-case, each run of non-alphanumerics one `-`, trimmed: `grok-4.7` and `Grok 4.7` are both `grok-4-7`
function provenance.modelId(text: string): string
	local dashed = string.gsub(string.lower(text), "[^%w]+", "-")
	local lead = string.gsub(dashed, "^%-+", "")
	local trimmed = string.gsub(lead, "%-+$", "")
	return trimmed
end

function provenance.human(name: string): string
	return `human:{name}`
end

function provenance.agent(model: string, effort: string?): string
	return `agent:{provenance.modelId(model)} effort {if effort and effort ~= "" then effort else "unknown"}`
end

local function stripSuffix(value: string): string
	return string.match(value, "^(.*) %(from git%)$")
		or string.match(value, "^(.*) %(from git, first add%)$")
		or value
end

local function liveForm(value: string): boolean
	if string.find(value, "[\r\n|]") then
		return false
	end
	if string.match(value, "^human:%S") then
		return true
	end
	return string.match(value, "^agent:[%l%d%-]+ effort %w+$") ~= nil
end

-- the form a command may record: no suffix, and not `unknown`
function provenance.isLive(value: string): boolean
	return liveForm(value) and stripSuffix(value) == value
end

-- the stored grammar: a live form, or `unknown`, each with the optional suffix of a value read from git
function provenance.isValid(value: string): boolean
	local base = stripSuffix(value)
	return base == "unknown" or liveForm(base)
end

-- The agent-session hint from an environment (a table of the variables the caller read): a session is an agent's when
-- `CLAUDECODE` (Claude Code), `AI_AGENT`, `CURSOR_AGENT` (the `agent` CLI), `GROK_SESSION_ID` (the `grok` CLI) or `ZN_DISPATCH` (a dispatched step) is set and non-empty; its effort is `CLAUDE_EFFORT`.
-- One definition for every layer: c0283's refusal of `approve` calls this function.
function provenance.hint(env: { [string]: string? }): Hint
	local function set(name: string): boolean
		local v = env[name]
		return v ~= nil and v ~= ""
	end
	return {
		agent = set("CLAUDECODE") or set("AI_AGENT") or set("CURSOR_AGENT") or set("GROK_SESSION_ID") or set(
			"ZN_DISPATCH"
		),
		effort = env.CLAUDE_EFFORT,
	}
end

-- flag, then env, then an agent-session hint, then the git name; a given value that is not a live form refuses
function provenance.resolve(flag: string?, env: string?, hint: Hint, gitName: string?): (string?, string?)
	for _, given in { flag, env } do
		if given and given ~= "" then
			if provenance.isLive(given) then
				return given, nil
			end
			return nil, `not an actor: {given} (human:<name> or agent:<model> effort <level>)`
		end
	end
	if hint.agent then
		return provenance.agent("unknown", hint.effort), nil
	end
	if gitName and gitName ~= "" then
		return provenance.human(gitName), nil
	end
	return "unknown", nil
end

local HEADER = "| when | event | actor | detail |\n|---|---|---|---|\n"

function provenance.render(id: string, rows: { Row }): string
	local out = { `# Provenance: {id}\n\n{HEADER}` }
	for _, r in rows do
		table.insert(out, `| {r.when} | {r.event} | {r.actor} | {r.detail} |\n`)
	end
	return table.concat(out)
end

local function known(event: string): boolean
	return table.find(provenance.EVENTS, event) ~= nil
end

-- The rows of a record, or nil and why. The file is exactly its grammar: line 1 `# Provenance: <id>`, line 2 empty,
-- line 3 the table header, line 4 its separator, then one row per line of exactly four cells (a `|` cannot be in a
-- cell), one final newline. Anything else refuses, naming the line: no line is skipped, so a malformed or
-- hand-formatted line can never be dropped by a merge that re-renders the rows.
function provenance.parse(text: string): ({ Row }?, string?)
	-- the final newline is the end of the last line: a file without it loses one character of its last line, which then
	-- is not a row (or not the separator), and a second newline leaves an empty line, which is not a row either
	local lines = string.split(string.sub(text, 1, -2), "\n")
	if not string.match(lines[1] or "", "^# Provenance: %S+$") then
		return nil, "line 1 is not `# Provenance: <id>`"
	end
	if lines[2] ~= "" then
		return nil, "line 2 is not empty"
	end
	if lines[3] ~= "| when | event | actor | detail |" then
		return nil, "line 3 is not the table header"
	end
	if lines[4] ~= "|---|---|---|---|" then
		return nil, "line 4 is not the table separator"
	end
	local rows: { Row } = {}
	for n = 5, #lines do
		local line = lines[n]
		local when, event, actor, detail =
			string.match(line, "^| (%d%d%d%d%-%d%d%-%d%d %d%d:%d%d) | (%S+) | ([^|]-) | ([^|]*) |$")
		if not when or not event or not actor or not detail then
			return nil, `line {n} is not a four-cell row: {line}`
		end
		if not known(event) then
			return nil, `line {n}: unknown event {event}`
		end
		if not provenance.isValid(actor) then
			return nil, `line {n}: bad actor {actor}`
		end
		table.insert(rows, { when = when, event = event, actor = actor, detail = detail })
	end
	return rows, nil
end

-- a `|` cannot split a row and a newline cannot start one
local function clean(detail: string): string
	local piped = string.gsub(detail, "|", "/")
	local flat = string.gsub(piped, "[\r\n]+", " ")
	return flat
end

-- The record with one row added (a new record when `text` is nil), or nil and why.
function provenance.record(
	text: string?,
	id: string,
	event: string,
	actor: string,
	detail: string,
	now: string
): (string?, string?)
	if not known(event) then
		return nil, `unknown event {event}`
	end
	if not provenance.isLive(actor) then
		return nil, `not a recordable actor: {actor}`
	end
	local rows: { Row } = {}
	if text then
		local parsed, why = provenance.parse(text)
		if not parsed then
			return nil, why
		end
		rows = parsed
	end
	table.insert(rows, { when = now, event = event, actor = actor, detail = clean(detail) })
	return provenance.render(id, rows), nil
end

-- The reason `new` is not `old` with rows appended (every old row, all four cells, in place; at least one new row;
-- the header naming `id`), or nil.
function provenance.appendOnly(old: string?, new: string, id: string): string?
	local n, why = provenance.parse(new)
	if not n then
		return `the new provenance.md does not parse: {why}`
	end
	if string.match(new, "^# Provenance: (%S+)") ~= id then
		return `the provenance.md header names another id, not {id}`
	end
	local before = 0
	if old then
		local o, owhy = provenance.parse(old)
		if not o then
			return `provenance.md on origin/main does not parse ({owhy})`
		end
		for i, r in o do
			local m = n[i]
			if
				not m
				or m.when ~= r.when
				or m.event ~= r.event
				or m.actor ~= r.actor
				or m.detail ~= r.detail
			then
				return `row {i} differs from origin/main: rows are only appended`
			end
		end
		before = #o
	end
	if #n <= before then
		return "no row was appended"
	end
	return nil
end

-- The publish rule: `appendOnly`, and every new row's event is one of `allowed`.
function provenance.publishProblem(old: string?, new: string, id: string, allowed: { string }): string?
	local reason = provenance.appendOnly(old, new, id)
	if reason then
		return reason
	end
	local n = (provenance.parse(new)) :: { Row }
	local before = if old then #((provenance.parse(old)) :: { Row }) else 0
	for i = before + 1, #n do
		if not table.find(allowed, n[i].event) then
			return `a {n[i].event} row is not published here (published: {table.concat(allowed, ", ")})`
		end
	end
	return nil
end

-- Whether `side`'s rows begin with all of `base`'s, cell for cell and in place.
local function extends(base: { Row }, side: { Row }): number?
	for i, r in base do
		local m = side[i]
		if not m or m.when ~= r.when or m.event ~= r.event or m.actor ~= r.actor or m.detail ~= r.detail then
			return i
		end
	end
	return nil
end

-- Two writers' records merged (the engine's merge of origin/main): the base's rows as they were, then the target
-- branch's (`theirs`, origin/main's) new rows, then ours' new rows minus theirs' taken as a multiset. After a merge
-- origin/main's record is still a prefix of ours, which a gate that compares them needs. Refuses (nil and why) a side
-- that does not parse or does not extend the base: a merge must never revert an edit or drop a removed row silently.
function provenance.union(base: string?, ours: string, theirs: string): (string?, string?)
	local id = string.match(ours, "^# Provenance: (%S+)")
		or string.match(theirs, "^# Provenance: (%S+)")
		or "?"
	local b: { Row } = {}
	if base then
		local parsed, why = provenance.parse(base)
		if not parsed then
			return nil, `the common version does not parse ({why})`
		end
		b = parsed
	end
	local o, ownWhy = provenance.parse(ours)
	if not o then
		return nil, `our version does not parse ({ownWhy})`
	end
	local t, theirWhy = provenance.parse(theirs)
	if not t then
		return nil, `origin/main's version does not parse ({theirWhy})`
	end
	local badO, badT = extends(b, o), extends(b, t)
	if badO then
		return nil,
			`our version changed or removed row {badO} of the shared one: rows are only appended: restore the row, or merge by hand if you meant it (a renumber, for one; zz-rules, Provenance)`
	end
	if badT then
		return nil, `origin/main's version changed or removed row {badT} of the shared one`
	end
	local function key(r: Row): string
		return `{r.when}|{r.event}|{r.actor}|{r.detail}`
	end
	local out: { Row } = {}
	for _, r in b do
		table.insert(out, r)
	end
	local taken: { [string]: number } = {}
	for i = #b + 1, #t do
		table.insert(out, t[i])
		taken[key(t[i])] = (taken[key(t[i])] or 0) + 1
	end
	for i = #b + 1, #o do
		local k = key(o[i])
		if (taken[k] or 0) > 0 then
			taken[k] -= 1
		else
			table.insert(out, o[i])
		end
	end
	return provenance.render(id, out), nil
end

-- The path of the record of item `id` among `paths` (a `git ls-tree -r --name-only` listing of one commit): the
-- `provenance.md` in the folder `<...>/<id>/`. Returns nil when the commit holds none, and nil and why when it holds
-- more than one (the item's folder in two places: not decided here).
function provenance.locate(paths: { string }, id: string): (string?, string?)
	local found: string? = nil
	for _, path in paths do
		local folder = string.match(path, `(.*/{id})/provenance%.md$`)
			or string.match(path, `^({id})/provenance%.md$`)
		if folder then
			if found then
				return nil, `{id} has a record in two places ({found} and {path})`
			end
			found = path
		end
	end
	return found, nil
end

-- audit: what is wrong with the record at `path` (in an item's folder, named by that folder's id)
function provenance.problems(path: string, text: string): { string }
	local rows, why = provenance.parse(text)
	if not rows then
		return { `{path}: {why}` }
	end
	local folderId = string.match(path, "/([fdcR]%d%d%d%d)/provenance%.md$")
	local header = string.match(text, "^# Provenance: (%S+)")
	if folderId and header ~= folderId then
		return { `{path}: the header names {header}, not {folderId}` }
	end
	return {}
end

return provenance
