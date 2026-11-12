--!strict
-- c0263: the record of who decided what on a ticket. `provenance.md` in an item's folder, append-only rows
-- `| when | event | actor | detail |` with no row numbers (so two appends merge). Pure over texts: the callers read the
-- files, the environment and git, and hand texts here (zz-arch).

export type Hint = { agent: boolean, effort: string? }
export type Row = { when: string, event: string, actor: string, detail: string }

local trail = require("./trail")

export type Commit = trail.Commit
-- one line of `./zn who`: what git or the record says, with its source
export type Entry = {
	when: string,
	event: string,
	actor: string,
	detail: string,
	source: "git" | "record",
	at: number?, -- a git entry's commit time in seconds (the order among derived entries)
}
-- the document's status word and `raft:` after a commit
export type Front = { status: string, raft: string }
-- the note a cut or ambiguous life carries (`capture` prints the same): its text, and whether the life starts at a cut
export type Mark = { note: string, cut: boolean }
-- what a ticket's life says by itself (c0280): each entry is read from git and never stored
export type Derived = {
	idea: Entry?,
	statuses: { Entry },
	unblocked: { Entry },
	rafted: Entry?,
	delivered: Entry?,
	merged: Entry?,
}
-- a spend row, as far as the worker goes (the model column today; host and CLI once c0254 adds them)
export type Spend = { phase: string, model: string?, host: string?, cli: string? }

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

-- What a merge of two branches does with one item's record, by its text on each side and at the merge base (nil: the
-- item has no record there). Returns the action and the text to write:
--   "keep"   neither side changed it;
--   "write"  the text to put beside the item's document (one side changed it, or both did and the union holds);
--   "remove" the side that changed it deleted it;
--   nil, nil, why   the merge must stop: a side did not only append, a record does not parse, or one side changed it
--   and the other no longer has a record under that id (a renumber or a compaction changed the id: `./zn remap`).
function provenance.settle(common: string?, ours: string?, theirs: string?): (string?, string?, string?)
	local changedOurs, changedTheirs = ours ~= common, theirs ~= common
	local function take(text: string?): (string?, string?, string?)
		if text == nil then
			return "remove", nil, nil
		end
		local _, why = provenance.parse(text)
		if why then
			return nil, nil, `the record does not parse ({why})`
		end
		return "write", text, nil
	end
	if not changedOurs and not changedTheirs then
		return "keep", nil, nil
	elseif changedOurs and not changedTheirs then
		return take(ours)
	elseif changedTheirs and not changedOurs then
		return take(theirs)
	end
	if ours == nil and theirs == nil then
		return "remove", nil, nil -- both sides deleted it
	end
	if ours == nil or theirs == nil then
		return nil,
			nil,
			"one side changed the record and the other has none under this id (an id changed: after a compaction run ./zn remap, after a renumber merge by hand)"
	end
	local united, why = provenance.union(common, ours, theirs)
	if not united then
		return nil, nil, why
	end
	return "write", united, nil
end

-- Whether a merge crosses a compaction: a side whose numbering of items differs from the merge base's (`z-nile/compaction.txt`,
-- nil for none) has reused ids, so an id may name another item on the other side. Settling by id would then put a
-- record, or a row, into the wrong item. Stops when a side compacted and the other side changed a record (so when both
-- compacted, possibly differently, any changed record stops it). Returns the reason to stop, or nil.
function provenance.compactionProblem(
	baseMap: string?,
	oursMap: string?,
	theirsMap: string?,
	oursChanged: boolean,
	theirsChanged: boolean
): string?
	local oursCompacted, theirsCompacted =
		(oursMap or "") ~= (baseMap or ""), (theirsMap or "") ~= (baseMap or "")
	-- (both sides compacted, possibly differently, and any record changed is the same two terms: whichever side changed
	-- it, the other side compacted)
	local crossing = (oursCompacted and theirsChanged) or (theirsCompacted and oursChanged)
	if crossing then
		return "the merge crosses a compaction (a side numbers items differently from the merge base) and a record changed on the other side: run ./zn remap (on the compaction's own branch, compact again on the current origin/main)"
	end
	return nil
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

