--!strict
-- The tracker board: reads the tracker tree into a model and renders it as one self-contained HTML page.
local boardprov = require("./boardprov")
local boardview = require("./boardview")
local chart = require("./chart")
local fs = require("@lune/fs")
local history = require("./history")
local ledger = require("./ledger")
local process = require("@lune/process")
local projects = require("./projects")
local serde = require("@lune/serde")
local stack = require("./stack")
local stats = require("./stats")
local status = require("./status")
local store = require("./store")
local who = require("./who")

local board = {}

export type Bucket = "ready" | "not" | "done"
export type ViewName = "board" | "rafts" | "issues"
export type Groups = { ready: { string }, ["not"]: { string }, done: { string } }
export type Raft = {
	id: string,
	kind: string, -- "raft"
	type: string, -- frontmatter type: "feature" | "defect" | "chore" | ""
	label: string, -- "feature" | "defect" | "chore" | "mix" | ""
	title: string,
	state: string, -- "backlog" | "active" | "done", from the directory
	design: string, -- frontmatter design ("" if absent)
	status: string, -- "done" | "active" | "ready" | "reviewed" | "draft"
	stage: string, -- status.effective: "new" | "preparing" | "prepared" | "active" | "done"
	single: boolean,
	pseudo: boolean, -- false for every raft; there is no No raft entry
	issues: { string }, -- member issue ids, sorted
	dependsOn: { string }, -- raft ids, sorted
	dependents: { string }, -- raft ids, sorted
	blockedBy: { string }, -- unfinished dependencies: raft ids and raftless issue ids, sorted
	topLevel: boolean, -- #blockedBy == 0
	command: string?, -- nil when this row has no next command
	body: string,
	project: string, -- the project whose root holds it (c0118)
	launched: boolean, -- a branch <R-id>-… exists, local or on origin
	branch: string?, -- that branch's name
	worktree: string?, -- the worktree that has it checked out
	doneAt: number?, -- first arrival in done/, UTC epoch seconds (history, else the members' newest spend row)
	doneFrom: string?, -- "history" or "spend": where doneAt came from
	rounds: { design: number, code: number }, -- review files of it, its members and the rafts retired into it
	dispatch: Dispatch?,
	pr: Pr?, -- c0121 fills these on the served page; the static page leaves them nil
	checks: Checks?,
	provenance: { boardprov.Entry }?, -- c0284: the entries ./zn who prints for it; nil when it has none
}
-- Reserved for c0121's served page (live `gh` data); nil in every model c0118 builds.
export type Pr = { number: number, url: string, state: string }
export type Checks = { state: string, url: string? }
-- The dispatcher's run state for an id (c0117's .cache/dispatch/<id>/state.json): its step, outcome and model, and
-- whether it waits for answers in questions.md.
export type Dispatch = { step: string, outcome: string, model: string, questions: boolean }
export type Spend = { minutes: number, tokens: number, added: number, removed: number, models: { string } }
export type Issue = {
	id: string,
	kind: string, -- always "issue"
	type: string,
	label: string, -- the issue's own type ("" when it has none)
	title: string,
	state: string,
	design: string,
	status: string,
	stage: string,
	raft: string?, -- frontmatter raft; nil when empty, absent or naming a raft that does not exist
	dependsOn: { string }, -- frontmatter depends_on ids, sorted, as written (even if they don't exist)
	dependents: { string }, -- raft ids whose members depend_on a raftless issue; {} otherwise
	emergent: boolean,
	command: string?,
	body: string,
	project: string,
	column: boardview.Column, -- c0118: ticket, design, raft, ready, run or done
	doneAt: number?,
	doneFrom: string?,
	age: number?, -- seconds between doneAt and the model's asOf
	spend: Spend, -- from its spend.md (ledger.parse)
	dispatch: Dispatch?,
	pr: Pr?, -- c0121's, as on Raft
	checks: Checks?,
	provenance: { boardprov.Entry }?, -- c0284, as on Raft
}
export type Project = { name: string, root: string }
-- What the board knows besides the tracker documents (c0118), all read locally: the instant the page is as of (HEAD's
-- commit time), the branches (refs/heads and refs/remotes/origin, short names, with each tip's commit time), the
-- worktrees, the dispatcher's state.
export type Ref = { name: string, at: number }
export type Facts = {
	asOf: number?,
	refs: { Ref },
	worktrees: { { path: string, branch: string } },
	dispatch: { [string]: Dispatch },
}
export type ProjectCharts = {
	rounds: { [string]: string },
	tokens: { [string]: string },
	captions: { rounds: { [string]: string }, tokens: { [string]: string } },
}
export type Model = {
	rafts: { Raft }, -- sorted by id
	issues: { Issue }, -- sorted by id
	views: { rafts: Groups, issues: Groups },
	home: { [string]: string }, -- every id maps to itself
	initialView: ViewName, -- always "board" (c0118)
	stats: stats.Stats,
	projects: { Project }, -- the registry's order; the first is selected when the page opens
	columns: { [string]: { [string]: { boardview.Band } } }, -- project -> column -> bands
	charts: { [string]: ProjectCharts }, -- project -> chart -> range key -> svg
	asOf: number?,
	history: boolean, -- false without git history (a shallow clone): done times then come from spend rows alone
	windows: { number },
	window: number,
	ranges: { { key: string, label: string } },
	range: string,
	problems: { string }, -- files the board could not read (a spend.md that does not parse)
}

board.MARKED_PATH = "z-nile/vendor/marked.umd.js"
board.MARKED_SHA256 = "21568877a938d2c4e7d74e27f18e60da96bb73a68809610ca39216e1efebae62"
board.TEMPLATE_PATH = "z-nile/engine/board.html"
-- The checkout that holds this module (two folders above z-nile/engine/board.luau): the paths above are relative to it,
-- and the board reads them from there, wherever it runs (c0120: specs run from a project's home)
board.TOP = string.match(debug.info(1, "s"), "^(.*)/[^/]+/[^/]+/[^/]+$") or "."
-- a path above, read from the checkout; an absolute one as it is
local function fromTop(path: string): string
	return if string.sub(path, 1, 1) == "/" then path else `{board.TOP}/{path}`
end

-- Errors unless the vendored marked is the pinned build.
function board.checkMarked(js: string)
	local got = serde.hash("sha256", js)
	if got ~= board.MARKED_SHA256 then
		error(
			`{board.MARKED_PATH} is not the pinned marked build (sha256 {got}, expected {board.MARKED_SHA256})`,
			0
		)
	end
end

-- marked without its trailing source-map comment, so a browser never fetches marked.umd.js.map.
function board.inlineMarked(js: string): string
	return (string.gsub(js, "\n//# sourceMappingURL=[^\n]*\n?$", "\n"))
end

local TYPES: { [string]: boolean } = { feature = true, defect = true, chore = true }

-- Every %w+ run of a frontmatter list like "[f0100, c0090]", sorted.
local function listOf(value: string?): { string }
	local out: { string } = {}
	for id in string.gmatch(value or "", "%w+") do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

local function sortedKeys(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for k in set do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

-- The document after its frontmatter, without leading blank lines; a document without frontmatter is all body.
local function bodyOf(text: string): string
	if string.sub(text, 1, 4) ~= "---\n" then
		return text
	end
	local _, closeEnd = string.find(text, "\n%-%-%-[^\n]*", 4)
	if not closeEnd then
		return text
	end
	return (string.gsub(string.sub(text, closeEnd + 1), "^\n+", ""))
end

type Raw = { id: string, state: string, front: { [string]: string }, body: string, root: string, dir: string }

-- { id, state, front, body, root } for every item directory of one kind under root.
local function scan(root: string, kind: string): { Raw }
	local found = {}
	local base = `{root}/{kind}`
	local function isId(name: string): boolean
		return if kind == "rafts" then store.isRaftId(name) else store.isIssueId(name)
	end
	for _, state in { "backlog", "active", "done" } do
		local dir = if state == "backlog" then base else `{base}/{state}`
		if not fs.isDir(dir) then
			continue
		end
		for _, name in fs.readDir(dir) do
			local doc = `{dir}/{name}/{name}.md`
			if isId(name) and fs.isFile(doc) then
				table.insert(found, {
					id = name,
					state = state,
					front = store.readFront(doc),
					body = bodyOf(fs.readFile(doc)),
					root = root,
					dir = `{dir}/{name}`,
				})
			end
		end
	end
	table.sort(found, function(a, b)
		return a.id < b.id
	end)
	return found
end

local function statusOf(state: string, design: string): string
	if state == "done" or state == "active" then
		return state
	end
	if design == "ready" or design == "reviewed" then
		return design
	end
	return "draft"
end

local VIEWS = { "month", "quarter", "year" }
local TYPE_ORDER = { "all", "feature", "defect", "chore" }
local TYPE_LABEL = { all = "All", feature = "Feature", defect = "Defect", chore = "Chore" }
local STATES = { "new", "preparing", "prepared", "active" }
local MINUS = utf8.char(0x2212)
type ChartKind = "bars" | "stacked" | "mirror" | "lines" | "hbars"

local function kindOf(value: string?): stats.Kind?
	if value == "feature" then
		return "feature"
	elseif value == "defect" then
		return "defect"
	elseif value == "chore" then
		return "chore"
	end
	return nil
end

local function dayOf(value: string?): string?
	return if value then string.match(value, "^(%d%d%d%d%-%d%d%-%d%d)") else nil
end

local function parentOf(dir: string): string
	local parent = string.match(dir, "^(.*)/[^/]+$")
	if not parent or parent == "" then
		return "."
	end
	return parent
end

local function spendPath(root: string, state: string, id: string): string
	if state == "backlog" then
		return `{root}/issues/{id}/spend.md`
	end
	return `{root}/issues/{state}/{id}/spend.md`
end

-- An issue's spend rows through the one reader of spend.md (ledger.parse, c0084 and c0117). A file that does not
-- parse gives no rows and is named in `problems`.
local spendCache: { [string]: { ledger.Row } } = {}
local spendBad: { [string]: boolean } = {} -- spend.md files that did not parse (c0284: `who` refuses such an item)
local function spendRows(path: string, problems: { string }): { ledger.Row }
	local hit = spendCache[path]
	if hit then
		return hit
	end
	local rows: { ledger.Row } = {}
	if fs.isFile(path) then
		local parsed, err = ledger.parse(fs.readFile(path))
		if parsed then
			rows = parsed.rows
		else
			table.insert(problems, `{path} does not parse: {err}`)
			spendBad[path] = true
		end
	end
	spendCache[path] = rows
	return rows
end

local function readSpend(
	path: string,
	problems: { string }
): { { day: string, added: number, removed: number, minutes: number } }
	local out = {}
	for _, row in spendRows(path, problems) do
		local day = dayOf(row.when)
		if day then
			table.insert(out, { day = day, added = row.added, removed = row.removed, minutes = row.minutes })
		end
	end
	return out
end

local function statistics(hist: history.Parsed?, rawIssues: { Raw }, problems: { string }): stats.Stats
	local items: { stats.Item } = {}
	local spends: { stats.Spend } = {}
	local latest = ""
	local function consider(day: string?)
		if day and day > latest then
			latest = day
		end
	end
	for _, raw in rawIssues do
		local kind = kindOf(raw.front.type)
		-- kindOf's singleton return is widened to string at the boundary; narrow it back.
		if kind == "feature" or kind == "defect" or kind == "chore" then
			local opened = dayOf(raw.front.created) or ""
			consider(if opened ~= "" then opened else nil)
			local closed: string? = nil
			local spells: { stats.Spell } = {}
			if hist then
				closed = hist.closed[raw.id]
				spells = hist.spells[raw.id] or {}
			end
			table.insert(
				items,
				{ id = raw.id, type = kind, opened = opened, closed = closed, spells = spells }
			)
			for _, row in readSpend(spendPath(raw.root, raw.state, raw.id), problems) do
				consider(row.day)
				table.insert(spends, {
					id = raw.id,
					type = kind,
					day = row.day,
					added = row.added,
					removed = row.removed,
					minutes = row.minutes,
				})
			end
		end
	end
	local today = if hist and hist.today and hist.today ~= "" then hist.today else latest
	local out = stats.compute(items, spends, today, hist ~= nil)
	if not hist then
		out.durations = {}
	end
	return out
end

local function labelsOf(rows: { stats.Row }): { string }
	local labels: { string } = {}
	for _, row in rows do
		table.insert(labels, row.bucket.label)
	end
	return labels
end

local function column(rows: { stats.Row }, metric: string, ty: string): { number? }
	local values: { number? } = table.create(#rows)
	for i, row in rows do
		local counts = (row :: any)[metric] :: stats.Counts
		values[i] = (counts :: any)[ty]
	end
	return values
end

local function typeSeries(rows: { stats.Row }, metric: string, ty: string, label: string?): { chart.Series }
	if ty == "all" then
		return {
			{ key = "feature", label = "Feature", values = column(rows, metric, "feature") },
			{ key = "defect", label = "Defect", values = column(rows, metric, "defect") },
			{ key = "chore", label = "Chore", values = column(rows, metric, "chore") },
		}
	end
	return { { key = ty, label = label or TYPE_LABEL[ty], values = column(rows, metric, ty) } }
end

local function hiddenAttr(view: string, ty: string): string
	if (view == "month" or view == "all") and (ty == "all" or ty == "any") then
		return ""
	end
	return " hidden"
end

local function figure(
	id: string,
	view: string,
	ty: string,
	caption: string,
	series: { chart.Series },
	opts: chart.Options
): string
	opts.id = id
	opts.labels = opts.labels
	local svg = chart.svg(series, opts)
	return `<figure class="chart-fig" data-view="{view}" data-type="{ty}"{hiddenAttr(view, ty)}>{svg}<figcaption>{caption}</figcaption></figure>`
end

local function num(n: number?): string
	if n == nil then
		return ""
	end
	if n == math.floor(n) then
		return tostring(n)
	end
	return string.format("%.1f", n)
end

local function num2(n: number?): string
	if n == nil then
		return ""
	end
	return string.format("%.2f", n)
end

local function viewTable(title: string, rows: { stats.Row }): string
	local body: { string } = {}
	for _, row in rows do
		table.insert(
			body,
			`<tr><td>{row.bucket.label}</td><td>{row.opened.all}</td><td>{row.closed.all}</td><td>{row.net.all}</td><td>{num(
				row.minutes.all
			)}</td><td>{row.added.all}</td><td>{row.removed.all}</td><td>{row.netLines.all}</td></tr>`
		)
	end
	return `<table><caption>{title}</caption><thead><tr><th>bucket</th><th>opened</th><th>closed</th><th>net</th><th>minutes</th><th>+lines</th><th>{MINUS}lines</th><th>net lines</th></tr></thead><tbody>{table.concat(
		body
	)}</tbody></table>`
end

local function pct(n: number?): string
	if n == nil then
		return ""
	end
	return `{num(n)}%`
end

local function periodsTable(
	periods: { week: stats.Row, month: stats.Row, quarter: stats.Row, year: stats.Row }?
): string
	local body: { string } = {}
	if periods then
		for _, name in { "week", "month", "quarter", "year" } do
			local row = (periods :: any)[name] :: stats.Row
			for _, ty in TYPE_ORDER do
				local ratios = if ty == "all"
					then `<td>{pct(row.ratios.defectCount)}</td><td>{pct(row.ratios.defectTime)}</td><td>{pct(
						row.ratios.choreCount
					)}</td><td>{pct(row.ratios.choreTime)}</td>`
					else "<td></td><td></td><td></td><td></td>"
				table.insert(
					body,
					`<tr><td>{row.bucket.label}</td><td>{TYPE_LABEL[ty]}</td><td>{(row.opened :: any)[ty]}</td><td>{(
						row.closed :: any
					)[ty]}</td><td>{num((row.minutes :: any)[ty])}</td>{ratios}</tr>`
				)
			end
		end
	end
	return `<table><caption>Periods</caption><thead><tr><th>period</th><th>type</th><th>opened</th><th>closed</th><th>minutes</th><th>defect %</th><th>defect time %</th><th>chore %</th><th>chore time %</th></tr></thead><tbody>{table.concat(
		body
	)}</tbody></table>`
end

local function durationsTable(durations: { [string]: stats.ByType }): string
	local body: { string } = {}
	for _, state in STATES do
		local by = durations[state]
		if by then
			for _, ty in { "all", "feature", "defect", "chore" } do
				local spread = (by :: any)[ty] :: stats.Spread
				table.insert(
					body,
					`<tr><td>{state}</td><td>{TYPE_LABEL[ty]}</td><td>{spread.n}</td><td>{num2(spread.mean)}</td><td>{num2(
						spread.median
					)}</td></tr>`
				)
			end
		end
	end
	return `<table><caption>Time in state</caption><thead><tr><th>state</th><th>type</th><th>n</th><th>mean days</th><th>median days</th></tr></thead><tbody>{table.concat(
		body
	)}</tbody></table>`
end

-- One line: the acceptance spec matches the stats section and the tables div without crossing a newline.
local function statsHtml(s: stats.Stats): string
	local parts: { string } = {}
	if not s.history then
		table.insert(
			parts,
			"<p>history unavailable (shallow or no git): closed and time in state are omitted</p>"
		)
	end
	if s.today == "" then
		table.insert(parts, "<p>no dated data</p>")
	end
	table.insert(
		parts,
		'<div id="stats-view"><button type="button" data-view="month" class="on">Month</button><button type="button" data-view="quarter">Quarter</button><button type="button" data-view="year">Year</button></div>'
	)
	table.insert(
		parts,
		'<div id="stats-type"><button type="button" data-type="all" class="on">All</button><button type="button" data-type="feature">Feature</button><button type="button" data-type="defect">Defect</button><button type="button" data-type="chore">Chore</button></div>'
	)
	table.insert(parts, '<button id="stats-table-toggle" type="button">Table</button>')
	local tables = {
		viewTable("Month", s.views.month),
		viewTable("Quarter", s.views.quarter),
		viewTable("Year", s.views.year),
		periodsTable(s.periods),
		durationsTable(s.durations),
	}
	table.insert(parts, `<div id="stats-tables" hidden>{table.concat(tables)}</div>`)
	for _, view in VIEWS do
		local rows = (s.views :: any)[view] :: { stats.Row }
		local labels = labelsOf(rows)
		for _, ty in TYPE_ORDER do
			local function add(
				metric: string,
				caption: string,
				series: { chart.Series },
				kind: ChartKind,
				unit: string,
				below: { chart.Series }?
			)
				table.insert(
					parts,
					figure(`{view}/{ty}/{metric}`, view, ty, caption, series, {
						id = "",
						title = caption,
						unit = unit,
						labels = labels,
						kind = kind,
						below = below,
					})
				)
			end
			add("opened", "Opened", typeSeries(rows, "opened", ty), "stacked", "issues", nil)
			add("closed", "Closed", typeSeries(rows, "closed", ty), "stacked", "issues", nil)
			add("minutes", "Minutes", typeSeries(rows, "minutes", ty), "stacked", "minutes", nil)
			add(
				"net",
				"Net issues",
				{ { key = "net", label = "Net", values = column(rows, "net", ty) } },
				"bars",
				"issues",
				nil
			)
			add(
				"lines",
				"Lines added and removed",
				typeSeries(rows, "added", ty, "Added"),
				"mirror",
				"lines",
				typeSeries(rows, "removed", ty, "Removed")
			)
		end
		local defectCount, choreCount, defectTime, choreTime = {}, {}, {}, {}
		for i, row in rows do
			defectCount[i] = row.ratios.defectCount
			choreCount[i] = row.ratios.choreCount
			defectTime[i] = row.ratios.defectTime
			choreTime[i] = row.ratios.choreTime
		end
		table.insert(
			parts,
			figure(`{view}/ratios-count`, view, "any", "Defect and chore share by count", {
				{ key = "defect", label = "Defect %", values = defectCount },
				{ key = "chore", label = "Chore %", values = choreCount },
			}, {
				id = "",
				title = "Defect and chore share by count",
				unit = "%",
				labels = labels,
				kind = "lines",
			})
		)
		table.insert(
			parts,
			figure(`{view}/ratios-time`, view, "any", "Defect and chore share by time", {
				{ key = "defect", label = "Defect %", values = defectTime },
				{ key = "chore", label = "Chore %", values = choreTime },
			}, {
				id = "",
				title = "Defect and chore share by time",
				unit = "%",
				labels = labels,
				kind = "lines",
			})
		)
	end
	local means: { [string]: { number? } } = { feature = {}, defect = {}, chore = {} }
	local notes: { [string]: { string? } } = { feature = {}, defect = {}, chore = {} }
	for i, state in STATES do
		local by = s.durations[state]
		for _, ty in { "feature", "defect", "chore" } do
			local spread = if by then (by :: any)[ty] :: stats.Spread else nil
			if spread and spread.mean ~= nil then
				means[ty][i] = spread.mean
				notes[ty][i] = `n={spread.n}`
			end
		end
	end
	table.insert(
		parts,
		figure("durations", "all", "any", "Mean days in state", {
			{ key = "feature", label = "Feature", values = means.feature, notes = notes.feature },
			{ key = "defect", label = "Defect", values = means.defect, notes = notes.defect },
			{ key = "chore", label = "Chore", values = means.chore, notes = notes.chore },
		}, {
			id = "",
			title = "Mean days in state",
			unit = "days",
			labels = STATES,
			kind = "hbars",
		})
	)
	return (string.gsub(table.concat(parts), "[\r\n]", ""))
end

-- The projects to read and the checkout whose history the stats come from: `root` alone (one tracker folder, as
-- specs pass; its project is named after the folder above it) with its parent, or else every project of `checkout`
-- (default ".") from its registry, in registry order (c0114, c0118). `base` is the root as read from here.
local function sources(
	root: string?,
	checkout: string?
): ({ { name: string, root: string, base: string } }, string)
	if root then
		local parent = parentOf(root)
		-- named by the folder (or, for `<name>/.tracker`, the folder above it), so the page is the same wherever it is
		local name = string.match(root, "([^/]+)$") or root
		if name == ".tracker" then
			name = string.match(parent, "([^/]+)$") or name
		end
		return { { name = name, root = name, base = root } }, parent -- no path from outside the tree reaches the page
	end
	local dir = checkout or "."
	local out = {}
	for _, p in projects.load(dir).projects do
		table.insert(
			out,
			{ name = p.name, root = p.root, base = if dir == "." then p.root else `{dir}/{p.root}` }
		)
	end
	return out, dir
end

local function run(dir: string, args: { string }): string?
	local ok, r = pcall(process.exec, "git", args, { cwd = dir })
	if not ok or not r.ok then
		return nil
	end
	return r.stdout
end

-- The facts of the checkout `dir` (c0118): HEAD's commit time, the branch names, the worktrees, and the dispatcher's
-- run state under `<dir>/.cache/dispatch/<id>/` (c0117). A git call that fails leaves its fact empty; nothing here
-- writes, fetches or reaches the network.
function board.readFacts(dir: string): Facts
	local facts: Facts = { asOf = nil, refs = {}, worktrees = {}, dispatch = {} }
	local head = run(dir, { "log", "-1", "--format=%ct", "HEAD" })
	facts.asOf = if head then tonumber((string.gsub(head, "%s+", ""))) else nil
	local refs = run(dir, {
		"for-each-ref",
		"--format=%(committerdate:unix) %(refname:short)",
		"refs/heads",
		"refs/remotes/origin",
	})
	for line in string.gmatch(refs or "", "[^\n]+") do
		local at, name = string.match(line, "^(%d+) (%S+)$")
		if at and name then
			table.insert(facts.refs, { name = name, at = tonumber(at) :: number })
		end
	end
	local wt = run(dir, { "worktree", "list", "--porcelain" })
	local path: string? = nil
	for line in string.gmatch(wt or "", "[^\n]+") do
		local p = string.match(line, "^worktree (.+)$")
		local b = string.match(line, "^branch refs/heads/(.+)$")
		if p then
			path = p
		elseif b and path then
			table.insert(facts.worktrees, { path = path, branch = b })
		end
	end
	local home = `{dir}/.cache/dispatch`
	if fs.isDir(home) then
		for _, name in fs.readDir(home) do
			local file = `{home}/{name}/state.json`
			if (store.isRaftId(name) or store.isIssueId(name)) and fs.isFile(file) then
				local ok, decoded = pcall(serde.decode, "json" :: "json", fs.readFile(file))
				if ok and type(decoded) == "table" then
					local st = decoded :: { [string]: any }
					facts.dispatch[name] = {
						step = if type(st.step) == "string" then st.step else "",
						outcome = if type(st.outcome) == "string" then st.outcome else "",
						model = if type(st.model) == "string" then st.model else "",
						questions = fs.isFile(`{home}/{name}/questions.md`),
					}
				end
			end
		end
	end
	return facts
end

local NO_FACTS: Facts = { asOf = nil, refs = {}, worktrees = {}, dispatch = {} }

-- The branch that launched raft `id`. A layer (`R0010/1/c0010`) wins, the highest position. Otherwise the
-- first ref, in name order, named `<id>-…` (local) or `origin/<id>-…`, whose tip is newer than the raft's
-- latest arrival in active/ (`since`). A branch left from before a stop and a new ready launched nothing.
local function branchOf(id: string, refs: { Ref }, since: number?): string?
	local sorted = table.clone(refs)
	table.sort(sorted, function(a, b)
		return a.name < b.name
	end)
	local best: string? = nil
	local bestPos = 0
	for _, ref in sorted do
		local name = if string.sub(ref.name, 1, 7) == "origin/" then string.sub(ref.name, 8) else ref.name
		local layer = stack.parse(name)
		if layer and layer.raft == id and layer.position >= bestPos and (since == nil or ref.at > since) then
			best = name
			bestPos = layer.position
		end
	end
	if best then
		return best
	end
	for _, ref in sorted do
		local name = if string.sub(ref.name, 1, 7) == "origin/" then string.sub(ref.name, 8) else ref.name
		if string.sub(name, 1, #id + 1) == id .. "-" and (since == nil or ref.at > since) then
			return name
		end
	end
	return nil
end

-- The model id a spend row records (c0117's tenth column, `ledger.Row.model`); nil for a row without one, and for every
-- row while the ledger has no model column yet.
local function modelOf(row: ledger.Row): string?
	local m = (row :: any).model
	return if type(m) == "string" and m ~= "" then m else nil
end

local function spendOf(rows: { ledger.Row }): Spend
	local out: Spend = { minutes = 0, tokens = 0, added = 0, removed = 0, models = {} }
	local seen: { [string]: boolean } = {}
	for _, row in rows do
		out.minutes += row.minutes
		out.tokens += row.tokens or 0
		out.added += row.added
		out.removed += row.removed
		local model = modelOf(row)
		if model and not seen[model] then
			seen[model] = true
			table.insert(out.models, model)
		end
	end
	table.sort(out.models)
	out.minutes = math.floor(out.minutes * 10 + 0.5) / 10
	return out
end

-- Every file path of the folder: which of them are review rounds is `boardview.rounds`' alone (c0118 §6, review 001 F3).
local function reviewFiles(dir: string, into: { string })
	if not fs.isDir(dir) then
		return
	end
	for _, name in fs.readDir(dir) do
		table.insert(into, `{dir}/{name}`)
	end
end

-- Every retired raft (`<root>/rafts/retired/<R-id>`, c0116) with the keeper its `retired:` names.
local function retiredOf(base: string): { { id: string, dir: string, keeper: string } }
	local out = {}
	local dir = `{base}/rafts/retired`
	if not fs.isDir(dir) then
		return out
	end
	for _, name in fs.readDir(dir) do
		local doc = `{dir}/{name}/{name}.md`
		if store.isRaftId(name) and fs.isFile(doc) then
			table.insert(
				out,
				{ id = name, dir = `{dir}/{name}`, keeper = store.readFront(doc).retired or "" }
			)
		end
	end
	return out
end

-- The svg and the caption that names what the picture cannot show by itself (review 001 F1): the unit the axis was scaled
-- to, and the series when there is only one (the chart draws a legend from two).
local function chartSvg(id: string, title: string, rawUnit: string, raw: boardview.Weekly): (string, string)
	local w, unit = boardview.scaled(raw, rawUnit)
	local series: { chart.Series } = {}
	for _, s in w.series do
		table.insert(series, { key = s.key, label = s.label, values = s.values })
	end
	local caption = if unit == "rounds" then "" else `, {unit}`
	if #series == 1 then
		caption ..= `: {series[1].label}`
	end
	return chart.svg(series, { id = id, title = title, unit = unit, labels = w.labels, kind = "stacked" }),
		caption
end

local function sortById(list: { Raw })
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
end

-- The model of every project (c0118). `facts` default to the checkout's own (board.readFacts), or to none when
-- `root` names one tracker folder (specs pass theirs).
function board.collect(root: string?, checkout: string?, given: Facts?): Model
	local sourceList, checkoutDir = sources(root, checkout)
	local facts: Facts = given or (if root then NO_FACTS else board.readFacts(checkoutDir))
	local problems: { string } = {}
	table.clear(spendCache)
	table.clear(spendBad)
	local rawRafts: { Raw }, rawIssues: { Raw } = {}, {}
	local projectOf: { [string]: string } = {}
	local retired = {}
	local projectList: { Project } = {}
	for _, src in sourceList do
		table.insert(projectList, { name = src.name, root = src.root })
		for _, r in scan(src.base, "rafts") do
			projectOf[r.id] = src.name
			table.insert(rawRafts, r)
		end
		for _, i in scan(src.base, "issues") do
			projectOf[i.id] = src.name
			table.insert(rawIssues, i)
		end
		for _, r in retiredOf(src.base) do
			table.insert(retired, r)
		end
	end
	local hist = history.read(checkoutDir)
	if hist and hist.warnings then
		for _, w in hist.warnings do
			table.insert(problems, `history: {w}`)
		end
	end
	local doneAt: { [string]: number } = if hist and hist.doneAt then hist.doneAt else {}
	local worktreeOf: { [string]: string } = {}
	for _, w in facts.worktrees do
		worktreeOf[w.branch] = w.path
	end
	sortById(rawRafts)
	sortById(rawIssues)

	local raftIds: { [string]: boolean } = {}
	for _, r in rawRafts do
		raftIds[r.id] = true
	end

	local issues: { Issue } = {}
	local issueById: { [string]: Issue } = {}
	for _, i in rawIssues do
		local named = i.front.raft
		local issueType = if TYPES[i.front.type or ""] then i.front.type else ""
		local issue: Issue = {
			id = i.id,
			kind = "issue",
			type = issueType,
			label = issueType,
			title = i.front.title or "",
			state = i.state,
			design = i.front.design or "",
			status = statusOf(i.state, i.front.design or ""),
			stage = status.effective(i.front, i.state),
			raft = if named and raftIds[named] then named else nil,
			dependsOn = listOf(i.front.depends_on),
			dependents = {},
			emergent = i.front.emergent == "true",
			body = i.body,
			project = projectOf[i.id],
			column = "ticket",
			doneAt = doneAt[i.id],
			doneFrom = if doneAt[i.id] then "history" else nil,
			age = nil,
			spend = spendOf(spendRows(spendPath(i.root, i.state, i.id), problems)),
			dispatch = facts.dispatch[i.id],
		}
		table.insert(issues, issue)
		issueById[i.id] = issue
	end

	local members: { [string]: { string } } = {}
	for _, issue in issues do
		if issue.raft then
			members[issue.raft] = members[issue.raft] or {}
			table.insert(members[issue.raft], issue.id)
		end
	end

	local function labelOf(raftType: string, memberIds: { string }): string
		local seen: { [string]: boolean } = {}
		for _, id in memberIds do
			local memberType = issueById[id].type
			if TYPES[memberType] then
				seen[memberType] = true
			end
		end
		local found = sortedKeys(seen)
		if #found == 0 then
			return raftType
		elseif #found == 1 then
			return found[1]
		end
		return "mix"
	end

	local rafts: { Raft } = {}
	local raftById: { [string]: Raft } = {}
	local raftBuckets: { [string]: Bucket } = {}
	for _, r in rawRafts do
		local raftType = if TYPES[r.front.type or ""] then r.front.type else ""
		local memberIds = members[r.id] or {}
		local stage = status.effective(r.front, r.state)
		local bucket: Bucket = if r.state == "done"
			then "done"
			elseif
				r.state == "active" or ((r.front.design or "") == "ready" and stage == "prepared")
			then "ready"
			else "not"
		local command: string? = nil
		if bucket == "ready" then
			command = if r.state == "active" then `/z-run {r.id}` else `/z-ready {r.id}`
		end
		raftBuckets[r.id] = bucket
		local raft: Raft = {
			id = r.id,
			kind = "raft",
			type = raftType,
			label = labelOf(raftType, memberIds),
			title = r.front.title or "",
			state = r.state,
			design = r.front.design or "",
			status = statusOf(r.state, r.front.design or ""),
			stage = stage,
			single = r.front.single == "true",
			pseudo = false,
			issues = memberIds,
			dependsOn = {},
			dependents = {},
			blockedBy = {},
			topLevel = true,
			command = command,
			body = r.body,
			project = projectOf[r.id],
			launched = false,
			branch = nil,
			worktree = nil,
			doneAt = doneAt[r.id],
			doneFrom = if doneAt[r.id] then "history" else nil,
			rounds = { design = 0, code = 0 },
			dispatch = facts.dispatch[r.id],
		}
		local branch = branchOf(r.id, facts.refs, if hist and hist.activeAt then hist.activeAt[r.id] else nil)
		if branch then
			raft.launched = true
			raft.branch = branch
			raft.worktree = worktreeOf[branch]
		end
		table.insert(rafts, raft)
		raftById[r.id] = raft
	end

	-- dependencies: raft -> raft through member issues, and raft -> raftless issue (blocks, never a raft dependency)
	local looseDependents: { [string]: { [string]: boolean } } = {}
	for _, raft in rafts do
		local deps: { [string]: boolean } = {}
		local blockers: { [string]: boolean } = {}
		for _, id in raft.issues do
			for _, dep in issueById[id].dependsOn do
				local target = issueById[dep]
				if not target then
					continue
				end
				if target.raft then
					if target.raft ~= raft.id then
						deps[target.raft] = true
					end
				else
					looseDependents[target.id] = looseDependents[target.id] or {}
					looseDependents[target.id][raft.id] = true
					if target.status ~= "done" then
						blockers[target.id] = true
					end
				end
			end
		end
		raft.dependsOn = sortedKeys(deps)
		for dep in deps do
			if raftById[dep].status ~= "done" then
				blockers[dep] = true
			end
		end
		raft.blockedBy = sortedKeys(blockers)
		raft.topLevel = #raft.blockedBy == 0
	end
	for _, raft in rafts do
		for _, dep in raft.dependsOn do
			table.insert(raftById[dep].dependents, raft.id)
		end
	end
	for _, raft in rafts do
		table.sort(raft.dependents)
	end

	local function groups(): Groups
		return { ready = {}, ["not"] = {}, done = {} }
	end
	local views = { rafts = groups(), issues = groups() }
	for _, raft in rafts do
		table.insert(views.rafts[raftBuckets[raft.id]], raft.id)
	end
	for _, issue in issues do
		if issue.raft then
			issue.dependents = {}
		else
			issue.dependents = sortedKeys(looseDependents[issue.id] or {})
		end
		local bucket: Bucket = "not"
		if issue.state == "done" then
			bucket = "done"
		elseif issue.raft and raftBuckets[issue.raft] == "ready" then
			bucket = "ready"
			issue.command = raftById[issue.raft].command
		elseif not issue.raft then
			issue.command = `/z-design {issue.id}`
		end
		table.insert(views.issues[bucket], issue.id)
	end
	table.sort(views.rafts.ready)
	table.sort(views.rafts["not"])
	table.sort(views.rafts.done)
	table.sort(views.issues.ready)
	table.sort(views.issues["not"])
	table.sort(views.issues.done)

	local home: { [string]: string } = {}
	for _, raft in rafts do
		home[raft.id] = raft.id
	end
	for _, issue in issues do
		home[issue.id] = issue.id
	end

	-- c0118: a done item that history leaves undated (a compaction ended its dated life, or there is no history: a
	-- shallow clone) is dated by its newest spend row (a raft by its members'), a field no id change rewrites; else it
	-- stays undated
	local function newestRow(i: Raw): number?
		local best: number? = nil
		for _, row in spendRows(spendPath(i.root, i.state, i.id), problems) do
			local at = boardview.rowInstant(row.when)
			if at and (best == nil or at > best) then
				best = at
			end
		end
		return best
	end
	local newestOf: { [string]: number } = {}
	for _, i in rawIssues do
		local issue = issueById[i.id]
		local at = newestRow(i)
		if at then
			newestOf[i.id] = at
		end
		if issue.state == "done" and not issue.doneAt and at then
			issue.doneAt, issue.doneFrom = at, "spend"
		end
	end
	for _, raft in rafts do
		if raft.state == "done" and not raft.doneAt then
			for _, id in raft.issues do
				local at = newestOf[id]
				if at and (raft.doneAt == nil or at > raft.doneAt :: number) then
					raft.doneAt, raft.doneFrom = at, "spend"
				end
			end
		end
	end

	-- c0118: columns and bands per project, from each issue's effective status and its raft's branch
	local columns: { [string]: { [string]: { boardview.Band } } } = {}
	for _, p in projectList do
		local cards: { [string]: { { id: string, raft: string? } } } = {}
		for _, c in boardview.COLUMNS do
			cards[c] = {}
		end
		for _, issue in issues do
			if issue.project == p.name then
				local raft = if issue.raft then raftById[issue.raft] else nil
				issue.column = boardview.column(issue.stage, raft ~= nil and raft.launched)
				issue.age = boardview.age(issue.doneAt, facts.asOf)
				table.insert(cards[issue.column], { id = issue.id, raft = issue.raft })
			end
		end
		columns[p.name] = {}
		for _, c in boardview.COLUMNS do
			columns[p.name][c] = boardview.bands(cards[c])
		end
	end

	-- c0118: review rounds of each raft (its folder, its members', and the rafts retired into it, followed to the
	-- raft that kept them), and the two charts per project and range
	local rawRaftById: { [string]: Raw } = {}
	for _, r in rawRafts do
		rawRaftById[r.id] = r
	end
	local files: { [string]: { string } } = {}
	for _, raft in rafts do
		files[raft.id] = {}
		reviewFiles(rawRaftById[raft.id].dir, files[raft.id])
	end
	for _, i in rawIssues do
		local issue = issueById[i.id]
		if issue.raft then
			reviewFiles(i.dir, files[issue.raft])
		end
	end
	local keeperOf: { [string]: string } = {}
	for _, r in retired do
		keeperOf[r.id] = r.keeper
	end
	for _, r in retired do
		local keeper, hops = r.keeper, 0
		while keeperOf[keeper] and hops < 100 do
			keeper, hops = keeperOf[keeper], hops + 1
		end
		if files[keeper] then
			reviewFiles(r.dir, files[keeper])
		end
	end
	for _, raft in rafts do
		local design, code = boardview.rounds(files[raft.id])
		raft.rounds = { design = design, code = code }
	end
	local charts: { [string]: ProjectCharts } = {}
	for _, p in projectList do
		local landed: { boardview.Landed } = {}
		for _, raft in rafts do
			if raft.project == p.name and raft.state == "done" and raft.doneAt then
				table.insert(
					landed,
					{ id = raft.id, at = raft.doneAt, design = raft.rounds.design, code = raft.rounds.code }
				)
			end
		end
		local rows: { boardview.TokenRow } = {}
		for _, i in rawIssues do
			if projectOf[i.id] == p.name then
				for _, row in spendRows(spendPath(i.root, i.state, i.id), problems) do
					local at = boardview.rowInstant(row.when)
					if at and row.tokens then
						table.insert(
							rows,
							{ at = at, phase = row.phase, tokens = row.tokens, model = modelOf(row) }
						)
					end
				end
			end
		end
		local pc: ProjectCharts = { rounds = {}, tokens = {}, captions = { rounds = {}, tokens = {} } }
		for _, range in boardview.RANGES do
			if facts.asOf then
				pc.rounds[range.key], pc.captions.rounds[range.key] = chartSvg(
					`{p.name}/rounds/{range.key}`,
					"Review rounds by week (rafts landed that week)",
					"rounds",
					boardview.roundsByWeek(landed, facts.asOf, range.days)
				)
				pc.tokens[range.key], pc.captions.tokens[range.key] = chartSvg(
					`{p.name}/tokens/{range.key}`,
					"Review tokens by model (design-review and code-review)",
					"tokens",
					boardview.tokensByWeek(rows, facts.asOf, range.days)
				)
			end
		end
		charts[p.name] = pc
	end
	local ranges = {}
	for _, range in boardview.RANGES do
		table.insert(ranges, { key = range.key, label = range.label })
	end
	-- c0284: each item's provenance, the entries `./zn who` prints (boardprov reads the history once for all of them)
	local items: { boardprov.Item } = {}
	for _, i in rawIssues do
		local path = spendPath(i.root, i.state, i.id)
		local rows = spendRows(path, problems)
		if not spendBad[path] then -- an unparsable spend.md is named once above; `who` refuses the item, so no entries
			table.insert(items, { id = i.id, kind = "issue", dir = i.dir, spend = who.spend(rows) })
		end
	end
	for _, r in rawRafts do
		table.insert(items, { id = r.id, kind = "raft", dir = r.dir, spend = {} })
	end
	local entries =
		boardprov.read(items, if hist or history.atTop(checkoutDir) then checkoutDir else nil, problems)
	for _, issue in issues do
		issue.provenance = entries[issue.id]
	end
	for _, raft in rafts do
		raft.provenance = entries[raft.id]
	end
	table.sort(problems)

	return {
		rafts = rafts,
		issues = issues,
		views = views,
		home = home,
		initialView = "board",
		stats = statistics(hist, rawIssues, problems),
		projects = projectList,
		columns = columns,
		charts = charts,
		asOf = facts.asOf,
		history = hist ~= nil,
		windows = boardview.WINDOWS,
		window = boardview.WINDOW,
		ranges = ranges,
		range = boardview.RANGE,
		problems = problems,
	}
end

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
	["<"] = "\\u003c",
}

local function encodeString(s: string): string
	local escaped = string.gsub(s, '[%c"\\<]', function(c: string): string
		return ESCAPES[c] or string.format("\\u%04x", string.byte(c))
	end)
	return `"{escaped}"`
end

-- Deterministic JSON: keys sorted, empty tables as [], and < escaped so data can never end a <script>.
function board.encode(v: any): string
	local kind = typeof(v)
	if kind == "string" then
		return encodeString(v)
	elseif kind == "boolean" then
		return if v then "true" else "false"
	elseif kind == "number" then
		return tostring(v)
	elseif kind ~= "table" then
		error(`board.encode cannot write a {kind}`, 0)
	end
	local parts: { string } = {}
	if next(v) == nil then
		return "[]"
	elseif #v > 0 then
		for _, item in v do
			table.insert(parts, board.encode(item))
		end
		return `[{table.concat(parts, ",")}]`
	end
	local keys: { string } = {}
	for k in v do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in keys do
		table.insert(parts, `{encodeString(k)}:{board.encode(v[k])}`)
	end
	return `\{{table.concat(parts, ",")}}`
end

-- The page: the template with marked, the stats section and the model in place of its placeholders.
-- Assembled from pieces, never with gsub, so `%` or a placeholder-looking string in marked, the
-- section or the data can't be misread.
function board.render(m: Model, markedJs: string): string
	local template = fs.readFile(fromTop(board.TEMPLATE_PATH))
	local markedAt, markedEnd = string.find(template, "{{MARKED}}", 1, true)
	local statsAt, statsEnd = string.find(template, "{{STATS}}", 1, true)
	local dataAt, dataEnd = string.find(template, "{{DATA}}", 1, true)
	if
		not (
			markedAt
			and markedEnd
			and statsAt
			and statsEnd
			and dataAt
			and dataEnd
			and markedEnd < statsAt
			and statsEnd < dataAt
		)
	then
		error(
			board.TEMPLATE_PATH .. " needs the MARKED, then the STATS, then the DATA placeholder, once each",
			0
		)
	end
	return table.concat({
		string.sub(template, 1, markedAt - 1),
		board.inlineMarked(markedJs),
		string.sub(template, markedEnd + 1, statsAt - 1),
		statsHtml(m.stats),
		string.sub(template, statsEnd + 1, dataAt - 1),
		board.encode(m),
		string.sub(template, dataEnd + 1),
	})
end

-- The page for the tracker under root (default: every project root of `checkout`, default "."), from the pinned
-- marked.
function board.build(root: string?, checkout: string?, facts: Facts?): string
	local markedJs = fs.readFile(fromTop(board.MARKED_PATH))
	board.checkMarked(markedJs)
	return board.render(board.collect(root, checkout, facts), markedJs)
end

return board
