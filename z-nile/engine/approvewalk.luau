--!strict
-- f0423 step 1: the walkthrough forms of `./zn approve` (the edge; the rules are waiting.luau's and the run folder's
-- are approverun.luau's). A scope (`R0050`, `--walk <id>`, or none) becomes a run: what waits, in order, and a brief.
-- The person's session reads the brief and writes rulings with `--ruling`; only `--apply`, typed on the real terminal,
-- records anything, one `y` per ruling, and only on the design that was walked. `main.luau` hands over the parsed
-- arguments and the few helpers it owns (`Ctx`); this module never requires it.
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
-- session, and only on a terminal. `hint` is the command the person runs themselves.
local function refuseAgent(ctx: Ctx, what: string, hint: string)
	local dispatched = process.env.ZN_DISPATCH
	if dispatched and dispatched ~= "" then
		ctx.fail(`{what}: approve is refused while ZN_DISPATCH is set. Run {hint} yourself, in a terminal.`)
	end
	local session = process.env.ZN_APPROVE_SESSION
	if session and session ~= "" then
		ctx.fail(
			`{what}: approve is refused inside a walkthrough session (ZN_APPROVE_SESSION is set): an agent never records an approval. Write rulings with ./zn approve --ruling, then ask the person to run ./zn approve --apply {session} in a terminal.`
		)
	end
	if not ctx.terminal() then
		ctx.fail(
			`{what}: approve is refused without a terminal on stdin. Run {hint} yourself, in a terminal.`
		)
	end
end

-- ---------------------------------------------------------------- reading the facts

type Facts = {
	copy: approveplace.Copy,
	place: string,
	where: string?, -- the worktree path when the design is there, nil for origin/main
	fact: waiting.Fact,
	verdict: waiting.Verdict,
}

local function factOf(item: store.Item, front: { [string]: string }, lands: boolean, ctx: Ctx): Facts?
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
	local built = false
	if item.state == "active" and (front.raft or "") ~= "" then
		built = #layergit.layersOf(front.raft :: string) > 0
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

local function readText(path: string): string
	return if fs.isFile(path) then fs.readFile(path) else ""
end

type Gathered = {
	rows: { approverun.QueueRow },
	entries: { approverun.Entry },
	waits: number,
	working: number,
}

-- What waits in the scope, the bottom of a stack first. `scope` is a raft id, a ticket id (`--walk`) or "" (the
-- folder's project).
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
	-- the raft's ticket order is its layer order
	local layerOf: { [string]: number } = {}
	local layersOfRaft: { [string]: { any } } = {}
	local landsOf: { [string]: boolean } = {}
	for _, i in picked do
		if i.unit ~= i.item.id and layerOf[i.item.id] == nil then
			local raft = store.find(i.unit)
			if raft then
				for n, m in layergit.orderedMembers(raft) do
					layerOf[m.id] = n
				end
				layersOfRaft[i.unit] = layergit.layersOf(i.unit) :: { any }
				landsOf[i.unit] = layergit.readyRecord(i.unit).lands
			end
		end
	end
	local byId: { [string]: Facts } = {}
	local placed: { waiting.Placed } = {}
	local working: { string } = {}
	for _, i in picked do
		local f = factOf(i.item, i.front, landsOf[i.unit] == true, ctx)
		if f then
			byId[i.item.id] = f
			if f.verdict.state == "waits" then
				table.insert(placed, { id = i.item.id, unit = i.unit, layer = layerOf[i.item.id] or 1 })
			elseif f.verdict.state == "working" then
				table.insert(working, i.item.id)
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
	local out: Gathered = { rows = {}, entries = {}, waits = #placed, working = #working }
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
		local base = f.where or sh.git({ "rev-parse", "--show-toplevel" })
		local guessText = readText(`{base}/{i.item.dir}/{guesses.FILE}`)
		local guessLines: { string } = {}
		for line in string.gmatch(guessText, "[^\n]+") do
			if string.sub(line, 1, 2) == "- " then
				table.insert(guessLines, string.sub(line, 3))
			end
		end
		local marks: { string } = {}
		for line in string.gmatch(readText(`{base}/{i.item.doc}`), "[^\n]+") do
			if string.find(line, "Guess (prep)", 1, true) then
				table.insert(marks, if #line > 300 then string.sub(line, 1, 300) .. "..." else line)
				if #marks == 5 then
					break
				end
			end
		end
		local layer: string? = nil
		if f.fact.stage == "built" then
			local layers = layersOfRaft[i.unit] or {}
			local found = layers[layerOf[id] or 0]
			layer = if found then (found :: any).name else nil
		end
		table.insert(out.entries, {
			id = id,
			title = i.front.title or i.front.slug or id,
			unit = i.unit,
			state = f.verdict.state :: string,
			why = f.verdict.why,
			stage = f.fact.stage :: string,
			doc = i.item.doc,
			place = f.place,
			hash = f.copy.hash or "-",
			guesses = guessLines,
			places = marks,
			layer = layer,
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
		approverun.brief(run :: string, scopeText(scope), g.entries)
	)
	if failed then
		ctx.fail(`approve: {failed}`)
	end
	return run, g
end

local function printQueue(run: string, root: string, g: Gathered)
	local dir = approverun.dir(root, run) :: string
	say(`approval run {run}: {g.waits} waiting for the owner, {g.working} still being worked`)
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

local function shellQuote(text: string): string
	return "'" .. string.gsub(text, "'", "'\\''") .. "'"
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

local function reworkLine(r: approverun.Ruling): string
	local bits = { `./zn rework {r.ticket} --stage {r.stage}` }
	if r.guess ~= "-" then
		table.insert(bits, `--guess {r.guess}`)
	end
	table.insert(bits, `--note {shellQuote(r.note)}`)
	if r.lesson ~= "-" then
		table.insert(bits, `--lesson {shellQuote(r.lesson)} --ask {shellQuote(r.ask)}`)
	end
	if r.into ~= "-" then
		table.insert(bits, `--into {r.into}`)
	end
	return table.concat(bits, " ")
end

-- `--apply <run>`: asks y/N for each ruling on the real terminal, then records the approvals the owner confirmed.
local function apply(run: string, root: string, ctx: Ctx)
	refuseAgent(ctx, run, `./zn approve --apply {run}`)
	local found, err = approverun.read(root, run)
	if not found then
		ctx.fail(`approve --apply: {err}`)
	end
	local current = found :: approverun.Run
	local top = sh.git({ "rev-parse", "--show-toplevel" })
	local recorded, printed, waited, refused = 0, 0, 0, 0
	local todo = 0
	for _, r in current.rulings do
		local done = false
		for _, a in current.applied do
			done = done or (a.ticket == r.ticket and a.guess == r.guess)
		end
		if done then
			continue
		end
		todo += 1
		local row: approverun.QueueRow? = nil
		for _, q in current.queue do
			if q.id == r.ticket then
				row = q
			end
		end
		if not row then
			say(`{r.ticket}: not in the queue of {run}; skipped`)
			continue
		end
		local queued = row :: approverun.QueueRow
		local title = "?"
		local item = store.find(r.ticket)
		if item then
			title = store.readFront(item.doc).title or r.ticket
		end
		local question = if r.action == "approve"
			then `Approve {r.ticket} ({title}) on the design walked in {run}? [y/N] `
			else `Change {r.ticket} ({title}) {if r.guess == "-" then "" else r.guess .. " "}at the {r.stage} stage: "{r.note}". {r.ticket} goes back to the {r.stage} stage. Apply? [y/N] `
		stdio.write(question)
		local answer = readTerminal()
		say("")
		if answer ~= "y" and answer ~= "Y" then
			waited += 1
			say(`{r.ticket}: nothing recorded; the ruling waits for a later ./zn approve --apply {run}`)
			continue
		end
		local when = os.date("!%Y-%m-%dT%H:%M:%SZ") :: string
		if r.action == "change" then
			say(`{r.ticket}: confirmed. To carry the change out, run: {reworkLine(r)}`)
			approverun.addApplied(
				root,
				run,
				{ ticket = r.ticket, guess = r.guess, outcome = "change-printed", when = when }
			)
			printed += 1
			continue
		end
		-- an approval is recorded only on the design that was walked
		local itemNow = if item then item else nil
		local nowFacts: Facts? = nil
		if itemNow then
			nowFacts = factOf(itemNow, store.readFront(itemNow.doc), false, ctx)
		end
		local currentHash = if nowFacts then (nowFacts :: Facts).copy.hash else nil
		if queued.hash == "-" or currentHash ~= queued.hash then
			local parts =
				changedParts(queued.parts, if nowFacts then (nowFacts :: Facts).copy.partHashes else nil)
			local named = if #parts > 0 then table.concat(parts, ", ") else "the design"
			stdio.ewrite(
				`{r.ticket}: not recorded: its contract changed since the walkthrough {run} ({named}). Walk it again: ./zn approve --walk {r.ticket}\n`
			)
			refused += 1
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
			ctx.fail(
				`{r.ticket}: ./zn approve {r.ticket} failed ({ran.code}); nothing is marked applied: fix it, then ./zn approve --apply {run}`
			)
		end
		approverun.addApplied(
			root,
			run,
			{ ticket = r.ticket, guess = r.guess, outcome = "recorded", when = when }
		)
		recorded += 1
	end
	if todo == 0 then
		say(`{run}: no rulings waiting to be applied`)
		return
	end
	say(`{run}: {recorded} approved, {printed} changes confirmed, {waited} left waiting, {refused} refused`)
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

-- Starts the owner's CLI on the run, on the terminal, and returns when it exits.
local function launch(run: string, root: string, scope: string, ctx: Ctx)
	local dir = approverun.dir(root, run) :: string
	local help =
		`The run is written: ./zn approve {scope} --queue prints it, and /z-approve {run} in a session walks it; then ./zn approve --apply {run}.`
	local ok, layers = pcall(models.walk, ".", "")
	local spec: models.Spec? = nil
	if ok then
		local resolved, got = pcall(models.resolveRole, layers :: { models.Layer }, "approve")
		if resolved then
			local r = got :: models.Resolved
			spec = r.specs[r.order[1]]
		end
	end
	if not spec then
		ctx.fail(`approve: .models.toml names no [roles.approve]. {help}`)
	end
	local chosen = spec :: models.Spec
	if chosen.cli ~= "claude" then
		ctx.fail(
			`approve: the walkthrough is started interactively only on claude, and [roles.approve] names {chosen.cli}. {help}`
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
	process.exec("sh", { "-c", 'exec "$@" </dev/tty', "sh", "claude", "--model", chosen.model, opening }, {
		cwd = root,
		env = { ZN_APPROVE_SESSION = run },
		stdio = "inherit",
	})
end

-- Handles the forms the walkthrough adds. True when it handled the call, false for the old forms (a bare issue id,
-- or --check/--publish with one), which `cmd.approve` keeps.
function approvewalk.run(pos: { string }, opts: { [string]: { string } }, ctx: Ctx): boolean
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
		apply(pos[1], root, ctx)
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
		if #pos > 1 or not string.match(asked, "^R%d%d%d%d$") then
			ctx.fail(
				`approve: {asked} is not a raft or a ticket. Scopes are a raft id (R0050), --walk <issue-id> and none (the folder's project); tributaries come with the board's reader.`
			)
		end
		scope = asked
	end
	local queueOnly = opts["--queue"] ~= nil
	if not queueOnly then
		refuseAgent(
			ctx,
			if scope == "" then "approve" else scope,
			`./zn approve {if scope == "" then "" else scope}`
		)
	end
	local run, g = writeRun(root, scope, ctx)
	if not run then
		say(`nothing waits for approval in {scopeText(scope)} ({g.working} still being worked)`)
		return true
	end
	printQueue(run, root, g)
	if queueOnly then
		say(
			`In a session, run /z-approve {run}; it writes rulings, then the person runs ./zn approve --apply {run} in a terminal.`
		)
		return true
	end
	launch(run, root, scope, ctx)
	apply(run, root, ctx)
	return true
end

return approvewalk