-- ---------------------------------------------------------------------------------------------------------------
-- c0280: what git says (the author of a capture, every change of the document's status word and who made it, the
-- delivery, the merge) and the worker (the spend rows), merged with the record's rows. Everything here is text and data
-- in, entries out.

local function stamp(time: number): string
	return os.date("!%Y-%m-%d %H:%M", time) :: string
end

-- "Name <email>" (a trailer's value): the name and the lower-cased email, either may be nil
local function person(value: string): (string?, string?)
	local name, email = string.match(value, "^%s*(.-)%s*<([^>]*)>%s*$")
	if name == nil then
		name = string.match(value, "^%s*(.-)%s*$")
		email = nil
	end
	if name == "" then
		name = nil
	end
	return name, if email and email ~= "" then string.lower(email) else nil
end

-- A `Co-Authored-By: Name <email>` trailer line as an agent actor read from git, nil for any other trailer, a name-less
-- value, or (with `people`, every commit author's lower-cased email of the log) a value whose email is a commit
-- author's: a person is whoever commits, so a co-author who is a person, under any name, is not an agent. A value with
-- no email counts as an agent.
function provenance.fromTrailer(trailer: string, people: { [string]: boolean }?): string?
	local value = string.match(trailer, "^[Cc][Oo]%-[Aa][Uu][Tt][Hh][Oo][Rr][Ee][Dd]%-[Bb][Yy]:(.*)$")
	if value == nil then
		return nil
	end
	local name, email = person(value)
	if name == nil or provenance.modelId(name) == "" then
		return nil
	end
	if people ~= nil and email ~= nil and people[email] then
		return nil
	end
	return `{provenance.agent(name, nil)} (from git)`
end

-- The agent of the last Co-Authored-By value (`values`, without the key) that is not a person's, else nil.
function provenance.agentOf(values: { string }, people: { [string]: boolean }): string?
	local agent: string? = nil
	for _, value in values do
		agent = provenance.fromTrailer(`Co-Authored-By: {value}`, people) or agent
	end
	return agent
end

-- A commit's actor: the agent of its trailers (agentOf), else the commit's author. Both read from git.
function provenance.fromCommit(author: string, trailers: { string }, people: { [string]: boolean }): string
	return provenance.agentOf(trailers, people) or `{provenance.human(author)} (from git)`
end

-- a commit's trailers, and those of its second parent when it is a merge (a `--no-ff` landing's top layer commit)
local function allTrailers(c: Commit): { string }
	local out: { string } = {}
	local own: { string } = c.trailers or {}
	local side: { string } = c.sideTrailers or {}
	for _, v in own do
		table.insert(out, v)
	end
	for _, v in side do
		table.insert(out, v)
	end
	return out
end

local function actorOf(c: Commit, people: { [string]: boolean }): string
	return provenance.fromCommit(c.author or "unknown", allTrailers(c), people)
end

local function isRecordPath(path: string): boolean
	return string.match(path, "/provenance%.md$") ~= nil
end

-- the folder a document path is in: its state
local function areaOf(path: string): string
	if string.find(path, "/done/", 1, true) then
		return "done"
	elseif string.find(path, "/active/", 1, true) then
		return "active"
	end
	return "backlog"
end

-- the document's status word: `prepared-marble-raging-otter` is `prepared`
local function wordOf(status: string): string?
	return string.match(status, "^([^%-%s]+)")
end

-- `life`: one item's commits, newest first, as `trail.read` returns them for the document and `provenance.md` (a
-- record change has `doc` false or a record path). `fronts` is the document's status word and `raft:` after each
-- commit, keyed `<sha>:<path>` (the added or modified path; a delete has none). `mark`: the commit that starts a cut life
-- gives the idea alone, marked, and no rafter.
function provenance.select(
	life: { Commit },
	people: { [string]: boolean },
	fronts: { [string]: Front },
	mark: Mark
): Derived
	local out: Derived = { statuses = {}, unblocked = {} }
	local records: { [string]: boolean } = {}
	local rows: { Commit } = {}
	for _, c in life do
		if isRecordPath(c.path) then
			records[c.sha] = true
		elseif c.doc then
			table.insert(rows, c)
		end
	end
	-- the document's commits, oldest first, one step per sha (a move is a delete and an add of one sha); a commit
	-- that only deletes a path of the document is no step
	type Step = { c: Commit, front: Front?, area: string }
	local steps: { Step } = {}
	local seen: { [string]: boolean } = {}
	for i = #life, 1, -1 do
		local c = life[i]
		if c.doc and not isRecordPath(c.path) and c.status ~= "D" and not seen[c.sha] then
			seen[c.sha] = true
			table.insert(steps, { c = c, front = fronts[`{c.sha}:{c.path}`], area = areaOf(c.path) })
		end
	end
	local function entry(c: Commit, event: string, actor: string, detail: string): Entry
		return {
			when = stamp(c.time),
			event = event,
			actor = actor,
			detail = detail,
			source = "git",
			at = c.time,
		}
	end
	-- the idea: the capture commit's author; a trailer is never read for it
	local capture, isCapture = trail.capture(rows)
	if mark.cut and steps[1] then
		capture, isCapture = steps[1].c, false
	end
	if capture and capture.author then
		local how = if isCapture then "from git" else "from git, first add"
		out.idea = entry(capture, "idea", `{provenance.human(capture.author)} ({how})`, mark.note)
	end
	-- every change of the status word, with the author of the commit that made it; a change to `new` by a
	-- `tracker: <id> new` commit is the unblock (once per commit, covered by a record change in the same commit);
	-- the commit that first brings the document into `done/` is the delivery, not a status change
	local prevWord: string? = nil
	local prevArea: string? = nil
	for _, step in steps do
		local word = if step.front then wordOf(step.front.status) else nil
		local delivery = step.area == "done"
			and prevArea ~= nil
			and prevArea ~= "done"
			and out.delivered == nil
		if delivery then
			local raft = if step.front then step.front.raft else ""
			out.delivered =
				entry(step.c, "delivered", actorOf(step.c, people), if raft ~= "" then `raft={raft}` else "")
			out.merged =
				entry(step.c, "merged", provenance.agentOf(allTrailers(step.c), people) or "unknown", "")
		elseif word ~= nil and prevWord ~= nil and word ~= prevWord then
			if word == "new" and string.match(step.c.subject, "^tracker: [fdcR]%d%d%d%d new$") then
				if not records[step.c.sha] then
					table.insert(out.unblocked, entry(step.c, "unblocked", actorOf(step.c, people), ""))
				end
			else
				table.insert(out.statuses, entry(step.c, `status:{word}`, actorOf(step.c, people), ""))
			end
		end
		if word ~= nil then
			prevWord = word
		end
		prevArea = step.area
	end
	-- the rafter: the oldest commit at which `raft:` became the value it has now and stayed so
	local current = ""
	for i = #steps, 1, -1 do
		if steps[i].front then
			current = (steps[i].front :: Front).raft
			break
		end
	end
	if current ~= "" then
		local start: Step? = nil
		for _, step in steps do
			if step.front then
				if (step.front :: Front).raft == current then
					start = start or step
				else
					start = nil
				end
			end
		end
		-- a run that reaches back to the commit that starts a cut life was made by an earlier life
		if mark.cut and start == steps[1] then
			start = nil
		end
		if start then
			out.rafted =
				entry((start :: Step).c, "rafted", actorOf((start :: Step).c, people), `raft={current}`)
		end
	end
	return out
