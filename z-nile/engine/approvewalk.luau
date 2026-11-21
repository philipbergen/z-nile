--!strict
-- f0423 step 1: the walkthrough forms of `./zn approve` (the edge; the rules are waiting.luau's and the run folder's
-- are approverun.luau's). A scope (`R0050`, `--walk <id>`, or none) becomes a run: what waits, in order, and a brief.
-- The person's session reads the brief and writes rulings with `--ruling`; only `--apply`, typed on the real terminal,
-- records anything, one `y` per ruling, and only on the design that was walked. `main.luau` hands over the parsed
-- arguments and the few helpers it owns (`Ctx`); this module never requires it.
local agentenv = require("./agentenv")
local approvalLib = require("./approval")
local approveplace = require("./approveplace")
local approverun = require("./approverun")
local closing = require("./closing")
local contract = require("./contract")
local depgraph = require("./depgraph")
local fs = require("@lune/fs")
local guesses = require("./guesses")
local layergit = require("./layergit")
local models = require("./models")
local process = require("@lune/process")
local sh = require("../lib/sh")
local stdio = require("@lune/stdio")
local store = require("./store")
local waiting = require("./waiting")

local approvewalk = {}

export type Ctx = {
	fail: (string) -> never,
	terminal: () -> boolean, -- a controlling terminal opens
	hasOrigin: () -> boolean,
	worktrees: () -> { approveplace.Tree },
	projectRoot: () -> string?, -- the folder's project root, for no scope (read only when it is asked for)
}

local RULING_OPTS = {
	["--ruling"] = true,
	["--stage"] = true,
	["--guess"] = true,
	["--note"] = true,
	["--lesson"] = true,
	["--ask"] = true,
	["--into"] = true,
}

local function say(text: string)
	stdio.write(text .. "\n")
end

-- ---------------------------------------------------------------- the refusals

-- The guard every form that starts a walk or records runs first: not under the dispatcher, not inside a walkthrough
-- session, not inside an agent session (any marker agentenv lists), and only on a terminal. `hint` is the command the
-- person runs themselves; `what` leads the message (empty for none). The engine's refusal is the real guard: the
-- hook refuses only the obvious forms.
-- The refusal for a shell that carries an agent marker: the one place the message is built.
function approvewalk.markerRefusal(lead: string, marker: string): string
	return `{lead}approve is refused inside an agent session ({marker} is set): only the person records an approval, in their own terminal. If this is your own terminal, open a new one that no agent CLI started.`
end

function approvewalk.refuseAgent(ctx: Ctx, what: string, hint: string)
	local lead = if what ~= "" then `{what}: ` else ""
	local dispatched = process.env.ZN_DISPATCH
	if dispatched and dispatched ~= "" then
		ctx.fail(`{lead}approve is refused while ZN_DISPATCH is set. Run {hint} yourself, in a terminal.`)
	end
	local session = process.env.ZN_APPROVE_SESSION
	if session and session ~= "" then
		ctx.fail(
			`{lead}approve is refused inside a walkthrough session (ZN_APPROVE_SESSION is set): an agent never records an approval. Write rulings with ./zn approve --ruling, then ask the person to run ./zn approve --apply {session} in a terminal.`
		)
	end
	local marker = agentenv.firstSet(process.env :: any, agentenv.MARKERS)
	if marker then
		ctx.fail(approvewalk.markerRefusal(lead, marker))
	end
	if not ctx.terminal() then
		ctx.fail(`{lead}approve is refused without a terminal on stdin. Run {hint} yourself, in a terminal.`)
	end
end
local refuseAgent = approvewalk.refuseAgent

-- ---------------------------------------------------------------- reading the facts

type Facts = {
	copy: approveplace.Copy,
	place: string,
	where: string?, -- the worktree path when the design is there, nil for origin/main
	fact: waiting.Fact,
	verdict: waiting.Verdict,
}

local function landsOf(front: { [string]: string }): boolean
	local raft = front.raft or ""
	return raft ~= "" and layergit.readyRecord(raft).lands
end

-- `built`: this ticket's own layer exists (the caller knows its position in the raft).
local function factOf(item: store.Item, lands: boolean, ctx: Ctx, built: boolean): Facts?
	local id = item.id
	local top = sh.git({ "rev-parse", "--show-toplevel" })
	local trees = ctx.worktrees()
	local scratch = `{trees[1].path}/.worktree/.approve-{id}`
	local main, seen = approveplace.load(id, top, scratch, trees)
	local choice = approveplace.choose(id, main, seen, false)
	local copy: approveplace.Copy? = main
	local place = "origin/main"
	local where: string? = nil
	local approved = false
	if choice then
		local c = choice :: approveplace.Choice
		if c.kind == "worktree" then
			for _, w in seen do
				if w.path == c.path then
					copy, place, where = w.copy, w.name, w.path
				end
			end
		elseif c.kind == "approved" or c.kind == "pushed" then
			approved = true
			place = c.name
		end
	end
	if not copy then
		return nil
	end
	local c = copy :: approveplace.Copy
	local standing: waiting.Approval = "none"
	if approved or c.state == "holds" then
		standing = "holds"
	elseif c.state == "bad" then
		standing = "bad"
	elseif c.state == "changed" then
		local diff = c.changed or {}
		standing = if #diff == 1 and diff[1] == "guesses" then "guesses" else "stale"
	end
	-- the rework facts are read from origin/main's rework.md once f0423's rework step exists; until then none is open
	local fact: waiting.Fact = {
		stage = if not c.ready then "draft" elseif built then "built" else "designed",
		approval = standing,
		changed = if approved then {} else c.changed or {},
		guesses = c.guesses or 0,
		lands = lands,
		reworkOpen = false,
		reworkSince = nil,
	}
	return { copy = c, place = place, where = where, fact = fact, verdict = waiting.of(fact) }
end

-- A file as the place the approval records holds it: the worktree's checkout, or origin/main. Nil when it is not there.
local function readAt(f: Facts, rel: string): string?
	if f.where then
		local path = `{f.where}/{rel}`
		return if fs.isFile(path) then fs.readFile(path) else nil
	end
	local shown = sh.run("git", { "show", `origin/main:{rel}` })
	return if shown.ok then shown.stdout else nil
end

-- The revision of the place (short sha).
local function revAt(f: Facts): string
	local r = if f.where
		then sh.run("git", { "-C", f.where, "rev-parse", "--short", "HEAD" })
		else sh.run("git", { "rev-parse", "--short", "origin/main" })
	return if r.ok then sh.trim(r.stdout) else "?"
end

local function sectionOf(doc: string, heading: string): string
	local hay = "\n" .. doc
	local mark = `\n## {heading}`
	local at = string.find(hay, mark, 1, true)
	if not at then
		return ""
	end
	local body = at + #mark
	local nextAt = string.find(hay, "\n## ", body, true)
	local chunk = if nextAt then string.sub(hay, body, nextAt - 1) else string.sub(hay, body)
	return (string.gsub(chunk, "^%s*(.-)%s*$", "%1"))
end

local function titleOf(doc: string): string
	return string.match(doc, "\ntitle:[ ]*([^\n]*)") or "?"
end

-- One guess as one line: G<n> (step, day): open. Chose: ... Why: ...
local function guessLine(g: guesses.Guess): string
	return `{g.id} ({g.step}, {g.when}): {g.open} Chose: {g.chose} Why: {g.why}`
end

local function guessesAt(f: Facts, dir: string): { guesses.Guess }
	local text = readAt(f, `{dir}/{guesses.FILE}`)
	local list = if text then guesses.parse(text) else nil
	return list or {}
end

type Issue = { item: store.Item, front: { [string]: string }, unit: string, deps: { string } }

-- Every open ticket of the checkout, with its unit (its raft, else itself) and the units it waits on.
local function universe(): { Issue }
	local list: { Issue } = {}
	local unitOf: { [string]: string } = {}
	for _, item in store.all("issue") do
		local front = store.readFront(item.doc)
		if item.state ~= "done" and not closing.isClosed(front) then
			local raft = front.raft or ""
			local unit = if raft ~= "" then raft else item.id
			unitOf[item.id] = unit
			table.insert(list, { item = item, front = front, unit = unit, deps = {} })
		end
	end
	for _, i in list do
		local seen: { [string]: boolean } = {}
		for _, dep in store.idList(i.front.depends_on) do
			local unit = if string.sub(dep, 1, 1) == "R" then dep else unitOf[dep]
			if unit and unit ~= i.unit and not seen[unit] then
				seen[unit] = true
				table.insert(i.deps, unit)
			end
		end
	end
	return list
end

-- The units `start` waits on, directly or not, and `start` itself.
local function closure(start: string, list: { Issue }): { [string]: boolean }
	local edges: { [string]: { string } } = {}
	for _, i in list do
		local into = edges[i.unit] or {}
		for _, d in i.deps do
			table.insert(into, d)
		end
		edges[i.unit] = into
	end
	local seen: { [string]: boolean } = { [start] = true }
	local function visit(unit: string)
		local below: { string } = edges[unit] or {}
		for _, nextUnit in below do
			if not seen[nextUnit] then
				seen[nextUnit] = true
				visit(nextUnit)
			end
		end
	end
	visit(start)
	return seen
end

type Gathered = {
	rows: { approverun.QueueRow },
	entries: { approverun.Entry },
	notes: { string },
	waits: number,
	working: number,
	drafts: number,
}

-- A raft's members when its Order section cannot be read: by depends_on depth, then by id.
local function byDependsThenId(raftId: string): { store.Item }
	local members = store.members(raftId)
	local inRaft: { [string]: boolean } = {}
	for _, m in members do
		inRaft[m.id] = true
	end
	local deps: { [string]: { string } } = {}
	for _, m in members do
		local own: { string } = {}
		for _, d in store.idList(store.readFront(m.doc).depends_on) do
			if inRaft[d] and d ~= m.id then
				table.insert(own, d)
			end
		end
		deps[m.id] = own
	end
	local depth: { [string]: number } = {}
	local function of(id: string, trail: { [string]: boolean }): number
		if depth[id] then
			return depth[id]
		end
		if trail[id] then
			return 1
		end
		trail[id] = true
		local best = 1
		for _, d in deps[id] do
			best = math.max(best, of(d, trail) + 1)
		end
		trail[id] = nil
		depth[id] = best
		return best
	end
	table.sort(members, function(a, b)
		local da, db = of(a.id, {}), of(b.id, {})
		if da ~= db then
			return da < db
		end
		return a.id < b.id
	end)
	return members
end

local function onGitHub(): boolean
	local r = sh.run("git", { "config", "--get", "remote.origin.url" })
	return r.ok and string.find(r.stdout, "github.com", 1, true) ~= nil
end

-- The pull request of a layer branch, when `gh` finds one (never raises; nil when not on GitHub or none found).
local function prOf(layer: string): string?
	if not onGitHub() then
		return nil
	end
	local ok, r = pcall(sh.run, "gh", { "pr", "view", layer, "--json", "url", "-q", ".url" })
	if ok and r.ok and sh.trim(r.stdout) ~= "" then
		return sh.trim(r.stdout)
	end
	return nil
end

-- What waits in the scope, the bottom of a stack first. `scope` is a raft id, a ticket id (`--walk`) or "" (the
-- folder's project). Refuses (exits) when this checkout's copy of a waiting ticket is not the copy the approval will
-- record, so the owner is never shown one design and the approval recorded on another.
local function gather(scope: string, ctx: Ctx): Gathered
	if ctx.hasOrigin() then
		sh.run("git", { "fetch", "-q", "origin", "main" })
	end
	local list = universe()
	local picked: { Issue } = {}
	if string.match(scope, "^R%d%d%d%d$") then
		local units = closure(scope, list)
		for _, i in list do
			if units[i.unit] then
				table.insert(picked, i)
			end
		end
		local own = false
		for _, i in picked do
			own = own or i.unit == scope
		end
		if not own then
			ctx.fail(`approve {scope}: no open ticket belongs to {scope} in this checkout`)
		end
	elseif scope ~= "" then
		for _, i in list do
			if i.item.id == scope then
				table.insert(picked, i)
			end
		end
		if #picked == 0 then
			ctx.fail(`approve --walk {scope}: {scope} is not an open ticket in this checkout`)
		end
	else
		local root = ctx.projectRoot()
		for _, i in list do
			if root == nil or i.item.root == root then
				table.insert(picked, i)
			end
		end
	end
	local notes: { string } = {}
	-- the raft's ticket order is its layer order; a raft whose Order section is inconsistent falls back to depends_on
	local layerOf: { [string]: number } = {}
	local layersOfRaft: { [string]: { any } } = {}
	local landsOfRaft: { [string]: boolean } = {}
	local ordered: { [string]: boolean } = {}
	for _, i in picked do
		if i.unit ~= i.item.id and not ordered[i.unit] then
			ordered[i.unit] = true
			local raft = store.find(i.unit)
			if raft then
				local members, problem = layergit.tryOrderedMembers(raft)
				if not members then
					table.insert(
						notes,
						`{i.unit}'s Order section is inconsistent ({problem}): its tickets are ordered by depends_on, then by id`
					)
					members = byDependsThenId(i.unit)
				end
				for n, m in members :: { store.Item } do
					layerOf[m.id] = n
				end
				layersOfRaft[i.unit] = layergit.layersOf(i.unit) :: { any }
				landsOfRaft[i.unit] = layergit.readyRecord(i.unit).lands
			end
		end
	end
	local top = sh.git({ "rev-parse", "--show-toplevel" })
	local byId: { [string]: Facts } = {}
	local placed: { waiting.Placed } = {}
	local working: { string } = {}
	local drafts = 0
	for _, i in picked do
		local layers = layersOfRaft[i.unit]
		local built = i.item.state == "active"
			and layers ~= nil
			and #layers >= (layerOf[i.item.id] or math.huge)
		local f = factOf(i.item, landsOfRaft[i.unit] == true, ctx, built)
		if f then
			byId[i.item.id] = f
			if f.verdict.state == "waits" then
				local mine = approveplace.inTree(top, i.item.id)
				if mine and mine.hash == nil then
					local _, _, why = approvalLib.collect(top, i.item)
					ctx.fail(
						`{i.item.id}: this checkout's copy of the contract cannot be built: {why or "unknown"}`
					)
				end
				if mine and mine.hash ~= f.copy.hash then
					local way = if f.where
						then `walk from {f.place}`
						else `run ./zn sync, or walk from {f.place}`
					ctx.fail(`{i.item.id}: this checkout's copy differs from {f.place}: {way}`)
				end
				table.insert(placed, { id = i.item.id, unit = i.unit, layer = layerOf[i.item.id] or 1 })
			elseif f.verdict.state == "working" then
				if f.fact.stage == "draft" then
					drafts += 1
				else
					table.insert(working, i.item.id)
				end
			end
		end
	end
	table.sort(working)
	local units: { depgraph.Unit } = {}
	local inScope: { [string]: boolean } = {}
	for _, i in picked do
		inScope[i.unit] = true
	end
	local edges: { [string]: { string } } = {}
	for _, i in picked do
		local into = edges[i.unit] or {}
		for _, d in i.deps do
			if inScope[d] then
				table.insert(into, d)
			end
		end
		edges[i.unit] = into
	end
	for unit, deps in edges do
		table.insert(units, { id = unit, waitsOn = deps })
	end
	local bands = depgraph.bands(units)
	local order = waiting.order(placed, bands)
	for _, id in working do
		table.insert(order, id)
	end
	local issueOf: { [string]: Issue } = {}
	for _, i in picked do
		issueOf[i.item.id] = i
	end
	local out: Gathered =
		{ rows = {}, entries = {}, notes = notes, waits = #placed, working = #working, drafts = drafts }
	for _, id in order do
		local f, i = byId[id], issueOf[id]
		local parts = if f.copy.partHashes then contract.encodeParts(f.copy.partHashes) else nil
		table.insert(out.rows, {
			id = id,
			place = f.place,
			hash = f.copy.hash or "-",
			state = f.verdict.state :: string,
			parts = parts or "-",
			why = f.verdict.why,
		})
		local doc = readAt(f, i.item.doc)
		if doc == nil then
			ctx.fail(
				`{id}: its document {i.item.doc} is not at {f.place}: run ./zn sync, or walk from {f.place}`
			)
		end
		local guessLines: { string } = {}
		for _, g in guessesAt(f, i.item.dir) do
			table.insert(guessLines, guessLine(g))
		end
		local marks: { string } = {}
		for line in string.gmatch(doc :: string, "[^\n]+") do
			if string.find(line, "Guess (prep)", 1, true) then
				table.insert(marks, if #line > 300 then string.sub(line, 1, 300) .. "..." else line)
				if #marks == 5 then
					break
				end
			end
		end
		local layer: string? = nil
		if f.fact.stage == "built" then
			local found = (layersOfRaft[i.unit] or {})[layerOf[id] or 0]
			layer = if found then (found :: any).name else nil
		end
		table.insert(out.entries, {
			id = id,
			title = titleOf("\n" .. (doc :: string)),
			unit = i.unit,
			state = f.verdict.state :: string,
			why = f.verdict.why,
			stage = f.fact.stage :: string,
			doc = i.item.doc,
			place = f.place,
			rev = revAt(f),
			hash = f.copy.hash or "-",
			problem = sectionOf(doc :: string, "Problem"),
			solution = sectionOf(doc :: string, "Solution"),
			guesses = guessLines,
			places = marks,
			layer = layer,
			pr = if layer then prOf(layer) else nil,
			rework = {},
			lessons = {},
		})
	end
	return out
end

-- ---------------------------------------------------------------- the forms

local function scopeText(scope: string): string
	if scope == "" then
		return "the folder's project"
	end
	return scope
end

local function writeRun(root: string, scope: string, ctx: Ctx): (string?, Gathered)
	local g = gather(scope, ctx)
	if g.waits == 0 then
		return nil, g
	end
	approverun.prune(root, os.time(), 14)
	local run = approverun.newRun(root, os.date("!%Y%m%dT%H%M%SZ") :: string, function()
		return math.random(0, 65535)
	end)
	if not run then
		ctx.fail("approve: could not draw a free run id")
	end
	local failed = approverun.write(
		root,
		run :: string,
		g.rows,
		approverun.brief(run :: string, scopeText(scope), g.entries, g.notes, g.drafts)
	)
	if failed then
		ctx.fail(`approve: {failed}`)
	end
	return run, g
end

local function printQueue(run: string, root: string, g: Gathered)
	local dir = approverun.dir(root, run) :: string
	say(`approval run {run}: {g.waits} waiting for the owner, {g.working + g.drafts} still being worked`)
	local n = 0
	for _, row in g.rows do
		if row.state == "waits" then
			n += 1
			local title = ""
			for _, e in g.entries do
				if e.id == row.id then
					title = e.title
				end
			end
			say(`  {n}. {row.id} {title}: {row.why}`)
		end
	end
	say(`brief: {dir}/{approverun.BRIEF}`)
end

-- Reads one line from the controlling terminal; "" when it cannot.
local function readTerminal(): string
	local r = process.exec("perl", {
		"-e",
		"open(my $f, q{<}, q{/dev/tty}) or exit 1; my $l = <$f>; print $l // q{}",
	})
	return if r.ok then sh.trim(r.stdout) else ""
end

-- The parts that differ between two encodings of part hashes, in contract order.
local function changedParts(walked: string, now: contract.Parts?): { string }
	local before: contract.Parts = {}
	if walked ~= "-" then
		before = contract.decodeParts(walked) or {}
	end
	local after: contract.Parts = now or {}
	local all: contract.Parts = table.clone(before)
	for name, hash in after do
		all[name] = hash
	end
	local out: { string } = {}
	for _, name in contract.order(all) do
		if before[name] ~= after[name] then
			table.insert(out, name)
		end
	end
	return out
end

-- "2026-11-20 18:40:00Z" from a run id.
local function runTime(run: string): string
	local y, mo, d, h, mi, sec = string.match(run, "^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z")
	return `{y}-{mo}-{d} {h}:{mi}:{sec}Z`
end

-- `--apply <run>`: for each ruling, works out what is true now, shows it, asks y/N on the real terminal and records an
-- approval only for a `y`, only for a ticket that waits now, and only on the design the walk showed. `shown` is the
-- queue the walk form just built (the folder's queue.tsv is read only by a separate --apply).
local function apply(run: string, root: string, ctx: Ctx, shown: { approverun.QueueRow }?)
	refuseAgent(ctx, run, `./zn approve --apply {run}`)
	local found, err = approverun.read(root, run)
	if not found then
		ctx.fail(`approve --apply: {err}`)
	end
	local current = found :: approverun.Run
	local queue = shown or current.queue
	local top = sh.git({ "rev-parse", "--show-toplevel" })
	local recorded, already, pending, waited, refused, todo = 0, 0, 0, 0, 0, 0
	local keys: { [string]: boolean } = {}
	for _, r in current.rulings do
		-- a duplicate row of the folder (hand-edited) is asked once
		local key = `{r.ticket} {r.guess} {r.action}`
		if keys[key] then
			continue
		end
		keys[key] = true
		local done = false
		for _, a in current.applied do
			done = done or (a.ticket == r.ticket and a.guess == r.guess)
		end
		if done then
			continue
		end
		todo += 1
		local row: approverun.QueueRow? = nil
		for _, q in queue do
			if q.id == r.ticket then
				row = q
			end
		end
		if not row then
			stdio.ewrite(`{r.ticket}: not in the queue of {run}; skipped\n`)
			refused += 1
			continue
		end
		local queued = row :: approverun.QueueRow
		local item = store.find(r.ticket)
		if not item then
			stdio.ewrite(`{r.ticket}: not recorded: it is not an open ticket in this checkout\n`)
			refused += 1
			continue
		end
		local front = store.readFront((item :: store.Item).doc)
		local now = factOf(item :: store.Item, landsOf(front), ctx, false)
		if not now then
			stdio.ewrite(`{r.ticket}: not recorded: no design of it was found\n`)
			refused += 1
			continue
		end
		local facts = now :: Facts
		local doc = readAt(facts, (item :: store.Item).doc) or ""
		local title = titleOf("\n" .. doc)
		if r.action == "change" then
			-- step 1 has no ./zn rework: the ruling is shown again by every --apply until it does
			say(
				`{r.ticket} ({title}): the owner ruled a change{if r.guess == "-"
					then ""
					else " to " .. r.guess} at the {r.stage} stage: "{r.note}". Nothing changes yet: ./zn rework is not built, so this ruling only stays in {run}'s rulings.tsv and is shown again by the next --apply.`
			)
			pending += 1
			continue
		end
		if facts.verdict.state ~= "waits" then
			if facts.verdict.state == "clear" and facts.fact.approval == "holds" then
				say(`{r.ticket} ({title}): already approved; nothing to record`)
				approverun.addApplied(root, run, {
					ticket = r.ticket,
					guess = r.guess,
					outcome = "already-approved",
					when = os.date("!%Y-%m-%dT%H:%M:%SZ") :: string,
				})
				already += 1
			else
				stdio.ewrite(
					`{r.ticket}: not recorded: it does not wait for approval now ({facts.verdict.why}); ./zn approve --walk {r.ticket} shows what is open\n`
				)
				refused += 1
			end
			continue
		end
		-- an approval is recorded only on the design that was walked
		if queued.hash == "-" or facts.copy.hash ~= queued.hash then
			local parts = changedParts(queued.parts, facts.copy.partHashes)
			local named = if #parts > 0 then table.concat(parts, ", ") else "the design"
			stdio.ewrite(
				`{r.ticket}: not recorded: its contract changed since the walkthrough {run} ({named}). Walk it again: ./zn approve --walk {r.ticket}\n`
			)
			refused += 1
			continue
		end
		-- what this command works out itself, before the question: one line, at most 5 guesses, a pointer to the rest
		local list = guessesAt(facts, (item :: store.Item).dir)
		say(
			`{r.ticket}: {title}; waits because: {facts.verdict.why}; {#list} guess(es); will be recorded in {facts.place}, unchanged since the walkthrough {runTime(
				run
			)}`
		)
		for n, g in list do
			if n > 5 then
				break
			end
			local chose = if #g.chose > 80 then string.sub(g.chose, 1, 80) .. "…" else g.chose
			say(`  {g.id} chose: {chose}`)
		end
		if #list > 5 then
			say(`  and {#list - 5} more: see {approverun.dir(root, run) :: string}/{approverun.BRIEF}`)
		end
		stdio.write(`Approve {r.ticket} ({title})? [y/N] `)
		local answer = readTerminal()
		say("")
		if answer ~= "y" and answer ~= "Y" then
			waited += 1
			say(`{r.ticket}: nothing recorded; the ruling waits for a later ./zn approve --apply {run}`)
			continue
		end
		local ran = process.exec("sh", {
			"-c",
			'exec lune run "$1/z-nile/engine/main" -- approve "$2" </dev/tty',
			"sh",
			top,
			r.ticket,
		}, {
			cwd = top,
			env = { ZN_TOP = top, ZN_CWD = "", ZN_APPROVE_RUN = run },
			stdio = "inherit",
		})
		if not ran.ok then
			stdio.ewrite(
				`{r.ticket}: ./zn approve {r.ticket} failed ({ran.code}); nothing is marked applied: fix it, then ./zn approve --apply {run}\n`
			)
			refused += 1
			continue
		end
		approverun.addApplied(root, run, {
			ticket = r.ticket,
			guess = r.guess,
			outcome = "recorded",
			when = os.date("!%Y-%m-%dT%H:%M:%SZ") :: string,
		})
		recorded += 1
	end
	if todo == 0 then
		say(`{run}: no rulings waiting to be applied`)
		return
	end
	say(
		`{run}: {recorded} approved, {already} already approved, {pending} changes pending, {waited} left waiting, {refused} refused`
	)
	if refused > 0 then
		process.exit(1)
	end
end

-- `--ruling <run> <id> approve | change ...`: one row in the run's rulings.tsv, written by approverun and nowhere else.
local function ruling(pos: { string }, opts: { [string]: { string } }, root: string, ctx: Ctx)
	local usage =
		"usage: approve --ruling <run> <issue-id> approve | change --stage idea|design|code [--guess G<n>|none] --note <owner's words> [--lesson <rule> --ask <question?>] [--into <skill>/<slug>]"
	local run = (opts["--ruling"] or {})[1] or ""
	local dispatched = process.env.ZN_DISPATCH
	if dispatched and dispatched ~= "" then
		ctx.fail(
			`{run}: --ruling is refused while ZN_DISPATCH is set: only a person's session writes a ruling.`
		)
	end
	for k in opts do
		if not RULING_OPTS[k] then
			ctx.fail(`{usage} (unknown option {k})`)
		end
	end
	if #pos ~= 2 or (pos[2] ~= "approve" and pos[2] ~= "change") then
		ctx.fail(usage)
	end
	local function value(name: string): string
		local got = opts[name]
		return if got and got[#got] then approverun.cell(got[#got]) else "-"
	end
	local guess = value("--guess")
	if guess == "none" then
		guess = "-"
	end
	local new: approverun.Ruling = {
		ticket = pos[1],
		guess = guess,
		action = pos[2],
		stage = value("--stage"),
		note = value("--note"),
		lesson = value("--lesson"),
		ask = value("--ask"),
		into = value("--into"),
	}
	if
		new.action == "approve"
		and (new.note ~= "-" or new.lesson ~= "-" or new.ask ~= "-" or new.into ~= "-")
	then
		ctx.fail(
			`{pos[1]}: an approval takes no --note, --lesson, --ask or --into; the owner approves, nothing else`
		)
	end
	local refused = approverun.addRuling(root, run, new)
	if refused then
		ctx.fail(`approve --ruling: {refused}`)
	end
	say(
		`ruling written for {new.ticket} in {run}: {new.action}{if new.guess == "-"
			then ""
			else " " .. new.guess}. Nothing is recorded until the person runs ./zn approve --apply {run}.`
	)
end

-- Starts the owner's CLI on the run, on the terminal, and returns when it exits, with its exit code.
local function launch(run: string, root: string, scopeArgs: string, ctx: Ctx): number
	local dir = approverun.dir(root, run) :: string
	local help =
		`The run is written: ./zn approve{if scopeArgs == "" then "" else " " .. scopeArgs} --queue prints it, and /z-approve {run} in a session walks it; then ./zn approve --apply {run}.`
	local ok, layers = pcall(models.walk, ".", "")
	local spec: models.Spec? = nil
	local reason = "it is not there"
	local where = "[roles.approve]"
	if ok and not models.config(layers :: { models.Layer }).legacy then
		where = "[activities.approve]"
	end
	if not ok then
		reason = tostring(layers)
	else
		-- f0421 step 6: the same resolution as every activity: the one CLI (ZN_CLI, then on a legacy walk the role's
		-- own), and what that CLI delivers for approve
		local found, problem =
			models.cliFor(layers :: { models.Layer }, "approve", nil, process.env.ZN_CLI, "approve")
		if found == nil then
			reason = problem :: string
		else
			local got, why =
				models.resolveActivity(layers :: { models.Layer }, found, "approve", "normal", nil)
			if got ~= nil then
				spec = got
			else
				reason = models.refusal(layers :: { models.Layer }, found, "approve", "normal", why)
			end
		end
	end
	if not spec then
		ctx.fail(`approve: .models.toml names no usable {where} ({reason}). {help}`)
	end
	local chosen = spec :: models.Spec
	if chosen.cli ~= "claude" then
		ctx.fail(
			`approve: the walkthrough is started interactively only on claude, and {where} names {chosen.cli}. {help}`
		)
	end
	if not sh.run("sh", { "-c", "command -v claude" }).ok then
		ctx.fail(`approve: claude is not on PATH. {help}`)
	end
	local opening =
		`Use the z-approve skill for approval run {run}. The brief is {dir}/{approverun.BRIEF}: read it first, then walk me through the tickets.`
	say(
		`starting claude ({chosen.model}) on run {run}; exit it when the walk is done, and the command asks you to confirm each ruling`
	)
	-- the CLI is a child with its own environment: nothing it sets comes back to this process, which records
	local ran = process.exec(
		"sh",
		{ "-c", 'exec "$@" </dev/tty', "sh", "claude", "--model", chosen.model, opening },
		{
			cwd = root,
			env = { ZN_APPROVE_SESSION = run },
			stdio = "inherit",
		}
	)
	return ran.code
end

-- Handles the forms the walkthrough adds. True when it handled the call, false for the old forms (a bare issue id,
-- or --check/--publish with one), which `cmd.approve` keeps.
function approvewalk.run(pos: { string }, opts: { [string]: { string } }, ctx: Ctx): boolean
	if opts["--help"] then
		say(
			"usage: approve <issue-id> [--check|--publish] | [<R-id>] [--walk <issue-id>] [--queue] | --ruling <run> <issue-id> approve|change ... | --apply <run>"
		)
		return true
	end
	local asked = pos[1]
	local walks = opts["--walk"] ~= nil
	local isNew = opts["--queue"] ~= nil
		or opts["--ruling"] ~= nil
		or opts["--apply"] ~= nil
		or walks
		or #pos == 0
		or (asked ~= nil and string.sub(asked, 1, 1) ~= "-" and not store.isIssueId(asked))
	if not isNew then
		return false
	end
	local trees = ctx.worktrees()
	local root = trees[1].path
	local forms = (if opts["--ruling"] then 1 else 0) + (if opts["--apply"] then 1 else 0)
	if
		forms > 1
		or (
			(opts["--ruling"] or opts["--apply"])
			and (opts["--check"] or opts["--publish"] or opts["--queue"] or walks)
		)
	then
		ctx.fail(
			"usage: approve [<R-id>] [--walk <issue-id>] [--queue] | --ruling <run> <issue-id> approve|change ... | --apply <run>"
		)
	end
	if opts["--ruling"] then
		ruling(pos, opts, root, ctx)
		return true
	end
	if opts["--apply"] then
		if #pos ~= 1 then
			ctx.fail("usage: approve --apply <run>")
		end
		for k in opts do
			if k ~= "--apply" then
				ctx.fail(`usage: approve --apply <run> (unknown option {k})`)
			end
		end
		apply(pos[1], root, ctx, nil)
		return true
	end
	if opts["--check"] or opts["--publish"] then
		ctx.fail("usage: approve <issue-id> [--check|--publish] (a scope takes --queue, or no option)")
	end
	for k in opts do
		if k ~= "--queue" and k ~= "--walk" then
			ctx.fail(`usage: approve [<R-id>] [--walk <issue-id>] [--queue] (unknown option {k})`)
		end
	end
	local scope = ""
	if walks then
		scope = (opts["--walk"] or {})[1] or ""
		if #pos > 0 or not store.isIssueId(scope) then
			ctx.fail("usage: approve --walk <issue-id> [--queue]")
		end
	elseif asked then
		if store.isIssueId(asked) then
			ctx.fail(`approve: {asked} is a ticket: use ./zn approve --walk {asked} [--queue]`)
		end
		if #pos > 1 or not string.match(asked, "^R%d%d%d%d$") then
			ctx.fail(
				`approve: {asked} is not a raft or a ticket. Scopes are a raft id (R0050), --walk <issue-id> and none (the folder's project); tributaries come with the board's reader.`
			)
		end
		scope = asked
	end
	local queueOnly = opts["--queue"] ~= nil
	if not queueOnly then
		local hint = if walks
			then `./zn approve --walk {scope}`
			elseif scope == "" then "./zn approve"
			else `./zn approve {scope}`
		refuseAgent(ctx, scope, hint)
	end
	local run, g = writeRun(root, scope, ctx)
	if not run then
		say(`nothing waits for approval in {scopeText(scope)} ({g.working + g.drafts} still being worked)`)
		return true
	end
	printQueue(run, root, g)
	if queueOnly then
		say(
			`In a session, run /z-approve {run}; it writes rulings, then the person runs ./zn approve --apply {run} in a terminal.`
		)
		return true
	end
	local code = launch(run, root, if walks then `--walk {scope}` else scope, ctx)
	if code ~= 0 then
		local found = approverun.read(root, run)
		local count = if found then #(found :: approverun.Run).rulings else 0
		say(`claude exited with code {code}`)
		if count == 0 then
			say(
				`the session wrote no rulings; nothing to apply. ./zn approve --apply {run} applies any written later`
			)
			return true
		end
		stdio.write(`the session ended with an error; apply the {count} rulings it wrote? [y/N] `)
		local answer = readTerminal()
		say("")
		if answer ~= "y" and answer ~= "Y" then
			say(`not applied: ./zn approve --apply {run} applies them later`)
			return true
		end
	end
	apply(run, root, ctx, g.rows)
	return true
end

return approvewalk
