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
	return string.match(value, "^(.*) %(from git%)$") or string.match(value, "^(.*) %(from git, first add%)$") or value
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

-- The rows of a record, or nil and why. Refuses (never skips) a row that is not `| when | event | actor | detail |`
-- with a known event and a valid actor, and a file with no header.
function provenance.parse(text: string): ({ Row }?, string?)
	local header = string.match(text, "^# Provenance: (%S+)\n")
	if not header then
		return nil, "no `# Provenance: <id>` header"
	end
	local rows: { Row } = {}
	local seenHead = false
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, 1) ~= "|" then
			continue
		end
		if line == "| when | event | actor | detail |" then
			seenHead = true
		elseif line == "|---|---|---|---|" then
			continue
		else
			local when, event, actor, detail =
				string.match(line, "^| (%d%d%d%d%-%d%d%-%d%d %d%d:%d%d) | (%S+) | (.-) | (.*) |$")
			if not when or not event or not actor or not detail then
				return nil, `bad row: {line}`
			end
			if not known(event) then
				return nil, `unknown event {event}`
			end
			if not provenance.isValid(actor) then
				return nil, `bad actor {actor}`
			end
			table.insert(rows, { when = when, event = event, actor = actor, detail = detail })
		end
	end
	if not seenHead then
		return nil, "no table header"
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
			if not m or m.when ~= r.when or m.event ~= r.event or m.actor ~= r.actor or m.detail ~= r.detail then
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

-- Two writers' records merged (the engine's merge of origin/main): the base's rows as they were, then the target
-- branch's (`theirs`, origin/main's) new rows, then ours' new rows minus theirs' taken as a multiset. After a merge
-- origin/main's record is still a prefix of ours, which a gate that compares them needs.
function provenance.union(base: string?, ours: string, theirs: string): string
	local id = string.match(ours, "^# Provenance: (%S+)") or string.match(theirs, "^# Provenance: (%S+)") or "?"
	local b: { Row } = if base then (provenance.parse(base)) or {} else {}
	local o: { Row } = (provenance.parse(ours)) or {}
	local t: { Row } = (provenance.parse(theirs)) or {}
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
	return provenance.render(id, out)
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