end

-- the `raft=` part of a detail, "" when it has none
local function raftPart(detail: string): string
	for part in string.gmatch(detail, "[^;]+") do
		local value = string.match(part, "^%s*(raft=%S+)%s*$")
		if value then
			return value
		end
	end
	return ""
end

-- true when a stored row of `event` stands for `entry` (a derived fallback): it names the same raft, or the entry
-- names none
local function stored(rows: { Row }, event: string, entry: Entry): boolean
	local want = raftPart(entry.detail)
	for _, r in rows do
		if r.event == event and (want == "" or raftPart(r.detail) == want) then
			return true
		end
	end
	return false
end

local function withWorker(detail: string, worker: string?): string
	if worker == nil then
		return detail
	end
	return if detail == "" then `worker={worker}` else `{detail}; worker={worker}`
end

-- The derived entries and the stored rows as one list, oldest first. Derived entries order by their commits' time
-- (to the second, then the order they came in); a stored row has only its minute, so against it the minute decides, a
-- derived entry before a stored one in the same minute. A stored `rafted` or `delivered` row for the raft wins over the
-- git fallback of its event; the worker joins every `delivered` entry as `worker=<…>`.
function provenance.merge(derived: Derived, rows: { Row }, worker: string?): { Entry }
	local list: { Entry } = {}
	local function add(entry: Entry?)
		if entry then
			table.insert(list, table.clone(entry))
		end
	end
	add(derived.idea)
	for _, e in derived.statuses do
		add(e)
	end
	for _, e in derived.unblocked do
		add(e)
	end
	if derived.rafted and not stored(rows, "rafted", derived.rafted) then
		add(derived.rafted)
	end
	if derived.delivered and not stored(rows, "delivered", derived.delivered) then
		add(derived.delivered)
	end
	add(derived.merged)
	local rank: { [Entry]: number } = {}
	for i, e in list do
		rank[e] = i
	end
	for i, r in rows do
		local entry: Entry =
			{ when = r.when, event = r.event, actor = r.actor, detail = r.detail, source = "record" }
		rank[entry] = i
		table.insert(list, entry)
	end
	for _, e in list do
		if e.event == "delivered" then
			e.detail = withWorker(e.detail, worker)
		end
	end
	table.sort(list, function(a: Entry, b: Entry): boolean
		if a.when ~= b.when then
			return a.when < b.when
		end
		if a.source ~= b.source then
			return a.source == "git"
		end
		if a.at ~= b.at and a.at ~= nil and b.at ~= nil then
			return a.at < b.at
		end
		return rank[a] < rank[b]
	end)
	return list
end

-- The spend row that names the worker of a delivered ticket: the newest `deliver` row that has a model, else the
-- newest `build` row that has one (`rows` in file order, oldest first).
function provenance.workerRow(rows: { Spend }): Spend?
	for _, phase in { "deliver", "build" } do
		for i = #rows, 1, -1 do
			local r = rows[i]
			if r.phase == phase and r.model ~= nil and r.model ~= "" then
				return r
			end
		end
	end
	return nil
end

-- A worker as one word: `host/cli/model` for the parts the row has (c0254 adds host and CLI), nil with none.
function provenance.workerOf(row: { model: string?, host: string?, cli: string? }?): string?
	if row == nil then
		return nil
	end
	local parts: { string } = {}
	for _, part in { row.host, row.cli, row.model } do
		if part ~= nil and part ~= "" then
			table.insert(parts, part)
		end
	end
	return if #parts > 0 then table.concat(parts, "/") else nil
end

-- one line of `./zn who`: `<when>  <event>  <actor>  <detail>  (git | record)`, an empty detail left out
function provenance.line(e: Entry): string
	local parts = { e.when, e.event, e.actor }
	if e.detail ~= "" then
		table.insert(parts, e.detail)
	end
	table.insert(parts, `({e.source})`)
	return table.concat(parts, "  ")
end

return provenance
